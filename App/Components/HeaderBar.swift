import SwiftUI
import MacVultureCore

@MainActor
final class HeaderBarViewModel: ObservableObject {
    @Published var disk: DiskInfo?
    @Published var reclaimable: Int64 = 0
    @Published var refreshing: Bool = false

    func refresh(catalog: PathCatalog?) async {
        refreshing = true
        defer { refreshing = false }
        disk = DiskInfo.forVolume()
        guard let catalog else { return }
        let userCats = catalog.categories.filter { $0.scope == .user }
        var paths: [String] = []
        for cat in userCats {
            for glob in cat.globs {
                paths.append(contentsOf: PathExpansion.resolve(glob).map(\.path))
            }
        }
        let sizes = await Sizing.sizes(of: paths)
        reclaimable = sizes.values.reduce(0, +)
    }
}

struct HeaderBar: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = HeaderBarViewModel()

    var body: some View {
        HStack(spacing: 16) {
            HeaderStat(
                icon: "internaldrive",
                title: "Disk Free",
                value: vm.disk.map { ByteCountFormatter.string(fromByteCount: $0.freeBytes, countStyle: .file) } ?? "—",
                tint: diskTint
            )
            Divider().frame(height: 30)
            HeaderStat(
                icon: "sparkles",
                title: "Reclaimable",
                value: vm.reclaimable > 0 ? ByteCountFormatter.string(fromByteCount: vm.reclaimable, countStyle: .file) : "—",
                tint: .blue
            )
            Divider().frame(height: 30)
            HeaderStat(
                icon: "chart.bar.fill",
                title: "Used",
                value: vm.disk.map { String(format: "%.0f%%", (1 - $0.freeFraction) * 100) } ?? "—",
                tint: usageTint
            )
            Spacer()
            Button {
                Task { await vm.refresh(catalog: appState.pathCatalog) }
            } label: {
                Image(systemName: vm.refreshing ? "arrow.clockwise" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(vm.refreshing)
            .opacity(vm.refreshing ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)  // matches sidebar top reservation for traffic lights
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .task { await vm.refresh(catalog: appState.pathCatalog) }
    }

    private var diskTint: Color {
        guard let d = vm.disk else { return .secondary }
        let frac = d.freeFraction
        if frac < 0.1 { return .red }
        if frac < 0.2 { return .orange }
        return .green
    }

    private var usageTint: Color {
        guard let d = vm.disk else { return .secondary }
        let used = 1 - d.freeFraction
        if used > 0.9 { return .red }
        if used > 0.8 { return .orange }
        return .secondary
    }
}

private struct HeaderStat: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
    }
}
