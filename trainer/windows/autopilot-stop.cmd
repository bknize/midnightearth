@echo off
rem Asks the training autopilot to stop: creates the STOP flag file in its data directory.
rem Usable over SSH as trainer with the MCP down: ssh PC C:\Users\trainer\trainer\autopilot-stop.cmd
rem The autopilot reaches a safe point, writes the block as interrupted, removes the file and
rem stops within 10 minutes (spec R36, plan P14). The data dir matches store.default_data_dir().
setlocal
if defined TRAINER_DATA (set "DATA=%TRAINER_DATA%") else (set "DATA=%USERPROFILE%\trainer-data")
if not exist "%DATA%\autopilot" mkdir "%DATA%\autopilot"
echo stop requested> "%DATA%\autopilot\STOP"
if exist "%DATA%\autopilot\STOP" (
  echo created %DATA%\autopilot\STOP; the autopilot stops at its next safe point, within 10 minutes
  exit /b 0
)
echo could not create %DATA%\autopilot\STOP
exit /b 1
