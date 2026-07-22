@echo off
title MT5 Gold Research - Configure AI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\QuantResearch\mt5-gold-research\scripts\set-ai-credentials.ps1"
if errorlevel 1 (
  echo.
  echo Configuration failed. See the error above.
  pause
  exit /b 1
)
echo.
echo AI credentials configured. The 24-hour worker will begin automatically.
pause
