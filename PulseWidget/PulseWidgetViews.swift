import SwiftUI
import WidgetKit
import AppIntents

struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    var body: some View {
        Group {
            if let stats = entry.stats {
                sizedContent(stats: stats)
            } else {
                emptyState
            }
        }
        // macOS 14 desktop widgets must supply their own container
        // background instead of an opaque view background, or the system
        // draws its default one behind/over ours.
        .containerBackground(for: .widget) {
            PulseTheme.backgroundGradient
        }
    }

    @ViewBuilder
    private func sizedContent(stats: StatsResponse) -> some View {
        switch family {
        case .systemSmall:
            SmallPulseView(stats: stats, entry: entry)
        case .systemMedium:
            MediumPulseView(stats: stats, entry: entry)
        default:
            if !stats.gpu.available {
                ServerPulseView(stats: stats, entry: entry)
            } else if entry.largeStyle == .classic {
                ClassicLargePulseView(stats: stats, entry: entry)
            } else {
                LargePulseView(stats: stats, entry: entry)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WidgetSystemSwitcher(entry: entry)
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
            Text(entry.systemName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            Text("No data yet · Open Advanced to connect")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            if let diagnostic = entry.diagnostic {
                Text(diagnostic)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .padding(.top, 4)
            }
        }
        .padding()
    }
}

/// App Intent buttons execute inside the widget extension, without an app window.
private struct WidgetSystemSwitcher: View {
    let entry: PulseEntry

    var body: some View {
        HStack(spacing: 3) {
            systemButton("PC", id: "pc")
            systemButton("VPS", id: "vps")
        }
        .padding(3)
        .background(.white.opacity(0.05), in: Capsule())
        .fixedSize()
    }

    private func systemButton(_ title: String, id: String) -> some View {
        Button(intent: SwitchSystemIntent(systemID: id)) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(entry.systemID == id ? .white : .white.opacity(0.45))
                .frame(width: 25, height: 20)
                .background(entry.systemID == id ? PulseTheme.cpuColor.opacity(0.4) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(id == "pc" ? "PC" : "VPS")")
        .accessibilityValue(entry.systemID == id ? "Selected" : "")
    }
}

/// Servers have no GPU: use the space for memory and storage instead.
private struct ServerPulseView: View {
    let stats: StatsResponse
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.systemName).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(stats.hostname).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 4)
                WidgetSystemSwitcher(entry: entry)
            }
            HStack {
                LargeRingStat(title: "CPU", subtitle: "\(stats.cpu.logicalCores) vCPU", percent: stats.cpu.percent,
                              value: PulseFormat.percent(stats.cpu.percent), color: PulseTheme.cpuColor)
                LargeRingStat(title: "MEMORY", subtitle: "\(PulseFormat.gb(stats.memory.totalGB)) total", percent: stats.memory.percent,
                              value: PulseFormat.percent(stats.memory.percent), color: PulseTheme.ramColor)
            }
            .padding(.vertical, 10)
            .background(PulseTheme.cardFill, in: RoundedRectangle(cornerRadius: 16))

            resourceRow("Memory", used: stats.memory.usedGB, total: stats.memory.totalGB,
                        percent: stats.memory.percent, color: PulseTheme.ramColor)
            resourceRow("Storage", used: stats.disk.usedGB, total: stats.disk.totalGB,
                        percent: stats.disk.percent, color: PulseTheme.diskColor)
            Spacer(minLength: 0)
            HStack {
                StatusPill(state: entry.isReachable ? .live : .offline, label: entry.isReachable ? "Live" : "Offline")
                Spacer()
                Label(PulseFormat.uptime(stats.uptimeSeconds), systemImage: "clock")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            if let date = entry.fetchedAt {
                Text((entry.isReachable ? "Updated " : "Last seen ") + PulseFormat.relativeTime(date))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
    }

    private func resourceRow(_ title: String, used: Double, total: Double, percent: Double, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                Text("\(PulseFormat.gb(used)) / \(PulseFormat.gb(total))").monospacedDigit()
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            PulseBar(percent: percent, color: color)
        }
    }
}

