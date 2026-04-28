import XCTest
@testable import MacVultureCore

final class PurgeScannerTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mv-purge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(rel), withIntermediateDirectories: true)
    }
    private func touch(_ rel: String, bytes: Int = 1) throws {
        let url = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0, count: bytes))
    }

    func testFindsNodeProject() async throws {
        try touch("repo-a/package.json")
        try touch("repo-a/node_modules/lodash/index.js", bytes: 8192)
        try touch("repo-a/node_modules/react/index.js", bytes: 8192)

        var found: [PurgeProject] = []
        for await proj in PurgeScanner.scan(roots: [tmp.path], maxDepth: 3) {
            found.append(proj)
        }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, "node")
        XCTAssertEqual(found.first?.artifacts.first?.target, "node_modules")
        XCTAssertGreaterThan(found.first?.artifacts.first?.sizeBytes ?? 0, 0)
    }

    func testFindsRustAndSkipsNonProjects() async throws {
        try touch("rust-app/Cargo.toml")
        try touch("rust-app/target/debug/foo", bytes: 4096)
        try touch("just-folder/data.txt")

        var found: [PurgeProject] = []
        for await proj in PurgeScanner.scan(roots: [tmp.path], maxDepth: 3) {
            found.append(proj)
        }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, "rust")
    }

    func testDoesNotRecurseIntoProject() async throws {
        // nested project under a project shouldn't be reported as separate
        try touch("outer/package.json")
        try touch("outer/node_modules/foo/index.js", bytes: 4096)
        try touch("outer/inner/package.json")  // pretend nested
        try touch("outer/inner/node_modules/bar/index.js", bytes: 4096)

        var found: [PurgeProject] = []
        for await proj in PurgeScanner.scan(roots: [tmp.path], maxDepth: 4) {
            found.append(proj)
        }
        XCTAssertEqual(found.count, 1, "should stop at first project root")
        XCTAssertEqual(found.first?.rootPath, tmp.appendingPathComponent("outer").path)
    }
}
