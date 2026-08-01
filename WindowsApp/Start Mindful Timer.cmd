@echo off
start "Mindful Timer" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0MindfulTimer.ps1"
