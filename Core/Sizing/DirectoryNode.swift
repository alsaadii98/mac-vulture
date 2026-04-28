import Foundation

public struct DirectoryNode: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let childCount: Int

    public init(path: String, sizeBytes: Int64, isDirectory: Bool, childCount: Int = 0) {
        self.id = path
        self.name = (path as NSString).lastPathComponent
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.childCount = childCount
    }
}

public enum AnalyzerScanner {
    /// One-level scan: returns immediate children with sizes computed in parallel.
    /// Uses fold list to skip deep recursion into known heavy dirs.
    public static func children(of root: String) async -> [DirectoryNode] {
        let url = URL(fileURLWithPath: root)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return await withTaskGroup(of: DirectoryNode?.self) { group in
            for entry in entries {
                group.addTask {
                    let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let size = (try? Sizing.sizeOf(path: entry.path)) ?? 0
                    var childCount = 0
                    if isDir {
                        childCount = (try? FileManager.default.contentsOfDirectory(atPath: entry.path).count) ?? 0
                    }
                    return DirectoryNode(path: entry.path, sizeBytes: size, isDirectory: isDir, childCount: childCount)
                }
            }
            var nodes: [DirectoryNode] = []
            for await n in group { if let n { nodes.append(n) } }
            return nodes.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    /// Overview: blueprint top-level folders + Library/Logs/etc.
    public static func overviewPaths(home: String = NSHomeDirectory()) -> [String] {
        [
            home,
            "\(home)/Library",
            "/Applications",
            "\(home)/Downloads",
            "\(home)/Library/Logs",
            "\(home)/Library/Caches",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/CoreSimulator/Devices",
            "\(home)/Library/Caches/Homebrew",
            "\(home)/.gradle/caches",
            "\(home)/Library/Caches/JetBrains",
            "\(home)/Library/Containers/com.docker.docker/Data",
            "\(home)/Library/Application Support/MobileSync/Backup"
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }
}
