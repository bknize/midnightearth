# Setting up the training PC

The PC is Windows 10 Home with a non-admin account `trainer`, reached by OpenSSH from the Mac
(default shell: PowerShell 5.1). A non-admin SSH session cannot change scheduled tasks, and
every process it starts dies when the session closes, so long-lived work goes through the
`trainer-runner` scheduled task and the runner in this folder (spec cycle 11, C11).

PowerShell 5.1 mangles quotes passed to native programs: never use inline `python -c`. Put
logic in files.

Below, `PC` is `trainer@192.168.68.63` and every command is typed on the Mac from the
repository root, unless it starts with `ssh`, in which case the quoted part runs on the PC.

## Part 1. Over SSH as `trainer` (no admin; the current PC)

Layout on the PC: `C:\Users\trainer\trainer\` (runner, `queue\`, `autostart\`, `logs\`),
`C:\Users\trainer\me\` (`repo`, `work`, `inbox`, `venv`, `logs`), `C:\Users\trainer\.trainer\token`,
and `C:\Users\trainer\trainer-data\`, the run store the service creates itself (`TRAINER_DATA`
overrides it): `trainer.db` (runs, positions, labels, fits), `runs\<id>\` (the label shards and
`report.json` of each run), `fits\<id>\` (each fit's `linear_weights.json` and `report.json`),
`logs\` and `serve.lock`. Back it up before wiping the PC; `sync_code` never touches it.

1. Create the folders.

   ```sh
   ssh PC 'New-Item -ItemType Directory -Force C:\Users\trainer\trainer\queue, C:\Users\trainer\trainer\autostart, C:\Users\trainer\trainer\logs, C:\Users\trainer\me\inbox, C:\Users\trainer\me\logs, C:\Users\trainer\.trainer | Out-Null'
   ```

2. Copy the Windows files to their stable place (the runner gets refreshed from the worktree
   by `sync_code` later; this is the first copy).

   ```sh
   scp trainer/windows/runner.ps1 trainer/windows/swap-runner.ps1 PC:C:/Users/trainer/trainer/
   scp trainer/windows/runner-shim.ps1 PC:C:/Users/trainer/trainer/runner-shim.ps1
   scp trainer/windows/start-mcp.cmd PC:C:/Users/trainer/trainer/autostart/start-mcp.cmd
   ```

3. Venv from the NuGet Python (the MSI installer needs admin), with the MCP SDK and numpy
   (the learner's only dependency; `health` shows its version, `none` when it is missing).

   ```sh
   ssh PC 'C:\Users\trainer\tools\python314\tools\python.exe -m venv C:\Users\trainer\me\venv'
   ssh PC 'C:\Users\trainer\me\venv\Scripts\python.exe -m pip install "mcp>=2.3,<3"'
   ssh PC 'C:\Users\trainer\me\venv\Scripts\python.exe -m pip install "numpy>=1.26,<3"'
   ```

4. First code: make a bundle on the Mac, copy it to the inbox and set up the training
   repository and worktree once by hand (afterwards `sync_code` does this).

   ```sh
   git bundle create /tmp/trainer.bundle <branch>
   scp /tmp/trainer.bundle PC:C:/Users/trainer/me/inbox/first.bundle
   ssh PC '$env:GIT_LFS_SKIP_SMUDGE = "1"; git init --bare C:\Users\trainer\me\repo; git -C C:\Users\trainer\me\repo fetch C:\Users\trainer\me\inbox\first.bundle <branch>; git -C C:\Users\trainer\me\repo worktree add --detach C:\Users\trainer\me\work FETCH_HEAD'
   ssh PC 'C:\Users\trainer\tools\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\Users\trainer\me\work\godot --import'
   ```

5. Token file: 32 random bytes, base64, one line, readable by `trainer` only. Nothing is
   printed.

   ```sh
   scp trainer/windows/make-token.ps1 PC:C:/Users/trainer/.trainer/make-token.ps1
   ```


   Then `ssh PC 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\trainer\.trainer\make-token.ps1'`
   and delete the script. To put the token in the Mac's `.env` as `BOT_TRAINER_TOKEN` without
   echoing it, pipe it straight into the file:
   `ssh PC 'Get-Content C:\Users\trainer\.trainer\token' | sed 's/^/BOT_TRAINER_TOKEN=/' >> .env`.

