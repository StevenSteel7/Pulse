import Foundation

@main
struct PairingIntegration {
    struct Server: Decodable { let port: Int; let token: String; let expires: Int; let fingerprint: String }
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func mustThrow(_ label: String, action: () async throws -> Void) async {
        do { try await action(); fatalError("Expected rejection: \(label)") } catch { }
    }
    static func main() async throws {
        let server = try JSONDecoder().decode(Server.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let base = "https://127.0.0.1:\(server.port)"
        let nonce = PairingProtocol.randomSecret()
        var probe = URLRequest(url: URL(string: base + "/pairing?nonce=\(nonce)")!)
        probe.httpMethod = "GET"
        probe.timeoutInterval = 4
        let discovered = try await SecureHTTP.send(probe, discovery: true)
        check(discovered.status == 200, "Discovery responds over self-signed TLS")
        check(discovered.fingerprint == server.fingerprint, "Capture actual peer certificate")
        let identity = try PairingProtocol.verify(data: discovered.data, token: server.token, nonce: nonce,
            fingerprint: discovered.fingerprint!, expectedExpiry: server.expires, platform: .linux)
        check(identity.verificationCode.count == 19, "Human verification code")
        await mustThrow("wrong TLS certificate") {
            _ = try await SecureHTTP.send(probe, pin: String(repeating: "0", count: 64))
        }
        await mustThrow("untrusted self-signed certificate without enrollment mode") {
            _ = try await SecureHTTP.send(probe)
        }
        await mustThrow("token mismatch") {
            _ = try PairingProtocol.verify(data: discovered.data, token: String(repeating: "f", count: 64), nonce: nonce,
                fingerprint: server.fingerprint, expectedExpiry: server.expires, platform: .linux)
        }
        await mustThrow("replayed nonce") {
            _ = try PairingProtocol.verify(data: discovered.data, token: server.token, nonce: "wrong",
                fingerprint: server.fingerprint, expectedExpiry: server.expires, platform: .linux)
        }
        await mustThrow("MITM certificate replacement") {
            _ = try PairingProtocol.verify(data: discovered.data, token: server.token, nonce: nonce,
                fingerprint: String(repeating: "0", count: 64), expectedExpiry: server.expires, platform: .linux)
        }
        await mustThrow("expired proof") {
            _ = try PairingProtocol.verify(data: discovered.data, token: server.token, nonce: nonce,
                fingerprint: server.fingerprint, expectedExpiry: server.expires, platform: .linux, now: Date(timeIntervalSince1970: Double(server.expires + 1)))
        }
        let profile = PulseSettings(id: "integration", name: "Test", host: "127.0.0.1", port: server.port,
            apiKey: String(repeating: "b", count: 64), useTLS: true, certificateFingerprint: server.fingerprint)
        await mustThrow("telemetry before approval") { _ = try await StatsClient.fetch(settings: profile) }
        var approval = URLRequest(url: URL(string: base + "/pairing/approve")!)
        approval.httpMethod = "POST"
        approval.httpBody = try JSONSerialization.data(withJSONObject: ["token": server.token, "credential": profile.apiKey])
        approval.timeoutInterval = 4
        let approved = try await SecureHTTP.send(approval, pin: server.fingerprint)
        check(approved.status == 200, "Approval succeeds over pinned TLS")
        let stats = try await StatsClient.fetch(settings: profile)
        check(stats.cpu.logicalCores == 4, "Real Swift client can read Linux stats after approval")
        let replay = try await SecureHTTP.send(approval, pin: server.fingerprint)
        check(replay.status == 403, "Enrollment token consumed")
        var redirect = URLRequest(url: URL(string: base + "/redirect")!)
        redirect.setValue(profile.apiKey, forHTTPHeaderField: "X-API-Key")
        let redirected = try await SecureHTTP.send(redirect, pin: server.fingerprint)
        check(redirected.status == 302, "Credential-bearing redirects are never followed")
        await mustThrow("large response") {
            _ = try await SecureHTTP.send(URLRequest(url: URL(string: base + "/oversize")!), pin: server.fingerprint)
        }
        var insecure = profile
        insecure.useTLS = false
        await mustThrow("HTTP downgrade") { _ = try await StatsClient.fetch(settings: insecure) }
        var credentialProbe = probe
        credentialProbe.setValue(profile.apiKey, forHTTPHeaderField: "X-API-Key")
        await mustThrow("discovery never carries credentials") { _ = try await SecureHTTP.send(credentialProbe, discovery: true) }
        try await PairingProtocol.revoke(profile)
        try await PairingProtocol.revoke(profile)
        await mustThrow("revoked credential") { _ = try await StatsClient.fetch(settings: profile) }
        check(PairingInvitation.isPublicIPv4("8.8.8.8"), "Public IPv4 allowed")
        for host in ["127.0.0.1", "192.168.1.1", "10.0.0.1", "100.64.0.1", "203.0.113.1", "1.2.3.4;touch /tmp/x", "https://8.8.8.8", "::1"] {
            check(!PairingInvitation.isPublicIPv4(host), "Reject nonpublic or invalid host: \(host)")
        }
        let invitation = try PairingInvitation(host: "8.8.8.8", port: 8843, platform: .linux)
        check(invitation.command.contains("--token " + invitation.token), "Linux command includes enrollment token")
        check(!invitation.command.contains("api-key"), "No permanent key in install command")
        print("PASS: real Swift↔Python HTTPS pairing, proof verification, pinning, approval, replay rejection, redirects, response limits, HTTP downgrade, and revocation")
    }
}
