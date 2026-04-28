import Foundation

public struct ScanItem: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
    public let modified: Date?
    public let categoryID: String

    public init(path: String, sizeBytes: Int64, modified: Date?, categoryID: String) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.modified = modified
        self.categoryID = categoryID
    }
}

public protocol Scanner: Sendable {
    func scan(category: PathCatalog.Category) -> AsyncStream<ScanItem>
}

/// Generic scanner that resolves each glob in a category and emits one ScanItem per
/// resolved entry, with size computed in parallel. Honors whitelist.
public struct GlobScanner: Scanner {
    public let home: String
    public let whitelist: Whitelist

    public init(home: String = NSHomeDirectory(), whitelist: Whitelist? = nil) {
        self.home = home
        self.whitelist = whitelist ?? Whitelist.loadDefault(home: home)
    }

    public func scan(category: PathCatalog.Category) -> AsyncStream<ScanItem> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                for glob in category.globs {
                    if Task.isCancelled { break }
                    let urls = PathExpansion.resolve(glob, home: home)
                    await withTaskGroup(of: ScanItem?.self) { group in
                        for url in urls {
                            let path = url.path
                            if whitelist.contains(path) { continue }
                            group.addTask {
                                if Task.isCancelled { return nil }
                                let size = (try? Sizing.sizeOf(path: path)) ?? 0
                                if size == 0 { return nil }
                                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                                let modified = attrs?[.modificationDate] as? Date
                                return ScanItem(path: path, sizeBytes: size, modified: modified, categoryID: category.id)
                            }
                        }
                        for await item in group {
                            if let item { continuation.yield(item) }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
