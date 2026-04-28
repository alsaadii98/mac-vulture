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

    private var categoryMeta: [String: (title: String, risk: PathCatalog.Risk)] = [:]
    @Published var pendingCategories: Int = 0

    func scan(categories: [PathCatalog.Category], home: String = NSHomeDirectory()) {
        cancel()
        groups.removeAll()
        groupIndex.removeAll()
        categoryMeta = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, ($0.title, $0.risk)) })
        checked.removeAll()
        expanded.removeAll()
        lastError = nil
        lastResult = nil
        isScanning = true
        pendingCategories = categories.count
        let scanner = GlobScanner(home: home)
        scanTask = Task { [self] in
            await withTaskGroup(of: Void.self) { group in
                for cat in categories {
                    group.addTask { [self] in
                        for await item in scanner.scan(category: cat) {
                            await self.append(item)
                        }
                        await self.completeCategory()
                    }
                }
            }
            self.markDone()
        }
    }

    @MainActor private func append(_ item: ScanItem) {
        if let idx = groupIndex[item.categoryID] {
            groups[idx].items.append(item)
        } else if let meta = categoryMeta[item.categoryID] {
            // lazy: create group only when first item arrives
            let g = CategoryGroup(id: item.categoryID, title: meta.title, risk: meta.risk, items: [item])
            groups.append(g)
            groupIndex[item.categoryID] = groups.count - 1
        }
        checked.insert(item.path)
    }

    @MainActor private func completeCategory() {
        if pendingCategories > 0 { pendingCategories -= 1 }
    }

    @MainActor private func markDone() {
        isScanning = false
        pendingCategories = 0
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
        .onAppear {
            if enabledCategoryIDs.isEmpty {
                enabledCategoryIDs = Set(categories.map(\.id))
            }
            hasFDA = TCC.hasFullDiskAccess()
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
    @State private var hasFDA: Bool = TCC.hasFullDiskAccess()

    @ViewBuilder
    private var tccBanner: some View {
        if !hideTCCBanner && !hasFDA {
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
            Text("\(vm.totalCount) items").font(.headline)
            Text("·").foregroundStyle(.secondary)
            Text("\(vm.groups.count) categories with results").foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text("\(vm.checked.count) selected").foregroundStyle(.secondary)
            Spacer()
            Button("All", action: vm.selectAll).disabled(vm.totalCount == 0)
            Button("None", action: vm.clearAll).disabled(vm.checked.isEmpty)
            if vm.isScanning {
                ProgressView().controlSize(.small)
                Text("\(vm.pendingCategories) pending").font(.caption).foregroundStyle(.secondary)
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
        ScrollView {
            LazyVStack(spacing: 0) {
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
                    Divider()
                }
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
        VStack(spacing: 0) {
            headerRow
            if expanded {
                Divider().padding(.leading, 56)
                ForEach(group.items.prefix(500)) { item in
                    ItemRow(
                        item: item,
                        isChecked: isChecked(item.path),
                        onToggle: { onToggleItem(item.path) }
                    )
                    .padding(.leading, 40)
                }
                if group.items.count > 500 {
                    Text("+ \(group.items.count - 500) more (toggle category to include all)")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 40).padding(.vertical, 4)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            // Chevron — toggles expand on tap
            Button {
                onExpand(!expanded)
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Tri-state checkbox — toggles select-all
            Button {
                onToggleAll(state != .all)
            } label: {
                triStateBox
            }
            .buttonStyle(.plain)

            // Risk icon
            Image(systemName: riskIcon).foregroundStyle(riskColor)

            // Title + count
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).fontWeight(.medium)
                Text("\(group.items.count) items · risk: \(group.risk.rawValue)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))
                .monospacedDigit().font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { onExpand(!expanded) }
    }

    private var triStateBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(state == .all ? Color.accentColor : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(state == .none ? Color.secondary : Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: 18, height: 18)
            switch state {
            case .all:
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            case .some:
                Rectangle().fill(Color.accentColor).frame(width: 10, height: 2)
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
        HStack(spacing: 10) {
            Button {
                onToggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isChecked ? Color.accentColor : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isChecked ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                        )
                        .frame(width: 16, height: 16)
                    if isChecked {
                        Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text((item.path as NSString).lastPathComponent).lineLimit(1).font(.callout)
                Text(item.path).font(.caption2.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                .monospacedDigit().font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .contextMenu {
            Button("Reveal in Finder") { Reveal.inFinder(item.path) }
            Button("Add to Whitelist") { WhitelistEditor.append([item.path]) }
        }
    }
}
