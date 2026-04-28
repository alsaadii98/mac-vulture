import Foundation
import SwiftUI
import MacVultureCore

@MainActor
final class AppState: ObservableObject {
    @Published var pathCatalog: PathCatalog?
    @Published var dryRunDefault: Bool = true
    @Published var lastScanDate: Date?

    init() {
        Task { await loadCatalog() }
    }

    func loadCatalog() async {
        do {
            pathCatalog = try PathCatalog.loadBundled()
        } catch {
            NSLog("path catalog load failed: \(error)")
        }
    }
}
