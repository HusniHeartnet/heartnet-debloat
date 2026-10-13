@echo off
rem Heartnet Debloat launcher. Opens the app without admin rights (the scan is read-only).
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\Main.ps1" %*
