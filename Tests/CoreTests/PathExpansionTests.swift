import XCTest
@testable import MacVultureCore

final class PathExpansionTests: XCTestCase {
    var tmp: URL!
    var home: String!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mv-pe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        home = tmp.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testResolveSkipsHiddenBugFix() throws {
        // Regression: ~/.Trash/* and ~/.cargo/* and ~/.npm/_cacache must resolve.
        let trash = tmp.appendingPathComponent(".Trash/file.txt")
        try FileManager.default.createDirectory(at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: trash.path, contents: Data("x".utf8))

        let cargo = tmp.appendingPathComponent(".cargo/registry/cache/foo")
        try FileManager.default.createDirectory(at: cargo.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cargo.path, contents: Data("x".utf8))

        let trashHits = PathExpansion.resolve("~/.Trash/*", home: home)
        XCTAssertEqual(trashHits.count, 1, "~/.Trash/* must resolve to hidden-dir contents")

        let cargoHits = PathExpansion.resolve("~/.cargo/registry/cache", home: home)
        XCTAssertEqual(cargoHits.count, 1)
    }

    func testResolveLiteralPath() {
        XCTAssertEqual(PathExpansion.resolve("/", home: home).count, 1)
    }

    func testGlobMatchSegments() {
        XCTAssertTrue(PathExpansion.match(path: "/a/b/c.txt", glob: "/a/*/c.txt"))
        XCTAssertTrue(PathExpansion.match(path: "/a/b/c/d.txt", glob: "/a/**/d.txt"))
        XCTAssertFalse(PathExpansion.match(path: "/a/b/c.txt", glob: "/x/*"))
    }
}
