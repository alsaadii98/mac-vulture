import SwiftUI
import MacVultureCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var disk: DiskInfo?
    @Published var quickReclaim: Int64 = 0
    @Published var working: Bool = false

    func refresh() async {
        disk = DiskInfo.forVolume()
        let paths = ["~/Library/Caches", "~/.Trash"].map { PathExpansion.expand($0) }
        let sizes = await Sizing.sizes(of: paths)
        quickReclaim = sizes.values.reduce(0, +)
    }

    func quickClean() async {
        working = true
        defer { working = false }
        let deleter = Deleter()
        let cachesGlob = "~/Library/Caches/*"
        let trashGlob = "~/.Trash/*"
        for url in PathExpansion.resolve(cachesGlob) + PathExpansion.resolve(trashGlob) {
            _ = try? await deleter.delete(url.path, mode: .trash)
        }
        await refresh()
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = MenuBarViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bird.fill").foregroundStyle(.tint)
                Text("Mac Vulture").font(.headline)
                Spacer()
                if vm.working { ProgressView().controlSize(.small) }
            }
            Divider()
            LabeledContent("Free space",
                value: vm.disk.map { ByteCountFormatter.string(fromByteCount: $0.freeBytes, countStyle: .file) } ?? "—")
            LabeledContent("Quick reclaim",
                value: ByteCountFormatter.string(fromByteCount: vm.quickReclaim, countStyle: .file))
            Divider()
            Button {
                Task { await vm.quickClean() }
            } label: { Label("Quick Clean", systemImage: "sparkles").frame(maxWidth: .infinity) }
            .disabled(vm.working)
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label("Open Mac Vulture", systemImage: "square.split.2x2").frame(maxWidth: .infinity) }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260)
        .task { await vm.refresh() }
    }
}
