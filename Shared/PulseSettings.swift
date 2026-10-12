import Foundation
import CryptoKit

struct PulseSettings: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var apiKey: String
    var useTLS: Bool
    var certificateFingerprint: String?

    init(id: String = "pc", name: String = "PC", host: String, port: Int, apiKey: String, useTLS: Bool = false, certificateFingerprint: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.apiKey = apiKey
        self.useTLS = useTLS
        self.certificateFingerprint = certificateFingerprint
    }

    static let `default` = PulseSettings(host: "192.168.1.54", port: 8801, apiKey: "")
    static let oracle = PulseSettings(id: "vps", name: "Oracle VPS", host: "127.0.0.1", port: 8802, apiKey: "")

    enum CodingKeys: String, CodingKey { case id, name, host, port, apiKey, useTLS, certificateFingerprint }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? "pc"
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "PC"
        host = try values.decode(String.self, forKey: .host)
        port = try values.decode(Int.self, forKey: .port)
        apiKey = CredentialStore.isAvailable ? (try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ((try? CredentialStore.read(id)) ?? "")) : ""
        useTLS = try values.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
        certificateFingerprint = try values.decodeIfPresent(String.self, forKey: .certificateFingerprint)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(host, forKey: .host)
        try values.encode(port, forKey: .port)
        try values.encode(useTLS, forKey: .useTLS)
        try values.encodeIfPresent(certificateFingerprint, forKey: .certificateFingerprint)
        // Credentials are saved in the Mac app’s login Keychain, never in profile JSON.
    }

    var isConfigured: Bool { baseURL != nil && (!apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || certificateFingerprint != nil) }

    var baseURL: URL? {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, (1...65535).contains(port),
              !cleanHost.contains(where: { $0.isWhitespace }),
              !cleanHost.contains("/"), !cleanHost.contains("@"),
              !cleanHost.contains("?"), !cleanHost.contains("#") else { return nil }
        var components = URLComponents()
        components.scheme = useTLS ? "https" : "http"
        components.host = cleanHost
        components.port = port
        return components.url
    }

    // Endpoint changes get a fresh cache; a late response from another
    // system or an old connection can never populate this connection's UI.
    var cacheKey: String {
        let identity = [id, host, String(port), String(useTLS), certificateFingerprint ?? ""].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Profiles and selection live in separate files. Widget taps only write
/// selection, so they cannot overwrite credentials being edited in the app.
enum SettingsStore {
    private static var directory: URL { SharedContainer.directory ?? SharedContainer.legacyDirectory }
    private static var profilesFile: URL { directory.appendingPathComponent("systems.json") }
    private static var selectionFile: URL { directory.appendingPathComponent("selected-system.json") }

    static func profiles() -> [PulseSettings] {
        if let data = try? Data(contentsOf: profilesFile),
           let profiles = try? JSONDecoder().decode([PulseSettings].self, from: data),
           !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count {
            return profiles
        }
        let existing = SharedContainer.settingsFile.flatMap(decode) ?? decode(SharedContainer.legacySettingsFile) ?? .default
        return [PulseSettings(id: "pc", name: existing.name, host: existing.host, port: existing.port, apiKey: existing.apiKey, useTLS: existing.useTLS), .oracle]
    }

    static func load() -> PulseSettings {
        let profiles = profiles()
        let selected = (try? Data(contentsOf: selectionFile)).flatMap { try? JSONDecoder().decode(String.self, from: $0) }
        return profiles.first { $0.id == selected } ?? profiles[0]
    }

    static func save(_ settings: PulseSettings) throws {
        var all = profiles()
        if let index = all.firstIndex(where: { $0.id == settings.id }) { all[index] = settings }
        else { all.append(settings) }
        try saveProfiles(all)
    }

    static func saveProfiles(_ profiles: [PulseSettings]) throws {
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count else { throw CocoaError(.fileWriteInvalidFileName) }
        for profile in profiles where !profile.apiKey.isEmpty { try CredentialStore.save(profile.apiKey, id: profile.id) }
        try JSONEncoder().encode(profiles).write(to: profilesFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profilesFile.path)
    }

    static func select(_ id: String) throws {
        guard profiles().contains(where: { $0.id == id }) else { return }
        try JSONEncoder().encode(id).write(to: selectionFile, options: .atomic)
    }

    static func remove(_ id: String) throws {
        let remaining = profiles().filter { $0.id != id }
        try saveProfiles(remaining.isEmpty ? [.default, .oracle] : remaining)
        try CredentialStore.delete(id)
        if load().id == id { try select(remaining.first?.id ?? "pc") }
    }

    static var pendingApprovalFile: URL { directory.appendingPathComponent("pending-approval.json") }

    private static func decode(_ file: URL) -> PulseSettings? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(PulseSettings.self, from: data)
    }
}
