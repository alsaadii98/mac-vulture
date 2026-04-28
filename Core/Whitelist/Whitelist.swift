import Foundation

public struct Whitelist: Sendable {
    public let patterns: [String]
    private let home: String

    /// Always-on protections. Cannot be disabled.
    /// Keeps OS plumbing and user-state apps untouched.
    public static let defaultPatterns: [String] = [
        // iCloud / sync
        "~/Library/Caches/CloudKit",
        "~/Library/Caches/com.apple.iCloudHelper",
        "~/Library/Caches/com.apple.cloudd",
        "~/Library/Mobile Documents",
        // Music / Photos / Messages local libraries
        "~/Library/Caches/com.apple.AMPLibraryAgent",
        "~/Library/Caches/com.apple.amsengagementd",
        "~/Library/Caches/com.apple.Music",
        "~/Library/Caches/com.apple.Photos",
        "~/Library/Caches/com.apple.MobileSMS",
        "~/Library/Caches/com.apple.imfoundation.IMRemoteURLConnectionAgent",
        // App Store / Mac App Store receipts
        "~/Library/Caches/com.apple.appstoreagent",
        "~/Library/Caches/com.apple.commerce",
        // HomeKit / Siri / Continuity
        "~/Library/Caches/com.apple.HomeKit",
        "~/Library/Caches/com.apple.assistant",
        "~/Library/Caches/com.apple.siri",
        // Safari local state (favicons, reading list)
        "~/Library/Caches/com.apple.Safari/WebpageIcons.db",
        // Firefox profile data
        "~/Library/Caches/Mozilla",
        "~/Library/Caches/Firefox/Profiles",
        // Keychain / credentials adjacent
        "~/Library/Keychains",
        // Mail message store (caches but expensive to rebuild)
        "~/Library/Caches/com.apple.mail",
        // Backups / Time Machine
        "~/Library/Application Support/MobileSync/Backup",
        "~/Library/Caches/com.apple.bird"
    ]

    public init(patterns: [String], home: String = NSHomeDirectory()) {
        self.patterns = patterns
        self.home = home
    }

    public static func loadDefault(fileManager: FileManager = .default, home: String = NSHomeDirectory()) -> Whitelist {
        let url = URL(fileURLWithPath: home).appendingPathComponent(".config/mac-vulture/whitelist")
        var userPatterns: [String] = []
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            userPatterns = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        // Merge defaults + user patterns. User patterns can extend, never disable defaults.
        var merged = defaultPatterns
        for p in userPatterns where !merged.contains(p) {
            merged.append(p)
        }
        return Whitelist(patterns: merged, home: home)
    }

    public func contains(_ path: String) -> Bool {
        let p = PathExpansion.expand(path, home: home)
        for pattern in patterns {
            if PathExpansion.match(path: p, glob: pattern, home: home) { return true }
            // also: prefix match — whitelist a directory protects everything inside
            let dir = PathExpansion.expand(pattern, home: home)
            if p == dir || p.hasPrefix(dir + "/") { return true }
        }
        return false
    }
}
