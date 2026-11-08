@echo off
rem Starts the PVP match server on the testing PC (cycle 12 plan P13, spec H).
rem Deployed as C:\Users\trainer\pvp\start-server.cmd; run by the pvp-server scheduled task
rem (and the first time through the trainer-runner queue) as the non-admin user trainer.
rem cmd.exe re-reads a running .cmd by byte offset: never overwrite this file while the
rem server runs. Stop the task first, copy, then start it again.
rem A second start while port 8766 is already listening does nothing.
netstat -ano | findstr /R /C:":8766 .*LISTENING" >nul
if %ERRORLEVEL% EQU 0 (
  echo pvp server already listening on 8766
  exit /b 0
)
if not defined GODOT_BIN set GODOT_BIN=C:\Users\trainer\tools\godot\Godot_v4.6.3-stable_win64_console.exe
set PVP_REPO=C:\Users\trainer\pvp\repo
set PVP_LOGS=C:\Users\trainer\pvp-logs
set PVP_OUT=C:\Users\trainer\pvp\logs
rem The server's build is the checkout's commit (plan P14); "unknown" when git is missing.
if not defined PVP_BUILD for /f %%i in ('git -C "%PVP_REPO%" rev-parse HEAD 2^>nul') do set PVP_BUILD=%%i
if not defined PVP_BUILD set PVP_BUILD=unknown
if not exist %PVP_OUT% mkdir %PVP_OUT%
if not exist %PVP_LOGS% mkdir %PVP_LOGS%
"%GODOT_BIN%" --headless --path "%PVP_REPO%\godot" -s res://server/server_main.gd -- --port=8766 --logs=%PVP_LOGS% --build=%PVP_BUILD% >> %PVP_OUT%\server.log 2>&1
