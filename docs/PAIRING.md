# Direct public-IP pairing

## User flow

1. In **Advanced → Add device**, select Windows/Linux and enter public IPv4 + port.
2. Generate the command. Pulse creates a 256-bit random token with an absolute ten-minute expiry and copies a platform-specific command.
3. Run it on the target device. It installs a separate HTTPS agent, creates a self-signed RSA certificate, and prints a 16-hex-digit verification code derived from that certificate.
4. Pulse polls the supplied address. A verified response produces an in-app banner and, when permitted, a local macOS notification.
5. Compare the installer and app codes, enter a name, and approve.
6. Pulse creates an independent 256-bit device credential. The agent consumes the pairing token and allows read-only telemetry.

No relay, public Mac address, domain, or public CA certificate is required. Public IPv6 and hostname onboarding are not implemented in this version. The chosen TCP port must be reachable; NAT forwarding and cloud/OS firewall rules remain your responsibility.

## Trust establishment

Discovery is the **only** request allowed to observe an unknown TLS certificate. It is an unauthenticated `GET /pairing?nonce=...`; it sends neither a pairing token nor an API credential.

The agent returns an exact UTF-8 JSON payload plus `HMAC-SHA256(pairing_token, payload_bytes)`. The authenticated payload includes protocol version, a fresh client nonce, device ID, reported OS/hostname, expiry, and SHA-256 of the agent's certificate DER.

Pulse validates the HMAC, nonce, platform, expiry, and that the signed fingerprint equals the certificate actually presented on its TLS connection. This prevents a relay that terminates TLS with a different certificate from borrowing the real device's proof. Approval additionally requires the user to confirm the installer code matches.

`POST /pairing/approve` uses the verified certificate pin and installs a newly generated credential. The token is atomically erased, and the agent stores only SHA-256 of the high-entropy credential. Concurrent approvals have one winner. An expired or consumed token cannot approve another credential over the network.

All subsequent stats and revocation requests require the pinned certificate and the device credential. HTTP downgrade and redirects are rejected. Responses are size-limited. The server limits concurrent connections, applies handshake/read timeouts, and rate-limits HTTP requests. It does not log tokens, headers, or request bodies.

## Storage and widget behavior

- **Mac:** permanent credentials are stored in the login Keychain under Pulse's application access controls. This uses the macOS file-based Keychain so personal development builds do not require provisioned shared Keychain groups.
- **Profiles:** device IDs, names, addresses, ports, and certificate pins are shared through the App Group. New profile JSON contains no credentials.
- **Widgets:** read sanitized cached metrics only. No credentials or network access are needed. Pulse must run for fresh telemetry; cached values remain visible when it stops.
- **Agent:** private TLS key and state have owner-only access on Linux and a restricted ACL on Windows. The temporary token exists there only while enrollment is pending; the permanent credential is stored only as a hash.

Older `settings.json` files may remain as legacy migration backups. New credentials are never written to them.

## Recovery, cancellation, and removal

Before sending approval, Pulse writes the new credential to Keychain and a secret-free pending-approval record to the App Group. If the response is lost or the app exits, **Retry confirmation** checks the retained credential against the pinned device and completes the profile save. A recovery record remains until successful completion or explicit discard.

If approval never reached the device and the app lost its temporary invitation, discard the attempt and generate a new command. A new enrollment installed on the same device replaces its previous controller. Do not discard an uncertain approval unless you are prepared to re-pair that device.

**Cancel pairing** stops local polling and clears Pulse's copy of the token. An already-installed agent still holds its pending token until its original expiry; cancellation is not remote revocation. It cannot expose stats until approved. Reinstall with a new invitation to immediately replace the pending token.

**Revoke & remove device** first makes an authenticated, pinned request that disables telemetry for that credential, then deletes the local profile and Keychain item. The device must be online. Revocation retries are idempotent, including after a lost response.

## Installers

- [Linux](../linux-agent/pair.sh): Python + OpenSSL, dedicated `pulse-paired` user, systemd startup, local pinned HTTPS health check. Uses port 8843 by default; doesn't alter cloud/firewall rules.
- [Windows](../windows-agent/pair.ps1): Python 3.10+, psutil, cryptography, restricted directory ACL, `PulsePairedAgent` logon task, Windows Firewall rule, local pinned HTTPS health check.
- Both download [the shared agent](../paired-agent/agent.py) from GitHub. These files must be published before generated commands can work. Legacy installers remain separate.

The ten-minute deadline includes installation. If dependency setup takes too long, generate another command; installed dependencies can be reused. Keep both machines' clocks synchronized.

## Verification and limits

`./tests/run.sh` covers local agent behavior and uses a real self-signed HTTPS server with the production Swift networking code to test proof checking, certificate binding, pin mismatch, token replay, approval, revocation, redirects, response limits, and HTTP downgrade rejection.

Signed local Keychain helpers verify actual macOS credential write/read/delete. A signed app/widget build verifies compilation. These checks do not replace an installation test on Windows or a systemd-based Linux host, nor do they constitute an independent security audit of the enrollment protocol.
