@echo off
rem Queue job, run by the OLD runner: starts the stable runner and stops the old one.
rem Logic lives in swap-runner.ps1 (copied to C:\Users\trainer\trainer by SETUP.md).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\trainer\trainer\swap-runner.ps1
