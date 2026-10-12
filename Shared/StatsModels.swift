import Foundation

/// Mirrors the JSON returned by `GET /stats` on the Windows agent
/// (see windows-agent/agent.py).
struct StatsResponse: Codable, Equatable {
    let hostname: String
    let os: String
    let timestamp: String
    let uptimeSeconds: Int
    let cpu: CPUStats
    let memory: MemoryStats
    let gpu: GPUStats
    let disk: DiskStats

    enum CodingKeys: String, CodingKey {
        case hostname, os, timestamp
        case uptimeSeconds = "uptime_seconds"
        case cpu, memory, gpu, disk
    }
}

struct CPUStats: Codable, Equatable {
    let percent: Double
    let logicalCores: Int
    let physicalCores: Int

    enum CodingKeys: String, CodingKey {
        case percent
        case logicalCores = "logical_cores"
        case physicalCores = "physical_cores"
    }
}

struct MemoryStats: Codable, Equatable {
    let usedGB: Double
    let totalGB: Double
    let percent: Double

    enum CodingKeys: String, CodingKey {
        case usedGB = "used_gb"
        case totalGB = "total_gb"
        case percent
    }
}

/// GPU stats are optional-valued because the agent still returns a 200 with
/// `available: false` when `nvidia-smi` can't be reached, rather than
/// failing the whole request.
struct GPUStats: Codable, Equatable {
    let available: Bool
    let name: String?
    let utilizationPercent: Double?
    let vramUsedMB: Double?
    let vramTotalMB: Double?
    let temperatureC: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case available, name, error
        case utilizationPercent = "utilization_percent"
        case vramUsedMB = "vram_used_mb"
        case vramTotalMB = "vram_total_mb"
        case temperatureC = "temperature_c"
    }

    var vramPercent: Double {
        guard let used = vramUsedMB, let total = vramTotalMB, total > 0 else { return 0 }
        return used / total * 100
    }
}

struct DiskStats: Codable, Equatable {
    let path: String
    let usedGB: Double
    let totalGB: Double
    let percent: Double

    enum CodingKeys: String, CodingKey {
        case path
        case usedGB = "used_gb"
        case totalGB = "total_gb"
        case percent
    }
}

extension StatsResponse {
    /// Sample data for widget/SwiftUI previews and the placeholder timeline entry.
    static let placeholder = StatsResponse(
        hostname: "SIXDX",
        os: "Windows 11",
        timestamp: "2026-07-23T12:00:00Z",
        uptimeSeconds: 341_022,
        cpu: CPUStats(percent: 23, logicalCores: 24, physicalCores: 16),
        memory: MemoryStats(usedGB: 21.3, totalGB: 64.0, percent: 33.3),
        gpu: GPUStats(
            available: true,
            name: "NVIDIA GeForce RTX 5090",
            utilizationPercent: 47,
            vramUsedMB: 9820,
            vramTotalMB: 32607,
            temperatureC: 63,
            error: nil
        ),
        disk: DiskStats(path: "C:\\", usedGB: 512.4, totalGB: 1863.0, percent: 27.5)
    )
}
