import Foundation
import WidgetKit

@MainActor
final class PulseMonitor: ObservableObject {
    @Published private(set) var latestStats: StatsResponse?
    @Published private(set) var history: [PulseHistoryPoint] = []
    @Published private(set) var isReachable = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var settings: PulseSettings

    private var pollTask: Task<Void, Never>?
    private var lastPoll = Date.distantPast

    init() {
        settings = SettingsStore.load()
        // Materialize legacy settings in the App Group before the sandboxed
        // extension tries to read them. Never print credentials on failure.
        do { try SettingsStore.saveProfiles(SettingsStore.profiles()) }
        catch { lastError = "Couldn't migrate system settings: \(error.localizedDescription)" }
        restoreSnapshot()
        start()
    }

    private func restoreSnapshot() {
        let cached = SharedStore.load(settings: settings)
        latestStats = cached?.stats
        lastUpdated = cached?.fetchedAt
        history = cached?.history ?? []
        isReachable = false
        lastError = nil
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let current = SettingsStore.load()
                if current != self.settings {
                    self.settings = current
                    self.restoreSnapshot()
                    self.lastPoll = .distantPast
                }
                if Date().timeIntervalSince(self.lastPoll) >= 5 {
                    self.lastPoll = Date()
                    await self.pollOnce()
                }
                // Detect selection changes from widget intents promptly.
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func selectSystem(_ id: String) {
        do {
            try SettingsStore.select(id)
            settings = SettingsStore.load()
            restoreSnapshot()
            lastPoll = .distantPast
            start()
            reloadWidgets()
        } catch { lastError = "Couldn't switch systems: \(error.localizedDescription)" }
    }

    func applySettings(_ profiles: [PulseSettings], selectedID: String) throws {
        try SettingsStore.saveProfiles(profiles)
        try SettingsStore.select(selectedID)
        settings = SettingsStore.load()
        restoreSnapshot()
        lastPoll = .distantPast
        start()
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "PulseWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "PulseClassicLargeWidget")
    }

    private func pollOnce() async {
        let requested = settings
        do {
            let stats = try await StatsClient.fetch(settings: requested, timeout: 3)
            guard !Task.isCancelled, SettingsStore.load() == requested else { return }
            let now = Date()
            latestStats = stats
            lastUpdated = now
            isReachable = true
            lastError = nil
            history = SharedStore.save(stats, settings: requested, fetchedAt: now)
            reloadWidgets()
        } catch {
            guard !Task.isCancelled, SettingsStore.load() == requested else { return }
            isReachable = false
            lastError = "\(error)"
            reloadWidgets()
        }
    }
}
