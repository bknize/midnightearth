#!/usr/bin/env python3
"""dashboard.py - the project's progress record, read from the vault (ADR 0007).

  scripts/dashboard.py                      write docs/dashboard.md
  scripts/dashboard.py --out <file>         write it somewhere else
  scripts/dashboard.py --set <note> <id> <status>
                                            set one row's Status cell: a task (T07) in a
                                            tasks.md, or an item (B-12) in backlog.md

Sources: every docs/specs/<slug>/tasks.md (the task table's Status column and the
verification checkboxes), docs/planning/cycles.md (the DC rows) and
docs/planning/backlog.md. Standard library only. The output is a vault note: wikilinks to
every spec, plan and tasks note, one folding callout per spec and for the backlog.

Exit codes: 0 written or set, 1 the row or a source was not found, 2 bad usage.
"""
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

NOTE_UID = "5d0c3b1e-7a52-4c8e-9f41-2b6e0a7d9c13"
NOTE_CREATED = "2026-11-09"


def short(text, limit=110):
    """The head of a long cell, cut where it leaves no open code span or wikilink."""
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text) if text.startswith("**") else text
    cut = re.search(r"[:;(]", text)
    head = text[:cut.start()].strip() if cut and 12 <= cut.start() <= limit else text
    if len(head) > limit:
        head = head[:limit].rstrip() + "…"
    if head.count("[[") > head.count("]]"):
        head = head[:head.rindex("[[")].rstrip() + "…"
    if head.count("`") % 2:
        head = head[:head.rindex("`")].rstrip() + "…"
    return head


def cell(text):
    """Text for a table cell: a pipe (a wikilink alias, a code span) is escaped."""
    return re.sub(r"(?<!\\)\|", r"\\|", text)


def status(value):
    return value if value in ("done", "dropped") else "**%s**" % value


def ended(cycle):
    return cycle["done"].strip() not in ("", "–", "-")


def callout(kind, fold, title, body):
    """An Obsidian callout, folded (`-`) or open (`+`); `body` is a list of lines."""
    return ["> [!%s]%s %s" % (kind, fold, title)] + [(">" + (" " + l if l else "")) for l in body] + [""]


def table(header, rows):
    return ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)] + [
        "| " + " | ".join(cell(c) for c in row) + " |" for row in rows]


def render(specs, cycles, backlog):
    tasks = [t for s in specs for g in s["groups"] for t in g["tasks"]]
    done = sum(t["status"] == "done" for t in tasks)
    dropped = sum(t["status"] == "dropped" for t in tasks)
    open_items = [b for b in backlog if b["status"] == "open"]
    out = ["---", "type: moc", "tags: [moc, dashboard, planning]", "status: evergreen",
           'related: ["[[planning/cycles]]", "[[planning/backlog]]", "[[specs/specs-moc]]", '
           '"[[decisions/0007-no-ticket-tracker]]"]',
           "created: %s" % NOTE_CREATED, "updated: %s" % date.today().isoformat(),
           "uid: %s" % NOTE_UID, "supersedes:", "---", "",
           "# Dashboard", "",
           "Written by `make dashboard` from every spec's `tasks.md`, [[planning/cycles]] and",
           "[[planning/backlog]] ([[decisions/0007-no-ticket-tracker]]). Do not edit it: change the",
           "source note and run `make dashboard` again.", ""]
    out += table(["Dev cycles done", "Tasks done", "Tasks to do", "Open backlog items"],
                 [["%d / %d" % (sum(ended(c) for c in cycles), len(cycles)),
                   "%d / %d" % (done, len(tasks) - dropped), str(len(tasks) - done - dropped),
                   str(len(open_items))]])
    out += ["", "## Cycles", ""]
    for spec in sorted(specs, key=spec_order, reverse=True):
        st = [t for g in spec["groups"] for t in g["tasks"]]
        d = sum(t["status"] == "done" for t in st)
        x = sum(t["status"] == "dropped" for t in st)
        dcs = [c for c in cycles if spec["slug"] in c["slugs"]]
        complete = bool(st) and d + x == len(st)
        base = "specs/%s/" % spec["slug"]
        body = ['<progress value="%d" max="%d"></progress> %s · [[%sspec|spec]] · [[%splan|plan]] · [[%stasks|tasks]]'
                % (d, max(len(st) - x, 1), ", ".join(c["id"] for c in dcs) or "no dev cycle yet",
                   base, base, base), ""]
        for c in dcs:
            body.append("- **%s %s** · %s → %s%s" % (
                c["id"], c["theme"], c["started"] or "?", c["done"] if ended(c) else "in progress",
                " · " + short(c["outcome"], 160) if c["outcome"] else ""))
        if dcs:
            body.append("")
        for group in spec["groups"]:
            if group["name"]:
                body += ["**%s**" % group["name"], ""]
            body += table(["#", "Task", "Area", "Who", "Status"],
                          [[t["id"], short(t["text"]), t["area"], t["who"], status(t["status"])]
                           for t in group["tasks"]]) + [""]
        if spec["checks"]:
            ok = sum(c["done"] for c in spec["checks"])
            body += ["**Verification: %d of %d checked**" % (ok, len(spec["checks"])), ""]
            body += ["- %s %s" % ("☑" if c["done"] else "☐", short(c["text"], 200)) for c in spec["checks"]]
        while body and not body[-1]:
            body.pop()
        out += callout("success" if complete else "todo", "-" if complete else "+",
                       "[[%sspec|%s]] · %d / %d" % (base, spec["title"], d, len(st) - x), body)
    known = {s["slug"] for s in specs}
    loose = [c for c in cycles if not known.intersection(c["slugs"])]
    if loose:
        out += callout("note", "-", "Cycles with no task note · %d" % len(loose),
                       table(["#", "Theme", "Done", "Outcome"],
                             [[c["id"], c["theme"], c["done"], short(c["outcome"], 160)] for c in loose]))
    out += ["## Backlog", ""]
    for kind, fold, label, items in (("todo", "+", "Open", open_items),
                                     ("success", "-", "Closed", [b for b in backlog if b["status"] != "open"])):
        out += callout(kind, fold, "%s · %d" % (label, len(items)),
                       table(["#", "Item", "Status", "Where"],
                             [[b["id"], b["text"], status(b["status"]), b["where"]] for b in items]))
    return "\n".join(out).rstrip("\n") + "\n"


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
    out = ROOT / "docs/dashboard.md"
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
