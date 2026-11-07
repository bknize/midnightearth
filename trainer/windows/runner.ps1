# Job runner for the trainer account (PowerShell 5.1, ASCII only).
# Layout under $Root: queue\*.cmd (jobs), queue\done\, queue\.lock, autostart\*.cmd, logs\.
# Every job is started detached (cmd.exe /c <job> > logs\<name>.log 2>&1), so it survives
# an SSH disconnect. Only one runner polls: it holds queue\.lock for its whole life.
param(
    [string]$Root = 'C:\Users\trainer\trainer',
    [int]$WaitSeconds = 0
)

$ErrorActionPreference = 'Continue'
$queue = Join-Path $Root 'queue'
$done = Join-Path $queue 'done'
$logs = Join-Path $Root 'logs'
$auto = Join-Path $Root 'autostart'
foreach ($d in @($Root, $queue, $done, $logs, $auto)) {
    New-Item -ItemType Directory -Force $d | Out-Null
}
$runnerLog = Join-Path $logs 'runner.log'

function Write-RunnerLog([string]$text) {
    Add-Content -Path $runnerLog -Value ('{0} {1}' -f (Get-Date -Format 's'), $text)
}

# Exclusive lock, held until this process ends. Exit quietly if another runner has it,
# after waiting up to -WaitSeconds for it to free.
$lockPath = Join-Path $queue '.lock'
$lock = $null
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ($null -eq $lock) {
    try {
        $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    } catch {
        if ((Get-Date) -ge $deadline) { exit 0 }
        Start-Sleep -Seconds 1
    }
}

function Start-Job-Detached([string]$jobPath) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($jobPath)
    $log = Join-Path $logs ($name + '.log')
    $p = Start-Process -FilePath cmd.exe -ArgumentList "/c $jobPath > $log 2>&1" `
        -WindowStyle Hidden -PassThru
    Write-RunnerLog ('started {0} pid={1}' -f $name, $p.Id)
}

Write-RunnerLog ('runner up pid={0} root={1}' -f $PID, $Root)

# Autostart jobs run once per runner start, from where they are (not moved).
Get-ChildItem -Path $auto -Filter '*.cmd' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { Start-Job-Detached $_.FullName }

while ($true) {
    $jobs = Get-ChildItem -Path $queue -Filter '*.cmd' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime
    foreach ($j in $jobs) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $target = Join-Path $done ($stamp + '-' + $j.Name)
        try {
            Move-Item -Path $j.FullName -Destination $target -Force -ErrorAction Stop
        } catch {
            continue
        }
        Start-Job-Detached $target
    }
    Start-Sleep -Seconds 5
}
