# Pulse Windows agent

## Recommended: pair a public-IP device

In Pulse on your Mac, open **Advanced → Add device → Windows**, enter the public IPv4 address and HTTPS port (default **8843**), and click **Generate & copy install command**.

Run that command on the target device within ten minutes. Once the agent is reachable, Pulse shows a pairing notice. Compare the displayed verification code with the installer's code, give the device a name, and approve. No permanent API key needs to be copied.

Windows requires Python 3.10+ on PATH and UAC approval. The installer opens the selected Windows Firewall port for all profiles and starts the `PulsePairedAgent` task at logon. For a PC behind a router, forward that TCP port to the PC. Files live in `%LOCALAPPDATA%\PulsePairedAgent`.

[Pairing installer](pair.ps1)

The new agent is separate from the legacy service below. Keep Pulse running for fresh widget readings. See [pairing and recovery](../docs/PAIRING.md).

---

## Legacy manual installation

Read-only CPU, memory, NVIDIA GPU, disk, and uptime telemetry for the Pulse Mac app.

## Install from GitHub

Install Python **3.10+** for Windows with **Add Python to PATH** enabled. Then paste this into PowerShell:

```powershell
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/StevenSteel7/Pulse/main/windows-agent/download.ps1' -OutFile "$env:TEMP\pulse-install.ps1"; if ($?) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\pulse-install.ps1" }
```

The download script fetches the agent's source files into `%LOCALAPPDATA%\PulseAgent`. On first install, it asks for your PC's LAN IPv4 address and suggests the address of an adapter with a default gateway. Choose the interface reachable from your Mac.

Approve the UAC prompt. The installer creates a virtual environment, installs dependencies, generates a random API key, creates a Private-profile firewall rule, and starts the `SixdxStatsAgent` scheduled task. The task starts again at user logon, not before login.

The installer prints **host**, **port**, and **API key**. Enter them under **Pulse menu bar → Advanced → gear → PC** on your Mac. Save, then select **PC** on the widget.

Your `config.json` and virtual environment are preserved on reinstall. If you already have an agent installed somewhere else, stop that old task/process before installing another copy. To reuse its API key, copy its `config.json` into `%LOCALAPPDATA%\PulseAgent` first.

## Install from a downloaded repository

Open `windows-agent/config.example.json`, copy it to `config.json`, and replace the example host with your PC's LAN IPv4 address. Leave the API-key placeholder; the installer generates a key. Then double-click `install.bat`.

The example address `192.168.1.54` belongs to the original development PC. It is not a universal default for other computers. Use a DHCP reservation or update `config.json` if your PC's address changes.

## Manage

Run task commands in PowerShell as needed:

```powershell
Get-ScheduledTask -TaskName SixdxStatsAgent
Start-ScheduledTask -TaskName SixdxStatsAgent
Stop-ScheduledTask -TaskName SixdxStatsAgent
```

- `run_now.bat`: run in the foreground for diagnostics; stop the scheduled task first.
- `install.bat`: rerun setup after editing connection settings.
- `uninstall.bat`: remove the task and firewall rule; retain the local configuration.

The firewall rule applies to **Private** networks only. Confirm the Windows network profile and that the Mac can reach the configured LAN address. If you change the port after installation, update the existing firewall rule to match it.

GPU stats use `nvidia-smi`. If there is no supported NVIDIA GPU, the agent continues serving the other metrics with `gpu.available: false`.

## API

- `GET /health`: unauthenticated `{"ok": true}` health check.
- `GET /stats`: JSON metrics; requires `X-API-Key: YOUR_KEY`.

Do not expose the plain-HTTP agent directly to the internet. Use a private VPN or an HTTPS reverse proxy for remote access. Never commit your real `config.json` or API key.

The GitHub bootstrap is intended for Windows PowerShell; it has not been executed on the Mac development host.
