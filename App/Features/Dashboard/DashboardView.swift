import SwiftUI
import MacVultureCore

@MainActor
final class DashboardViewModel: ObservableObject {
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

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Dashboard").font(.largeTitle.bold())
                    Spacer()
                    if vm.refreshing { ProgressView().controlSize(.small) }
                    Button {
                        Task { await vm.refresh(catalog: appState.pathCatalog) }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    StatCard(
                        title: "Disk Free",
                        value: vm.disk.map { ByteCountFormatter.string(fromByteCount: $0.freeBytes, countStyle: .file) } ?? "—",
                        icon: "internaldrive"
                    )
                    StatCard(
                        title: "Reclaimable",
                        value: vm.reclaimable > 0 ? ByteCountFormatter.string(fromByteCount: vm.reclaimable, countStyle: .file) : "—",
                        icon: "sparkles"
                    )
                    StatCard(
                        title: "Disk Usage",
                        value: vm.disk.map { String(format: "%.0f%%", (1 - $0.freeFraction) * 100) } ?? "—",
                        icon: "chart.bar.fill"
                    )
                    StatCard(
                        title: "Last Scan",
                        value: appState.lastScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never",
                        icon: "clock"
                    )
                }
                Spacer()
            }
            .padding(24)
        }
        .task {
            await vm.refresh(catalog: appState.pathCatalog)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(.tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(value).font(.title.bold()).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
