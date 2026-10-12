# Pulse Linux agent

A **single self-contained installer** for systemd-based Ubuntu, Debian, and
Oracle Linux. Runs on ARM64 (including Oracle Ampere) and x86-64. It detects
vCPU count, usable RAM, CPU usage, root filesystem usage, and uptime; it does
not hardcode the 4-vCPU / 24-GB plan. Linux may report slightly less than the
advertised RAM. GPU telemetry is intentionally unavailable on this VPS agent.

No pip packages, virtual environment, or container required. The script
installs Python 3 if missing, generates a unique API key, writes a restricted
systemd service, enables it at boot, starts it, and verifies an authenticated
stats response. Reinstalling preserves the API key, bind address, and port.

## Install on your VPS

Copy `install.sh` to the VPS and run:

```bash
sudo bash install.sh
```

The default binds to **127.0.0.1:8801**. On your **Mac**, keep this tunnel running
(replace `USER` with your SSH username, commonly `ubuntu` or `opc`, and
`VPS_IP` with your VPS address):

```bash
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:8802:127.0.0.1:8801 USER@VPS_IP
```

In **Pulse menu bar → Advanced → gear → Oracle VPS**:

- Host: `127.0.0.1`
- Port: `8802`
- HTTPS: off (SSH encrypts the connection)
- API key: the key printed by the installer

Save, then click **VPS** on the widget. Click **PC** to return to your Windows
machine. Selection is shared across all Pulse widgets, the menu bar, and the
dashboard. Buttons do not open an app window. Configure both systems once;
each retains separate credentials, cached readings, and graph history.

The SSH connection must remain alive while monitoring. Closing its terminal
or disconnecting the tunnel makes the VPS appear offline. This setup needs
only your existing SSH access; it does not require opening another public port.

## Optional direct private/VPN connection

If the Mac can already reach the VPS over a private network or VPN, bind to
that VPS interface's local IP (it must exist on the VPS):

```bash
sudo bash install.sh --bind 10.0.0.10 --port 8801
```

Use that reachable IP and port `8801` in Pulse. Private Oracle VCN IPs are not
reachable from your home Mac without routing/VPN access. A public Oracle IP
may be NAT-mapped and cannot necessarily be bound directly inside the VM.

The service speaks HTTP with an `X-API-Key` header. Use SSH/VPN for encryption,
or place it behind an HTTPS reverse proxy and enable HTTPS in Pulse. If you
choose direct access, configure both Oracle's NSG/security-list ingress and
the OS firewall for the intended source. This installer changes neither.
See [Oracle security rules](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securityrules.htm).

## Install directly from GitHub

Yes. Once the project is in a **public GitHub repository**, users can run one
shell command. Replace `OWNER`, `REPO`, and `main` (or use a release tag/commit):

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/macos-app/linux-agent/install.sh -o pulse-install.sh && sudo bash pulse-install.sh
```

This assumes the repository contains `macos-app/` and `windows-agent/` at its
root, matching the current parent project. If you publish **only macos-app** as
the repository root, remove `macos-app/` from the URL. A private repository
requires authenticated download. The downloaded file is complete before it
runs; there are no second-stage downloads of agent source code.

This Linux Bash script doesn't install the Windows agent. For Windows, the
existing `windows-agent/install.bat` installs its dependencies, firewall rule,
and scheduled task after the folder has been downloaded. A single PowerShell
command can download the repository archive and run that installer; see
[GitHub installation](../GITHUB-INSTALL.md). Windows still needs Python 3.10+
and its normal administrator/UAC approval.

## Manage the service

```bash
sudo systemctl status pulse-agent --no-pager
sudo journalctl -u pulse-agent -n 40 --no-pager
sudo systemctl restart pulse-agent
sudo systemctl disable --now pulse-agent
```

Files:

- `/opt/pulse-agent/agent.py`: installed read-only telemetry agent
- `/etc/pulse-agent/config.json`: persistent connection settings and API key (root only)
- `/etc/pulse-agent/agent.env`: service environment (root only)
- `/etc/systemd/system/pulse-agent.service`: boot service, runs as a dynamic unprivileged user

To display your existing key again: `sudo cat /etc/pulse-agent/config.json`.
To change the address/port, rerun the installer with `--bind`/`--port`.

`GET /health` returns `{"ok":true}` without credentials. `GET /stats` requires
`X-API-Key` and returns the same JSON schema as the Windows agent. Samples are
collected once per second; the app polls every five seconds while running.
The server limits concurrent requests and request read time, and never logs
request headers. WidgetKit controls the final widget redraw schedule.

## Verification

From the macOS project: `./tests/run.sh`. Tests extract the actual embedded
Python agent, exercise metric parsing and HTTP authentication, and decode its
JSON with the app's real Swift models. Storage tests cover old-settings
migration, system selection, separate caches/history, and endpoint changes.
A full systemd installation must be exercised on Linux; the macOS tests do
not claim to validate Oracle networking or service startup on a real VPS.
