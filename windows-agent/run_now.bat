@echo off
REM Runs the agent in the foreground for a quick manual test - lets you see
REM log output and confirm it starts cleanly. Close this window or press
REM Ctrl+C to stop. This does NOT touch the scheduled task; if
REM SixdxStatsAgent is already running in the background (via install.bat),
REM stop it first with: Stop-ScheduledTask -TaskName SixdxStatsAgent
REM (otherwise both copies will fight over the same port).

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo .venv not found - run install.bat first.
    pause
    exit /b 1
)

.venv\Scripts\python.exe agent.py
pause
