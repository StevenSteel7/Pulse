import Foundation
import Security

enum CredentialStore {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain access failed (\(status)). Unlock your login Keychain and allow Pulse to access its device credentials." }
    }

    // The Mac app owns credentials. Widgets consume only cached telemetry,
    // avoiding provisioned shared-Keychain requirements for personal builds.
    static var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "NSExtension") == nil }

    private static func query(_ id: String) -> [String: Any] {
        let value: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.stevensteel.pulse.devices",
                                   kSecAttrAccount as String: id,
                                   kSecUseDataProtectionKeychain as String: false]
        return value
    }

    static func read(_ id: String) throws -> String? {
        guard isAvailable else { return nil }
        var value = query(id)
        value[kSecReturnData as String] = true
        value[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(value as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ secret: String, id: String) throws {
        guard isAvailable else { throw Failure(status: errSecMissingEntitlement) }
        let value = query(id)
        let attributes = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(value as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addition = value.merging(attributes) { _, new in new }
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess { throw Failure(status: status) }
    }

    static func delete(_ id: String) throws {
        guard isAvailable else { throw Failure(status: errSecMissingEntitlement) }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
