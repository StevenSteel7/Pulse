import SwiftUI

/// A circular percent gauge. Kept deliberately simple (Shape + stroke, no
/// materials/blurs) since it's shared with the widget extension, where
/// rendering is more constrained than in the main app's window.
struct PulseRing: View {
    let percent: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, percent / 100)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A horizontal percent bar used for RAM/VRAM/Disk rows.
struct PulseBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.18))
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0, min(1, percent / 100)))
            }
        }
        .frame(height: 6)
    }
}

/// Small "Online / Offline / Not configured" badge shown in the app,
/// menu bar panel, and every widget size.
struct StatusPill: View {
    enum State { case live, offline, unknown }

    let state: State
    let label: String

    private var color: Color {
        switch state {
        case .live: return .green
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }
}

/// Compact ring + percent + title, used for the small widget and menu bar.
struct MiniRingStat: View {
    let title: String
    let percent: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                PulseRing(percent: percent, color: color, lineWidth: 5)
                Text(PulseFormat.percent(percent))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}