6. Install the shim over the spike runner (the file the existing task launches) and swap
   the live runner. The old runner runs the swap job, which starts the new runner detached
   and then stops the old one. Running the job twice is harmless: it does nothing when a
   runner already holds `queue\.lock`.

   ```sh
   ssh PC 'Copy-Item C:\Users\trainer\spike\runner.ps1 C:\Users\trainer\spike\runner.ps1.bak -ErrorAction SilentlyContinue; Copy-Item C:\Users\trainer\trainer\runner-shim.ps1 C:\Users\trainer\spike\runner.ps1 -Force'
   scp trainer/windows/swap-runner.cmd PC:C:/Users/trainer/spike/queue/swap-runner.cmd
   ```

   The swap happens within 5 s; look at `C:\Users\trainer\trainer\logs\runner.log` and
   `swap-runner.log` (in `spike\logs\`). The queue now lives in `C:\Users\trainer\trainer\queue\`;
   `spike\queue\` is no longer polled.

7. Start the service now (the runner starts it at every boot from `autostart\`; the script does
   nothing if port 8765 is already listening).

   ```sh
   scp trainer/windows/start-mcp.cmd PC:C:/Users/trainer/trainer/queue/start-mcp.cmd
   ```

   Check `C:\Users\trainer\me\logs\serve.log`. Later code updates come through `sync_code`,
   which also refreshes `C:\Users\trainer\trainer\runner.ps1` (a runner already running keeps
   the old copy until it restarts). A sync that changes `trainer/` replies `restart: scheduled`,
   the service exits with code 75 and the loop in `start-mcp.cmd` starts it on the new code.
   `health` shows `restart_loop: true` when that loop is behind the service; without it a sync
   replies `restart: needed` and the service stays up on the old code.

8. Changing `start-mcp.cmd` on a running PC. `sync_code` never copies it, and cmd.exe re-reads a
   running batch file by byte offset, so the file in `autostart\` cannot be overwritten while the
   service runs from it. With no run active and no training night under way:

   ```sh
   scp trainer/windows/start-mcp.cmd PC:C:/Users/trainer/trainer/start-mcp.new
   scp trainer/windows/swap-start-mcp.cmd PC:C:/Users/trainer/trainer/queue/swap-start-mcp.cmd
   ```

   The runner takes the job within 5 s: it kills the service, moves the new file over the old
   once nothing is reading it and starts the service from it. Check
   `C:\Users\trainer\trainer\logs\` for its log and `health` for `restart_loop: true`.

## Training autopilot

The autopilot (`trainer/autopilot.py`, spec cycle 16) runs the training loop inside the
trainer service: blocks of labelling, fit and judging, with a local LLM proposing each block's
plan. It replaces the night `.cmd` jobs and `spike\night*.py`, which are retired: do not
schedule or run them, and delete any copies still under `C:\Users\trainer\spike\` once the
autopilot has run one block. The data directory below is `C:\Users\trainer\trainer-data\`
(`TRAINER_DATA` overrides it); everything the autopilot writes is under `autopilot\`.

**The LLM config.** Put `autopilot\config.json` there (example:
`trainer/windows/autopilot-config.example.json`; other fields are refused):

| Field | Meaning |
|---|---|
| `server_path` | `llama-server.exe` |
| `model_path` | the `.gguf` model file |
| `host`, `port` | where the server listens; keep `127.0.0.1` and `8080` |
| `server_args` | the `llama-server` arguments; the default is the spike's working line |
| `health_timeout_s` | seconds to wait for `/health` after launch (default 300) |
| `reply_timeout_s` | seconds to wait for the advisor's reply (default 300) |
| `model_name` | label written to the advisor files; defaults to the model file's name |

```sh
ssh PC 'New-Item -ItemType Directory -Force C:\Users\trainer\trainer-data\autopilot | Out-Null'
scp trainer/windows/autopilot-config.example.json PC:C:/Users/trainer/trainer-data/autopilot/config.json
```

Then edit the two paths to match the PC. The autopilot starts and stops the LLM server itself
at block boundaries and never leaves it running: do not start it by hand, and a `llama-server`
still running between blocks is a fault.

**First start.** After `sync_code`, call the MCP tool `autopilot_start` with the start config
(example: `trainer/windows/autopilot-start.example.json`). Its fields:

| Field | Meaning |
|---|---|
| `block_hours` | length of a full block (3.0) |
| `grace_minutes` | extra minutes allowed to finish a stage past the deadline (20) |
| `trial_minutes` | budget of a trial block for one out-of-bounds value (20) |
| `min_positions` | fewest labelled positions worth fitting and judging (300) |
| `plateau_blocks` | blocks without a new champion before the plateau flag is set (6) |
| `disk_floor_gb` | the autopilot starts no work below this much free disk (5) |
| `judge_cap` | pair cap of each judge game set; a capped judgment counts as no change |
| `candidates` | fit ids judged first to seed the champion: F0 `05182ca9d62f` and the fit of DC-21's last round (replace the placeholder) |
| `run_seed_base` | each run's seed is this plus a counter, so no two runs share a seed |

Unknown fields are refused. `autopilot_status` shows the block, stage, deadline and champion.

**Stopping.** Either call the MCP tool `autopilot_stop`, or, with the MCP down, over SSH:

```sh
scp trainer/windows/autopilot-stop.cmd PC:C:/Users/trainer/trainer/autopilot-stop.cmd
ssh PC 'C:\Users\trainer\trainer\autopilot-stop.cmd'
```

Both raise one flag, the file `C:\Users\trainer\trainer-data\autopilot\STOP`. The autopilot
looks for it at safe points (after a labelling batch, between fit and judge, between judge
games), writes the open block's entry marked `interrupted`, clears `running`, removes the file
and stops within 10 minutes. Stop it before `sync_code`, then start it again.

**Restarts.** The service starts at every boot from `autostart\`. If the autopilot was running
when the service last stopped, it starts again and resumes the open block at its original
wall-clock deadline: a reboot does not extend a block. While it runs, `sync_code` is refused
with a message naming the autopilot.

**Where things are** (under `C:\Users\trainer\trainer-data\autopilot\`):

| Path | What |
|---|---|
| `findings.jsonl` | one entry per block, append-only; the Mac pulls this |
| `state.json` | running flag, block, deadline, open run and stage, counters |
| `champion.json` | the champion's fit id, stamp, judge lines and block |
| `advisor\<block>.json` | the advisor's prompt digest, model and reply |
| `advisor\llama-server.log` | the LLM server's output |
| `steering\` | steering files applied (`<n>.json`) or refused (`refused-<n>.json`) |
| `STOP` | the stop flag, present only between a request and the stop |

**Steering inbox.** The Mac copies an approved `steering.json` to
`C:\Users\trainer\me\inbox\steering.json`. At the next block boundary the autopilot validates
it, moves it to `steering\<n>.json` and applies it; an invalid file, or one without
`approved_by`, is moved to `steering\refused-<n>.json`.

## Part 2. Admin steps for a fresh PC only

Run in one elevated PowerShell window on the PC, in order. The account's password goes in a
password manager; nothing below contains a secret.

1. The account, and its profile folder.

   ```powershell
   $pw = Read-Host -AsSecureString "Password for trainer"
   New-LocalUser -Name trainer -Password $pw -PasswordNeverExpires -AccountNeverExpires -Description "Bot trainer (SSH only)"
   Start-Process cmd.exe -ArgumentList '/c exit' -Credential (New-Object pscredential('trainer', $pw)) -LoadUserProfile -Wait
   Test-Path C:\Users\trainer
   ```

2. OpenSSH server, PowerShell as its shell, key login only for `trainer`.

   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
   Set-Service sshd -StartupType Automatic; Start-Service sshd
   $c = "$env:ProgramData\ssh\sshd_config"
   $lines = @(Get-Content $c) -replace '^#?\s*PasswordAuthentication\s.*', 'PasswordAuthentication no'
   $m = 0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^Match\s' } | Select-Object -First 1
   if ($null -eq $m) { $lines += 'AllowUsers trainer' } else { $lines = $lines[0..($m - 1)] + 'AllowUsers trainer' + $lines[$m..($lines.Count - 1)] }
   Set-Content -Path $c -Value $lines -Encoding ascii
   & "$env:WINDIR\System32\OpenSSH\sshd.exe" -t; if ($LASTEXITCODE -eq 0) { Restart-Service sshd; "sshd ok" }
   ```

3. The Mac's public key (replace the placeholder with the contents of the Mac's `.pub` file).

   ```powershell
   $d = 'C:\Users\trainer\.ssh'; New-Item -ItemType Directory -Force $d | Out-Null
   Set-Content -Path "$d\authorized_keys" -Encoding ascii -Value '<public key line>'
   icacls "$d\authorized_keys" /inheritance:r /grant 'trainer:F' /grant 'SYSTEM:F' /grant 'Administrators:F'
   icacls "$d\authorized_keys" /setowner trainer
   ```