// MARK: - Small (CPU + RAM + GPU summary)

struct SmallPulseView: View {
    let stats: StatsResponse
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stats.hostname)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                WidgetSystemSwitcher(entry: entry)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                MiniRingStat(title: "CPU", percent: stats.cpu.percent, color: PulseTheme.cpuColor)
                MiniRingStat(title: "RAM", percent: stats.memory.percent, color: PulseTheme.ramColor)
                MiniRingStat(title: stats.gpu.available ? "GPU" : "Disk", percent: stats.gpu.available ? (stats.gpu.utilizationPercent ?? 0) : stats.disk.percent, color: stats.gpu.available ? PulseTheme.gpuColor : PulseTheme.diskColor)
            }
            Spacer(minLength: 0)
            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(14)
    }

    private var footerText: String {
        guard let fetchedAt = entry.fetchedAt else { return "No data" }
        return (entry.isReachable ? "Updated " : "Last seen ") + PulseFormat.relativeTime(fetchedAt)
    }
}

// MARK: - Medium (adds VRAM + Disk)

struct MediumPulseView: View {
    let stats: StatsResponse
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(stats.hostname)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                WidgetSystemSwitcher(entry: entry)
            }

            HStack(spacing: 12) {
                MiniRingStat(title: "CPU", percent: stats.cpu.percent, color: PulseTheme.cpuColor)
                MiniRingStat(title: "RAM", percent: stats.memory.percent, color: PulseTheme.ramColor)
                MiniRingStat(title: stats.gpu.available ? "GPU" : "Disk", percent: stats.gpu.available ? (stats.gpu.utilizationPercent ?? 0) : stats.disk.percent, color: stats.gpu.available ? PulseTheme.gpuColor : PulseTheme.diskColor)
                if stats.gpu.available {
                    MiniRingStat(title: "VRAM", percent: stats.gpu.vramPercent, color: PulseTheme.gpuColor.opacity(0.75))
                }
            }

            VStack(spacing: 5) {
                HStack {
                    Label("Disk", systemImage: "internaldrive")
                    Spacer()
                    Text("\(PulseFormat.gb(stats.disk.usedGB)) / \(PulseFormat.gb(stats.disk.totalGB))")
                        .monospacedDigit()
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
                PulseBar(percent: stats.disk.percent, color: PulseTheme.diskColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Large Classic

private struct ClassicLargePulseView: View {
    let stats: StatsResponse
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.hostname).font(.headline).foregroundStyle(.white)
                    Text(stats.os).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                WidgetSystemSwitcher(entry: entry)
            }

            HStack(alignment: .top, spacing: 12) {
                MiniRingStat(title: "CPU", percent: stats.cpu.percent, color: PulseTheme.cpuColor)
                MiniRingStat(title: "RAM", percent: stats.memory.percent, color: PulseTheme.ramColor)
                ClassicGPUDialStat(gpu: stats.gpu)
                ClassicTemperatureStat(gpu: stats.gpu)
            }

            VStack(spacing: 10) {
                detailRow(
                    title: "Memory",
                    detail: "\(PulseFormat.gb(stats.memory.usedGB)) / \(PulseFormat.gb(stats.memory.totalGB))",
                    percent: stats.memory.percent,
                    color: PulseTheme.ramColor
                )
                detailRow(
                    title: "VRAM",
                    detail: vramDetail,
                    percent: stats.gpu.vramPercent,
                    color: PulseTheme.gpuColor
                )
                detailRow(
                    title: "Disk",
                    detail: "\(PulseFormat.gb(stats.disk.usedGB)) / \(PulseFormat.gb(stats.disk.totalGB))",
                    percent: stats.disk.percent,
                    color: PulseTheme.diskColor
                )
            }

            Spacer(minLength: 0)

            HStack {
                Label(PulseFormat.uptime(stats.uptimeSeconds), systemImage: "clock")
                Spacer()
                Text(footerText)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
    }

    private var vramDetail: String {
        guard let used = stats.gpu.vramUsedMB, let total = stats.gpu.vramTotalMB else {
            return "N/A"
        }
        return "\(PulseFormat.mbAsGB(used)) / \(PulseFormat.mbAsGB(total))"
    }

    private var footerText: String {
        guard let fetchedAt = entry.fetchedAt else { return "No data" }
        return (entry.isReachable ? "Updated " : "Last seen ") + PulseFormat.relativeTime(fetchedAt)
    }

    private func detailRow(
        title: String,
        detail: String,
        percent: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            PulseBar(percent: percent, color: color)
        }
    }
}

