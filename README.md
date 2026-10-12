<h1 align="center">Pulse</h1>
<p align="center"><strong>Your PC and VPS. One quiet corner of your Mac.</strong></p>
<p align="center">A native macOS menu bar app and desktop widget for monitoring your Windows PC and Linux server.</p>
<p align="center"><a href="#quick-start">Quick start</a> · <a href="#windows-agent">Windows</a> · <a href="#linux--oracle-vps-agent">Linux / Oracle VPS</a> · <a href="#build-the-mac-app">Build for Mac</a></p>

<table>
  <tr><th>Windows PC</th><th>Linux / Oracle VPS</th></tr>
  <tr>
    <td><img src="docs/images/pc-large.png" alt="Pulse PC widget showing CPU, GPU, activity and storage" width="360"></td>
    <td><img src="docs/images/vps-large.png" alt="Pulse VPS widget showing CPU, memory and storage" width="360"></td>
  </tr>
</table>
<p align="center"><sub>Rendered previews with sample readings.</sub></p>

## At a glance

- **Switch on the widget.** Compact **device buttons** change systems without opening a window.
- **See the metrics that matter.** CPU, RAM, storage, and uptime; NVIDIA GPU usage, VRAM, and temperature on Windows.
- **Keep it quiet.** Pulse lives in the menu bar. **Advanced** opens the dashboard and connection settings.
- **Keep systems separate.** Each named device has its own credential, pinned certificate, cached readings, and history.
- **Know when a system is offline.** Previous readings remain available; a missing connection never substitutes the other machine's data.
- **Choose your size.** Small, medium, and large widgets, plus a classic large layout.

## Quick start: pair a device

