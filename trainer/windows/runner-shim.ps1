# Replaces C:\Users\trainer\spike\runner.ps1, the file the trainer-runner scheduled task
# launches, so the task needs no change. Runs the stable runner that sync_code refreshes.
$stable = 'C:\Users\trainer\trainer\runner.ps1'
if (-not (Test-Path $stable)) { exit 1 }
& $stable
