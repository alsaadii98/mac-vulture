import Foundation

public enum WhitelistEditor {
    public static var path: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/mac-vulture/whitelist")
    }

    public static func read() -> String {
        (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    public static func write(_ contents: String) {
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? contents.write(to: path, atomically: true, encoding: .utf8)
    }

    public static func append<S: Sequence>(_ paths: S) where S.Element == String {
        var existing = read()
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        for p in paths {
            existing += p + "\n"
        }
        write(existing)
    }
}
