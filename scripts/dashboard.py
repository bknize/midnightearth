#!/usr/bin/env python3
"""dashboard.py - the project's progress record, read from the vault (ADR 0007).

  scripts/dashboard.py                      write docs/dashboard.html
  scripts/dashboard.py --out <file>         write it somewhere else
  scripts/dashboard.py --set <note> <id> <status>
                                            set one row's Status cell: a task (T07) in a
                                            tasks.md, or an item (B-12) in backlog.md

Sources: every docs/specs/<slug>/tasks.md (the task table's Status column and the
verification checkboxes), docs/planning/cycles.md (the DC rows) and
docs/planning/backlog.md. Standard library only; the page is one self-contained file.

Exit codes: 0 written or set, 1 the row or a source was not found, 2 bad usage.
"""
import html
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASK_STATUSES = ("todo", "done", "dropped")
BACKLOG_STATUSES = ("open", "done", "dropped")


# --- parsing -----------------------------------------------------------------------

def split_row(line):
    """Cells of a Markdown table row; a pipe inside a code span or escaped stays put."""
    cells, cur, in_code, i = [], "", False, 0
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body) and body[i + 1] == "|":
            cur += "|"
            i += 2
            continue
        if ch == "`":
            in_code = not in_code
        if ch == "|" and not in_code:
            cells.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    if cur.strip():
        cells.append(cur.strip())
    return cells


def is_separator(line):
    return bool(re.match(r"^\|[-| :]+\|\s*$", line))


def row_id(cell):
    """T07 for a task cell ('7', '17a', 'T07'), B-12 for a backlog cell, else None."""
    cell = cell.strip()
    m = re.fullmatch(r"T?(\d+)([a-z]?)", cell)
    if m:
        return "T%02d%s" % (int(m.group(1)), m.group(2))
    return cell if re.fullmatch(r"B-\d+", cell) else None


def frontmatter(text):
    out = {}
    if text.startswith("---\n"):
        for line in text[4:text.find("\n---", 4)].split("\n"):
            key, sep, value = line.partition(":")
            if sep:
                out[key.strip()] = value.strip()
    return out


def status_tables(text):
    """Yield (heading, header cells, rows) for each table that has a Status column."""
    heading, header, rows = "", None, []
    for line in text.split("\n"):
        if line.startswith("#"):
            heading = line.lstrip("#").strip()
        if line.startswith("|"):
            if header is None:
                cells = split_row(line)
                if cells and cells[0] == "#" and "Status" in cells:
                    header, rows = cells, []
            elif not is_separator(line):
                rows.append(split_row(line))
            continue
        if header is not None:
            yield heading, header, rows
            header = None
    if header is not None:
        yield heading, header, rows


def parse_tasks(path):
    text = path.read_text(encoding="utf-8")
    meta = frontmatter(text)
    title = re.search(r"^# (?:Tasks: )?(.+)$", text, re.M)
    spec = {"slug": path.parent.name, "title": title.group(1).strip() if title else path.parent.name,
            "created": meta.get("created", ""), "groups": [], "checks": []}
    for heading, header, rows in status_tables(text):
        col = {name: i for i, name in enumerate(header)}
        tasks = []
        for cells in rows:
            tid = row_id(cells[0]) if cells else None
            if tid is None or len(cells) < len(header):
                continue
            tasks.append({"id": tid, "text": cells[col["Task"]],
                          "area": cells[col["Area"]] if "Area" in col else "",
                          "who": cells[col["Who"]] if "Who" in col else "",
                          "status": cells[col["Status"]]})
        group = heading if heading.lower().startswith("milestone") else ""
        spec["groups"].append({"name": group, "tasks": tasks})
    section = ""
    for line in text.split("\n"):
        if line.startswith("## "):
            section = line[3:].strip()
        m = re.match(r"^\s*- \[([ xX])\] (.+)$", line)
        if m and section.lower().startswith("verification"):
            spec["checks"].append({"done": m.group(1) != " ", "text": m.group(2), "section": section})
    return spec


