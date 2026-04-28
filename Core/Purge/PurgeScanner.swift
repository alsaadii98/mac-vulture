import Foundation

public struct PurgeProject: Sendable, Identifiable, Hashable {
    public var id: String { rootPath }
    public let rootPath: String
    public let kind: String
    public let artifacts: [PurgeArtifact]
    public var totalBytes: Int64 { artifacts.reduce(0) { $0 + $1.sizeBytes } }
    public var name: String { (rootPath as NSString).lastPathComponent }

    public init(rootPath: String, kind: String, artifacts: [PurgeArtifact]) {
        self.rootPath = rootPath
        self.kind = kind
        self.artifacts = artifacts
    }
}

public struct PurgeArtifact: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let target: String
    public let sizeBytes: Int64

    public init(path: String, target: String, sizeBytes: Int64) {
        self.path = path
        self.target = target
        self.sizeBytes = sizeBytes
    }
}

public enum PurgeScanner {

    /// Default search roots from blueprint.
    public static let defaultRoots: [String] = [
        "~/www", "~/dev", "~/Projects", "~/GitHub",
        "~/Code", "~/Workspace", "~/Repos", "~/Development"
    ]

    /// Heavy artifact directory names.
    public static let targets: Set<String> = [
        "node_modules", "target", "build", "dist", "venv", ".venv",
        ".pytest_cache", ".mypy_cache", ".tox", ".nox", ".ruff_cache",
        ".gradle", "__pycache__", ".next", ".nuxt", ".output",
        "vendor", ".turbo", ".parcel-cache", ".dart_tool",
        ".zig-cache", "zig-out", ".angular", ".svelte-kit", ".astro",
        "coverage", "DerivedData", "Pods", ".cxx", ".expo", ".build"
    ]

    public static let projectIndicators: Set<String> = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
        "requirements.txt", "pom.xml", "build.gradle", "Gemfile",
        "composer.json", "pubspec.yaml", "Package.swift", "Makefile",
        "build.zig", "build.zig.zon", ".git"
    ]

    /// Resolve user-configured roots from `~/.config/mac-vulture/purge_paths`,
    /// fall back to defaults. Returns existing absolute paths.
    public static func roots(home: String = NSHomeDirectory()) -> [String] {
        let configURL = URL(fileURLWithPath: home).appendingPathComponent(".config/mac-vulture/purge_paths")
        var raw: [String] = []
        if let text = try? String(contentsOf: configURL, encoding: .utf8) {
            raw = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        if raw.isEmpty { raw = defaultRoots }
        return raw
            .map { PathExpansion.expand($0, home: home) }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Scan roots for projects and their heavy artifact dirs.
    /// Streams results so the UI updates as projects are discovered.
    public static func scan(roots: [String], maxDepth: Int = 4) -> AsyncStream<PurgeProject> {
        AsyncStream { (continuation: AsyncStream<PurgeProject>.Continuation) in
            let task = Task.detached(priority: .userInitiated) {
                let yield: @Sendable (PurgeProject) -> Void = { p in continuation.yield(p) }
                for root in roots {
                    if Task.isCancelled { break }
                    await walk(URL(fileURLWithPath: root), depth: 0, maxDepth: maxDepth, yield: yield)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    @Sendable
    private static func walk(
        _ url: URL,
        depth: Int,
        maxDepth: Int,
        yield: @Sendable (PurgeProject) -> Void
    ) async {
        if Task.isCancelled || depth > maxDepth { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            atPath: url.path
        ) else { return }
        let entrySet = Set(entries)

        let isProject = !projectIndicators.isDisjoint(with: entrySet)
        if isProject {
            // collect artifacts at this level
            var artifacts: [PurgeArtifact] = []
            for name in entries where targets.contains(name) {
                let p = url.appendingPathComponent(name).path
                let size = (try? Sizing.sizeOf(path: p)) ?? 0
                if size > 0 {
                    artifacts.append(PurgeArtifact(path: p, target: name, sizeBytes: size))
                }
            }
            if !artifacts.isEmpty {
                yield(PurgeProject(rootPath: url.path, kind: kindOf(entrySet), artifacts: artifacts))
            }
            return  // don't recurse into a project
        }

        // recurse into children that look like containers
        for entry in entries {
            if entry.hasPrefix(".") { continue }
            let child = url.appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            await walk(child, depth: depth + 1, maxDepth: maxDepth, yield: yield)
        }
    }

    private static func kindOf(_ entries: Set<String>) -> String {
        if entries.contains("package.json") { return "node" }
        if entries.contains("Cargo.toml") { return "rust" }
        if entries.contains("go.mod") { return "go" }
        if entries.contains("pyproject.toml") || entries.contains("requirements.txt") { return "python" }
        if entries.contains("Package.swift") || entries.contains("Pods") { return "swift" }
        if entries.contains("build.gradle") || entries.contains("pom.xml") { return "jvm" }
        return "project"
    }
}
