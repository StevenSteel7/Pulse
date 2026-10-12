#Requires -RunAsAdministrator
<#
  Removes the scheduled task and firewall rule created by install.ps1.
  Does not delete config.json, .venv, or your API key - just stops the
  agent from running/being reachable. Run via uninstall.bat.
#>

$ErrorActionPreference = "Continue"

Write-Host "Stopping and removing scheduled task 'SixdxStatsAgent'..."
Stop-ScheduledTask -TaskName "SixdxStatsAgent" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "SixdxStatsAgent" -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "Removing firewall rule 'SIXDX Stats Agent'..."
Remove-NetFirewallRule -DisplayName "SIXDX Stats Agent" -ErrorAction SilentlyContinue

Write-Host "Done. The agent no longer runs at logon and port 8801 is no longer open."
Write-Host "config.json and .venv were left in place in case you reinstall later."
