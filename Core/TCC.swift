import Foundation

public enum TCC {
    /// Probe Full Disk Access by attempting to read a path that requires FDA.
    /// `/Library/Application Support/com.apple.TCC/TCC.db` is the canonical TCC db
    /// — readable only with FDA. Returns true if accessible.
    public static func hasFullDiskAccess() -> Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(NSHomeDirectory())/Library/Safari/Bookmarks.plist"
        ]
        for path in probes {
            if FileManager.default.isReadableFile(atPath: path) {
                return true
            }
            // Try opening for read — isReadableFile can lie under TCC.
            if let fh = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) {
                try? fh.close()
                return true
            }
        }
        return false
    }
}