private struct ClassicGPUDialStat: View {
    let gpu: GPUStats

    private var usedVRAMText: String {
        guard let usedVRAM = gpu.vramUsedMB else { return "N/A" }
        return PulseFormat.mbAsGB(usedVRAM)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                PulseRing(
                    percent: gpu.utilizationPercent ?? 0,
                    color: PulseTheme.gpuColor,
                    lineWidth: 5
                )
                Text(usedVRAMText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
            }
            .frame(width: 46, height: 46)

            Text("GPU")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ClassicTemperatureStat: View {
    let gpu: GPUStats

    private var temperatureText: String {
        guard let temperature = gpu.temperatureC else { return "N/A" }
        return "\(Int(temperature))°C"
    }

    private var temperatureColor: Color {
        guard let temperature = gpu.temperatureC else { return .white.opacity(0.5) }
        return PulseTheme.statusColor(forPercent: temperature)
    }

    var body: some View {
        VStack(spacing: 7) {
            VStack(spacing: 5) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(temperatureColor)
                Text(temperatureText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            Text("GPU Temp")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large (full dashboard)

struct LargePulseView: View {
    let stats: StatsResponse
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.hostname).font(.headline).foregroundStyle(.white)
                    Text(stats.os).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                WidgetSystemSwitcher(entry: entry)
            }

            HStack(spacing: 28) {
                LargeRingStat(
                    title: "CPU",
                    subtitle: "Load",
                    percent: stats.cpu.percent,
                    value: PulseFormat.percent(stats.cpu.percent),
                    color: PulseTheme.cpuColor
                )
                LargeRingStat(
                    title: "GPU",
                    subtitle: "VRAM used",
                    percent: stats.gpu.utilizationPercent ?? 0,
                    value: stats.gpu.vramUsedMB.map(PulseFormat.mbAsGB) ?? "N/A",
                    color: PulseTheme.gpuColor
                )
            }
            .padding(.vertical, 4)
            .background(PulseTheme.cardFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PulseTheme.cardStroke, lineWidth: 0.75))

            VStack(spacing: 10) {
                LargeGPUHistoryGraph(
                    history: entry.history,
                    gpu: stats.gpu,
                    latestDate: entry.fetchedAt ?? entry.date
                )
                detailRow(title: "Disk", detail: "\(PulseFormat.gb(stats.disk.usedGB)) / \(PulseFormat.gb(stats.disk.totalGB))", percent: stats.disk.percent, color: PulseTheme.diskColor)
            }

            Spacer(minLength: 0)

            HStack {
                Label(PulseFormat.uptime(stats.uptimeSeconds), systemImage: "clock")
                Spacer()
                Text(footerText)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footerText: String {
        guard let fetchedAt = entry.fetchedAt else { return "No data" }
        return (entry.isReachable ? "Updated " : "Last seen ") + PulseFormat.relativeTime(fetchedAt)
    }

    @ViewBuilder
    private func detailRow(title: String, detail: String, percent: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            PulseBar(percent: percent, color: color)
        }
    }
}

private struct LargeRingStat: View {
    let title: String
    let subtitle: String
    let percent: Double
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                PulseRing(percent: percent, color: color, lineWidth: 5)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LargeGPUHistoryGraph: View {
    let history: [PulseHistoryPoint]
    let gpu: GPUStats
    let latestDate: Date

    private let gpuLoadColor = Color(red: 0.35, green: 0.80, blue: 1.00)
    private let vramUsageColor = Color(red: 0.06, green: 0.38, blue: 0.82)

    private var points: [PulseHistoryPoint] {
        var result = Array(history.suffix(40))
        let latestPoint = PulseHistoryPoint(
            date: latestDate,
            vramPercent: gpu.vramPercent,
            gpuPercent: gpu.utilizationPercent ?? 0
        )

        if let last = result.last, abs(last.date.timeIntervalSince(latestDate)) < 1 {
            result[result.count - 1] = latestPoint
        } else {
            result.append(latestPoint)
        }
        return result
    }

    private var chartPoints: [PulseHistoryPoint] {
        let maximumBars = 12
        guard points.count > maximumBars else { return points }

        let step = Double(points.count - 1) / Double(maximumBars - 1)
        return (0..<maximumBars).map { index in
            points[Int((Double(index) * step).rounded())]
        }
    }

    private var timeRangeText: String {
        guard let first = points.first, let last = points.last else { return "Now" }
        guard points.count > 1 else { return "Now" }
        let seconds = max(0, last.date.timeIntervalSince(first.date))
        if seconds < 60 { return "\(max(1, Int(seconds.rounded())))s" }
        return "\(max(1, Int((seconds / 60).rounded())))m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("ACTIVITY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))

                graphKey(
                    label: "GPU \(PulseFormat.percent(points.last?.gpuPercent ?? 0))",
                    color: gpuLoadColor
                )
                graphKey(
                    label: "VRAM \(PulseFormat.percent(points.last?.vramPercent ?? 0))",
                    color: vramUsageColor
                )

                Spacer(minLength: 4)

                Text(timeRangeText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            TimeChartView(
                points: chartPoints,
                gpuLoadColor: gpuLoadColor,
                vramUsageColor: vramUsageColor
            )
            .frame(height: 62)

            HStack {
                Text(timeLabel(chartPoints.first?.date))
                Spacer()
                Text(timeLabel(chartPoints.isEmpty ? nil : chartPoints[chartPoints.count / 2].date))
                Spacer()
                Text(timeLabel(chartPoints.last?.date))
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.75)
        )
    }

    private func graphKey(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func timeLabel(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct TimeChartView: View {
    let points: [PulseHistoryPoint]
    let gpuLoadColor: Color
    let vramUsageColor: Color

    var body: some View {
        GeometryReader { geo in
            let axisWidth: CGFloat = 22
            let plotWidth = max(0, geo.size.width - axisWidth - 4)
            let plotHeight = max(0, geo.size.height - 6)

            HStack(alignment: .top, spacing: 4) {
                ZStack {
                    chartGrid
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(points.indices, id: \.self) { index in
                            HStack(alignment: .bottom, spacing: 2) {
                                activityBar(
                                    percent: points[index].gpuPercent,
                                    color: gpuLoadColor,
                                    height: plotHeight
                                )
                                activityBar(
                                    percent: points[index].vramPercent,
                                    color: vramUsageColor,
                                    height: plotHeight
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(width: plotWidth, height: plotHeight)

                yAxisLabels
                    .frame(width: axisWidth, height: plotHeight)
            }
            .padding(.vertical, 3)
        }
    }

    private var chartGrid: some View {
        GeometryReader { geo in
            ZStack {
                Path { path in
                    for index in 0...4 {
                        let y = geo.size.height * CGFloat(index) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 0.7, dash: [2, 3])
                )

                Path { path in
                    let divisions = max(points.count, 1)
                    for index in 0...divisions {
                        let x = geo.size.width * CGFloat(index) / CGFloat(divisions)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                }
                .stroke(
                    Color.white.opacity(0.07),
                    style: StrokeStyle(lineWidth: 0.7, dash: [2, 3])
                )
            }
        }
    }

    private var yAxisLabels: some View {
        VStack(spacing: 0) {
            Text("100")
            Spacer()
            Text("75")
            Spacer()
            Text("50")
            Spacer()
            Text("25")
            Spacer()
            Text("0")
        }
        .font(.system(size: 7, design: .monospaced))
        .foregroundStyle(.white.opacity(0.36))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func activityBar(percent: Double, color: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.82), color],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(
                width: 6,
                height: max(3, height * CGFloat(max(0, min(100, percent)) / 100))
            )
            .shadow(color: color.opacity(0.18), radius: 2, y: 1)
    }
}

private struct GPUUsageGraph: View {
    let history: [PulseHistoryPoint]?
    let gpu: GPUStats?

    init(history: [PulseHistoryPoint]) {
        self.history = history
        self.gpu = nil
    }

    init(gpu: GPUStats) {
        self.history = nil
        self.gpu = gpu
    }

    private var points: [PulseHistoryPoint] {
        Array(history?.suffix(40) ?? [])
    }

    private var hasValidHistory: Bool {
        points.count > 1
    }

    private var latestText: String {
        if let latest = points.last {
            return "GPU \(PulseFormat.percent(latest.gpuPercent)) • VRAM \(PulseFormat.percent(latest.vramPercent))"
        }
        if let gpu = gpu {
            return "GPU \(PulseFormat.percent(gpu.utilizationPercent ?? 0)) • VRAM \(PulseFormat.percent(gpu.vramPercent))"
        }
        return "GPU • VRAM"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GPU / VRAM history").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(latestText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if hasValidHistory {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                    ChartView(points: points)
                        .padding(8)
                }
                .frame(height: 92)
            } else if let gpu = gpu {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GPU Usage").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                            Text(PulseFormat.percent(gpu.utilizationPercent ?? 0)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("VRAM Usage").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                            Text(PulseFormat.percent(gpu.vramPercent)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    PulseBar(percent: gpu.utilizationPercent ?? 0, color: PulseTheme.gpuColor)
                    PulseBar(percent: gpu.vramPercent, color: PulseTheme.gpuColor.opacity(0.85))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Collecting history…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    PulseBar(percent: 0, color: PulseTheme.gpuColor)
                        .frame(height: 8)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }
        }
    }
}

private struct ChartView: View {
    let points: [PulseHistoryPoint]

    private var maxPercent: Double {
        max(points.map { max($0.gpuPercent, $0.vramPercent) }.max() ?? 100, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let step = width / max(CGFloat(points.count - 1), 1)

            ZStack {
                gridLines(height: height)
                linePath(color: PulseTheme.gpuColor, value: { $0.gpuPercent }, width: width, height: height, step: step)
                linePath(color: PulseTheme.gpuColor.opacity(0.5), value: { $0.vramPercent }, width: width, height: height, step: step)
            }
        }
    }

    private func linePath(color: Color, value: (PulseHistoryPoint) -> Double, width: CGFloat, height: CGFloat, step: CGFloat) -> some View {
        Path { path in
            for index in points.indices {
                let x = CGFloat(index) * step
                let y = height - CGFloat(value(points[index]) / maxPercent) * height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func gridLines(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4) { index in
                Rectangle()
                    .fill(Color.white.opacity(index == 0 ? 0.15 : 0.08))
                    .frame(height: 1)
                    .offset(y: 0)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VRAMRingStat: View {
    let gpu: GPUStats

    private var usedText: String {
        guard let used = gpu.vramUsedMB else { return "N/A" }
        return PulseFormat.mbAsGB(used)
    }

    private var temperatureText: String? {
        guard let temp = gpu.temperatureC else { return nil }
        return "\(Int(temp))°C"
    }

    private var temperatureColor: Color {
        guard let temp = gpu.temperatureC else { return .white.opacity(0.5) }
        return PulseTheme.statusColor(forPercent: temp)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PulseRing(percent: gpu.vramPercent, color: PulseTheme.gpuColor, lineWidth: 6)
                VStack(spacing: 2) {
                    Text(usedText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("VRAM")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: 72, height: 72)

            if let temp = temperatureText {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11))
                        .foregroundStyle(temperatureColor)
                    Text(temp)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview(as: .systemSmall) {
    PulseWidget()
} timeline: {
    PulseEntry(date: .now, stats: .placeholder, fetchedAt: .now, isReachable: true)
}

#Preview(as: .systemMedium) {
    PulseWidget()
} timeline: {
    PulseEntry(date: .now, stats: .placeholder, fetchedAt: .now, isReachable: true)
}

#Preview(as: .systemLarge) {
    PulseWidget()
} timeline: {
    PulseEntry(date: .now, stats: .placeholder, fetchedAt: .now, isReachable: true)
}
