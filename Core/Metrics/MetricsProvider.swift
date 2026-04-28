import Foundation

public struct CPUSample: Sendable {
    public let usagePercent: Double
    public let coreCount: Int
}

public struct MemorySample: Sendable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let pressurePercent: Double
}

public struct BatterySample: Sendable {
    public let percent: Int?
    public let isCharging: Bool
    public let timeToFullMin: Int?
    public let timeRemainingMin: Int?
}

public struct ProcessSample: Sendable, Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: Int64
}

public struct StatusSnapshot: Sendable {
    public let cpu: CPUSample
    public let memory: MemorySample
    public let disk: DiskInfo?
    public let battery: BatterySample
    public let topProcesses: [ProcessSample]
}

public protocol MetricsProvider: Sendable {
    func snapshot() async -> StatusSnapshot
}
