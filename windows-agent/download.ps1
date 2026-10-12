<# Downloads the Pulse Windows agent, then launches its existing UAC installer.
   Run from PowerShell with Python 3.10+ installed on PATH. #>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Ref = 'main'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AgentDirectory = Join-Path $env:LOCALAPPDATA 'PulseAgent'
$StageDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Pulse-' + [guid]::NewGuid())
$BaseUrl = "https://raw.githubusercontent.com/StevenSteel7/Pulse/$Ref/windows-agent"
$Files = @('agent.py', 'install.ps1', 'install.bat', 'install_task.ps1',
           'requirements.txt', 'config.example.json', 'run_now.bat',
           'uninstall.ps1', 'uninstall.bat')

if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    throw 'Install Python 3.10+ from https://www.python.org/downloads/windows/ with Add Python to PATH, then rerun.'
}
& python.exe -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'Python 3.10+ is required.' }

New-Item -ItemType Directory -Path $StageDirectory | Out-Null
try {
    Write-Host 'Downloading Pulse Windows agent...'
    # Finish every download before modifying an existing installation.
    foreach ($File in $Files) {
        Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$File" -OutFile (Join-Path $StageDirectory $File)
    }
    New-Item -ItemType Directory -Force -Path $AgentDirectory | Out-Null
    $ConfigPath = Join-Path $AgentDirectory 'config.json'
    if (-not (Test-Path $ConfigPath)) {
        $SuggestedAddress = Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            ForEach-Object { $_.IPv4Address.IPAddress } |
            Select-Object -First 1
        $Prompt = if ($SuggestedAddress) { "PC LAN IPv4 address [$SuggestedAddress]" } else { 'PC LAN IPv4 address' }
        $Address = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($Address)) { $Address = $SuggestedAddress }
        $ParsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($Address, [ref]$ParsedAddress) -or
            $ParsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            $Address -eq '0.0.0.0') {
            throw 'Enter the IPv4 address of your PC LAN adapter, not 0.0.0.0.'
        }
        $LocalAddresses = @(Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress)
        if ($Address -notin $LocalAddresses) { throw "The address $Address is not assigned to this PC." }
        $Config = Get-Content (Join-Path $StageDirectory 'config.example.json') -Raw | ConvertFrom-Json
        $Config.host = $Address
        # The existing installer replaces this placeholder with a random key.
        $Config | ConvertTo-Json | Set-Content -Encoding ASCII $ConfigPath
    }
    foreach ($File in $Files) {
        Copy-Item (Join-Path $StageDirectory $File) -Destination (Join-Path $AgentDirectory $File) -Force
    }
    Write-Host "Agent location: $AgentDirectory"
    Write-Host 'Approve the administrator prompt. The installer will display your host, port, and API key.'
    $Installer = Start-Process -FilePath (Join-Path $AgentDirectory 'install.bat') -Verb RunAs -Wait -PassThru
    if ($Installer.ExitCode -ne 0) { throw "Installer exited with code $($Installer.ExitCode)." }
} finally {
    if (Test-Path $StageDirectory) { Remove-Item -Recurse -Force $StageDirectory }
}
