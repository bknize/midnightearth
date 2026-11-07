---
type: planning
tags: [planning, bot, training, llm, spike, windows, ssh]
status: growing
related: ["[[planning/bot-trainer-architecture]]", "[[planning/planning-moc]]", "[[systems/bot-training]]"]
created: 2026-11-06
updated: 2026-11-07
uid: 6ff633e9-bfe0-48b8-af55-206e04d5aa3b
linear:
supersedes:
---

# Bot trainer spike: a one-day checklist for the Windows PC

> Ben's short admin session at the training PC, then the orchestrator's runbook over SSH from the Mac. Together they replace the estimates in [[planning/bot-trainer-architecture]] with measured numbers before `/spec` for cycle A.

**The spike answers five questions:**

1. Does the project run headless on native Windows (T1)?
2. Do the PC's matches come out exactly the same as the Mac's?
3. How fast are match-length play-outs, and how many workers does the PC sustain?
4. Which ~8–9B model runs fast enough on the RTX 3070, and does it slow the play-outs down?
5. Can the Mac reach an MCP server on the PC across the LAN?

**Who does what (T7).** Ben does Part A at the PC, as an administrator: about 20 minutes, and
everything that needs admin rights or a person in the room. The orchestrator then does Part B
from the Mac, over SSH, as the non-admin Windows account `trainer`. No step in Part B needs
admin rights. Downloads in Part B are listed with sources and sizes, and Ben approves them in
chat first.

