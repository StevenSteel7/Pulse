import Foundation

enum PulseFormat {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func gb(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    static func mbAsGB(_ mb: Double) -> String {
        gb(mb / 1024.0)
    }

    static func uptime(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
