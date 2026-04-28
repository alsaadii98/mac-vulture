import XCTest
@testable import MacVultureCore

final class PathCatalogTests: XCTestCase {
    func testBundledCatalogLoads() throws {
        let catalog = try PathCatalog.loadBundled()
        XCTAssertEqual(catalog.version, 1)
        XCTAssertFalse(catalog.categories.isEmpty)
    }

    func testCategoriesHaveUniqueIDs() throws {
        let catalog = try PathCatalog.loadBundled()
        let ids = catalog.categories.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate category id")
    }

    func testEveryUserCategoryGlobIsUnderHome() throws {
        let catalog = try PathCatalog.loadBundled()
        for cat in catalog.categories where cat.scope == .user {
            for glob in cat.globs {
                XCTAssertTrue(
                    glob.hasPrefix("~/") || glob.hasPrefix("$HOME"),
                    "user-scope glob must start under $HOME: \(cat.id) -> \(glob)"
                )
            }
        }
    }

    func testTildeExpansion() {
        XCTAssertTrue(expandTilde("~/foo").hasPrefix("/"))
    }
}
