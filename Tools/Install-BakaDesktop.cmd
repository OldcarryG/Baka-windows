@echo off
REM BAKA Desktop update for BAKA Windows. Double-click it in the extracted zip folder.
REM "Install-BakaDesktop.cmd rollback" puts the previous BAKA Desktop back.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Asking for administrator approval...
  REM the path goes through an environment variable, so folder names with quotes or spaces work
  set "BAKA_UPDATE_SELF=%~f0"
  if /i "%~1"=="rollback" (
    powershell -NoProfile -Command "Start-Process -FilePath $env:BAKA_UPDATE_SELF -ArgumentList 'rollback' -Verb RunAs"
  ) else (
    powershell -NoProfile -Command "Start-Process -FilePath $env:BAKA_UPDATE_SELF -Verb RunAs"
  )
  exit /b
)
set "MODE="
if /i "%~1"=="rollback" set "MODE=-Rollback"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-BakaDesktop.ps1" %MODE%
echo.
pause
