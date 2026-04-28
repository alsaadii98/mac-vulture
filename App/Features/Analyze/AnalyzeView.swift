import SwiftUI
import MacVultureCore

@MainActor
final class AnalyzeViewModel: ObservableObject {
    @Published var nodes: [DirectoryNode] = []
    @Published var breadcrumbs: [String] = []
    @Published var isLoading: Bool = false

    var currentPath: String { breadcrumbs.last ?? "" }

    func loadOverview() async {
        breadcrumbs = []
        isLoading = true
        defer { isLoading = false }
        let paths = AnalyzerScanner.overviewPaths()
        var collected: [DirectoryNode] = []
        await withTaskGroup(of: DirectoryNode.self) { group in
            for p in paths {
                group.addTask {
                    let size = (try? Sizing.sizeOf(path: p)) ?? 0
                    return DirectoryNode(path: p, sizeBytes: size, isDirectory: true)
                }
            }
            for await n in group { collected.append(n) }
        }
        nodes = collected.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func drillIn(_ node: DirectoryNode) async {
        guard node.isDirectory else { return }
        breadcrumbs.append(node.path)
        isLoading = true
        nodes = await AnalyzerScanner.children(of: node.path)
        isLoading = false
    }

    func navigate(to index: Int) async {
        if index < 0 {
            await loadOverview()
            return
        }
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        isLoading = true
        nodes = await AnalyzerScanner.children(of: breadcrumbs[index])
        isLoading = false
    }

    func trash(_ node: DirectoryNode) async -> Bool {
        let deleter = Deleter(allowedRoots: ["/"])
        do {
            _ = try await deleter.delete(node.path, mode: .trash)
            nodes.removeAll { $0.path == node.path }
            return true
        } catch {
            return false
        }
    }
}

struct AnalyzeView: View {
    @StateObject private var vm = AnalyzeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Task { await vm.navigate(to: -1) }
                } label: { Image(systemName: "house") }
                ForEach(Array(vm.breadcrumbs.enumerated()), id: \.offset) { idx, p in
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    Button((p as NSString).lastPathComponent) {
                        Task { await vm.navigate(to: idx) }
                    }
                }
                Spacer()
                if vm.isLoading { ProgressView().controlSize(.small) }
            }
            .padding()
            Divider()

            List(vm.nodes) { node in
                AnalyzerRow(node: node, total: vm.nodes.first?.sizeBytes ?? node.sizeBytes)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        Task { await vm.drillIn(node) }
                    }
                    .contextMenu {
                        if node.isDirectory {
                            Button("Open") { Task { await vm.drillIn(node) } }
                        }
                        Button("Reveal in Finder") { Reveal.inFinder(node.path) }
                        Divider()
                        Button("Move to Trash", role: .destructive) {
                            Task { _ = await vm.trash(node) }
                        }
                    }
            }
        }
        .task { await vm.loadOverview() }
    }
}

struct AnalyzerRow: View {
    let node: DirectoryNode
    let total: Int64

    var bar: Double { total > 0 ? Double(node.sizeBytes) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(node.name).fontWeight(.medium)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: node.sizeBytes, countStyle: .file))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.tertiary).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(.tint).frame(width: geo.size.width * bar, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }
}