1. [Build and launch Pulse](#build-the-mac-app) on **macOS 14 Sonoma or later**.
2. Open **Pulse menu bar → Advanced → Add device**.
3. Choose **Windows** or **Linux**, enter the device's **public IPv4 address**, and leave HTTPS port **8843** unless you need another port.
4. Click **Generate & copy install command**. Run the copied command on that device within **10 minutes**.
5. Allow inbound TCP traffic to that port in the device's firewall and cloud/router rules.
6. Pulse shows **Device ready to pair**. Compare its verification code with the installer, enter a name, and click **Approve & add device**.
7. Add the widget from **desktop → Edit Widgets → Pulse**. Switch between your saved devices using its buttons.

Pulse initiates the connection to the public IP. **Your Mac needs no public IP, inbound port, account, or relay.** Keep Pulse running in the menu bar to collect fresh readings. Up to two devices use compact named buttons; with more devices, the widget shows previous/next buttons and a device count.

> Publish the new pairing installers and `paired-agent/agent.py` to GitHub before using copied installation commands. The commands download from `StevenSteel7/Pulse/main`.

### What happens during pairing?

The copied command contains a random, single-use **pairing token**, not a permanent API key. The agent creates a TLS certificate, proves it knows your token, and waits for approval. Pulse binds that proof to the certificate presented by the device. After you verify the displayed code and approve, Pulse creates a separate permanent credential, stores it in your Mac's **login Keychain**, and pins the device's certificate for subsequent connections.

The agent erases the pairing token on approval and stores only a hash of the permanent credential. Stats remain inaccessible before approval. [Protocol and security details](docs/PAIRING.md).

## Windows agent

**Requires:** Windows PowerShell, **Python 3.10+** on PATH, and administrator approval.

Use **Add device → Windows → Generate & copy install command** in Pulse. The personalized command downloads [the Windows pairing installer](https://raw.githubusercontent.com/StevenSteel7/Pulse/main/windows-agent/pair.ps1) and supplies your temporary token automatically.

The installer:

- Uses `%LOCALAPPDATA%\PulsePairedAgent` for its Python environment and protected device state.
- Generates a TLS certificate and prints a verification code.
- Opens the chosen TCP port in Windows Firewall and starts the **PulsePairedAgent** scheduled task.
- Starts the agent again when you log in to Windows.

If the PC is behind a router, forward its public TCP port to the same port on the PC. A public address does not by itself bypass NAT or firewall rules. GPU telemetry requires NVIDIA's `nvidia-smi`; CPU, RAM, and disk monitoring work without it.

[Windows setup guide](windows-agent/README.md) · [Installer source](windows-agent/pair.ps1)

## Linux / Oracle VPS agent

**Requires:** a systemd-based Ubuntu, Debian, or Oracle Linux host and sudo access. Supports ARM64 and x86-64. The installer installs Python 3, OpenSSL, and curl if missing.

Use **Add device → Linux → Generate & copy install command** in Pulse. The personalized command downloads [the Linux pairing installer](https://raw.githubusercontent.com/StevenSteel7/Pulse/main/linux-agent/pair.sh) and supplies your temporary token automatically.

The installer creates a dedicated unprivileged service user, stores device state under `/var/lib/pulse-paired`, starts **pulse-paired.service**, and verifies the local HTTPS endpoint. It starts automatically at boot.

For Oracle Cloud, allow inbound **TCP 8843** (or your chosen port) in both the applicable **NSG/security list** and the Linux firewall. Restrict the source to your Mac's public address when practical. The installer does not edit Oracle Cloud or Linux firewall rules.

```bash
sudo systemctl status pulse-paired --no-pager
sudo journalctl -u pulse-paired -n 40 --no-pager
```

[Linux setup guide](linux-agent/README.md) · [Installer source](linux-agent/pair.sh)

### Existing manual connections

Existing PC/VPS settings are preserved. The older LAN/SSH agents remain available through [legacy installation instructions](GITHUB-INSTALL.md#legacy-manual-installation). Public-IP pairing installs a separate service on port 8843 and does not stop the old service on 8801.

The new flow supports **public IPv4 only**. Existing manual connections can still use LAN addresses, SSH tunnels, or an HTTPS reverse proxy.

## Build the Mac app

Requires full **Xcode** with a macOS 14+ SDK. The generated Xcode project is included.

```bash
git clone https://github.com/StevenSteel7/Pulse.git
cd Pulse
open Pulse.xcodeproj
```

1. In Xcode, choose the **Pulse** project and open **Signing & Capabilities** for both **Pulse** and **PulseWidgetExtension**.
2. Select the same development team for both targets. The shared App Group uses `$(DEVELOPMENT_TEAM).com.stevensteel.pulse`.
3. Select the **Pulse** scheme and run it. Look for its icon in the menu bar; the dashboard opens from **Advanced**.

If you regenerate the project, set your team in `project.yml` first, then run `xcodegen generate`. XcodeGen is only required when regenerating the project.

To package a DMG after configuring signing:

```bash
./build_dmg.sh YOUR_TEAM_ID
```

The result is `dist/Pulse.dmg`. Development signing supports local development; distribution to other Macs requires an appropriate signing and notarization workflow. This repository does not provide an automated notarized release.

To start Pulse at login, add it in **System Settings → General → Login Items**.

## How it works

```text
Windows PC ── HTTPS stats agent ──┐
                                 ├── Pulse on Mac ── menu bar + desktop widget
Linux VPS ─── HTTPS stats agent ──┘
```

Paired agents expose read-only `GET /stats` over pinned HTTPS, authenticated with an `X-API-Key` header. Pulse polls the selected system every five seconds while running and shares cached readings with the widget through a macOS App Group. Widgets have no credentials and perform no network requests.

**Widget redraw timing is controlled by macOS.** Pulse requests refreshes, but a five-second poll does not guarantee a five-second desktop widget update. The menu bar and dashboard display the app's latest readings directly.

The selected device is shared across Pulse widgets and the app. Legacy single-PC settings migrate automatically. Linux servers use a CPU, memory, and storage layout rather than empty GPU gauges.

## Troubleshooting

| Symptom | Check |
|---|---|
| Waiting for the device | Run its copied command; verify the public IPv4 address, HTTPS port, and cloud/OS/router rules. |
| Pairing command expired | Generate and run a new command. Check that the Mac and device clocks are correct. |
| Verification codes differ | Do not approve. Confirm the IP and rerun a fresh command on the intended device. |
| Approval response was lost | Use **Retry confirmation**. Pulse saved a recovery record before sending approval. |
| Certificate changed | Re-pair the device. Pulse never silently accepts a changed certificate. |
| Keychain error | Unlock your login Keychain and allow Pulse to access its device credentials. |
| Widget is stale | Keep Pulse running. Widgets use its cached readings; macOS controls redraw timing. |
| No system notification | The **Device ready** banner remains available in Advanced and the menu bar. |

To disconnect a paired device, choose **Advanced → gear → device → Revoke & remove device**. The device must be reachable so Pulse can revoke its credential first. To use it again, run a fresh pairing command.

## Development

```text
Pulse/             macOS menu bar, dashboard, and settings
PulseWidget/       WidgetKit layouts and timeline provider
Shared/            Models, system selection, caches, and App Intent
windows-agent/     Windows pairing installer and legacy LAN agent
linux-agent/       Linux pairing installer and legacy SSH/LAN installer
paired-agent/      Shared HTTPS agent and enrollment protocol
tests/             Linux endpoint and Swift storage/decoding checks
docs/images/       Widget previews using sample data
```

Run the local checks on macOS:

```bash
./tests/run.sh
```

These cover metric parsing, settings migration, secret-free profile serialization, isolated caches, expiry and replay rejection, concurrent approval, revocation, and a real Swift-to-Python HTTPS integration test including certificate pinning and redirect rejection. Windows installation and systemd startup require testing on their respective operating systems.

## Connection notes

New paired connections always use HTTPS with an explicitly verified certificate. The temporary command can appear in clipboard or shell history; it expires after ten minutes, and cannot authorize telemetry without approval. Pulse clears its copied command on cancellation, expiry, or completion if the clipboard has not since changed.

The agent is read-only; it has no terminal, file access, or remote-control endpoint. Use a fresh pairing command to replace a lost credential or changed certificate. Re-pairing the same agent revokes its previous controller.

Keep real configuration, certificate private keys, and API keys out of Git. Mac device credentials are kept in the login Keychain; shared profiles and widget snapshots contain no new credentials. Legacy plaintext configuration may remain as a migration backup from older installs.

[Pairing design](docs/PAIRING.md) · [Installation reference](GITHUB-INSTALL.md) · [Windows guide](windows-agent/README.md) · [Linux guide](linux-agent/README.md)
