import Foundation

public enum Sizing {
    /// Sum of file sizes under a path. Follows the directory tree without crossing
    /// symlinks. Returns 0 if path is missing.
    public static func sizeOf(path: String, fileManager: FileManager = .default) throws -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }
        var total: Int64 = 0
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        for case let item as URL in enumerator {
            let res = try? item.resourceValues(forKeys: Set(keys))
            if res?.isSymbolicLink == true { continue }
            if res?.isRegularFile == true {
                total += Int64(res?.totalFileAllocatedSize ?? res?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Parallel size for a list of roots. Useful for category totals.
    public static func sizes(of paths: [String]) async -> [String: Int64] {
        await withTaskGroup(of: (String, Int64).self) { group in
            for p in paths {
                group.addTask {
                    let s = (try? sizeOf(path: p)) ?? 0
                    return (p, s)
                }
            }
            var out: [String: Int64] = [:]
            for await (p, s) in group { out[p] = s }
            return out
        }
    }
}
