#Requires -RunAsAdministrator
<#
  One-click setup for the SIXDX Stats Agent. Run via install.bat (which
  handles the admin-elevation prompt), or directly from an elevated
  PowerShell prompt:

      .\install.ps1

  Safe to re-run any time (e.g. after editing config.json) - it won't
  overwrite an API key that's already set, and re-registering the scheduled
  task just refreshes its definition.
#>

$ErrorActionPreference = "Stop"
$AgentDir = $PSScriptRoot
Set-Location $AgentDir

function Section($title) {
    Write-Host ""
    Write-Host "== $title ==" -ForegroundColor Cyan
}

# 1. Python present?
Section "Checking for Python"
$python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "Python was not found on PATH." -ForegroundColor Red
    Write-Host "Install it from https://www.python.org/downloads/windows/ (check 'Add python.exe to PATH'), then re-run this script."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "Found $($python.Source)"

# 2. Virtual environment + dependencies
Section "Setting up virtual environment"
if (-not (Test-Path ".venv")) {
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw "python -m venv failed (exit code $LASTEXITCODE)." }
    Write-Host "Created .venv"
} else {
    Write-Host ".venv already exists, skipping creation"
}

Write-Host "Installing dependencies..."
.\.venv\Scripts\pip.exe install -q -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit code $LASTEXITCODE). Check your internet connection and re-run." }
Write-Host "Dependencies installed."

# 3. Config file + API key
Section "Configuring config.json"
$apiKey = $null
if (-not (Test-Path "config.json")) {
    Copy-Item "config.example.json" "config.json"
    $apiKey = (& .\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_hex(32))").Trim()
    $config = Get-Content "config.json" -Raw | ConvertFrom-Json
    $config.api_key = $apiKey
    $config | ConvertTo-Json -Depth 5 | Set-Content "config.json"
    Write-Host "Created config.json with a freshly generated API key."
} else {
    $config = Get-Content "config.json" -Raw | ConvertFrom-Json
    if (-not $config.api_key -or $config.api_key -eq "REPLACE-WITH-A-LONG-RANDOM-SECRET" -or $config.api_key -eq "CHANGE-ME-TO-A-LONG-RANDOM-SECRET") {
        $apiKey = (& .\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_hex(32))").Trim()
        $config.api_key = $apiKey
        $config | ConvertTo-Json -Depth 5 | Set-Content "config.json"
        Write-Host "config.json existed but had no real API key set - generated one."
    } else {
        $apiKey = $config.api_key
        Write-Host "config.json already configured, leaving your existing API key as-is."
    }
}

# 4. Firewall rule
Section "Opening firewall port $($config.port) (Private profile only)"
$existingRule = Get-NetFirewallRule -DisplayName "SIXDX Stats Agent" -ErrorAction SilentlyContinue
if (-not $existingRule) {
    New-NetFirewallRule -DisplayName "SIXDX Stats Agent" -Direction Inbound -Protocol TCP -LocalPort $config.port -Action Allow -Profile Private | Out-Null
    Write-Host "Firewall rule created."
} else {
    Write-Host "Firewall rule already exists, skipping."
}

# 5. Scheduled task (auto-start at logon, auto-restart on crash)
Section "Registering scheduled task"
& "$AgentDir\install_task.ps1"

Section "Starting the agent now"
try {
    Start-ScheduledTask -TaskName "SixdxStatsAgent"
    Start-Sleep -Seconds 2
    Write-Host "Task started."
} catch {
    Write-Warning "Could not start the task automatically: $_"
}

# 6. Quick self-test
Section "Testing http://$($config.host):$($config.port)/health"
try {
    $resp = Invoke-WebRequest -Uri "http://$($config.host):$($config.port)/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host "Agent responded: $($resp.Content)" -ForegroundColor Green
} catch {
    Write-Warning "Could not reach the agent yet. It may still be starting - check with: Get-ScheduledTask -TaskName SixdxStatsAgent"
}

Section "Done"
Write-Host "Host:    $($config.host)"
Write-Host "Port:    $($config.port)"
Write-Host "API key: $apiKey" -ForegroundColor Yellow
Write-Host ""
Write-Host "Enter the host, port, and API key above into the Pulse app's Settings on your Mac."
