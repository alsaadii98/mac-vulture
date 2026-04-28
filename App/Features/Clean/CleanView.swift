import SwiftUI
import MacVultureCore

@MainActor
final class CleanViewModel: ObservableObject {
    @Published private(set) var groups: [CategoryGroup] = []
    @Published var checked: Set<String> = []
    @Published var expanded: Set<String> = []
    @Published var isScanning: Bool = false
    @Published var lastError: String?
    @Published var lastResult: String?

    private var scanTask: Task<Void, Never>?
    private var groupIndex: [String: Int] = [:]

    struct CategoryGroup: Identifiable, Hashable {
        let id: String         // categoryID
        let title: String
        let risk: PathCatalog.Risk
        var items: [ScanItem]
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
        var paths: Set<String> { Set(items.map(\.path)) }
    }

    func scan(categories: [PathCatalog.Category], home: String = NSHomeDirectory()) {
        cancel()
        groups = categories.map { CategoryGroup(id: $0.id, title: $0.title, risk: $0.risk, items: []) }
        groupIndex = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1.id, $0) })
        checked.removeAll()
        expanded.removeAll()
        lastError = nil
        lastResult = nil
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
        guard let idx = groupIndex[item.categoryID] else { return }
        groups[idx].items.append(item)
        checked.insert(item.path)
    }

    @MainActor private func markDone() {
        isScanning = false
        // drop empty groups for cleaner UI
        groups = groups.filter { !$0.items.isEmpty }
        groupIndex = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1.id, $0) })
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: selection helpers

    func togglePath(_ path: String) {
        if checked.contains(path) { checked.remove(path) } else { checked.insert(path) }
    }

    func setCategoryChecked(_ id: String, on: Bool) {
        guard let idx = groupIndex[id] else { return }
        let paths = groups[idx].paths
        if on { checked.formUnion(paths) } else { checked.subtract(paths) }
    }

    func categoryState(_ id: String) -> ToggleState {
        guard let idx = groupIndex[id] else { return .none }
        let paths = groups[idx].paths
        let inter = checked.intersection(paths).count
        if inter == 0 { return .none }
        if inter == paths.count { return .all }
        return .some
    }

    enum ToggleState { case none, some, all }

    func selectAll() { checked = Set(groups.flatMap(\.items).map(\.path)) }
    func clearAll() { checked.removeAll() }

    // MARK: trash

    func trashSelected(dryRun: Bool) async {
        let deleter = Deleter()
        var ok = 0, fail = 0
        var failures: [String] = []
        for path in checked {
            do {
                _ = try await deleter.delete(path, mode: dryRun ? .dryRun : .trash)
                ok += 1
            } catch {
                fail += 1
                failures.append("\(path): \(error)")
            }
        }
        if dryRun {
            lastResult = "Dry run: would trash \(ok) item(s)" + (fail > 0 ? ", \(fail) blocked" : "")
        } else {
            lastResult = "Trashed \(ok) item(s)" + (fail > 0 ? ", \(fail) failed" : "")
            // remove deleted from groups
            for i in groups.indices {
                groups[i].items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
            }
            groups = groups.filter { !$0.items.isEmpty }
            groupIndex = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1.id, $0) })
            checked = checked.filter { p in groups.contains { $0.paths.contains(p) } }
        }
        if !failures.isEmpty {
            lastError = failures.prefix(3).joined(separator: "\n")
        } else {
            lastError = nil
        }
    }

    var totalBytesSelected: Int64 {
        groups.flatMap(\.items)
            .filter { checked.contains($0.path) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var totalCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }
}

