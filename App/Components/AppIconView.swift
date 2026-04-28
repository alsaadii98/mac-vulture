import SwiftUI
import AppKit

/// Renders a macOS app's icon by path. Uses NSWorkspace which caches internally.
struct AppIconView: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