def parse_cycles(path):
    cycles = []
    if not path.exists():
        return cycles
    for line in path.read_text(encoding="utf-8").split("\n"):
        cells = split_row(line) if line.startswith("|") else []
        if len(cells) >= 7 and re.fullmatch(r"DC-\d+", cells[0]):
            link = r"\[\[specs/([^/\]|]+)/"
            slugs = re.findall(link, cells[3]) or re.findall(link, cells[2])[:1]
            branch = re.search(r"`([^`]+)`", cells[2])
            cycles.append({"id": cells[0], "theme": cells[1], "branch": branch.group(1) if branch else "",
                           "started": cells[4], "done": cells[5], "outcome": cells[6],
                           "slugs": list(dict.fromkeys(slugs))})
            if not slugs and branch:  # `cycle-7b-bot-players` is milestone B of cycle-7-bot-players
                cycles[-1]["slugs"] = [re.sub(r"^(cycle-\d+)b-", r"\1-", branch.group(1))]
    return cycles


def parse_backlog(path):
    items = []
    if not path.exists():
        return items
    for _heading, header, rows in status_tables(path.read_text(encoding="utf-8")):
        col = {name: i for i, name in enumerate(header)}
        for cells in rows:
            if cells and row_id(cells[0]) and len(cells) >= len(header):
                items.append({"id": cells[0], "text": cells[col["Item"]], "status": cells[col["Status"]],
                              "where": cells[col["Where"]] if "Where" in col else ""})
    return items


def spec_order(spec):
    m = re.match(r"cycle-(\d+)", spec["slug"])
    return (spec["created"], int(m.group(1)) if m else 0, spec["slug"])


# --- setting a status --------------------------------------------------------------

def set_status(path, wanted, status):
    """Rewrite the Status cell of the row whose id is `wanted`. Returns True when found."""
    lines = path.read_text(encoding="utf-8").split("\n")
    header = None
    for n, line in enumerate(lines):
        if not line.startswith("|"):
            header = None
            continue
        cells = split_row(line)
        if header is None:
            if cells and cells[0] == "#" and "Status" in cells:
                header = cells
            continue
        if is_separator(line) or not cells or row_id(cells[0]) != row_id(wanted):
            continue
        if header[-1] == "Status":
            lines[n] = re.sub(r"\|[^|]*\|\s*$", "| %s |" % status, line)
        else:  # Status is not last (backlog.md): rebuild the row
            cells[header.index("Status")] = status
            lines[n] = "| " + " | ".join(c.replace("|", "\\|") if "`" not in c else c for c in cells) + " |"
        path.write_text("\n".join(lines), encoding="utf-8")
        return True
    return False


# --- rendering ---------------------------------------------------------------------

def inline(text):
    """Escape, then the little Markdown the notes use: wikilinks, code spans."""
    text = re.sub(r"\[\[([^\]|]+)\|([^\]]+)\]\]", r"\2", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", lambda m: m.group(1).split("/")[-2] if "/" in m.group(1) else m.group(1), text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)


def short(text, limit=110):
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text) if text.startswith("**") else text
    cut = re.search(r"[:;(]", text)
    head = text[:cut.start()].strip() if cut and 12 <= cut.start() <= limit else text
    return head if len(head) <= limit else head[:limit].rstrip() + "…"


def bar(done, dropped, total):
    if not total:
        return ""
    d, x = 100.0 * done / total, 100.0 * dropped / total
    return ('<span class="bar" role="img" aria-label="%d of %d done"><span class="fill" style="width:%.1f%%"></span>'
            '<span class="drop" style="width:%.1f%%"></span></span>' % (done, total, d, x))


def pill(status):
    return '<span class="pill %s">%s</span>' % (html.escape(status), html.escape(status))


