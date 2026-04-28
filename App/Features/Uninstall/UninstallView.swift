import SwiftUI
import MacVultureCore

@MainActor
final class UninstallViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var loading: Bool = false
    @Published var search: String = ""
    @Published var selected: InstalledApp?
    @Published var leftovers: [Leftover] = []
    @Published var leftoverLoading: Bool = false
    @Published var checkedLeftovers: Set<String> = []
    @Published var lastError: String?

    var filtered: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    func load() async {
        loading = true
        defer { loading = false }
        apps = await InstalledApp.discoverAll()
    }

    func select(_ app: InstalledApp) async {
        selected = app
        leftovers = []
        checkedLeftovers = []
        leftoverLoading = true
        defer { leftoverLoading = false }
        let l = await LeftoverResolver.leftovers(for: app)
        leftovers = l
        checkedLeftovers = Set(l.filter { $0.sizeBytes > 0 }.map(\.path))
    }

    func uninstall(includeApp: Bool, mode: DeleteMode) async {
        guard let app = selected else { return }
        let deleter = Deleter(allowedRoots: ["/Applications", "\(NSHomeDirectory())/Applications", NSHomeDirectory()])
        var failures: [String] = []
        for path in checkedLeftovers {
            do {
                _ = try await deleter.delete(path, mode: mode)
            } catch {
                failures.append(path)
            }
        }
        if includeApp {
            do {
                _ = try await deleter.delete(app.appPath, mode: mode)
            } catch {
                failures.append(app.appPath)
            }
        }
        if !failures.isEmpty {
            lastError = "\(failures.count) item(s) failed"
        }
        if mode != .dryRun {
            apps.removeAll { $0.bundleID == app.bundleID && !FileManager.default.fileExists(atPath: app.appPath) }
            await select(app)
        }
    }
}

struct UninstallView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = UninstallViewModel()

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 320, idealWidth: 360)
            detailPane
        }
        .navigationTitle("Uninstaller")
        .task { await vm.load() }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $vm.search)
                    .textFieldStyle(.plain)
                if vm.loading { ProgressView().controlSize(.small) }
            }.padding(8)
            Divider()
            List(vm.filtered, selection: Binding(
                get: { vm.selected?.bundleID },
                set: { id in
                    if let id, let app = vm.apps.first(where: { $0.bundleID == id }) {
                        Task { await vm.select(app) }
                    }
                }
            )) { app in
                HStack {
                    VStack(alignment: .leading) {
                        Text(app.name).fontWeight(.medium)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if app.isRunning {
                        Text("running").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                    Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(app.bundleID)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let app = vm.selected {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.name).font(.title2.bold())
                    Text(app.bundleID).font(.callout.monospaced()).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label(app.version, systemImage: "tag").font(.caption)
                        Label(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file),
                              systemImage: "internaldrive").font(.caption)
                        if app.isRunning {
                            Label("Running", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding()
                Divider()

                if vm.leftoverLoading {
                    ProgressView("Scanning leftovers…").padding()
                }
                List {
                    Section("Leftover files (\(vm.leftovers.count))") {
                        ForEach(vm.leftovers) { l in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { vm.checkedLeftovers.contains(l.path) },
                                    set: { on in if on { vm.checkedLeftovers.insert(l.path) } else { vm.checkedLeftovers.remove(l.path) } }
                                )) {
                                    VStack(alignment: .leading) {
                                        Text(l.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                                        Text(l.kind.rawValue).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: l.sizeBytes, countStyle: .file))
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("Reveal in Finder") { Reveal.inFinder(l.path) }
                            }
                        }
                    }
                }

                Divider()
                HStack {
                    Toggle("Dry run", isOn: $appState.dryRunDefault)
                    Spacer()
                    if app.isRunning {
                        Text("Quit \(app.name) before uninstalling.").font(.caption).foregroundStyle(.orange)
                    }
                    Button(appState.dryRunDefault ? "Preview" : "Uninstall", role: .destructive) {
                        Task { await vm.uninstall(includeApp: true, mode: appState.dryRunDefault ? .dryRun : .trash) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isRunning && !appState.dryRunDefault)
                }
                .padding()
            }
        } else {
            Placeholder(title: "Select an app", subtitle: "Choose an app on the left to see its leftovers.", icon: "trash")
        }
    }
}
