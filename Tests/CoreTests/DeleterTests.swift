import XCTest
@testable import MacVultureCore

final class DeleterTests: XCTestCase {
    var tmp: URL!
    var home: String!
    var deleter: Deleter!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac-vulture-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        home = tmp.path
        deleter = Deleter(home: home, whitelist: Whitelist(patterns: [], home: home), allowedRoots: [home])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func make(_ rel: String, dir: Bool = false) throws -> String {
        let url = tmp.appendingPathComponent(rel)
        if dir {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data("hello".utf8))
        }
        return url.path
    }

    func testValidateAcceptsHomePath() throws {
        let p = try make("Library/Caches/foo.txt")
        let resolved = try deleter.validate(p)
        XCTAssertEqual(resolved, (p as NSString).standardizingPath)
    }

    func testValidateRejectsTraversal() throws {
        let p = try make("Library/Caches/foo.txt")
        XCTAssertThrowsError(try deleter.validate(p + "/../../../etc/passwd")) { err in
            XCTAssertEqual(err as? DeleteError, .pathTraversal)
        }
    }

    func testValidateRejectsOutsideHome() throws {
        XCTAssertThrowsError(try deleter.validate("/etc/hosts")) { err in
            XCTAssertEqual(err as? DeleteError, .outsideHome)
        }
    }

    func testValidateRejectsSystemProtected() throws {
        let d = Deleter(home: home, whitelist: Whitelist(patterns: [], home: home), allowedRoots: ["/"])
        XCTAssertThrowsError(try d.validate("/System/Library/Frameworks")) { err in
            if case .systemProtected = err as? DeleteError {} else { XCTFail("expected systemProtected") }
        }
    }

    func testValidateRejectsUserProtectedSuffix() throws {
        _ = try make("Documents/important.txt")
        let p = tmp.appendingPathComponent("Documents/important.txt").path
        XCTAssertThrowsError(try deleter.validate(p)) { err in
            if case .systemProtected = err as? DeleteError {} else { XCTFail("expected systemProtected on Documents") }
        }
    }

    func testValidateHonorsWhitelist() throws {
        let p = try make("Library/Caches/keepme/data.txt")
        let wl = Whitelist(patterns: ["~/Library/Caches/keepme"], home: home)
        let d = Deleter(home: home, whitelist: wl, allowedRoots: [home])
        XCTAssertThrowsError(try d.validate(p)) { err in
            XCTAssertEqual(err as? DeleteError, .whitelisted)
        }
    }

    func testValidateMissingFile() {
        XCTAssertThrowsError(try deleter.validate(tmp.appendingPathComponent("nope").path)) { err in
            XCTAssertEqual(err as? DeleteError, .missingFile)
        }
    }

    func testDryRunDoesNotDelete() async throws {
        let p = try make("Library/Caches/foo/file.txt")
        let outcome = try await deleter.delete(p, mode: .dryRun)
        XCTAssertEqual(outcome.mode, .dryRun)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p))
    }

    func testPermanentDeleteRemovesFile() async throws {
        let p = try make("Library/Caches/foo/file.txt")
        _ = try await deleter.delete(p, mode: .permanent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: p))
    }
}
