@echo off
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0tools\android-workbench.ps1"
if errorlevel 1 (
  echo Workbench could not start. See apps\android\.dart_tool\android-workbench\launcher.log
  pause
)
