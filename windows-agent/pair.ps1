# Public-IP enrollment installer. Run the command copied from Pulse.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$Token,
    [Parameter(Mandatory=$true)][long]$Expires,
    [ValidateRange(1024,65535)][int]$Port = 8843,
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Ref = 'main'
)
$ErrorActionPreference = 'Stop'
$Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Admin) {
    $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Token $Token -Expires $Expires -Port $Port -Ref $Ref"
    $Child = Start-Process powershell.exe -Verb RunAs -ArgumentList $Arguments -Wait -PassThru
    if ($Child.ExitCode -ne 0) { throw 'Elevated installation failed.' }
    exit
}
try {
    & python.exe -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)'
    if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.10+ with Add Python to PATH first.' }
    $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($Expires -le $Now -or $Expires -gt ($Now + 660)) { throw 'Command expired. Copy a new command from Pulse.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $AgentDirectory = Join-Path $env:LOCALAPPDATA 'PulsePairedAgent'
    $StateDirectory = Join-Path $AgentDirectory 'state'
    New-Item -ItemType Directory -Force $StateDirectory | Out-Null
    $UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $AgentDirectory /inheritance:r /grant:r "*$($UserSid):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /T /Q
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the agent directory.' }
    Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/StevenSteel7/Pulse/$Ref/paired-agent/agent.py" -OutFile (Join-Path $AgentDirectory 'agent.py.new')
    if (-not (Test-Path (Join-Path $AgentDirectory '.venv\Scripts\python.exe'))) {
        & python.exe -m venv (Join-Path $AgentDirectory '.venv')
        if ($LASTEXITCODE -ne 0) { throw 'Virtual environment creation failed.' }
    }
    $Python = Join-Path $AgentDirectory '.venv\Scripts\python.exe'
    & $Python -m pip install --disable-pip-version-check 'psutil==6.1.1' 'cryptography>=46,<47'
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    & $Python -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' (Join-Path $AgentDirectory 'agent.py.new')
    if ($LASTEXITCODE -ne 0) { throw 'Agent validation failed.' }
    if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -ge $Expires) { throw 'Command expired during installation. Copy a fresh command; dependencies are now installed.' }
    Stop-ScheduledTask -TaskName PulsePairedAgent -ErrorAction SilentlyContinue
    Move-Item (Join-Path $AgentDirectory 'agent.py.new') (Join-Path $AgentDirectory 'agent.py') -Force
    & $Python (Join-Path $AgentDirectory 'agent.py') --state-dir $StateDirectory --configure --token $Token --expires $Expires --port $Port
    if ($LASTEXITCODE -ne 0) { throw 'Agent enrollment configuration failed.' }
    $Action = New-ScheduledTaskAction -Execute (Join-Path $AgentDirectory '.venv\Scripts\pythonw.exe') -Argument "`"$(Join-Path $AgentDirectory 'agent.py')`" --state-dir `"$StateDirectory`"" -WorkingDirectory $AgentDirectory
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)
    $Principal = New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName PulsePairedAgent -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force | Out-Null
    Get-NetFirewallRule -DisplayName 'Pulse Paired HTTPS' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'Pulse Paired HTTPS' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any | Out-Null
    Start-ScheduledTask -TaskName PulsePairedAgent
    & $Python (Join-Path $AgentDirectory 'agent.py') --state-dir $StateDirectory --check
    if ($LASTEXITCODE -ne 0) { throw 'HTTPS health check failed. Check the scheduled task and port.' }
    Write-Host "Agent started on HTTPS port $Port. If behind a router, forward that TCP port to this PC."
    Write-Host 'Approve the matching verification code in Pulse. The task starts at Windows logon.'
    Read-Host 'Press Enter to close'
} catch {
    Write-Host $_ -ForegroundColor Red
    Read-Host 'Installation failed. Press Enter to close'
    exit 1
}