4. Network profile Private, then the firewall rules for the Mac only (192.168.68.52): SSH 22
   and the service port 8765.

   ```powershell
   Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory
   Set-NetConnectionProfile -InterfaceAlias "<alias>" -NetworkCategory Private
   New-NetFirewallRule -DisplayName "ssh-from-mac" -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 192.168.68.52 -Profile Private -Action Allow
   New-NetFirewallRule -DisplayName "bot-trainer-mcp-from-mac" -Direction Inbound -Protocol TCP -LocalPort 8765 -RemoteAddress 192.168.68.52 -Profile Private -Action Allow
   ```

5. No sleep, then Git for Windows (all users, with Git LFS) and the NVIDIA driver.

   ```powershell
   powercfg /change standby-timeout-ac 0
   powercfg /change hibernate-timeout-ac 0
   powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
   powercfg /setactive SCHEME_CURRENT
   ```

6. The "Log on as a batch job" right for `trainer` (prints `0` on success). Copy
   `grant-batch-logon.ps1` to the PC first. A SID works in place of the name.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\grant-batch-logon.ps1 -Account trainer
   ```

7. After Part 1 steps 1 to 2 have put the shim at `C:\Users\trainer\spike\runner.ps1` (on a
   fresh PC, create that folder and copy `runner-shim.ps1` there as `runner.ps1`), register the
   task. It launches the shim, which runs `C:\Users\trainer\trainer\runner.ps1`.

   ```powershell
   $cred = Get-Credential trainer
   $a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Users\trainer\spike\runner.ps1'
   $t = New-ScheduledTaskTrigger -AtStartup
   $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Days 365) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
   Register-ScheduledTask -TaskName trainer-runner -Action $a -Trigger $t -Settings $s -User trainer -Password $cred.GetNetworkCredential().Password -RunLevel Limited
   Start-ScheduledTask trainer-runner
   ```

   Without the batch-logon right the task fails at logon with `2147943785` (0x80070569).

8. Install Godot 4.6.3 (console build) and the NuGet Python 3.14 under
   `C:\Users\trainer\tools\`; then continue with Part 1. The trainer looks for Godot in one
   place (`trainer/repo.py`): `GODOT_BIN` when set, else that path, else `godot` on PATH.
