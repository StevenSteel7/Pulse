import WidgetKit
import SwiftUI

enum LargeWidgetStyle {
    case graph
    case classic
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let stats: StatsResponse?
    let fetchedAt: Date?
    let isReachable: Bool
    let history: [PulseHistoryPoint]
    let largeStyle: LargeWidgetStyle
    let systemID: String
    let systemName: String
    /// Only set when `stats` is nil, to explain why directly in the widget's
    /// UI instead of requiring Console.app - the widget process is too
    /// short-lived to reliably catch in `log stream`. Never includes the
    /// actual API key value, only whether one is present.
    var diagnostic: String? = nil

    init(
        date: Date,
        stats: StatsResponse?,
        fetchedAt: Date?,
        isReachable: Bool,
        history: [PulseHistoryPoint] = [],
        largeStyle: LargeWidgetStyle = .graph,
        diagnostic: String? = nil,
        systemID: String = "pc",
        systemName: String = "PC"
    ) {
        self.date = date
        self.stats = stats
        self.fetchedAt = fetchedAt
        self.isReachable = isReachable
        self.history = history
        self.largeStyle = largeStyle
        self.diagnostic = diagnostic
        self.systemID = systemID
        self.systemName = systemName
    }
}

/// Refresh-rate reality check: WidgetKit does not let a widget "poll" in the
/// background on its own schedule — the system decides when to call
/// `getTimeline` again based on a per-widget refresh budget (typically a
/// handful of reloads per hour for an app the user isn't actively using).
/// Asking for a 1s/5s/30s reload policy here would just be ignored.
///
/// So this provider does the honest thing: each time the system *does* call
/// it, fetch fresh data and ask for another reload in a realistic window.
/// The gap between those system-driven reloads is covered by
/// `PulseMonitor` in the main app (see Pulse/PulseMonitor.swift), which
/// polls every few seconds while running and writes into the same App Group
/// cache, plus nudges `WidgetCenter.reloadTimelines` — so the widget shows
/// the freshest available value even when it isn't the one that just fetched it.
struct PulseTimelineProvider: TimelineProvider {
    let largeStyle: LargeWidgetStyle

    init(largeStyle: LargeWidgetStyle = .graph) {
        self.largeStyle = largeStyle
    }

    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(
            date: Date(),
            stats: .placeholder,
            fetchedAt: Date(),
            isReachable: true,
            history: [],
            largeStyle: largeStyle
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task {
            completion(await currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        Task {
            let entry = await currentEntry()
            let nextReload = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextReload)))
        }
    }

    private func currentEntry() async -> PulseEntry {
        // Retry a selection change during a fetch; don't publish PC data
        // with the VPS button selected (or vice versa).
        for _ in 0..<3 {
            let settings = SettingsStore.load()
            do {
                let stats = try await StatsClient.fetch(settings: settings, timeout: 4)
                guard SettingsStore.load() == settings else { continue }
                let now = Date()
                let history = SharedStore.save(stats, settings: settings, fetchedAt: now)
                return PulseEntry(date: now, stats: stats, fetchedAt: now, isReachable: true,
                                  history: history, largeStyle: largeStyle,
                                  systemID: settings.id, systemName: settings.name)
            } catch {
                guard SettingsStore.load() == settings else { continue }
                return cachedEntry(settings: settings)
            }
        }
        return cachedEntry(settings: SettingsStore.load())
    }

    private func cachedEntry(settings: PulseSettings) -> PulseEntry {
        let cached = SharedStore.load(settings: settings)
        return PulseEntry(date: Date(), stats: cached?.stats, fetchedAt: cached?.fetchedAt,
                          isReachable: false, history: cached?.history ?? [], largeStyle: largeStyle,
                          diagnostic: settings.isConfigured ? "Check the agent or network connection." : "Add this system's API key in Advanced → Settings.",
                          systemID: settings.id, systemName: settings.name)
    }

}

struct PulseWidget: Widget {
    let kind: String = "PulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseTimelineProvider(largeStyle: .graph)) { entry in
            PulseWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Pulse Systems")
        .description("Switch between your PC and VPS for live system stats.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PulseClassicLargeWidget: Widget {
    let kind: String = "PulseClassicLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseTimelineProvider(largeStyle: .classic)) { entry in
            PulseWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Pulse Systems — Classic")
        .description("Your PC and VPS with classic gauges and usage bars.")
        .supportedFamilies([.systemLarge])
    }
}
