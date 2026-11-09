@echo off
rem Starts the trainer service from the training worktree, and starts it again each time it
rem exits with code 75: a sync that changed trainer/ (trainer/server.py RESTART_EXIT).
rem Run by the runner from autostart\. A second start while port 8765 is listening does nothing.
rem Never overwrite this file while it runs (cmd.exe re-reads a running batch file by byte
rem offset): swap-start-mcp.cmd replaces it, see SETUP.md.
netstat -ano | findstr /R /C:":8765 .*LISTENING" >nul
if %ERRORLEVEL% EQU 0 (
  echo service already listening on 8765
  exit /b 0
)
if not exist C:\Users\trainer\me\logs mkdir C:\Users\trainer\me\logs
call C:\Users\trainer\me\venv\Scripts\activate.bat
cd /d C:\Users\trainer\me\work
set TRAINER_RESTART_LOOP=1
:serve
python -I trainer serve --host 0.0.0.0 --port 8765 >> C:\Users\trainer\me\logs\serve.log 2>&1
if %ERRORLEVEL% NEQ 75 exit /b %ERRORLEVEL%
rem Give the old process's port and lock time to free.
ping -n 4 127.0.0.1 >nul
goto serve
