import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum RunningApps {
    /// Returns true if any running app's bundle id matches `bundleID` (case-insensitive prefix).
    public static func isRunning(bundleID: String) -> Bool {
        #if canImport(AppKit)
        let lower = bundleID.lowercased()
        return NSWorkspace.shared.runningApplications.contains { app in
            (app.bundleIdentifier ?? "").lowercased() == lower
        }
        #else
        return false
        #endif
    }

    /// Heuristic: derive a bundle id candidate from a cache path like
    /// `~/Library/Caches/com.apple.Safari/...` -> `com.apple.Safari`.
    public static func bundleIDGuess(forPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let cachesIdx = parts.firstIndex(of: "Caches"),
              cachesIdx + 1 < parts.count else { return nil }
        let candidate = parts[cachesIdx + 1]
        return candidate.contains(".") && candidate.split(separator: ".").count >= 2 ? candidate : nil
    }
}
