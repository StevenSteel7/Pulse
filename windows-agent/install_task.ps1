#Requires -RunAsAdministrator
<#
  Registers the SIXDX Stats Agent as a Windows Task Scheduler task that:
    - starts automatically at user logon
    - restarts automatically if it crashes
    - runs hidden (no console window)
    - is fully independent of any other local service/tool on this PC

  Usage (from an elevated PowerShell prompt, in this folder):
      .\install_task.ps1

  Re-run it any time after changing config.json to pick up changes (it just
  re-registers the same task definition).
#>

$TaskName    = "SixdxStatsAgent"
$AgentDir    = $PSScriptRoot

# Use the venv's own interpreter, not whatever "python" resolves to on PATH -
# the venv is where fastapi/uvicorn/psutil actually got installed.
$PythonExe = Join-Path $AgentDir ".venv\Scripts\pythonw.exe"
if (-not (Test-Path $PythonExe)) {
    $PythonExe = Join-Path $AgentDir ".venv\Scripts\python.exe"
    if (Test-Path $PythonExe) {
        Write-Warning "pythonw.exe not found in .venv; falling back to python.exe (a console window may briefly appear at logon)."
    } else {
        throw "No .venv found in $AgentDir. Run install.bat first (or 'python -m venv .venv' + pip install -r requirements.txt)."
    }
}

$Action = New-ScheduledTaskAction `
    -Execute $PythonExe `
    -Argument "`"$AgentDir\agent.py`"" `
    -WorkingDirectory $AgentDir

$Trigger = New-ScheduledTaskTrigger -AtLogOn

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

$Principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal `
    -Description "Read-only LAN stats agent for the Pulse macOS widget. Independent of other local services." `
    -Force

Write-Host "Registered scheduled task '$TaskName'."
Write-Host "It will start at your next logon. To start it right now:"
Write-Host "    Start-ScheduledTask -TaskName $TaskName"
Write-Host ""
Write-Host "Also remember to open the firewall port (run once, elevated):"
Write-Host "    New-NetFirewallRule -DisplayName 'SIXDX Stats Agent' -Direction Inbound -Protocol TCP -LocalPort 8801 -Action Allow -Profile Private"
