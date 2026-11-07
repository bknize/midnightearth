# Swap the live runner (spike\runner.ps1, no lock) for the stable one. Safe to run twice:
# if a runner already holds queue\.lock, nothing is done.
$stable = 'C:\Users\trainer\trainer\runner.ps1'
$lockPath = 'C:\Users\trainer\trainer\queue\.lock'
New-Item -ItemType Directory -Force (Split-Path $lockPath) | Out-Null

# Is the lock held? (Open it exclusively, and let go at once.)
try {
    $probe = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $probe.Close()
} catch {
    'a runner already holds the lock; nothing to swap'
    exit 0
}

if (-not (Test-Path $stable)) { 'missing ' + $stable; exit 1 }

# Start the new runner detached, so it outlives this job.
$p = Start-Process -FilePath powershell.exe -WindowStyle Hidden -PassThru -ArgumentList `
    ('-NoProfile -ExecutionPolicy Bypass -File ' + $stable + ' -WaitSeconds 20')
'started new runner pid=' + $p.Id

# Stop the old runner: a powershell whose command line names spike\runner.ps1.
$old = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*spike\runner.ps1*' -and $_.ProcessId -ne $PID }
foreach ($o in $old) {
    Stop-Process -Id $o.ProcessId -Force
    'stopped old runner pid=' + $o.ProcessId
}