**Nothing from the spike is committed as code.** The throwaway scripts live in
`C:\Users\trainer\spike\` on the PC. The results go into the table at the end, and the
orchestrator copies them into the architecture note.

Paths used below, all under the `trainer` profile:

| Name | Path |
|---|---|
| Spike folder | `C:\Users\trainer\spike\` (logs in `spike\logs\`) |
| Repo clone | `C:\Users\trainer\spike\midnightearth\` |
| Godot | `C:\Users\trainer\tools\godot\Godot_v4.6.3-stable_win64_console.exe` |
| Python | `C:\Users\trainer\tools\python314\tools\python.exe` (NuGet package, no installer) |
| llama.cpp | `C:\Users\trainer\tools\llama\` |
| Models | `C:\Users\trainer\models\` |

## Part A: Ben at the PC (admin, about 20 min)

Run everything in **one administrator PowerShell window**, in order.

- [ ] **A1. Plug in the charger, use the vendor's performance mode** (Eluktronics Control Center),
      and keep the vents clear.
- [ ] **A2. Create the `trainer` account.** Use a strong password and keep it in your password
      manager. Nobody needs it day to day, because SSH uses the key. Then sign the account in
      once with no window, so Windows creates its profile folder.

  ```powershell
  $pw = Read-Host -AsSecureString "Password for trainer"
  New-LocalUser -Name trainer -Password $pw -PasswordNeverExpires -AccountNeverExpires -Description "Bot trainer (SSH only)"
  Start-Process cmd.exe -ArgumentList '/c exit' -Credential (New-Object pscredential('trainer', $pw)) -LoadUserProfile -Wait
  Test-Path C:\Users\trainer   # must print True
  ```

- [ ] **A3. Install the SSH server,** make PowerShell its default shell, and start it
      automatically.

  ```powershell
  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
  New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
  Set-Service sshd -StartupType Automatic; Start-Service sshd
  ```

- [ ] **A4. Key login only, and only for `trainer`.** This turns passwords off and inserts
      `AllowUsers trainer` before any `Match` block (sshd refuses it inside one). Then it tests
      the config and restarts the server.

  ```powershell
  $c = "$env:ProgramData\ssh\sshd_config"
  $lines = @(Get-Content $c) -replace '^#?\s*PasswordAuthentication\s.*', 'PasswordAuthentication no'
  $m = 0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^Match\s' } | Select-Object -First 1
  if ($null -eq $m) { $lines += 'AllowUsers trainer' } else { $lines = $lines[0..($m - 1)] + 'AllowUsers trainer' + $lines[$m..($lines.Count - 1)] }
  Set-Content -Path $c -Value $lines -Encoding ascii
  & "$env:WINDIR\System32\OpenSSH\sshd.exe" -t; if ($LASTEXITCODE -eq 0) { Restart-Service sshd; "sshd ok" }
  ```

- [ ] **A5. Install the Mac's public key** for `trainer`, readable only by `trainer`, SYSTEM and
      Administrators. This is a public key, so it's safe to paste.

  ```powershell
  $d = 'C:\Users\trainer\.ssh'; New-Item -ItemType Directory -Force $d | Out-Null
  Set-Content -Path "$d\authorized_keys" -Encoding ascii -Value 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINQCIx6Dw59pXW/P5Rt9KT5tA0czoAclMdaNOkewPJdP midnightearth-mac-to-pc'
  icacls "$d\authorized_keys" /inheritance:r /grant 'trainer:F' /grant 'SYSTEM:F' /grant 'Administrators:F'
  icacls "$d\authorized_keys" /setowner trainer
  ```

- [ ] **A6. Firewall: the network must be Private.** Then open SSH (22) and the spike's MCP
      port (8765) to the Mac only (192.168.68.52).

  ```powershell
  Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory
  # If it says Public:  Set-NetConnectionProfile -InterfaceAlias "<alias>" -NetworkCategory Private
  New-NetFirewallRule -DisplayName "ssh-from-mac" -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 192.168.68.52 -Profile Private -Action Allow
  New-NetFirewallRule -DisplayName "bot-trainer-mcp-from-mac" -Direction Inbound -Protocol TCP -LocalPort 8765 -RemoteAddress 192.168.68.52 -Profile Private -Action Allow
  ```

- [ ] **A7. Stop sleep and lid-close actions** (the Nov 5 run was killed from outside), and
      pause Windows Update (Settings → Windows Update → Pause updates). Set Active hours to cover
      overnight runs.

  ```powershell
  powercfg /change standby-timeout-ac 0
  powercfg /change hibernate-timeout-ac 0
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
  ```

- [ ] **A8. Install Git for Windows** for all users (it includes Git LFS) with the defaults, and
      **update the NVIDIA driver** (current Studio or Game Ready). Check both: `git --version`
      and `nvidia-smi`.
- [ ] **A9. Router:** add DHCP reservations for the PC and for the Mac. The Mac must keep
      192.168.68.52, or the firewall rules stop matching.
- [x] **A10. Send the orchestrator the PC's address:**
      `(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "<alias>").IPAddress`.
      Done 2026-11-06: **192.168.68.63** (Wi-Fi 2).
- [x] **A11. The job runner** (added after B0 showed SSH can't start long jobs; see B0). First
      give `trainer` the "Log on as a batch job" right, then register the `trainer-runner` task.
      Windows 10 Home has no Local Security Policy window, and `secedit /configure` failed twice
      (a SID needs a leading `*`, and the second file wouldn't open). Use the account-rights
      function directly, `LsaAddAccountRights`, through a small `Add-Type` block that calls
      `[LsaRights]::Grant('<trainer SID>', 'SeBatchLogonRight')` and prints `0` on success.
      The code is in this session's transcript; cycle A turns it into a script. Then:

  ```powershell
  $cred = Get-Credential trainer
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Users\trainer\spike\runner.ps1'
  $t = New-ScheduledTaskTrigger -AtStartup
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Days 365) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName trainer-runner -Action $a -Trigger $t -Settings $s -User trainer -Password $cred.GetNetworkCredential().Password -RunLevel Limited
  Start-ScheduledTask trainer-runner
  ```

  Without the batch-logon right, the task fails at logon with error `2147943785` (0x80070569,
  logon type not granted). Windows only reports it in the Task Scheduler history log, which is
  off by default (`wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true`).
  The runner checks `spike\queue\` every 5 s and starts each `.cmd` it finds, logging output to
  `spike\logs\<name>.log`.

**Part A gotchas met on 2026-11-06:**
- `New-LocalUser` says "access denied" in a PowerShell window that isn't elevated, and a retry
  then reports "already exists". Use **Run as administrator**, and set the password with
  `Set-LocalUser` if the account already exists.
- The Wi-Fi came up as **Public**, so the Private-profile firewall rules didn't apply and SSH
  timed out, even though the PC answered ping. Fix: `Set-NetConnectionProfile -NetworkCategory Private`.
- `Add-WindowsCapability` for the OpenSSH server took several minutes. Leave Windows Update
  unpaused until it finishes.

## Part B: the orchestrator over SSH

### B0. Connect and run long jobs (done 2026-11-06)

- [x] **Mac:** `~/.ssh/config` has `Host midnight-pc`: HostName 192.168.68.63, User trainer,
      IdentityFile `~/.ssh/midnight_pc`, IdentitiesOnly yes, ServerAliveInterval 30.
      `whoami` prints `desktop-q7m5vjd\trainer`, and `trainer` is not in Administrators.
      Windows' SSH server doesn't offer post-quantum key exchange, so every connection prints a
      warning. It's harmless on the LAN.
- [x] **Long jobs:** Windows OpenSSH ends every process a session started when the session
      closes (verified: a background writer stopped at disconnect). A standard user's network
      logon is also refused by WMI (`Win32_Process.Create`, "Access denied") and can't create
      scheduled tasks. So long jobs go through the **runner** (A11): drop a `.cmd` file into
      `spike\queue\`. Verified: a 30 s job queued over SSH ran to the end after the disconnect,
      and `nvidia-smi` worked from the runner's session.

### B1. Tools, as `trainer` (done 2026-11-06; downloads approved by Ben)

| Download | Source | Size | SHA-256 (first 16) |
|---|---|---|---|
| Python 3.14.10, NuGet package `python` | nuget.org (Python Software Foundation) | 14.9 MB | `F54BA67C9951C3D7` |
| Python 3.14.10 installer (unused, see below) | python.org | 32 MB | `92480239264744FE` |
| `Godot_v4.6.3-stable_win64.exe.zip` | GitHub godotengine/godot, tag `4.6.3-stable` | 76 MB | `E39986A178D585CE` |
| `llama-b12180-bin-win-cuda-12.4-x64.zip` | GitHub ggml-org/llama.cpp, tag `b12180` | 275 MB | `3C5308A2C2FE8388` |
| `cudart-llama-bin-win-cuda-12.4-x64.zip` | same | 373 MB | `8C79A9B226DE4B3C` |
| `mcp` 2.3.0, `huggingface_hub` 2.4.0 into `spike\venv` | PyPI | — | — |

- [x] **Python:** the python.org installer exits with **1601** (Windows Installer can't be
      reached) for a non-admin account, from SSH and from the runner alike. Use the NuGet package
      instead: unzip it to `tools\python314\`, which gives `tools\python314\tools\python.exe`.
      `venv`, `ensurepip` and pip all work.
- [x] **Godot:** `tools\godot\Godot_v4.6.3-stable_win64_console.exe` prints
      `4.6.3.stable.official.7d41c59c4`. `GODOT_BIN` is set for `trainer` with `setx`.
- [x] **llama.cpp b12180** (it reports `0.9.0-dev`) in `tools\llama\`, the CUDA **12.4** build,
      because the NVIDIA driver is 566.36 and the CUDA 13.5 builds need a newer one. From SSH
      and from the runner, `--list-devices` shows
      `CUDA0: NVIDIA GeForce RTX 3070 Laptop GPU (8191 MiB, 7118 MiB free)`.
      Note: GitHub's "latest release" for llama.cpp is now a tag with no binaries. Pick the newest
      `bNNNNN` pre-release.
- [x] **venv** at `spike\venv` with `mcp[cli]` and `huggingface_hub`.
- **Quoting:** Windows PowerShell 5.1 mangles double quotes inside arguments to native programs
  (`python -c "…"`). Put code in a file instead of passing it inline.

### B2. Code onto the PC as a bundle (about 10 min)

**Done 2026-11-07** on `master` `bee0500` (rules version 7, after the DC-13 and DC-14 merge). The bundle is 2.2 MB; the clone is clean.

This is a manual version of `sync_code` (T2). Nothing is pushed.

- [ ] **Mac:** `git bundle create` of `master`, then `scp` it to `midnight-pc:spike/midnightearth.bundle`.
- [ ] **PC:** `$env:GIT_LFS_SKIP_SMUDGE="1"; git clone spike\midnightearth.bundle spike\midnightearth`.
      Art isn't needed headless, and the bundle holds only LFS pointers. The commit must match
      the Mac's `master`.

### B3. Does it run headless on Windows? (about 30 min)

**Done 2026-11-07, all pass.** Import 15 s; boot 2 s with `Main ready`; every gate suite PASSED (43 s). The only error lines are Godot's exit-time leak report ("138 resources still in use at exit" and two PagedAllocator lines), which the Mac gate tolerates too. The 50-seed sweep PASSED (41 s). Its 33 summary and pairing lines are **identical to the Mac's once timing fields are removed**. The PC's p99 is 2,042 µs against the Mac's 1,190 µs, with the random bot. The driver selftest was skipped: DC-13 left `scripts/bot/` driving nothing.

From `spike\midnightearth\godot`, the same commands `scripts/check.sh` runs, each logged and
searched for `SCRIPT ERROR|Parse Error|Failed to load script|ERROR:`:

- [ ] **Import:** `--headless --path . --import`
- [ ] **Boot:** `--headless --path . --quit-after 120 -- --seed=1`. The output must contain
      `Main ready`.
- [ ] **Gate tests:** `-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue --add res://tests --ignore res://tests/sweep`.
      Exit 0 or 101 passes. Note the `Statistics:` line.