struct CleanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CleanViewModel()
    @State private var enabledCategoryIDs: Set<String> = []
    @State private var confirmingTrash: Bool = false

    var categories: [PathCatalog.Category] {
        (appState.pathCatalog?.categories ?? []).filter { $0.scope == .user }
    }

    var body: some View {
        HSplitView {
            categorySidebar
                .frame(minWidth: 260, idealWidth: 300)
            resultsPane
        }
        .navigationTitle("Clean")
        .onAppear {
            if enabledCategoryIDs.isEmpty {
                enabledCategoryIDs = Set(categories.map(\.id))
            }
        }
        .confirmationDialog(
            "Move \(vm.checked.count) item(s) to Trash?",
            isPresented: $confirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await vm.trashSelected(dryRun: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Total: \(ByteCountFormatter.string(fromByteCount: vm.totalBytesSelected, countStyle: .file)). Items go to the system Trash and can be recovered until you empty it.")
        }
    }

    // MARK: - Sidebar

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Categories").font(.headline)
                Spacer()
                Button("All") { enabledCategoryIDs = Set(categories.map(\.id)) }
                    .buttonStyle(.borderless)
                Button("None") { enabledCategoryIDs = [] }
                    .buttonStyle(.borderless)
            }
            .padding([.top, .horizontal])

            List {
                ForEach(categories, id: \.id) { cat in
                    Toggle(isOn: Binding(
                        get: { enabledCategoryIDs.contains(cat.id) },
                        set: { on in
                            if on { enabledCategoryIDs.insert(cat.id) } else { enabledCategoryIDs.remove(cat.id) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(cat.title).font(.callout)
                            Text("risk: \(cat.risk.rawValue)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Whitelist: \(Whitelist.defaultPatterns.count) core patterns active")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal).padding(.bottom, 8)
        }
    }

    // MARK: - Results

    private var resultsPane: some View {
        VStack(spacing: 0) {
            tccBanner
            scanButtonBar
            summaryBar

            if vm.groups.isEmpty && !vm.isScanning {
                emptyState
            } else {
                groupedList
            }

            statusMessages
            Divider()
            footer
        }
    }

    @AppStorage("hideTCCBanner") private var hideTCCBanner: Bool = false

    @ViewBuilder
    private var tccBanner: some View {
        if !hideTCCBanner {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grant Full Disk Access for fewer prompts").font(.callout.bold())
                    Text("System Settings → Privacy & Security → Full Disk Access → add Mac Vulture. Without it, macOS re-asks for Downloads/Desktop/Documents access on every rebuild.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button {
                    hideTCCBanner = true
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal).padding(.top, 8)
        }
    }

    private var scanButtonBar: some View {
        HStack(spacing: 12) {
            if vm.isScanning {
                Button(role: .cancel) { vm.cancel() } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else {
                Button {
                    let cats = categories.filter { enabledCategoryIDs.contains($0.id) }
                    vm.scan(categories: cats.isEmpty ? categories : cats)
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(categories.isEmpty || enabledCategoryIDs.isEmpty)
            }
        }
        .padding(.horizontal).padding(.top, 12)
    }

    private var summaryBar: some View {
        HStack {
            Text("\(vm.totalCount) items in \(vm.groups.count) categories").font(.headline)
            Text("·").foregroundStyle(.secondary)
            Text("\(vm.checked.count) selected").foregroundStyle(.secondary)
            Spacer()
            Button("All", action: vm.selectAll).disabled(vm.totalCount == 0)
            Button("None", action: vm.clearAll).disabled(vm.checked.isEmpty)
            if vm.isScanning {
                ProgressView().controlSize(.small)
            }
        }
        .padding([.top, .horizontal])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Nothing scanned yet")
            Text("Pick categories on the left and press Scan.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedList: some View {
        List {
            ForEach(vm.groups) { group in
                CategorySection(
                    group: group,
                    expanded: vm.expanded.contains(group.id),
                    state: vm.categoryState(group.id),
                    onExpand: { isOpen in
                        if isOpen { vm.expanded.insert(group.id) } else { vm.expanded.remove(group.id) }
                    },
                    onToggleAll: { on in vm.setCategoryChecked(group.id, on: on) },
                    isChecked: { vm.checked.contains($0) },
                    onToggleItem: { vm.togglePath($0) }
                )
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let err = vm.lastError {
            Text(err).font(.caption).foregroundStyle(.red)
                .padding(.horizontal).lineLimit(3)
        }
        if let r = vm.lastResult {
            Text(r).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Dry run", isOn: $appState.dryRunDefault)
            Spacer()
            Text("Selected: \(ByteCountFormatter.string(fromByteCount: vm.totalBytesSelected, countStyle: .file))")
                .foregroundStyle(.secondary).monospacedDigit()
            if appState.dryRunDefault {
                Button {
                    Task { await vm.trashSelected(dryRun: true) }
                } label: { Label("Preview", systemImage: "eye") }
                .disabled(vm.checked.isEmpty)
            } else {
                Button(role: .destructive) {
                    confirmingTrash = true
                } label: { Label("Move to Trash", systemImage: "trash") }
                .buttonStyle(.borderedProminent)
                .disabled(vm.checked.isEmpty)
            }
        }
        .padding(12)
    }
}

// MARK: - Category section row

private struct CategorySection: View {
    let group: CleanViewModel.CategoryGroup
    let expanded: Bool
    let state: CleanViewModel.ToggleState
    let onExpand: (Bool) -> Void
    let onToggleAll: (Bool) -> Void
    let isChecked: (String) -> Bool
    let onToggleItem: (String) -> Void

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(get: { expanded }, set: { onExpand($0) })
        ) {
            // Inner item list — only renders when expanded
            ForEach(group.items.prefix(500)) { item in
                ItemRow(
                    item: item,
                    isChecked: isChecked(item.path),
                    onToggle: { onToggleItem(item.path) }
                )
            }
            if group.items.count > 500 {
                Text("+ \(group.items.count - 500) more (toggle category to include)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 10) {
                triStateBox
                    .onTapGesture { onToggleAll(state != .all) }
                Image(systemName: riskIcon).foregroundStyle(riskColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).fontWeight(.medium)
                    Text("\(group.items.count) items · risk: \(group.risk.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))
                    .monospacedDigit().font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var triStateBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(.secondary, lineWidth: 1)
                .frame(width: 16, height: 16)
            switch state {
            case .all:
                Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.tint)
            case .some:
                Rectangle().fill(.tint).frame(width: 8, height: 2)
            case .none:
                EmptyView()
            }
        }
    }

    private var riskIcon: String {
        switch group.risk {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.shield"
        case .high: return "xmark.shield"
        }
    }
    private var riskColor: Color {
        switch group.risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

private struct ItemRow: View {
    let item: ScanItem
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { isChecked }, set: { _ in onToggle() })) { EmptyView() }
                .toggleStyle(.checkbox)
            Text((item.path as NSString).lastPathComponent).lineLimit(1)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                .monospacedDigit().font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Reveal in Finder") { Reveal.inFinder(item.path) }
            Button("Add to Whitelist") { WhitelistEditor.append([item.path]) }
        }
    }
}
