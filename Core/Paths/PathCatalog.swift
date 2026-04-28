import Foundation

public struct PathCatalog: Codable, Sendable {
    public let version: Int
    public let categories: [Category]

    public enum Scope: String, Codable, Sendable {
        case user, system, mixed
    }

    public enum Risk: String, Codable, Sendable {
        case low, medium, high
    }

    public struct Category: Codable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let scope: Scope
        public let risk: Risk
        public let runningAppCheck: Bool
        public let globs: [String]
        public let notes: String?

        enum CodingKeys: String, CodingKey {
            case id, title, scope, risk, globs, notes
            case runningAppCheck = "running_app_check"
        }
    }

    public static func loadBundled() throws -> PathCatalog {
        guard let url = Bundle.module.url(forResource: "path_catalog", withExtension: "json") else {
            throw CatalogError.notFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PathCatalog.self, from: data)
    }

    public enum CatalogError: Error { case notFound }
}
