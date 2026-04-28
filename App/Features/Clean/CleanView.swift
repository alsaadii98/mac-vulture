import SwiftUI
import MacVultureCore

@MainActor
final class CleanViewModel: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var selectedPaths: Set<String> = []
    @Published var isScanning: Bool = false
    @Published var lastError: String?

    private var scanTask: Task<Void, Never>?

    func scan(categories: [PathCatalog.Category], home: String = NSHomeDirectory()) {
        cancel()
        items.removeAll()
        selectedPaths.removeAll()
        isScanning = true
        let scanner = GlobScanner(home: home)
        scanTask = Task { [self] in
            await withTaskGroup(of: Void.self) { group in
                for cat in categories {
                    group.addTask { [self] in
                        for await item in scanner.scan(category: cat) {
                            await self.append(item)
                        }
                    }
                }
            }
            self.markDone()
        }
    }

    @MainActor private func append(_ item: ScanItem) {
        items.append(item)
        selectedPaths.insert(item.path)
    }

    @MainActor private func markDone() {
        isScanning = false
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func trashSelected(dryRun: Bool) async {
        let deleter = Deleter()
        var failures: [String] = []
        for path in selectedPaths {
            do {
                _ = try await deleter.delete(path, mode: dryRun ? .dryRun : .trash)
            } catch {
                failures.append("\(path): \(error)")
            }
        }
        if !failures.isEmpty {
            lastError = failures.prefix(3).joined(separator: "\n")
        }
        items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        selectedPaths = Set(items.map(\.path))
    }

    var totalBytes: Int64 {
        items.filter { selectedPaths.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }
}

struct CleanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CleanViewModel()
    @State private var checked: Set<String> = []

    var categories: [PathCatalog.Category] {
        (appState.pathCatalog?.categories ?? []).filter { $0.scope == .user }
    }

    var body: some View {
        HSplitView {
            categorySidebar
                .frame(minWidth: 240, idealWidth: 280)
            resultsPane
        }
        .navigationTitle("Clean")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if vm.isScanning {
                    Button("Stop") { vm.cancel() }
                } else {
                    Button {
                        let cats = categories.filter { checked.contains($0.id) }
                        vm.scan(categories: cats.isEmpty ? categories : cats)
                    } label: { Label("Scan", systemImage: "magnifyingglass") }
                    .disabled(categories.isEmpty)
                }
            }
        }
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Categories").font(.headline).padding([.top, .horizontal])
            List {
                ForEach(categories, id: \.id) { cat in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { checked.contains(cat.id) || checked.isEmpty },
                            set: { on in if on { checked.insert(cat.id) } else { checked.remove(cat.id) } }
                        )) {
                            VStack(alignment: .leading) {
                                Text(cat.title)
                                Text("risk: \(cat.risk.rawValue)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.items.count) items").font(.headline)
                Spacer()
                if vm.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(.secondary)
                }
            }
            .padding([.top, .horizontal])

            Table(vm.items, selection: $vm.selectedPaths) {
                TableColumn("Size") { item in
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Path") { item in
                    Text(item.path).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("Category", value: \.categoryID)
                    .width(min: 120, ideal: 160)
            }
            .contextMenu(forSelectionType: String.self) { selection in
                if !selection.isEmpty {
                    Button("Reveal in Finder") {
                        if let path = selection.first { Reveal.inFinder(path) }
                    }
                    Divider()
                    Button("Add to Whitelist") {
                        WhitelistEditor.append(selection)
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                Toggle("Dry run", isOn: $appState.dryRunDefault)
                Spacer()
                Text("Selected: \(ByteCountFormatter.string(fromByteCount: vm.totalBytes, countStyle: .file))")
                    .foregroundStyle(.secondary).monospacedDigit()
                Button {
                    Task { await vm.trashSelected(dryRun: appState.dryRunDefault) }
                } label: {
                    Label(appState.dryRunDefault ? "Preview Trash" : "Move to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.selectedPaths.isEmpty || vm.isScanning)
            }
            .padding(12)
        }
    }
}
