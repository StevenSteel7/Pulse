import Foundation
import CryptoKit

enum PairingFailure: LocalizedError {
    case invalidAddress, expired, identityMismatch, invalidProof, unavailable, rejected
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a public IPv4 address and a port between 1024 and 65535."
        case .expired: return "Pairing expired. Generate and run a new install command."
        case .identityMismatch: return "The device identity doesn't match. Do not approve it. Generate a new pairing command."
        case .invalidProof: return "The device couldn't prove it has your pairing token. Check the address and install command."
        case .unavailable: return "Waiting for the agent. Check that its HTTPS port is reachable through the firewall or router."
        case .rejected: return "The device rejected pairing. The command may have expired or already been used."
        }
    }
}

enum PairingPlatform: String, CaseIterable, Identifiable {
    case windows = "Windows", linux = "Linux"
    var id: String { rawValue }
}

struct PairingInvitation {
    let host: String
    let port: Int
    let platform: PairingPlatform
    let token: String
    let expires: Int

    init(host: String, port: Int, platform: PairingPlatform, now: Date = Date()) throws {
        guard Self.isPublicIPv4(host), (1024...65535).contains(port) else { throw PairingFailure.invalidAddress }
        self.host = host
        self.port = port
        self.platform = platform
        token = PairingProtocol.randomSecret()
        expires = Int(now.timeIntervalSince1970) + 600
    }

    static func isPublicIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4, zip(parts, octets).allSatisfy({ String($0.0) == String($0.1) }) else { return false }
        let a = Int(octets[0]), b = Int(octets[1]), c = Int(octets[2])
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) { return false }
        if a == 192 && (b == 168 || b == 0 && (c == 0 || c == 2)) { return false }
        if a == 198 && ((18...19).contains(b) || b == 51 && c == 100) { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }

    var command: String {
        let base = "https://raw.githubusercontent.com/StevenSteel7/Pulse/main"
        switch platform {
        case .linux:
            return "curl -fsSL --proto '=https' --tlsv1.2 \(base)/linux-agent/pair.sh -o pulse-pair.sh && sudo bash pulse-pair.sh --token \(token) --expires \(expires) --port \(port)"
        case .windows:
            return "Invoke-WebRequest -UseBasicParsing '\(base)/windows-agent/pair.ps1' -OutFile \"$env:TEMP\\pulse-pair.ps1\"; if ($?) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$env:TEMP\\pulse-pair.ps1\" -Token \(token) -Expires \(expires) -Port \(port) }"
        }
    }
}

struct PairingIdentity: Codable, Equatable {
    let protocolVersion: String
    let nonce: String
    let deviceID: String
    let hostname: String
    let os: String
    let expires: Int
    let fingerprint: String
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol", deviceID = "device_id"
        case nonce, hostname, os, expires, fingerprint
    }
    var verificationCode: String {
        let value = Array(fingerprint.prefix(16).uppercased())
        return stride(from: 0, to: value.count, by: 4).map { String(value[$0..<min($0 + 4, value.count)]) }.joined(separator: "-")
    }
}

enum PairingProtocol {
    static func randomSecret() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    }

    static func hexData(_ string: String, bytes: Int) -> Data? {
        guard string.count == bytes * 2, string.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        let chars = Array(string)
        return Data(stride(from: 0, to: chars.count, by: 2).compactMap { UInt8(String(chars[$0...($0 + 1)]), radix: 16) })
    }

    static func verify(data: Data, token: String, nonce: String, fingerprint: String,
                       expectedExpiry: Int, platform: PairingPlatform, now: Date = Date()) throws -> PairingIdentity {
        struct Envelope: Decodable { let payload: String; let proof: String }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let key = hexData(token, bytes: 32), let proof = hexData(envelope.proof, bytes: 32),
              HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: Data(envelope.payload.utf8), using: SymmetricKey(data: key)) else {
            throw PairingFailure.invalidProof
        }
        let identity = try JSONDecoder().decode(PairingIdentity.self, from: Data(envelope.payload.utf8))
        guard identity.protocolVersion == "pulse-pair-v1", identity.nonce == nonce,
              identity.fingerprint == fingerprint, hexData(fingerprint, bytes: 32) != nil,
              hexData(identity.deviceID, bytes: 16) != nil, identity.os == platform.rawValue,
              identity.expires == expectedExpiry else { throw PairingFailure.identityMismatch }
        guard identity.expires > Int(now.timeIntervalSince1970) else { throw PairingFailure.expired }
        return identity
    }

    static func probe(_ invitation: PairingInvitation) async throws -> PairingIdentity {
        guard Date().timeIntervalSince1970 < Double(invitation.expires) else { throw PairingFailure.expired }
        let nonce = randomSecret()
        let url = URL(string: "https://\(invitation.host):\(invitation.port)/pairing?nonce=\(nonce)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        let result = try await SecureHTTP.send(request, discovery: true)
        guard result.status == 200, let fingerprint = result.fingerprint else { throw PairingFailure.unavailable }
        return try verify(data: result.data, token: invitation.token, nonce: nonce, fingerprint: fingerprint,
                          expectedExpiry: invitation.expires, platform: invitation.platform)
    }

    static func approve(_ invitation: PairingInvitation, profile: PulseSettings) async throws {
        guard Date().timeIntervalSince1970 < Double(invitation.expires) else { throw PairingFailure.expired }
        var request = URLRequest(url: profile.baseURL!.appendingPathComponent("pairing/approve"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": invitation.token, "credential": profile.apiKey])
        let result = try await SecureHTTP.send(request, pin: profile.certificateFingerprint)
        guard result.status == 200 else { throw PairingFailure.rejected }
    }

    static func revoke(_ profile: PulseSettings) async throws {
        guard profile.certificateFingerprint != nil, let base = profile.baseURL else { throw PairingFailure.identityMismatch }
        var request = URLRequest(url: base.appendingPathComponent("revoke"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue(profile.apiKey, forHTTPHeaderField: "X-API-Key")
        let result = try await SecureHTTP.send(request, pin: profile.certificateFingerprint)
        guard result.status == 200 else { throw PairingFailure.rejected }
    }
}
