@echo off
REM One-click installer for the SIXDX Stats Agent.
REM Double-click this file (or run it from a CLI/Run box), or pin it to the
REM Start menu / desktop - it will prompt for admin rights via Windows UAC
REM (needed for the firewall rule and scheduled task registration).

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"

set "INSTALL_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %INSTALL_EXIT%
