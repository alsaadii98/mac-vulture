import Foundation

public actor OperationLog {
    public static let shared = OperationLog()

    private let url: URL
    private let formatter: ISO8601DateFormatter
    private var handle: FileHandle?

    public init(home: String = NSHomeDirectory()) {
        self.url = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Logs/mac-vulture/operations.log")
        self.formatter = ISO8601DateFormatter()
    }

    public func log(action: String, path: String, sizeBytes: Int64? = nil, result: String) async {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if handle == nil {
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        let ts = formatter.string(from: Date())
        let size = sizeBytes.map { String($0) } ?? "-"
        let line = "\(ts)\t\(action)\t\(result)\t\(size)\t\(path)\n"
        if let data = line.data(using: .utf8) {
            try? handle?.write(contentsOf: data)
        }
    }
}
