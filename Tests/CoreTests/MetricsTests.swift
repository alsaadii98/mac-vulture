import XCTest
@testable import MacVultureCore

final class MetricsTests: XCTestCase {
    func testSnapshotProducesMemoryReading() async {
        let metrics = SystemMetrics()
        // prime + one real sample
        _ = await metrics.snapshot()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let snap = await metrics.snapshot()
        XCTAssertGreaterThan(snap.memory.totalBytes, 0)
        XCTAssertGreaterThan(snap.memory.usedBytes, 0)
        XCTAssertGreaterThanOrEqual(snap.cpu.coreCount, 1)
    }

    func testDiskInfoReadable() {
        let d = DiskInfo.forVolume(at: "/")
        XCTAssertNotNil(d)
        XCTAssertGreaterThan(d!.totalBytes, 0)
    }
}
