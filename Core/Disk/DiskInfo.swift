import Foundation

public struct DiskInfo: Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var freeFraction: Double { totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) : 0 }

    public static func forVolume(at path: String = "/") -> DiskInfo? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else { return nil }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskInfo(totalBytes: total, freeBytes: free)
    }
}
