import SwiftUI

enum PulseTheme {
    static let cpuColor = Color(red: 0.40, green: 0.64, blue: 1.00)   // blue
    static let ramColor = Color(red: 0.68, green: 0.52, blue: 1.00)   // violet
    static let gpuColor = Color(red: 0.32, green: 0.87, blue: 0.64)   // mint green
    static let diskColor = Color(red: 1.00, green: 0.68, blue: 0.34)  // amber

    static func statusColor(forPercent percent: Double) -> Color {
        switch percent {
        case ..<60: return .green
        case 60..<85: return .yellow
        default: return .red
        }
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.085, green: 0.115, blue: 0.19),
                Color(red: 0.035, green: 0.045, blue: 0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardFill: Color { Color.white.opacity(0.06) }
    static var cardStroke: Color { Color.white.opacity(0.08) }
}
