import SwiftUI
import AppKit

/// Reaches the underlying NSWindow once it's attached, so we can tweak chrome
/// (title bar, full-size content view, traffic-light position).
struct WindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { onAttach(w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { onAttach(w) }
        }
    }
}
