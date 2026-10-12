# One-command installation from GitHub

Use a public repository containing the complete project:

```
windows-agent/
macos-app/
  linux-agent/install.sh
```

Replace `OWNER/REPO` with your GitHub repository. A tag or commit can replace
`main` to keep installations on a known version. These are templates until
the repository is uploaded; nothing has been published by this change.

## Linux / Oracle VPS

Run on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/macos-app/linux-agent/install.sh -o pulse-install.sh && sudo bash pulse-install.sh
```

Follow the printed SSH-tunnel command and enter the API key in Pulse's
Oracle VPS settings. See [Linux setup](linux-agent/README.md).

## Windows

Python 3.10+ must already be installed on PATH. Paste this **one line into
PowerShell**; it downloads the archive, keeps the agent in your local app-data
folder, preserves an existing `config.json`, and starts the existing installer
with a UAC prompt:

```powershell
$ErrorActionPreference='Stop'; $repo='OWNER/REPO'; $stage=Join-Path $env:TEMP ('Pulse-'+[guid]::NewGuid()); New-Item -ItemType Directory -Path $stage | Out-Null; Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile "$stage\source.zip"; Expand-Archive "$stage\source.zip" -DestinationPath $stage; $source=Get-ChildItem $stage -Directory | Select-Object -First 1; $agent=Join-Path $env:LOCALAPPDATA 'PulseAgent'; New-Item -ItemType Directory -Force -Path $agent | Out-Null; Get-ChildItem (Join-Path $source.FullName 'windows-agent') | Where-Object { $_.Name -notin @('config.json','.venv','__pycache__') } | Copy-Item -Destination $agent -Recurse -Force; Start-Process -FilePath (Join-Path $agent 'install.bat') -Verb RunAs
```

The Windows command is provided for use on Windows; it hasn't been executed
on this Mac. It invokes the existing Windows setup, whose default bind address
is `192.168.1.54`. Other Windows machines need their own LAN address in
`config.json`; do not reuse SIXDX's address on another computer. Its scheduled
task starts at user logon, while the Linux service starts at boot.

## Before publishing

Do not upload the live `windows-agent/config.json`, API keys, `.venv`, caches,
or build products. Put these patterns in the **repository-root** `.gitignore`
(the macOS folder's ignore file cannot exclude sibling Windows files):

```gitignore
**/config.json
**/agent.env
**/.venv/
**/__pycache__/
macos-app/build/
macos-app/dist/
.DS_Store
```

Keep `config.example.json` with placeholder values. Ignoring files does not
remove secrets already committed; rotate any key that has already been made
public. Agent installers are separate from macOS distribution: sharing the
Mac app still needs its normal signing/distribution workflow.
