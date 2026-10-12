# Install Pulse agents from GitHub

Repository: [StevenSteel7/Pulse](https://github.com/StevenSteel7/Pulse).
The agent directories are at the repository root; installer URLs do **not** contain `macos-app/`.

## Public-IP pairing (recommended)

Use **Pulse → Advanced → Add device** to generate a personalized command containing a short-lived, single-use token. Choose Windows or Linux, enter the public IPv4 address and port, then run the copied command on that device.

Installer links:

- [Windows pairing installer](https://raw.githubusercontent.com/StevenSteel7/Pulse/main/windows-agent/pair.ps1)
- [Linux pairing installer](https://raw.githubusercontent.com/StevenSteel7/Pulse/main/linux-agent/pair.sh)

These installers require the token and expiry supplied by Pulse; downloading and running them without the app-generated arguments won't start enrollment. Publish both installers and `paired-agent/agent.py` before using copied commands.

Compare the verification codes, give the device a name, and approve it in Pulse. [Full workflow](docs/PAIRING.md).

## Legacy manual installation

The commands below install the older API-key agents for LAN/SSH use. They do not initiate the new app approval flow.

### Linux / Oracle VPS

Run on your Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/StevenSteel7/Pulse/main/linux-agent/install.sh -o pulse-install.sh && sudo bash pulse-install.sh
```

[Direct installer](https://raw.githubusercontent.com/StevenSteel7/Pulse/main/linux-agent/install.sh) · [Full Linux setup](linux-agent/README.md)

The installer prints the API key and Mac-side SSH-tunnel command. The default agent listens on `127.0.0.1:8801`; connect Pulse to the local tunnel at `127.0.0.1:8802`.

### Windows

With Python 3.10+ on PATH, run in PowerShell:

```powershell
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/StevenSteel7/Pulse/main/windows-agent/download.ps1' -OutFile "$env:TEMP\pulse-install.ps1"; if ($?) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\pulse-install.ps1" }
```

[Direct installer](https://raw.githubusercontent.com/StevenSteel7/Pulse/main/windows-agent/download.ps1) · [Full Windows setup](windows-agent/README.md)

Choose your LAN IPv4 address and approve UAC. Files are installed to `%LOCALAPPDATA%\PulseAgent`, and setup prints the values to enter in Pulse's PC connection. Existing keys are preserved. The Windows task starts at logon; the Linux service starts at boot.

## Versioned installations

These commands follow `main`. For a fixed version, replace `main` in the download URL with a release tag or commit SHA. When using a fixed Windows bootstrap, also pass `-Ref THE_SAME_TAG_OR_SHA` to its `powershell.exe -File` invocation so the downloaded agent files use that version too.

The files must be pushed to GitHub before their raw links become available. Downloaded scripts are saved completely before execution. No account is needed to download this public repository's installers.

These commands install monitoring agents only. [Build the Mac app separately](README.md#build-the-mac-app).
