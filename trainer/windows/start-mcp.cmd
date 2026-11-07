@echo off
rem Starts the trainer service from the training worktree. Run by the runner from autostart\.
rem A second start while port 8765 is already listening does nothing.
netstat -ano | findstr /R /C:":8765 .*LISTENING" >nul
if %ERRORLEVEL% EQU 0 (
  echo service already listening on 8765
  exit /b 0
)
rem The runner's task may have started before `setx GODOT_BIN`, so its environment can lack it.
if not defined GODOT_BIN set GODOT_BIN=C:\Users\trainer\tools\godot\Godot_v4.6.3-stable_win64_console.exe
if not exist C:\Users\trainer\me\logs mkdir C:\Users\trainer\me\logs
call C:\Users\trainer\me\venv\Scripts\activate.bat
cd /d C:\Users\trainer\me\work
python -I trainer serve --host 0.0.0.0 --port 8765 >> C:\Users\trainer\me\logs\serve.log 2>&1