- [ ] **50-seed sweep:** the same, with `--add res://tests/sweep`. Note `p99_us=` and `stamp=`.
      This p99 is for information only; the 10 ms rule is judged on the Mac.
- [ ] **Driver selftest:** `python -I scripts\bot\driver.py selftest`. Any path or POSIX failure
      becomes cycle A work.

### B4. Same seeds, same matches? (about 20 min)

**Done 2026-11-07: identical.** DC-13 deleted `godot/tools/bot_worker.gd`, so `bench.py` below no longer runs. The spike used a throwaway `godot/tools/spike_bench.gd`, untracked and copied into both clones (the Mac's is a scratch worktree of `bee0500`). It plays random vs random on each seed's own pairing, with no scans, and records SHA-256 of the full action log and of the final `full_state()`. A driver, `bench2.py`, hashes those records. Seeds 1–50 gave `c3b954706528fc4b` and seeds 1–400 gave `e5f48322e7e3b68d` on **both** machines, at every worker count. Seed 1 is combo vs graveyard in 265 actions, the same as the gate's golden pin.

The PC's labels are only worth anything if a match played there replays exactly the same on
the Mac. `bench.py` (below) runs the bot worker directly over a seed range, on N workers at once.
It prints games per minute and a SHA-256 **digest** of every game record and every decision's
action, with timings left out. It calls the worker directly, not `driver.py eval`, because the
eval's SPRT can stop early, and then the two machines wouldn't play the same seeds.

Verified on the Mac 2026-11-06: seeds 1–4, tuned vs `greedy_v1`, gave the same digest
(`ddebd095c9686a8c`) at 1 and 2 workers.

- [ ] **Both machines,** from the repo root:
      `python -I <bench.py> --a tuned --b greedy_v1 --seeds 1-50 --workers 2`.
- [ ] **The `digest=` lines must be equal.** If they differ, rerun with `--keep`, copy both
      outputs to the Mac, and find the first decision that differs. That is an engine bug (a
      cross-platform determinism fault), and the spike stops there.

### B5. How fast are play-outs? (about 1.5 h, detached)

**Measured 2026-11-07** with `spike_bench.gd` (random vs random, full matches, about 146 actions each, batches of 25 per Godot process):

| Machine | Workers | Matches per minute | Seconds per match per worker |
|---|---|---|---|
| PC | 16 | 1,246 | 0.77 |
| PC | 12 | 1,083 | 0.67 |
| PC | 8 | 1,040 | 0.46 |
| Mac (M3) | 8 | 1,783 | 0.27 |

The PC does about 70% of the Mac's throughput. SMT threads 9–16 add only about 20%. Rules v2 matches are longer than v6's (about 146 actions against 82 decisions), so the architecture's per-rollout costs need re-estimating (see the architecture note's 2026-11-07 section). Throttling run: see the results table.

