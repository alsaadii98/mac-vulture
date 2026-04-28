import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum Reveal {
    public static func inFinder(_ path: String) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }
}
