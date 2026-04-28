import Foundation

public enum PathExpansion {
    /// Expand `~`, `$HOME`, env vars. Returns absolute, standardized path.
    public static func expand(_ path: String, home: String? = nil) -> String {
        var p = path
        let h = home ?? NSHomeDirectory()
        if p.hasPrefix("~/") { p = h + String(p.dropFirst(1)) }
        else if p == "~" { p = h }
        if p.hasPrefix("$HOME") { p = h + String(p.dropFirst("$HOME".count)) }
        return (p as NSString).standardizingPath
    }

    /// Match a path against a glob with `*` (single segment) and `**` (multi-segment).
    /// Globs are expanded first via `expand`.
    public static func match(path: String, glob: String, home: String? = nil) -> Bool {
        let g = expand(glob, home: home)
        let p = expand(path, home: home)
        return globMatch(pattern: g, string: p)
    }

    /// Resolve a glob to existing filesystem entries. Supports `*` and `**`.
    public static func resolve(_ glob: String, home: String? = nil, fileManager: FileManager = .default) -> [URL] {
        let expanded = expand(glob, home: home)
        guard expanded.contains("*") else {
            let url = URL(fileURLWithPath: expanded)
            return fileManager.fileExists(atPath: expanded) ? [url] : []
        }
        let parts = expanded.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let root = parts.first(where: { !$0.contains("*") && !$0.isEmpty }) ?? "/"
        let rootIndex = parts.firstIndex(of: root) ?? 0
        var prefix = "/" + parts[1...rootIndex].joined(separator: "/")
        if prefix == "//" { prefix = "/" }
        let remaining = Array(parts[(rootIndex + 1)...])
        var results: [URL] = []
        walk(URL(fileURLWithPath: prefix), patternParts: remaining, fileManager: fileManager, results: &results)
        return results
    }

    private static func walk(_ url: URL, patternParts: [String], fileManager: FileManager, results: inout [URL]) {
        if patternParts.isEmpty {
            results.append(url)
            return
        }
        let head = patternParts[0]
        let tail = Array(patternParts.dropFirst())
        guard let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else {
            return
        }
        if head == "**" {
            results.append(url)
            for c in children {
                walk(c, patternParts: patternParts, fileManager: fileManager, results: &results)
                walk(c, patternParts: tail, fileManager: fileManager, results: &results)
            }
            return
        }
        for c in children where fnmatch(pattern: head, name: c.lastPathComponent) {
            walk(c, patternParts: tail, fileManager: fileManager, results: &results)
        }
    }

    /// Single-segment fnmatch with `*` and `?`.
    static func fnmatch(pattern: String, name: String) -> Bool {
        let p = Array(pattern), n = Array(name)
        var memo: [[Bool?]] = Array(repeating: Array(repeating: nil, count: n.count + 1), count: p.count + 1)
        func m(_ i: Int, _ j: Int) -> Bool {
            if let v = memo[i][j] { return v }
            let r: Bool
            if i == p.count { r = j == n.count }
            else if p[i] == "*" {
                if m(i + 1, j) { r = true }
                else if j < n.count { r = m(i, j + 1) }
                else { r = false }
            } else if j < n.count && (p[i] == "?" || p[i] == n[j]) {
                r = m(i + 1, j + 1)
            } else {
                r = false
            }
            memo[i][j] = r
            return r
        }
        return m(0, 0)
    }

    /// Full-path glob match, supporting `**`.
    static func globMatch(pattern: String, string: String) -> Bool {
        let pp = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let ss = string.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return matchSegments(pp, 0, ss, 0)
    }

    private static func matchSegments(_ p: [String], _ i: Int, _ s: [String], _ j: Int) -> Bool {
        if i == p.count { return j == s.count }
        if p[i] == "**" {
            for k in j...s.count {
                if matchSegments(p, i + 1, s, k) { return true }
            }
            return false
        }
        if j == s.count { return false }
        if !fnmatch(pattern: p[i], name: s[j]) { return false }
        return matchSegments(p, i + 1, s, j + 1)
    }
}
