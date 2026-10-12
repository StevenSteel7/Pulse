import Foundation

struct PulseHistoryPoint: Codable, Equatable {
    let date: Date
    let vramPercent: Double
    let gpuPercent: Double
}

struct PulseCachedSnapshot: Codable {
    let stats: StatsResponse
    let fetchedAt: Date
    let history: [PulseHistoryPoint]
    let isReachable: Bool

    enum CodingKeys: String, CodingKey {
        case stats, fetchedAt, history, isReachable
    }

    init(stats: StatsResponse, fetchedAt: Date, history: [PulseHistoryPoint] = [], isReachable: Bool = true) {
        self.stats = stats
        self.fetchedAt = fetchedAt
        self.history = history
        self.isReachable = isReachable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stats = try container.decode(StatsResponse.self, forKey: .stats)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        history = try container.decodeIfPresent([PulseHistoryPoint].self, forKey: .history) ?? []
        isReachable = try container.decodeIfPresent(Bool.self, forKey: .isReachable) ?? true
    }
}

/// Caches the most recently *successfully* fetched snapshot in the shared
/// App Group file (see SharedContainer.swift). Whichever side fetches most recently —
/// the widget's own TimelineProvider, or the main app's more-frequent
/// menu-bar poller — wins, so the widget can always render the freshest
/// known value even between its own throttled refresh cycles, and can fall
/// back to it when that system is unreachable instead of showing nothing.
enum SharedStore {
    private static let maxHistoryPoints = 40

    private static func file(for settings: PulseSettings) -> URL {
        let directory = SharedContainer.directory ?? SharedContainer.legacyDirectory
        return directory.appendingPathComponent("snapshot-\(settings.cacheKey).json")
    }

    static func resetSnapshotCache() {
        for directory in [SharedContainer.directory, SharedContainer.legacyDirectory].compactMap({ $0 }) {
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                if file.lastPathComponent == "snapshot.json" || (file.lastPathComponent.hasPrefix("snapshot-") && file.pathExtension == "json") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    @discardableResult
    static func save(_ stats: StatsResponse, settings: PulseSettings, fetchedAt: Date = Date()) -> [PulseHistoryPoint] {
        let previous = load(settings: settings)
        // The app and extension may complete requests out of order.
        if let previous, previous.fetchedAt > fetchedAt { return previous.history }
        var history = previous?.history ?? []
        history.append(PulseHistoryPoint(date: fetchedAt, vramPercent: stats.gpu.vramPercent, gpuPercent: stats.gpu.utilizationPercent ?? 0))
        history = Array(history.suffix(maxHistoryPoints))
        let snapshot = PulseCachedSnapshot(stats: stats, fetchedAt: fetchedAt, history: history)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file(for: settings), options: .atomic)
        }
        return history
    }

    static func markUnreachable(settings: PulseSettings) {
        guard let cached = load(settings: settings) else { return }
        let updated = PulseCachedSnapshot(stats: cached.stats, fetchedAt: cached.fetchedAt, history: cached.history, isReachable: false)
        if let data = try? JSONEncoder().encode(updated) { try? data.write(to: file(for: settings), options: .atomic) }
    }

    static func load(settings: PulseSettings) -> PulseCachedSnapshot? {
        // Deliberately don't import the old unscoped snapshot: it has no
        // endpoint identity and could belong to a different machine.
        guard let data = try? Data(contentsOf: file(for: settings)) else { return nil }
        return try? JSONDecoder().decode(PulseCachedSnapshot.self, from: data)
    }
}
