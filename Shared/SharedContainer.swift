import Foundation

/// Where the main app and widget extension exchange settings + the cached
/// stats snapshot.
///
/// WidgetKit extensions must be sandboxed, so a normal
/// `~/Library/Application Support` file is not visible to both processes.
/// The supported bridge is a shared App Group container. On macOS the group
/// identifier must be prefixed with the signing Team ID (not `group.`).
enum SharedContainer {
    static let appGroupIdentifier =
        Bundle.main.object(forInfoDictionaryKey: "PulseAppGroupIdentifier") as? String
        ?? ""

    static let directory: URL? = {
        guard !appGroupIdentifier.isEmpty else { return nil }
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Location used by builds before the widget was moved back to a
    /// correctly signed App Group. The main app uses this only to migrate
    /// the user's existing settings and last snapshot on first launch.
    static let legacyDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Pulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var settingsFile: URL? { directory?.appendingPathComponent("settings.json") }
    static var snapshotFile: URL? { directory?.appendingPathComponent("snapshot.json") }
    static var legacySettingsFile: URL { legacyDirectory.appendingPathComponent("settings.json") }
    static var legacySnapshotFile: URL { legacyDirectory.appendingPathComponent("snapshot.json") }
}
