import SwiftUI
import AppKit

/// The compact glyph/percent shown in the menu bar itself.
struct MenuBarLabel: View {
    @ObservedObject var monitor: PulseMonitor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: monitor.isReachable ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
            if let stats = monitor.latestStats {
                Text("\(Int(stats.cpu.percent))%")
            }
        }
    }
}

/// The dropdown panel shown when the menu bar item is clicked.
struct MenuBarContentView: View {
    @EnvironmentObject private var monitor: PulseMonitor
    let openAdvanced: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PulseTheme.cpuColor)
                    .frame(width: 40, height: 40)
                    .background(PulseTheme.cpuColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("PULSE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(monitor.settings.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                StatusPill(state: statusState, label: statusLabel)
            }

            Picker("System", selection: Binding(get: { monitor.settings.id }, set: monitor.selectSystem)) {
                ForEach(SettingsStore.profiles()) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)

            if let stats = monitor.latestStats {
                VStack(spacing: 16) {
                    row("CPU", stats.cpu.percent, PulseTheme.cpuColor)
                    row("RAM", stats.memory.percent, PulseTheme.ramColor)
                    row("GPU", stats.gpu.utilizationPercent, PulseTheme.gpuColor)
                    row("Disk", stats.disk.percent, PulseTheme.diskColor)
                }
                .padding(14)
                .background(PulseTheme.cardFill, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PulseTheme.cardStroke))
                if let updated = monitor.lastUpdated {
                    Label((monitor.isReachable ? "Updated " : "Last seen ") + PulseFormat.relativeTime(updated), systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(monitor.settings.isConfigured ? "Connecting to \(monitor.settings.name)…" : "Your system, at a glance.")
                        .font(.subheadline.weight(.medium))
                    Text(monitor.settings.isConfigured ? "Your metrics will appear here shortly." : "Open Advanced to set up your connection.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PulseTheme.cardFill, in: RoundedRectangle(cornerRadius: 14))
            }

            PairingMenuNotice(coordinator: monitor.pairing, openAdvanced: openAdvanced)

            HStack {
                Button(action: openAdvanced) {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(18)
        .frame(width: 310)
        .foregroundStyle(.white)
        .background(PulseTheme.backgroundGradient)
        .preferredColorScheme(.dark)
    }

    private var statusState: StatusPill.State {
        if monitor.latestStats == nil { return .unknown }
        return monitor.isReachable ? .live : .offline
    }

    private var statusLabel: String {
        if monitor.latestStats == nil { return monitor.settings.isConfigured ? "Connecting…" : "No data" }
        return monitor.isReachable ? "Online" : "Offline"
    }

    @ViewBuilder
    private func row(_ title: String, _ percent: Double?, _ color: Color) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 34, alignment: .leading)
            PulseBar(percent: percent ?? 0, color: color)
            Text(percent.map(PulseFormat.percent) ?? "N/A")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct PairingMenuNotice: View {
    @ObservedObject var coordinator: PairingCoordinator
    let openAdvanced: () -> Void
    var body: some View {
        if coordinator.identity != nil || coordinator.recovery != nil {
            Button {
                openAdvanced()
                coordinator.isPresented = true
            } label: {
                Label("Device ready · Review pairing", systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundStyle(PulseTheme.gpuColor)
            }
            .buttonStyle(.plain)
        }
    }
}
