import Foundation

/// Domains whose Service Worker / offline-app data we never delete.
/// Mirrors the Mole protection list. Browsers store SW data under paths that
/// contain the origin string; if the path has a match here, skip.
public enum ServiceWorkerProtection {
    public static let protectedDomains: Set<String> = [
        "capcut.com", "photopea.com", "pixlr.com",
        "docs.google.com", "sheets.google.com", "slides.google.com",
        "drive.google.com", "mail.google.com",
        "github.com", "gitlab.com",
        "codepen.io", "codesandbox.io", "replit.com", "stackblitz.com",
        "notion.so", "figma.com", "linear.app", "excalidraw.com"
    ]

    /// Returns true if the path appears to belong to one of the protected SW domains.
    public static func isProtected(_ path: String) -> Bool {
        let lower = path.lowercased()
        // Service Workers usually live under .../Service Worker/... or .../ServiceWorker/...
        // The origin appears as a directory name (eg `https_github.com_0`) or in a settings file.
        guard lower.contains("service worker") || lower.contains("serviceworker") else {
            return false
        }
        for domain in protectedDomains {
            if lower.contains(domain) { return true }
        }
        return false
    }
}
