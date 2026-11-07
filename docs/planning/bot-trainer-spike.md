---
type: planning
tags: [planning, bot, training, llm, spike, windows]
status: seedling
related: ["[[planning/bot-trainer-architecture]]", "[[planning/planning-moc]]", "[[systems/bot-training]]"]
created: 2026-11-06
updated: 2026-11-06
uid: 6ff633e9-bfe0-48b8-af55-206e04d5aa3b
linear:
supersedes:
---

# Bot trainer spike: a one-day checklist for the Windows PC

> What Ben does at the training PC (and the orchestrator does on the Mac) in one day, to replace the estimates in [[planning/bot-trainer-architecture]] with measured numbers before `/spec` for cycle A.

**The spike answers five questions:**

1. Does the project run headless on native Windows (T1)?
2. Do the PC's matches come out exactly the same as the Mac's?
3. How fast are match-length play-outs, and how many workers does the PC sustain?
4. Which ~8–9B model runs fast enough on the RTX 3070, and does it slow the play-outs down?
5. Can the Mac reach an MCP server on the PC across the LAN?

**Nothing from the spike is committed as code.** The throwaway scripts below live outside the
repo, in `C:\trainer-spike\`. The results go into the table at the end, and the orchestrator
copies them into the architecture note.

Commands are PowerShell unless they're marked **Mac**. Placeholders are in angle brackets.

## 0. Prepare the PC (about 45 min)

- [ ] **Plug in the charger and stop sleep.** The Nov 5 run was killed from outside. Here sleep,
      lid close and update reboots are the risks.

  ```powershell
  powercfg /change standby-timeout-ac 0
  powercfg /change hibernate-timeout-ac 0
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
  ```

- [ ] **Use the vendor's performance mode** (Eluktronics Control Center) and the Windows
      "Best performance" power mode. Keep the vents clear.
- [ ] **Pause Windows Update for a week** (Settings → Windows Update → Pause updates), and set
      Active hours to cover the overnight run.
- [ ] **Give the PC a fixed LAN address:** a DHCP reservation on the router. Note the address as
      `<PC_IP>`, and note the Mac's as `<MAC_IP>`.
- [ ] **Update the NVIDIA driver** (Studio or Game Ready, current), then check it with
      `nvidia-smi`. Note the driver and CUDA versions.
- [ ] **Install Git for Windows** (it includes Git LFS) and **Python 3.14 for Windows**, to match
      the Mac's 3.14.6. Tick "Add to PATH". Check:

  ```powershell
  git --version; py -3.14 --version
  ```

- [ ] **Install Godot 4.6.3 for Windows:** download `Godot_v4.6.3-stable_win64.exe.zip` from
      godotengine.org and unzip it to `C:\Godot\`. Use the
      `Godot_v4.6.3-stable_win64_console.exe` build, which prints to the terminal.

  ```powershell
  setx GODOT_BIN "C:\Godot\Godot_v4.6.3-stable_win64_console.exe"
  ```

  Open a new PowerShell window so `GODOT_BIN` takes effect.

## 1. Get the code onto the PC as a bundle (about 15 min)

This is a manual version of `sync_code` (T2). Nothing is pushed.

- [ ] **Mac:** make a bundle of `master`.

  ```bash
  git -C /Users/Crofts/Dev/nightscience/midnightearth bundle create ~/Desktop/midnightearth.bundle master
  ```

- [ ] **Copy the file to the PC** (USB stick or a shared folder) as `C:\trainer-spike\midnightearth.bundle`.
- [ ] **PC:** clone it without fetching the art. Art isn't needed headless, and the bundle holds
      only LFS pointers.

  ```powershell
  cd C:\trainer-spike
  $env:GIT_LFS_SKIP_SMUDGE = "1"
  git clone midnightearth.bundle midnightearth
  cd midnightearth; git log --oneline -1
  ```

  Note the commit. It must match the Mac's `master`.

## 2. Does it run headless on Windows? (about 30 min)

- [ ] **Import:** this builds `godot\.godot`. Check the log for errors.

  ```powershell
  cd C:\trainer-spike\midnightearth\godot
  & $env:GODOT_BIN --headless --path . --import *> import.log
  Select-String -Path import.log -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script|ERROR:'
  ```

  No matches means it passed.
- [ ] **Boot:** the output must contain `Main ready`.

  ```powershell
  & $env:GODOT_BIN --headless --path . --quit-after 120 -- --seed=1 *> boot.log
  Select-String -Path boot.log -Pattern 'Main ready|SCRIPT ERROR|ERROR:'
  ```

- [ ] **Gate tests (gdUnit4):** a run that ends in exit code 0 or 101 passed. Note the
      `Statistics:` line.

  ```powershell
  & $env:GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue --add res://tests --ignore res://tests/sweep *> test.log; $LASTEXITCODE
  Select-String -Path test.log -Pattern 'Statistics:|FAILED'
  ```

- [ ] **The 50-seed sweep:** note the `Sweep:` lines, especially `p99_us=` and `stamp=`. The
      PC's p99 is for information only; the 10 ms rule is judged on the Mac.

  ```powershell
  & $env:GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue --add res://tests/sweep *> sweep.log
  Select-String -Path sweep.log -Pattern 'Sweep:|Sweep pairing|Statistics:'
  ```

- [ ] **The Python driver on Windows:** it uses only the standard library.

  ```powershell
  cd C:\trainer-spike\midnightearth
  py -3.14 -I scripts\bot\driver.py selftest
  ```

  Note any failures. Path or POSIX problems here become cycle A work.

## 3. Same seeds, same matches? (about 30 min)

The PC's labels are only worth anything if a match played there replays exactly the same on
the Mac. The engine is integer-only and seeded, so they should match. This step proves it.
It calls the bot worker directly rather than `driver.py eval`, because the eval's SPRT can stop
early, and then the two machines wouldn't play the same set of seeds.

Both machines run the same stdlib script, `bench.py` (below). It runs the worker over a seed
range in batches of 25, on N workers at once, then prints:
- games per minute;
- a SHA-256 **digest** of every game record and every decision's action, with timings left
  out.

The same commit, seeds and bots must give the same digest on both machines.

- [ ] **PC:**

  ```powershell
  cd C:\trainer-spike\midnightearth
  py -3.14 -I C:\trainer-spike\bench.py --a tuned --b greedy_v1 --seeds 1-50 --workers 2
  ```

- [ ] **Mac** (save the same script to the scratchpad or `~/Desktop/bench.py`; `GODOT_BIN` is
      the Mac's Godot):

  ```bash
  cd /Users/Crofts/Dev/nightscience/midnightearth
  GODOT_BIN="/Applications/Godot 4.6.app/Contents/MacOS/Godot" python3 -I ~/Desktop/bench.py --a tuned --b greedy_v1 --seeds 1-50 --workers 2
  ```

- [ ] **Compare the `digest=` lines.** Equal means the matches are identical. If they differ,
      rerun both with `--keep` and send the orchestrator both `bench-out` folders. It finds
      the first decision that differs. That is an engine bug (a cross-platform determinism
      fault), and the spike stops here.

## 4. How fast are play-outs? (about 1.5 h, mostly waiting)

There's no rollout-from-mid-match entry yet; that's cycle A. A full match from the start is the
longest possible play-out, so it gives an upper bound. `greedy_v1` on both sides is a greedy
rollout policy.

- [ ] **Workers sweep:** 200 seeds each, at 16, 12 and 8 workers. Record games per minute for
      each.

  ```powershell
  foreach ($w in 16, 12, 8) { py -3.14 -I C:\trainer-spike\bench.py --a greedy_v1 --b greedy_v1 --seeds 1-200 --workers $w }
  ```

- [ ] **Throttling:** 30 minutes at the best worker count from the sweep. `bench.py` prints games
      per minute every 5 minutes; compare the first and last. Note the CPU temperature if the
      vendor tool shows it.

  ```powershell
  py -3.14 -I C:\trainer-spike\bench.py --a greedy_v1 --b greedy_v1 --seeds 1-3000 --workers <best> --minutes 30
  ```

- [ ] **Mac, for scale:** the same 200-seed run at 8 workers, so the PC's numbers can be read
      against the 0.34 s per match the architecture estimate is built on.

`C:\trainer-spike\bench.py` (standard library only; run from the repo root):

```python
import argparse, concurrent.futures, hashlib, json, os, shutil, subprocess, tempfile, time
ap = argparse.ArgumentParser()
ap.add_argument("--a", required=True); ap.add_argument("--b", required=True)
ap.add_argument("--seeds", required=True); ap.add_argument("--workers", type=int, default=8)
ap.add_argument("--minutes", type=float, default=0); ap.add_argument("--keep", action="store_true")
args = ap.parse_args()
lo, hi = map(int, args.seeds.split("-"))
batches = [(s, min(s + 24, hi)) for s in range(lo, hi + 1, 25)]
out = tempfile.mkdtemp(prefix="bench-out-")
godot = os.environ["GODOT_BIN"]
def run(batch):
    f = os.path.join(out, "b-%d-%d.jsonl" % batch)
    subprocess.run([godot, "--headless", "--path", "godot", "-s", "res://tools/bot_worker.gd",
                    "--", "--a=" + args.a, "--b=" + args.b, "--seeds=%d-%d" % batch,
                    "--decks=seeded", "--out=" + os.path.abspath(f), "--label=bench"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return f
t0 = time.time(); games = 0; last = t0; files = []
with concurrent.futures.ThreadPoolExecutor(args.workers) as ex:
    futs = [ex.submit(run, b) for b in batches]
    for fut in concurrent.futures.as_completed(futs):
        files.append(fut.result())
        games += sum(1 for l in open(files[-1]) if '"t":"g"' in l)
        if time.time() - last > 300:
            last = time.time(); print("  %.0f min: %.1f games/min" % ((last - t0) / 60, games / (last - t0) * 60), flush=True)
        if args.minutes and time.time() - t0 > args.minutes * 60:
            for f2 in futs: f2.cancel()
            break
wall = time.time() - t0
h = hashlib.sha256()
for f in sorted(files, key=lambda p: int(os.path.basename(p).split("-")[1])):
    for line in open(f):
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("t") == "g": h.update(json.dumps(r, sort_keys=True).encode())
        elif r.get("t") == "d": h.update(json.dumps([r["seed"], r["game"], r["seat"], r["action"]], sort_keys=True).encode())
        elif r.get("t") == "end" and (r.get("rejected") or r.get("replay_mismatches")): print("  WARNING end record:", r)
print("bench: a=%s b=%s seeds=%s workers=%d games=%d minutes=%.1f games_per_min=%.1f digest=%s"
      % (args.a, args.b, args.seeds, args.workers, games, wall / 60, games / wall * 60, h.hexdigest()[:16]))
if args.keep: print("  kept", out)
else: shutil.rmtree(out, ignore_errors=True)
```

## 5. Which model, and how fast? (about 2 h)

- [ ] **Install llama.cpp:** from the llama.cpp GitHub releases, download the newest
      `llama-<build>-bin-win-cuda-12.x-x64.zip` and the matching `cudart-llama-bin-win-cuda-12.x-x64.zip`.
      Unzip both into `C:\llama\`. Check:

  ```powershell
  C:\llama\llama-cli.exe --version; C:\llama\llama-cli.exe --list-devices
  ```

  The RTX 3070 must be listed.
- [ ] **Download 2–3 GGUF models at Q4_K_M,** each about 5–7 GB, from Hugging Face into
      `C:\models\`. Check the current names on Hugging Face first. Candidates:
      - a Qwen ~8–9B instruct (the current Qwen3 / Qwen3.5 build)
      - a Llama 3.x 8B instruct
      - a Gemma ~9–12B instruct. A 12B only fits with a smaller context, so try it last.
- [ ] **Raw speed:** prompt processing at 2,048 tokens and generation of 256 tokens, with every
      layer on the GPU.

  ```powershell
  C:\llama\llama-bench.exe -m C:\models\<model>.gguf -ngl 99 -p 2048 -n 256
  ```

  Record `pp2048` and `tg256` in tokens per second, and the VRAM in use (`nvidia-smi`).
- [ ] **Parallel serving:** start the server with 4 slots and a 16k context shared between
      them.

  ```powershell
  C:\llama\llama-server.exe -m C:\models\<model>.gguf -ngl 99 -c 16384 -np 4 --host 127.0.0.1 --port 8080
  ```

  Then run `C:\trainer-spike\llm_load.py` (below) to time 40 requests at 4 at a time. Record
  the aggregate tokens per second and the median seconds per request.
- [ ] **Play-outs and LLM together:** run `bench.py` at the best worker count (step 4) while
      `llm_load.py` loops. Record the play-out games per minute and the LLM tokens per second.
      How much each one drops is the number that matters.
- [ ] **A plan proposal, by eye:** send one real prompt per model (the orchestrator writes it
      from the rules, the two decklists and one position from a step 3 game kept with `--keep`) and paste back
      the replies. This only checks that the model returns valid JSON plans and isn't
      nonsense; the real model choice comes from play-out scores in cycle C.

`C:\trainer-spike\llm_load.py` (standard library only):

```python
import json, time, urllib.request, concurrent.futures, statistics
URL = "http://127.0.0.1:8080/v1/chat/completions"
PROMPT = "You operate a card-game deck. " * 120 + "Propose two plans as JSON."
def one(_):
    body = json.dumps({"messages": [{"role": "user", "content": PROMPT}],
                       "max_tokens": 256, "temperature": 0.7}).encode()
    t = time.time()
    req = urllib.request.Request(URL, body, {"Content-Type": "application/json"})
    out = json.load(urllib.request.urlopen(req))
    return time.time() - t, out["usage"]["completion_tokens"]
t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(4) as ex:
    res = list(ex.map(one, range(40)))
wall = time.time() - t0
print("median s/request %.2f  aggregate tok/s %.1f"
      % (statistics.median(r[0] for r in res), sum(r[1] for r in res) / wall))
```

## 6. Can the Mac reach MCP on the PC? (about 30 min)

- [ ] **PC:** install the MCP Python SDK in a spike virtual environment.

  ```powershell
  cd C:\trainer-spike; py -3.14 -m venv venv; .\venv\Scripts\pip install "mcp[cli]"
  ```

- [ ] **PC:** save `C:\trainer-spike\health_server.py`:

  ```python
  import os, platform, shutil, subprocess
  from mcp.server.fastmcp import FastMCP
  mcp = FastMCP("bot-trainer-spike", host="0.0.0.0", port=8765)
  @mcp.tool()
  def health() -> dict:
      """Spike health check: host, Python, Godot, GPU, free disk."""
      godot = subprocess.run([os.environ["GODOT_BIN"], "--version"],
                             capture_output=True, text=True).stdout.strip()
      gpu = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.used,memory.total",
                            "--format=csv,noheader"], capture_output=True, text=True).stdout.strip()
      return {"host": platform.node(), "python": platform.python_version(), "godot": godot,
              "gpu": gpu, "free_gb": shutil.disk_usage("C:\\").free // 2**30}
  if __name__ == "__main__":
      mcp.run(transport="streamable-http")
  ```

  Run it with `.\venv\Scripts\python health_server.py`.
- [ ] **PC:** allow the port from the Mac only, on the Private profile. Run this in an
      administrator PowerShell. The spike has no token, so this firewall rule is its only
      lock; cycle A adds the bearer token.

  ```powershell
  New-NetFirewallRule -DisplayName "bot-trainer-spike" -Direction Inbound -Protocol TCP -LocalPort 8765 -RemoteAddress <MAC_IP> -Profile Private -Action Allow
  ```

  Check that the Wi-Fi or Ethernet network is set to Private.
- [ ] **Mac:** add it for this machine only, outside the repo's `.mcp.json`, then start a new
      Claude Code session and ask it to call `health`.

  ```bash
  claude mcp add --transport http --scope local bot-trainer-spike http://<PC_IP>:8765/mcp
  ```

  Record the reply and the round-trip time.
- [ ] **Clean up at the end of the spike:** remove the firewall rule
      (`Remove-NetFirewallRule -DisplayName "bot-trainer-spike"`) and the Mac entry
      (`claude mcp remove bot-trainer-spike`).

## Results (fill in)

| # | Measure | Result |
|---|---|---|
| 1 | Commit on the PC = Mac `master`? | |
| 2 | Import / boot (`Main ready`) / gate tests (`Statistics:`) | |
| 2 | Sweep `p99_us=` and `stamp=` on the PC | |
| 2 | `driver.py selftest` on Windows | |
| 3 | `digest=` on the PC and on the Mac, equal? | |
| 4 | Games per minute at 16 / 12 / 8 workers (and the Mac at 8) | |
| 4 | First vs last 5 min of the 30-min run (throttling) | |
| 5 | Each model: `pp2048`, `tg256`, VRAM used | |
| 5 | Server with 4 slots: aggregate tok/s, median s/request | |
| 5 | Play-outs + LLM together: games/min and tok/s, each vs alone | |
| 5 | Plan JSON valid and sensible? (each model) | |
| 6 | MCP `health` from the Mac: reply and round trip | |
| — | Driver version, CUDA version, peak CPU temperature | |

## Go / no-go for `/spec` cycle A

- **Go** when steps 2, 3 and 6 pass. Slow numbers in steps 4 or 5 change the sizing, not the plan.
- **Stop and fix first** when step 3 finds any mismatch (an engine determinism bug), or step 2
  can't import or boot on Windows.
- **Revisit T1** (native Windows) only if step 2's Python driver needs heavy changes and the
  play-out throughput is still poor after them.

From the results, the orchestrator updates [[planning/bot-trainer-architecture]]:
- throughput and labels per night;
- the worker count;
- the chosen model and how many slots it gets;
- anything Windows-specific cycle A has to fix.

## Related

- [[planning/bot-trainer-architecture]]: the design these numbers feed
- [[systems/bot-training]]: the driver, the sweep and the gates exercised here
- [[planning/planning-moc]]
