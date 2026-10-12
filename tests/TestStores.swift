import Foundation

// Isolated filesystem substitute: never read or mutate the user's settings.
enum SharedContainer {
    static let legacyDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-tests-\(UUID().uuidString)")
    static let directory: URL? = legacyDirectory.appendingPathComponent("group")
    static var settingsFile: URL? { directory?.appendingPathComponent("settings.json") }
    static var legacySettingsFile: URL { legacyDirectory.appendingPathComponent("settings.json") }
}

// Keychain substitute for isolated storage tests; production uses Security.framework.
enum CredentialStore {
    static let isAvailable = true
    static var values: [String: String] = [:]
    static func read(_ id: String) throws -> String? { values[id] }
    static func save(_ secret: String, id: String) throws { values[id] = secret }
    static func delete(_ id: String) throws { values.removeValue(forKey: id) }
}