CSS = """
:root{--bg:#f6f5f1;--card:#fff;--ink:#1c1f24;--mute:#687078;--line:#dedbd3;--done:#2f7d5b;
--todo:#b3721b;--drop:#8a8f96;--accent:#2a5f8f;--code:#eeece6}
@media (prefers-color-scheme:dark){:root{--bg:#14171b;--card:#1c2026;--ink:#e6e4de;--mute:#98a0a8;
--line:#2c323a;--done:#5fbf93;--todo:#e0a550;--drop:#737a82;--accent:#7fb2de;--code:#262b32}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1040px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:26px;margin:0 0 4px}h2{font-size:17px;margin:36px 0 12px}
.sub{color:var(--mute);margin:0 0 24px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}
.stat{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.stat b{display:block;font-size:24px;font-variant-numeric:tabular-nums}.stat span{color:var(--mute);font-size:13px}
details{background:var(--card);border:1px solid var(--line);border-radius:10px;margin:0 0 10px}
summary{cursor:pointer;padding:12px 16px;display:grid;grid-template-columns:1fr auto 120px;gap:14px;align-items:center;list-style:none}
summary::-webkit-details-marker{display:none}
summary .name{font-weight:600}summary .meta{display:block;color:var(--mute);font-size:13px;font-weight:400}
.count{font-variant-numeric:tabular-nums;color:var(--mute);white-space:nowrap}
.bar{display:flex;height:8px;border-radius:4px;background:var(--line);overflow:hidden}
.fill{background:var(--done)}.drop{background:var(--drop)}
.body{padding:0 16px 14px;overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:14px}
th{text-align:left;color:var(--mute);font-weight:500;font-size:12px;text-transform:uppercase;letter-spacing:.04em}
th,td{padding:6px 10px 6px 0;border-top:1px solid var(--line);vertical-align:top}
td.id{font-variant-numeric:tabular-nums;white-space:nowrap;color:var(--mute)}td.nw{white-space:nowrap;color:var(--mute)}
h3{font-size:13px;margin:16px 0 6px;color:var(--mute);font-weight:600}
.pill{display:inline-block;padding:1px 9px;border-radius:999px;font-size:12px;border:1px solid currentColor}
.pill.done{color:var(--done)}.pill.todo,.pill.open{color:var(--todo)}.pill.dropped{color:var(--drop)}
.dc{margin:0 0 10px;padding:0;list-style:none;color:var(--mute);font-size:13px}
.dc b{color:var(--ink);font-weight:600}
ul.checks{margin:0;padding:0;list-style:none;font-size:14px}ul.checks li{padding:3px 0 3px 24px;text-indent:-24px}
code{background:var(--code);padding:1px 4px;border-radius:4px;font-size:.92em}
@media (max-width:640px){summary{grid-template-columns:1fr auto}summary .bar{grid-column:1/-1}.hide-s{display:none}}
"""


def render(specs, cycles, backlog):
    tasks = [t for s in specs for g in s["groups"] for t in g["tasks"]]
    done = sum(t["status"] == "done" for t in tasks)
    dropped = sum(t["status"] == "dropped" for t in tasks)
    open_items = [b for b in backlog if b["status"] == "open"]
    cycles_done = sum(1 for c in cycles if c["done"].strip() not in ("", "–", "-"))
    out = ['<!doctype html><html lang="en"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width,initial-scale=1">',
           "<title>Midnight Earth progress</title><style>%s</style></head><body><main>" % CSS,
           "<h1>Midnight Earth progress</h1>",
           '<p class="sub">Generated %s by <code>make dashboard</code> from the task notes.</p>' % date.today().isoformat(),
           '<div class="stats">',
           '<div class="stat"><b>%d / %d</b><span>dev cycles done</span></div>' % (cycles_done, len(cycles)),
           '<div class="stat"><b>%d / %d</b><span>tasks done</span></div>' % (done, len(tasks) - dropped),
           '<div class="stat"><b>%d</b><span>tasks to do</span></div>' % (len(tasks) - done - dropped),
           '<div class="stat"><b>%d</b><span>open backlog items</span></div>' % len(open_items),
           "</div>", "<h2>Cycles</h2>"]
    for spec in sorted(specs, key=spec_order, reverse=True):
        st = [t for g in spec["groups"] for t in g["tasks"]]
        d = sum(t["status"] == "done" for t in st)
        x = sum(t["status"] == "dropped" for t in st)
        dcs = [c for c in cycles if spec["slug"] in c["slugs"]]
        complete = bool(st) and d + x == len(st)
        tags = ", ".join(c["id"] for c in dcs) or "no dev cycle yet"
        out.append("<details%s><summary><span class=\"name\">%s<span class=\"meta\">%s · %s</span></span>"
                   "<span class=\"count\">%d / %d</span>%s</summary><div class=\"body\">"
                   % ("" if complete else " open", inline(spec["title"]), html.escape(spec["slug"]),
                      html.escape(tags), d, len(st) - x, bar(d, x, len(st))))
        if dcs:
            out.append('<ul class="dc">')
            for c in dcs:
                ended = c["done"].strip() not in ("", "–", "-")
                out.append("<li><b>%s %s</b> · %s → %s · %s</li>" % (
                    html.escape(c["id"]), inline(c["theme"]), html.escape(c["started"] or "?"),
                    html.escape(c["done"]) if ended else "in progress",
                    inline(short(c["outcome"], 160)) if c["outcome"] else ""))
            out.append("</ul>")
        for group in spec["groups"]:
            if group["name"]:
                out.append("<h3>%s</h3>" % inline(group["name"]))
            out.append('<table><thead><tr><th>#</th><th>Task</th><th class="hide-s">Area</th>'
                       '<th class="hide-s">Who</th><th>Status</th></tr></thead><tbody>')
            for t in group["tasks"]:
                out.append('<tr><td class="id">%s</td><td title="%s">%s</td><td class="nw hide-s">%s</td>'
                           '<td class="nw hide-s">%s</td><td>%s</td></tr>'
                           % (t["id"], html.escape(t["text"], quote=True), inline(short(t["text"])),
                              inline(t["area"]), inline(t["who"]), pill(t["status"])))
            out.append("</tbody></table>")
        if spec["checks"]:
            ok = sum(c["done"] for c in spec["checks"])
            out.append("<h3>Verification: %d of %d checked</h3><ul class=\"checks\">" % (ok, len(spec["checks"])))
            for c in spec["checks"]:
                out.append("<li>%s %s</li>" % ("☑" if c["done"] else "☐", inline(short(c["text"], 200))))
            out.append("</ul>")
        out.append("</div></details>")
    known = {s["slug"] for s in specs}
    loose = [c for c in cycles if not known.intersection(c["slugs"])]
    if loose:
        out.append("<h2>Cycles with no task note</h2><details open><summary><span class=\"name\">%d cycles</span>"
                   "<span></span><span></span></summary><div class=\"body\"><table><tbody>" % len(loose))
        for c in loose:
            out.append('<tr><td class="id">%s</td><td>%s</td><td class="nw">%s</td><td>%s</td></tr>' % (
                html.escape(c["id"]), inline(c["theme"]), html.escape(c["done"]), inline(short(c["outcome"], 160))))
        out.append("</tbody></table></div></details>")
    out.append("<h2>Backlog</h2>")
    for label, items, is_open in (("Open", open_items, True),
                                  ("Closed", [b for b in backlog if b["status"] != "open"], False)):
        out.append("<details%s><summary><span class=\"name\">%s</span><span class=\"count\">%d</span><span></span>"
                   "</summary><div class=\"body\"><table><thead><tr><th>#</th><th>Item</th><th>Status</th>"
                   "<th class=\"hide-s\">Where</th></tr></thead><tbody>" % (" open" if is_open else "", label, len(items)))
        for b in items:
            out.append('<tr><td class="id">%s</td><td>%s</td><td>%s</td><td class="hide-s">%s</td></tr>' % (
                html.escape(b["id"]), inline(b["text"]), pill(b["status"]), inline(b["where"])))
        out.append("</tbody></table></div></details>")
    out.append("</main></body></html>\n")
    return "\n".join(out)


