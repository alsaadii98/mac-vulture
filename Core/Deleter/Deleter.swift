import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum DeleteMode: Sendable {
    case trash
    case permanent
    case dryRun
}

public enum DeleteError: Error, Equatable, Sendable {
    case pathTraversal
    case outsideHome
    case systemProtected(String)
    case whitelisted
    case missingFile
    case symlinkResolutionFailed
    case ioError(String)
}

public struct DeleteOutcome: Sendable {
    public let path: String
    public let bytesReclaimed: Int64
    public let mode: DeleteMode
    public let trashedURL: URL?
}

public struct Deleter: Sendable {
    public let home: String
    public let whitelist: Whitelist
    public let allowedRoots: [String]

    /// Hardcoded system-critical path prefixes that are never deletable.
    /// Conservative — when in doubt, deny.
    public static let systemProtected: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Applications",
        "/Library/Keychains",
        "/private/var/db/timemachine",
        "/private/var/db/dslocal",
        "/private/var/folders",
        "/private/var/root",
    ]

    /// User-home prefixes that v1 must never touch.
    public static let userProtectedSuffixes: [String] = [
        "/Library/Keychains",
        "/Library/Mobile Documents",
        "/.ssh",
        "/.gnupg",
        "/Documents",
        "/Desktop",
        "/Pictures",
        "/Movies",
        "/Music",
    ]

    public init(home: String = NSHomeDirectory(),
                whitelist: Whitelist? = nil,
                allowedRoots: [String]? = nil) {
        self.home = home
        self.whitelist = whitelist ?? Whitelist.loadDefault(home: home)
        self.allowedRoots = allowedRoots ?? [home]
    }

    /// Validate a path. Throws on any rule violation. Returns the resolved absolute path.
    public func validate(_ rawPath: String) throws -> String {
        if rawPath.contains("..") { throw DeleteError.pathTraversal }
        let expanded = PathExpansion.expand(rawPath, home: home)

        var resolved = expanded
        if let realpath = (expanded as NSString).resolvingSymlinksInPath as String? {
            resolved = realpath
        }
        if resolved.contains("..") { throw DeleteError.pathTraversal }

        for prefix in Self.systemProtected {
            if resolved == prefix || resolved.hasPrefix(prefix + "/") {
                throw DeleteError.systemProtected(prefix)
            }
        }
        for suffix in Self.userProtectedSuffixes {
            if resolved == home + suffix || resolved.hasPrefix(home + suffix + "/") {
                throw DeleteError.systemProtected(home + suffix)
            }
        }

        let underAllowed = allowedRoots.contains { resolved == $0 || resolved.hasPrefix($0 + "/") }
        if !underAllowed { throw DeleteError.outsideHome }

        if whitelist.contains(resolved) { throw DeleteError.whitelisted }

        if !FileManager.default.fileExists(atPath: resolved) {
            throw DeleteError.missingFile
        }
        return resolved
    }

    /// Delete a single path. Trash by default. Logs every outcome.
    @discardableResult
    public func delete(_ rawPath: String, mode: DeleteMode = .trash) async throws -> DeleteOutcome {
        let resolved = try validate(rawPath)
        let size = (try? Sizing.sizeOf(path: resolved)) ?? 0

        switch mode {
        case .dryRun:
            await OperationLog.shared.log(action: "dryRun", path: resolved, sizeBytes: size, result: "ok")
            return DeleteOutcome(path: resolved, bytesReclaimed: size, mode: .dryRun, trashedURL: nil)

        case .trash:
            #if canImport(AppKit)
            return try await MainActor.run {
                var trashedURL: NSURL?
                let url = URL(fileURLWithPath: resolved)
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                    Task { await OperationLog.shared.log(action: "trash", path: resolved, sizeBytes: size, result: "ok") }
                    return DeleteOutcome(path: resolved, bytesReclaimed: size, mode: .trash, trashedURL: trashedURL as URL?)
                } catch {
                    Task { await OperationLog.shared.log(action: "trash", path: resolved, sizeBytes: size, result: "error: \(error.localizedDescription)") }
                    throw DeleteError.ioError(error.localizedDescription)
                }
            }
            #else
            throw DeleteError.ioError("Trash unavailable on non-AppKit platforms")
            #endif

        case .permanent:
            do {
                try FileManager.default.removeItem(atPath: resolved)
                await OperationLog.shared.log(action: "permanent", path: resolved, sizeBytes: size, result: "ok")
                return DeleteOutcome(path: resolved, bytesReclaimed: size, mode: .permanent, trashedURL: nil)
            } catch {
                await OperationLog.shared.log(action: "permanent", path: resolved, sizeBytes: size, result: "error: \(error.localizedDescription)")
                throw DeleteError.ioError(error.localizedDescription)
            }
        }
    }
}
