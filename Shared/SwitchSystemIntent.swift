import AppIntents
import WidgetKit

struct SwitchSystemIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch monitored system"
    static var description = IntentDescription("Display another saved system in Pulse.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "System ID") var systemID: String

    init() {}
    init(systemID: String) { self.systemID = systemID }

    func perform() async throws -> some IntentResult {
        try SettingsStore.select(systemID)
        WidgetCenter.shared.reloadTimelines(ofKind: "PulseWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "PulseClassicLargeWidget")
        return .result()
    }
}
