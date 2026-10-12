#!/usr/bin/env bash
# Public-IP enrollment installer; copied from Pulse > Add device.
set -euo pipefail
umask 077
PAIR_TOKEN=''
PAIR_EXPIRES=''
PAIR_PORT=8843
PAIR_REF=main
while (($#)); do
    case "$1" in
        --token) PAIR_TOKEN="${2:?missing token}"; shift 2 ;;
        --expires) PAIR_EXPIRES="${2:?missing expiry}"; shift 2 ;;
        --port) PAIR_PORT="${2:?missing port}"; shift 2 ;;
        --ref) PAIR_REF="${2:?missing ref}"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done
[[ $(uname -s) == Linux && $EUID == 0 ]] || { echo 'Run on Linux with sudo.' >&2; exit 1; }
[[ "$PAIR_TOKEN" =~ ^[0-9a-f]{64}$ && "$PAIR_EXPIRES" =~ ^[0-9]+$ && "$PAIR_PORT" =~ ^[0-9]+$ && "$PAIR_REF" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'Use a fresh install command from Pulse.' >&2; exit 1; }
command -v systemctl >/dev/null || { echo 'systemd is required.' >&2; exit 1; }
if ! command -v python3 >/dev/null || ! command -v openssl >/dev/null || ! command -v curl >/dev/null; then
    if command -v apt-get >/dev/null; then
        apt-get update
        apt-get install -y python3 openssl curl ca-certificates
    elif command -v dnf >/dev/null; then
        dnf install -y python3 openssl curl ca-certificates
    else
        echo 'Install python3, openssl, curl, and ca-certificates, then rerun.' >&2; exit 1
    fi
fi
PAIR_STAGE=$(mktemp -d)
trap 'rm -rf "$PAIR_STAGE"' EXIT
curl -fsSL --proto '=https' --tlsv1.2 "https://raw.githubusercontent.com/StevenSteel7/Pulse/$PAIR_REF/paired-agent/agent.py" -o "$PAIR_STAGE/agent.py"
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$PAIR_STAGE/agent.py"
if ! id pulse-paired >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/pulse-paired --shell /sbin/nologin pulse-paired
fi
install -d -m 755 /opt/pulse-paired
install -d -m 700 -o pulse-paired -g pulse-paired /var/lib/pulse-paired
# Validate expiry before disturbing any existing service.
python3 - "$PAIR_EXPIRES" "$PAIR_PORT" <<'PY'
import sys,time
assert int(time.time()) < int(sys.argv[1]) <= int(time.time()) + 660, 'Pairing expired. Copy a new command from Pulse.'
assert 1024 <= int(sys.argv[2]) <= 65535, 'Invalid port'
PY
systemctl stop pulse-paired.service 2>/dev/null || true
install -m 644 "$PAIR_STAGE/agent.py" /opt/pulse-paired/agent.py
runuser -u pulse-paired -- python3 /opt/pulse-paired/agent.py --state-dir /var/lib/pulse-paired --configure --token "$PAIR_TOKEN" --expires "$PAIR_EXPIRES" --port "$PAIR_PORT"
PAIR_PYTHON=$(command -v python3)
cat > /etc/systemd/system/pulse-paired.service <<SERVICE
[Unit]
Description=Pulse HTTPS paired telemetry agent
After=network-online.target
Wants=network-online.target
[Service]
User=pulse-paired
Group=pulse-paired
ExecStart=$PAIR_PYTHON -B /opt/pulse-paired/agent.py --state-dir /var/lib/pulse-paired
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/pulse-paired
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=
UMask=0077
[Install]
WantedBy=multi-user.target
SERVICE
chmod 644 /etc/systemd/system/pulse-paired.service
systemctl daemon-reload
systemctl enable --now pulse-paired.service
systemctl is-active --quiet pulse-paired.service
runuser -u pulse-paired -- python3 /opt/pulse-paired/agent.py --state-dir /var/lib/pulse-paired --check
echo "Agent started. Allow inbound TCP $PAIR_PORT in your OS firewall and Oracle security rules, then approve the matching code in Pulse."
echo 'Existing legacy agents have not been modified. Logs: sudo journalctl -u pulse-paired -n 40'