There's no rollout-from-mid-match entry yet; that's cycle A. A full match from the start is the
longest possible play-out, so it gives an upper bound. `greedy_v1` on both sides is a greedy
rollout policy. All of these are queued on the runner (`spike\queue\*.cmd`).

- [ ] **Workers sweep:** `--seeds 1-200` at 16, 12 and 8 workers. Record games per minute for each.
- [ ] **Throttling:** 30 minutes at the best worker count (`--seeds 1-3000 --minutes 30`).
      `bench.py` prints games per minute every 5 minutes; compare the first and last.
- [ ] **Mac, for scale:** the same 200-seed run at 8 workers.

`C:\Users\trainer\spike\bench.py` (standard library only; run from the repo root):

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

### B6. Which model, and how fast? (about 2 h)

**Done 2026-11-07 with one model (Ben chose b: Qwen only).** `unsloth/Qwen3.5-9B-GGUF`,
file `Qwen3.5-9B-Q4_K_M.gguf`, 5,680,522,464 bytes, SHA-256
`03B74727A860A56338E042C4420BB3F04B2FEC5734175F4CB9FA853DAF52B7E8` (matches Hugging Face),
in `C:\Users\trainer\models\`. Downloaded with `curl.exe` through the runner, not `hf download`.
Ministral-3-8B-Instruct-2512 (5.20 GB) and gemma-4-12b-it at Q3_K_M (5.69 GB) were the other
candidates and stay untested; Gemma 4 12B at Q4_K_M (7.12 GB) leaves no room for four slots.

- **The server line in the checklist below is wrong for 8 GB.** `-ngl 99 -c 65536 -np 4` with an
  f16 cache overflows the card (7.85 GB used); Windows then pages into shared memory and every
  slot crawls at about 7 tok/s (24 tok/s aggregate). The working line is
  `llama-server.exe -m <model> -c 40960 -np 4 -fa on -ctk q8_0 -ctv q8_0 --jinja`
  (10k tokens a slot, 7.0 GB). Swept: 64k q8 cache 47 tok/s; 40k f16 cache 63 tok/s; 40k q8
  cache 107 tok/s with or without `-ngl 99`.
- **Thinking off.** Qwen3.5 thinks by default. `chat_template_kwargs: {enable_thinking: false}`
  per request. With thinking on, the plan prompt spent 8,000 tokens (158 s) reasoning and never
  answered.
- **The plan prompt** is 8,952 tokens: rules-v2, the card-table key, the Combo and Graveyard
  sections of cards-v2 (with their R62 plans), the six Crew rows, the plan language, and the
  Combo seat's view at Round 2, Turn 1 of seed 1 (a throwaway `spike_position.gd` dumps it). The
  reply is constrained to a JSON schema. Two slots of 20k for this test.
- **For cycle C:** one schema per plan term (`oneOf`, no shared filler fields); reject any plan
  that names a card outside the seat's hand, Deck or Crew, or that holds and pairs the same card;
  and trim the prompt so it fits a 10k slot with room for the reply (rules digest, not the full
  rules note). At about 1,000 tokens a reply and 107 tok/s, the PC proposes roughly 6 plan sets a
  minute, or 350 an hour, alongside the play-out farm. Play-out scores, not reading, decide
  whether the plans are any good.

- [ ] **Download 2–3 GGUF models at Q4_K_M** with `hf download` into `models\`. Candidates: a
      Qwen ~8–9B instruct (the current Qwen3 / Qwen3.5 build), a Llama 3.x 8B instruct, and a
      Gemma ~9–12B instruct, which needs a smaller context. Confirm the exact repos on Hugging
      Face, and get Ben's approval of the list, before downloading.
- [ ] **Raw speed:** `llama-bench.exe -m <model> -ngl 99 -p 2048 -n 256`. Record `pp2048`, `tg256`,
      and the VRAM in use (`nvidia-smi`).
- [ ] **Parallel serving:** start `llama-server.exe -m <model> -ngl 99 -c 16384 -np 4 --host 127.0.0.1 --port 8080`
      detached, then run `llm_load.py` (below). Record the aggregate tokens per second and the
      median seconds per request.
- [ ] **Play-outs and LLM together:** `bench.py` at the best worker count while `llm_load.py`
      loops. Record how much each one drops.
- [ ] **A plan proposal, by eye:** one real prompt per model (the rules, the two decklists and one
      position from a B4 game kept with `--keep`). This only checks that the JSON plans are valid
      and sensible; the real model choice comes from play-out scores in cycle C.

`C:\Users\trainer\spike\llm_load.py` (standard library only):

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

### B7. Can the Mac reach MCP on the PC? (about 20 min)

**Done 2026-11-07: pass.** The venv has `mcp` 2.3.0, where `FastMCP` is now `MCPServer`
(`mcp.server.mcpserver`) and host and port move to `run()`; the script below is the 2.x
version (the 1.x one failed to import). Started through the runner. From the Mac, a raw
streamable-HTTP session (`initialize`, `tools/list`, `tools/call health`) answered `health` in
0.67 s cold and 0.37–0.39 s warm (the call shells out to Godot and `nvidia-smi`); a `ping`
round trip is 17 ms. `claude mcp add --scope local` then `claude mcp get` reported
**Connected**; the entry was removed again and the server stopped. The 8765 firewall rule stays.
Cycle A pins `mcp>=2.3,<3` and adds the bearer token.

- [ ] **PC:** save `spike\health_server.py` (below) and start it detached from the venv. It
      listens on 8765, which only the Mac can reach (A6). The spike has no token, so that
      firewall rule is its only lock; cycle A adds the bearer token.
- [ ] **Mac:** add it for this machine only, outside the repo's `.mcp.json`:
      `claude mcp add --transport http --scope local bot-trainer-spike http://<PC_IP>:8765/mcp`.
      Then, in a new session, call `health`. Record the reply and the round-trip time.
