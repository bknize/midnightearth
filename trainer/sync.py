"""`sync_code` (plan P17, R51, R52): bring a git bundle into the PC's training repository,
check the commit out in the training worktree and run the Godot import there.

Plain function API, so the MCP layer (T10) can call it. Every external program goes through
the injected `run` function (default: subprocess with an argument list, never a shell), so
tests drive it with a fake git and a fake godot.
"""
import base64
import binascii
import hashlib
import os
import re
import shutil
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Optional, Tuple

# (argv, cwd, env) -> (returncode, combined output)
RunFn = Callable[[List[str], Optional[Path], Mapping[str, str]], Tuple[int, str]]

ERROR_RE = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|ERROR:")
COMMIT_RE = re.compile(r"^[0-9a-fA-F]{7,64}$")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
RULES_RE = re.compile(r"^const\s+RULES_VERSION\s*:\s*int\s*=\s*(\d+)", re.M)


def default_run(argv: List[str], cwd: Optional[Path], env: Mapping[str, str]) -> Tuple[int, str]:
    try:
        p = subprocess.run(argv, cwd=None if cwd is None else str(cwd), env=dict(env),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           stdin=subprocess.DEVNULL, check=False)
    except OSError as e:
        return 127, "cannot start %s: %s" % (argv[0], e)
    return p.returncode, p.stdout.decode("utf-8", errors="replace")


def stamp_of(work: Path) -> str:
    """Same string as scripts/bot/records.current_stamp, computed on the checked-out files."""
    data = work / "godot" / "engine" / "data"
    rules = (work / "godot" / "engine" / "match_rules.gd").read_bytes().decode("utf-8")
    m = RULES_RE.search(rules)
    if m is None:
        raise ValueError("RULES_VERSION not found in match_rules.gd")
    h = hashlib.sha256()
    for name in ("cards.json", "decks.json", "crew.json"):
        h.update((data / name).read_bytes())
    return "r%d-%s" % (int(m.group(1)), h.hexdigest()[:16])


def _tail(text: str, lines: int = 8) -> str:
    return "\n".join(text.strip().splitlines()[-lines:])


def sync_code(commit: str, bundle_b64: str = "", inbox_file: str = "", *, root: Path,
              godot_bin: str, run_active: Optional[str] = None,
              run: Optional[RunFn] = None, git: str = "git",
              runner_dest: Optional[Path] = None) -> Dict[str, Any]:
    """Returns {commit, stamp, import_s} or {"error": text}.

    `root` holds `repo/` (training repository), `work/` (worktree) and `inbox/`.
    `run_active` is the id of the run in state running or stopping, or None/"".
    `runner_dest` is the stable runner path (default `~/trainer/runner.ps1`)."""
    runf: RunFn = run or default_run
    if run_active:
        return {"error": "run %s is active; stop it before syncing" % run_active}
    if not COMMIT_RE.match(commit or ""):
        return {"error": "commit must be a hex hash"}
    if bool(bundle_b64) == bool(inbox_file):
        return {"error": "give exactly one of bundle_b64 and inbox_file"}
    root = Path(root)
    inbox = root / "inbox"
    repo, work = root / "repo", root / "work"
    env = dict(os.environ)
    env["GIT_LFS_SKIP_SMUDGE"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"

    if bundle_b64:
        try:
            raw = base64.b64decode(bundle_b64, validate=True)
        except (binascii.Error, ValueError):
            return {"error": "bundle_b64 is not valid base64"}
        inbox.mkdir(parents=True, exist_ok=True)
        bundle = inbox / ("%s.bundle" % uuid.uuid4().hex[:12])
        bundle.write_bytes(raw)
    else:
        if not NAME_RE.match(inbox_file):
            return {"error": "inbox_file must be a plain file name"}
        bundle = inbox / inbox_file
        if not bundle.is_file():
            return {"error": "no such file in the inbox: %s" % inbox_file}

    rc, out = runf([git, "bundle", "verify", str(bundle)], None, env)
    if rc != 0:
        return {"error": "bundle verify failed: %s" % _tail(out)}

    first_time = not repo.exists()
    if first_time:
        root.mkdir(parents=True, exist_ok=True)
        rc, out = runf([git, "init", "--bare", str(repo)], None, env)
        if rc != 0:
            return {"error": "git init failed: %s" % _tail(out)}
    rc, out = runf([git, "-C", str(repo), "fetch", str(bundle), commit], None, env)
    if rc != 0:
        if first_time:
            shutil.rmtree(str(repo), ignore_errors=True)
        return {"error": "fetch failed (commit not in bundle?): %s" % _tail(out)}

    if (work / ".git").exists():
        argv = [git, "-C", str(work), "checkout", "--detach", commit]
    else:
        argv = [git, "-C", str(repo), "worktree", "add", "--detach", str(work), commit]
    rc, out = runf(argv, None, env)
    if rc != 0:
        return {"error": "checkout failed: %s" % _tail(out)}

    t0 = time.monotonic()
    rc, out = runf([godot_bin, "--headless", "--path", str(work / "godot"), "--import"],
                   None, env)
    import_s = round(time.monotonic() - t0, 2)
    if ERROR_RE.search(out):
        bad = [ln for ln in out.splitlines() if ERROR_RE.search(ln)]
        return {"error": "import errors: %s" % "; ".join(bad[:5])}
    if rc != 0:
        return {"error": "import exited %d: %s" % (rc, _tail(out))}

    try:
        stamp = stamp_of(work)
    except (OSError, ValueError) as e:
        return {"error": "stamp: %s" % e}
    src = work / "trainer" / "windows" / "runner.ps1"
    dest = Path(runner_dest) if runner_dest else Path.home() / "trainer" / "runner.ps1"
    if src.is_file():
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(src), str(dest))
    return {"commit": commit, "stamp": stamp, "import_s": import_s}