def build(root):
    specs = [parse_tasks(p) for p in sorted((root / "docs/specs").glob("*/tasks.md"))]
    cycles = parse_cycles(root / "docs/planning/cycles.md")
    backlog = parse_backlog(root / "docs/planning/backlog.md")
    return specs, cycles, backlog


def main(argv):
    if len(argv) >= 1 and argv[0] == "--set":
        if len(argv) != 4 or row_id(argv[2]) is None:
            print("usage: scripts/dashboard.py --set <note> <id> <status>", file=sys.stderr)
            return 2
        path, wanted, status = Path(argv[1]), argv[2], argv[3]
        allowed = BACKLOG_STATUSES if wanted.startswith("B-") else TASK_STATUSES
        if status not in allowed:
            print("dashboard: status must be one of %s" % ", ".join(allowed), file=sys.stderr)
            return 2
        if not path.exists() or not set_status(path, wanted, status):
            print("dashboard: no row %s with a Status column in %s" % (wanted, path), file=sys.stderr)
            return 1
        print("dashboard: %s is %s in %s" % (row_id(wanted), status, path))
        return 0
    out = ROOT / "docs/dashboard.html"
    if argv[:1] == ["--out"] and len(argv) == 2:
        out = Path(argv[1])
    elif argv:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    specs, cycles, backlog = build(ROOT)
    if not specs:
        print("dashboard: no docs/specs/*/tasks.md under %s" % ROOT, file=sys.stderr)
        return 1
    out.write_text(render(specs, cycles, backlog), encoding="utf-8")
    tasks = [t for s in specs for g in s["groups"] for t in g["tasks"]]
    print("dashboard: %s (%d specs, %d of %d tasks done, %d backlog items open)" % (
        out, len(specs), sum(t["status"] == "done" for t in tasks), len(tasks),
        sum(b["status"] == "open" for b in backlog)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
