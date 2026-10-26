@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\BAKA\Scripts\SetupComplete.ps1"
exit /b %errorlevel%
