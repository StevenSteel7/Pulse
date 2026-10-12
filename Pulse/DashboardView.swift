import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var monitor: PulseMonitor
    @State private var showSettings = false

    var body: some View {
        ZStack {
            PulseTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                DevicePairingControls(coordinator: monitor.pairing)
                Picker("System", selection: Binding(get: { monitor.settings.id }, set: monitor.selectSystem)) {
                    ForEach(SettingsStore.profiles()) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                ScrollView {
                    if let stats = monitor.latestStats {
                        statsGrid(stats)
                    } else {
                        emptyState
                    }
                }
                .scrollIndicators(.hidden)
                footer
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: monitor.settings) { updated, selectedID in
                try monitor.applySettings(updated, selectedID: selectedID)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("SYSTEM OVERVIEW")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(PulseTheme.cpuColor)
                Text(monitor.settings.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                StatusPill(state: statusState, label: statusLabel)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(PulseTheme.cardFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .help("Connection and widget settings")
            .accessibilityLabel("Settings")
        }
    }

    private var statusState: StatusPill.State {
        if monitor.latestStats == nil { return .unknown }
        return monitor.isReachable ? .live : .offline
    }

    private var statusLabel: String {
        if monitor.latestStats == nil { return monitor.settings.isConfigured ? "Connecting…" : "Not configured" }
        return monitor.isReachable ? "Online" : "Offline"
    }

    @ViewBuilder
    private func statsGrid(_ stats: StatsResponse) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(title: "CPU", percent: stats.cpu.percent, color: PulseTheme.cpuColor, detail: "\(stats.cpu.logicalCores) threads")
                StatCard(title: "RAM", percent: stats.memory.percent, color: PulseTheme.ramColor, detail: "\(PulseFormat.gb(stats.memory.usedGB)) / \(PulseFormat.gb(stats.memory.totalGB))")
            }
            HStack(spacing: 16) {
                if stats.gpu.available {
                    StatCard(title: "GPU", percent: stats.gpu.utilizationPercent ?? 0, color: PulseTheme.gpuColor, detail: stats.gpu.temperatureC.map { "\(Int($0))°C" } ?? "N/A")
                }
                StatCard(title: "Disk", percent: stats.disk.percent, color: PulseTheme.diskColor, detail: "\(PulseFormat.gb(stats.disk.usedGB)) / \(PulseFormat.gb(stats.disk.totalGB))")
            }
            if stats.gpu.available {
                GPUUsageGraph(gpu: stats.gpu)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.4))
            Text(monitor.settings.isConfigured ? "Waiting for \(monitor.settings.name)…" : "No connection configured yet")
                .foregroundStyle(.white.opacity(0.7))
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            if let stats = monitor.latestStats {
                Label(PulseFormat.uptime(stats.uptimeSeconds), systemImage: "clock")
            }
            Spacer()
            if let updated = monitor.lastUpdated {
                Text((monitor.isReachable ? "Updated " : "Last seen ") + PulseFormat.relativeTime(updated))
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.45))
    }
}

private struct StatCard: View {
    let title: String
    let percent: Double
    let color: Color
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                PulseRing(percent: percent, color: color, lineWidth: 8)
                Text(PulseFormat.percent(percent))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            Text(title).font(.subheadline.bold()).foregroundStyle(.white.opacity(0.85))
            Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [color.opacity(0.12), PulseTheme.cardFill], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(PulseTheme.cardStroke, lineWidth: 1))
    }
}

private struct GPUUsageGraph: View {
    let gpu: GPUStats

    private var gpuUsage: Double {
        gpu.utilizationPercent ?? 0
    }

    private var vramUsage: Double {
        gpu.vramPercent
    }

    private var vramText: String {
        guard let used = gpu.vramUsedMB, let total = gpu.vramTotalMB else { return "N/A" }
        return "\(PulseFormat.mbAsGB(used)) / \(PulseFormat.mbAsGB(total))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GPU Usage").font(.caption).fontWeight(.semibold).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(PulseFormat.percent(gpuUsage)).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            PulseBar(percent: gpuUsage, color: PulseTheme.gpuColor)
                .frame(height: 8)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VRAM Usage").font(.caption).fontWeight(.semibold).foregroundStyle(.white.opacity(0.7))
                    Text(vramText).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text(PulseFormat.percent(vramUsage)).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            PulseBar(percent: vramUsage, color: PulseTheme.gpuColor.opacity(0.85))
                .frame(height: 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(PulseTheme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(PulseTheme.cardStroke, lineWidth: 1))
    }
}

#Preview {
    DashboardView()
        .environmentObject(PulseMonitor())
        .frame(width: 420, height: 560)
}