- [ ] **Clean up:** stop the server, `claude mcp remove bot-trainer-spike`. Keep the 8765 firewall
      rule for cycle A's server.

`C:\Users\trainer\spike\health_server.py`:

```python
import os, platform, shutil, subprocess
from mcp.server.mcpserver import MCPServer
mcp = MCPServer("bot-trainer-spike")
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
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8765)
```

## Results (fill in)

| # | Measure | Result |
|---|---|---|
| A/B0 | SSH as `trainer` works, `trainer` not an admin, the detached job survives a disconnect | **Pass** (2026-11-06): SSH as `desktop-q7m5vjd\trainer`, not an admin; long jobs through the `trainer-runner` task; CUDA visible from the runner |
| B2 | Commit on the PC = Mac `master`? | **Pass**: `bee0500` (rules version 7) |
| B3 | Import / boot (`Main ready`) / gate tests (`Statistics:`) | **Pass**: 15 s / 2 s / all suites PASSED |
| B3 | Sweep `p99_us=` and `stamp=` on the PC | **Pass**: p99 2,042 µs (Mac 1,190); no stamp any more (DC-13); counters identical to the Mac |
| B3 | `driver.py selftest` on Windows | Skipped: the bot tooling drives nothing after DC-13 |
| B4 | `digest=` on the PC and on the Mac, equal? | **Pass**: `c3b954706528fc4b` (1–50), `e5f48322e7e3b68d` (1–400) on both |
| B5 | Games per minute at 16 / 12 / 8 workers (and the Mac at 8) | 1,246 / 1,083 / 1,040 (Mac 1,783), random vs random, full matches |
| B5 | First vs last 5 min of the 30-min run (throttling) | **No throttling**: 45,000 matches in 30.75 min at 16 workers (batches of 100), 0 failures, 1,464 a minute overall. The running average rose from 1,308 (first 5 min, including startup) to 1,489, so the last 5 min ran at about 1,525 a minute. Bigger batches cut the per-process startup cost (1,246 a minute with batches of 25). |
| B6 | Each model: `pp2048`, `tg256`, VRAM used | Qwen3.5-9B Q4_K_M: pp2048 1,922 tok/s, tg256 59.8 tok/s; 7.0 GB with the 4-slot server |
| B6 | Server with 4 slots: aggregate tok/s, median s/request | 107 tok/s, 8.9 s (855-token prompt, 256 out), at `-c 40960 -fa on -ctk q8_0 -ctv q8_0`. The checklist's f16 cache overflowed VRAM: 24 tok/s |
| B6 | Play-outs + LLM together: games/min and tok/s, each vs alone | 16 workers: 1,172 → 940 games/min (−20%), LLM 107 → 74 tok/s (−31%). 12 workers: 1,177 → 892, LLM 81–105. Digest `7ae72eeb21c8d00d` (seeds 1–2000) unchanged by the load. GPU peaked at 80 °C |
| B6 | Plan JSON valid and sensible? (each model) | **Valid, half sensible.** 18–28 s a reply, three plans each, always schema-valid. It reads the deck's R62 plan (hold Encore and Finale for the late Turns, Wick and Twin early, Shade to re-reveal) but misreads details: holds a card it also pairs, calls Reverb a 6/5, says Shade "checks the board", and fills required fields with filler (`n`, `mode`, `cards: ["4"]`). Thinking on: no answer in 8,000 tokens |
| B7 | MCP `health` from the Mac: reply and round trip | **Pass**: host DESKTOP-Q7M5VJD, Python 3.14.10, Godot 4.6.3, RTX 3070 Laptop 863/8192 MiB, 116 GB free; 0.37–0.67 s a call, 17 ms ping; Claude Code reports Connected |
| B1 | Tools installed | **Pass**: Python 3.14.10 (NuGet), Godot 4.6.3, llama.cpp b12180 CUDA 12.4, mcp 2.3.0, huggingface_hub 2.4.0 |
| — | Driver version, CUDA version, peak CPU temperature | Driver 566.36 (CUDA 12.x; not updated in A8), 136 GB free on C:; temperature pending |

## Go / no-go for `/spec` cycle A

**Verdict 2026-11-07: Go.** B0, B3, B4 and B7 pass; B5 and B6 set the sizing (about 1,500 matches a
minute alone, 940 beside the LLM; Qwen3.5-9B at 107 tok/s on four 10k slots).

- **Go** when B0, B3, B4 and B7 pass. Slow numbers in B5 or B6 change the sizing, not the plan.
- **Stop and fix first** when B4 finds any mismatch (an engine determinism bug), or B3 can't
  import or boot on Windows.
- **Revisit T1** (native Windows) only if the Python driver needs heavy changes and the
  play-out throughput is still poor after them.

From the results, the orchestrator updates [[planning/bot-trainer-architecture]]:
- throughput and labels per night;
- the worker count;
- the chosen model and how many slots it gets;
- anything Windows-specific cycle A has to fix.

## Related

- [[planning/bot-trainer-architecture]]: the design these numbers feed (T7, T8 for access)
- [[systems/bot-training]]: the driver, the sweep and the gates exercised here
- [[planning/planning-moc]]
