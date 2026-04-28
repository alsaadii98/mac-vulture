import XCTest
@testable import MacVultureCore

final class BundleResolverTests: XCTestCase {
    func testReadsCalculatorBundle() throws {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Calculator.app not present on this OS")
        }
        let app = InstalledApp.from(bundleURL: url)
        XCTAssertNotNil(app)
        XCTAssertEqual(app?.bundleID, "com.apple.calculator")
        XCTAssertEqual(app?.name.lowercased(), "calculator")
    }

    func testLeftoversFromSyntheticApp() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mv-bun-\(UUID().uuidString)")
        let home = tmp.path
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cache = tmp.appendingPathComponent("Library/Caches/com.example.fake")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cache.appendingPathComponent("data.bin").path,
                                        contents: Data(repeating: 0xab, count: 4096))
        let app = InstalledApp(name: "Fake", bundleID: "com.example.fake", version: "1.0",
                                appPath: "/tmp/Fake.app", sizeBytes: 0, isRunning: false)
        let lefts = await LeftoverResolver.leftovers(for: app, home: home)
        XCTAssertTrue(lefts.contains { $0.path.hasSuffix("Caches/com.example.fake") },
                      "expected leftover discovered: \(lefts.map(\.path))")
    }
}
