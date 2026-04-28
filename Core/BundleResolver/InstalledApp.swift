import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { bundleID }
    public let name: String
    public let bundleID: String
    public let version: String
    public let appPath: String
    public let sizeBytes: Int64
    public var isRunning: Bool

    public static func discoverAll() async -> [InstalledApp] {
        let roots = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications"
        ].filter { FileManager.default.fileExists(atPath: $0) }

        var bundles: [URL] = []
        for root in roots {
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                bundles += entries.filter { $0.pathExtension == "app" }
            }
        }

        return await withTaskGroup(of: InstalledApp?.self) { group in
            for url in bundles {
                group.addTask { Self.from(bundleURL: url) }
            }
            var apps: [InstalledApp] = []
            for await app in group { if let app { apps.append(app) } }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static func from(bundleURL url: URL) -> InstalledApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? (url.deletingPathExtension().lastPathComponent)
        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String) ?? ""
        let size = (try? Sizing.sizeOf(path: url.path)) ?? 0
        let running = RunningApps.isRunning(bundleID: bundleID)
        return InstalledApp(name: name, bundleID: bundleID, version: version,
                            appPath: url.path, sizeBytes: size, isRunning: running)
    }
}
