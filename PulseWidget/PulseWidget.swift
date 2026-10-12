import WidgetKit
import SwiftUI

struct WidgetSystem: Identifiable {
    let id: String
    let name: String
}

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
    let systems: [WidgetSystem]
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
        systemName: String = "PC",
        systems: [WidgetSystem] = SettingsStore.profiles().map { WidgetSystem(id: $0.id, name: $0.name) }
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
        self.systems = systems
    }
}

/// Widgets read sanitized snapshots only. The running Mac app owns the
/// Keychain credentials, polls devices, and requests WidgetKit refreshes.
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
            var entries = [entry]
            if entry.isReachable, let fetchedAt = entry.fetchedAt {
                entries.append(PulseEntry(date: max(Date().addingTimeInterval(1), fetchedAt.addingTimeInterval(30)),
                                          stats: entry.stats, fetchedAt: fetchedAt, isReachable: false,
                                          history: entry.history, largeStyle: entry.largeStyle,
                                          systemID: entry.systemID, systemName: entry.systemName, systems: entry.systems))
            }
            completion(Timeline(entries: entries, policy: .after(nextReload)))
        }
    }

    private func currentEntry() async -> PulseEntry {
        let settings = SettingsStore.load()
        let cached = SharedStore.load(settings: settings)
        let fresh = cached.map { $0.isReachable && Date().timeIntervalSince($0.fetchedAt) < 30 } ?? false
        return PulseEntry(date: Date(), stats: cached?.stats, fetchedAt: cached?.fetchedAt,
                          isReachable: fresh, history: cached?.history ?? [], largeStyle: largeStyle,
                          diagnostic: "Keep Pulse running in the menu bar for fresh readings.",
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
