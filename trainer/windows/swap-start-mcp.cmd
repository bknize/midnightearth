@echo off
rem Queue job: replaces autostart\start-mcp.cmd with C:\Users\trainer\trainer\start-mcp.new and
rem starts the service from it. cmd.exe re-reads a running batch file by byte offset, so the
rem old file may only change once the instance running it has ended: kill the service (the
rem instance then reads its next line and ends), wait, move the new file in. See SETUP.md.
set NEW=C:\Users\trainer\trainer\start-mcp.new
set LIVE=C:\Users\trainer\trainer\autostart\start-mcp.cmd
if not exist %NEW% (
  echo no %NEW%; nothing changed
  exit /b 1
)
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":8765 .*LISTENING"') do taskkill /PID %%P /F
ping -n 6 127.0.0.1 >nul
move /y %NEW% %LIVE%
call %LIVE%
