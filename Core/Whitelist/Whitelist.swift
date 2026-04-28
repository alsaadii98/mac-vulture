import Foundation

public struct Whitelist: Sendable {
    public let patterns: [String]
    private let home: String

    public init(patterns: [String], home: String = NSHomeDirectory()) {
        self.patterns = patterns
        self.home = home
    }

    public static func loadDefault(fileManager: FileManager = .default, home: String = NSHomeDirectory()) -> Whitelist {
        let url = URL(fileURLWithPath: home).appendingPathComponent(".config/mac-vulture/whitelist")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return Whitelist(patterns: [], home: home)
        }
        let patterns = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return Whitelist(patterns: patterns, home: home)
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
