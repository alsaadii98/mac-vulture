import Foundation

public struct Leftover: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
    public let kind: Kind

    public enum Kind: String, Sendable, CaseIterable {
        case applicationSupport, caches, logs, preferences, containers, savedState
        case launchAgents, plugins, group, other
    }
}

public enum LeftoverResolver {
    /// Patterns from Functionality_Paths.md (Uninstall: User Leftover Paths).
    /// Variables: $name, $bundle.
    private static let userPatterns: [(String, Leftover.Kind)] = [
        ("~/Library/Application Support/$name", .applicationSupport),
        ("~/Library/Application Support/$bundle", .applicationSupport),
        ("~/Library/Caches/$bundle", .caches),
        ("~/Library/Caches/$name", .caches),
        ("~/Library/Logs/$name", .logs),
        ("~/Library/Logs/$bundle", .logs),
        ("~/Library/Saved Application State/$bundle.savedState", .savedState),
        ("~/Library/Containers/$bundle", .containers),
        ("~/Library/Group Containers/$bundle", .group),
        ("~/Library/HTTPStorages/$bundle", .other),
        ("~/Library/HTTPStorages/$bundle.binarycookies", .other),
        ("~/Library/Cookies/$bundle.binarycookies", .other),
        ("~/Library/Application Scripts/$bundle", .other),
        ("~/Library/WebKit/$bundle", .other),
        ("~/Library/Preferences/$bundle.plist", .preferences),
        ("~/Library/Preferences/$bundle", .preferences),
        ("~/Library/Autosave Information/$bundle", .other),
        ("~/Library/SyncedPreferences/$bundle.plist", .preferences),
        ("~/Library/LaunchAgents/$bundle.plist", .launchAgents),
        ("~/Library/Caches/com.apple.nsurlsessiond/Downloads/$bundle", .caches),
        ("~/Library/Application Support/CrashReporter/$name", .logs),
        ("~/Library/Application Support/CrashReporter/$name_*.plist", .logs),
        ("~/.config/$name", .other),
        ("~/.local/share/$name", .other),
    ]

    public static func leftovers(for app: InstalledApp, home: String = NSHomeDirectory()) async -> [Leftover] {
        let nameVariants = Set([app.name, app.name.replacingOccurrences(of: " ", with: "")])
        var candidates: [(String, Leftover.Kind)] = []
        for (template, kind) in userPatterns {
            for name in nameVariants {
                let p = template
                    .replacingOccurrences(of: "$name", with: name)
                    .replacingOccurrences(of: "$bundle", with: app.bundleID)
                candidates.append((p, kind))
            }
        }

        return await withTaskGroup(of: Leftover?.self) { group in
            for (pattern, kind) in candidates {
                group.addTask {
                    let urls = PathExpansion.resolve(pattern, home: home)
                    guard let url = urls.first else { return nil }
                    let size = (try? Sizing.sizeOf(path: url.path)) ?? 0
                    return Leftover(path: url.path, sizeBytes: size, kind: kind)
                }
            }
            var seen: Set<String> = []
            var out: [Leftover] = []
            for await l in group {
                if let l, !seen.contains(l.path) {
                    seen.insert(l.path)
                    out.append(l)
                }
            }
            return out.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }
}
