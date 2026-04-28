import Foundation

public enum MacVultureCore {
    public static let version = "0.2.0"
}

public func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}
