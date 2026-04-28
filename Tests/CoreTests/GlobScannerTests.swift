import XCTest
@testable import MacVultureCore

final class GlobScannerTests: XCTestCase {
    var tmp: URL!
    var home: String!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mv-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        home = tmp.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func writeFile(_ rel: String, bytes: Int = 100) throws {
        let url = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0xab, count: bytes))
    }

    func testScanFindsCacheEntries() async throws {
        try writeFile("Library/Caches/AppA/data.bin", bytes: 1024)
        try writeFile("Library/Caches/AppB/data.bin", bytes: 2048)

        let cat = PathCatalog.Category(
            id: "user_caches", title: "User Caches",
            scope: .user, risk: .low, runningAppCheck: false,
            globs: ["~/Library/Caches/*"], notes: nil
        )
        let scanner = GlobScanner(home: home, whitelist: Whitelist(patterns: [], home: home))
        var items: [ScanItem] = []
        for await item in scanner.scan(category: cat) {
            items.append(item)
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.categoryID).sorted(), ["user_caches", "user_caches"])
        let total = items.reduce(0) { $0 + $1.sizeBytes }
        // sizeBytes uses totalFileAllocatedSize (block-aligned), so >= logical size.
        XCTAssertGreaterThanOrEqual(total, 3072)
    }

    func testScanHonorsWhitelist() async throws {
        try writeFile("Library/Caches/Keep/data.bin", bytes: 1024)
        try writeFile("Library/Caches/Drop/data.bin", bytes: 2048)
        let cat = PathCatalog.Category(
            id: "user_caches", title: "User Caches",
            scope: .user, risk: .low, runningAppCheck: false,
            globs: ["~/Library/Caches/*"], notes: nil
        )
        let wl = Whitelist(patterns: ["~/Library/Caches/Keep"], home: home)
        let scanner = GlobScanner(home: home, whitelist: wl)
        var items: [ScanItem] = []
        for await item in scanner.scan(category: cat) {
            items.append(item)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].path.hasSuffix("/Drop"))
    }

    func testScanCancellation() async throws {
        for i in 0..<50 {
            try writeFile("Library/Caches/App\(i)/data.bin", bytes: 1024)
        }
        let cat = PathCatalog.Category(
            id: "user_caches", title: "User Caches",
            scope: .user, risk: .low, runningAppCheck: false,
            globs: ["~/Library/Caches/*"], notes: nil
        )
        let scanner = GlobScanner(home: home, whitelist: Whitelist(patterns: [], home: home))
        let task = Task {
            var count = 0
            for await _ in scanner.scan(category: cat) {
                count += 1
                if count >= 1 { break }
            }
            return count
        }
        let n = await task.value
        XCTAssertGreaterThanOrEqual(n, 1)
    }
}
