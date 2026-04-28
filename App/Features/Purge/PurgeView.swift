import SwiftUI
import MacVultureCore

@MainActor
final class PurgeViewModel: ObservableObject {
    @Published var projects: [PurgeProject] = []
    @Published var selectedArtifacts: Set<String> = []
    @Published var isScanning: Bool = false
    @Published var roots: [String] = PurgeScanner.roots()
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    func scan() {
        task?.cancel()
        projects.removeAll()
        selectedArtifacts.removeAll()
        isScanning = true
        let r = roots
        task = Task { [self] in
            for await proj in PurgeScanner.scan(roots: r) {
                self.append(proj)
            }
            self.markDone()
        }
    }

    private func append(_ proj: PurgeProject) {
        projects.append(proj)
        for art in proj.artifacts { selectedArtifacts.insert(art.path) }
    }

    private func markDone() { isScanning = false }

    func cancel() { task?.cancel(); isScanning = false }

    func trash(dryRun: Bool) async {
        let deleter = Deleter(allowedRoots: ["/"])
        var failures: [String] = []
        let paths = Array(selectedArtifacts)
        for path in paths {
            do {
                _ = try await deleter.delete(path, mode: dryRun ? .dryRun : .trash)
            } catch {
                failures.append(path)
            }
        }
        if !failures.isEmpty { lastError = "\(failures.count) failed" }
        if !dryRun {
            // remove deleted artifacts
            projects = projects.compactMap { proj in
                let remaining = proj.artifacts.filter { FileManager.default.fileExists(atPath: $0.path) }
                if remaining.isEmpty { return nil }
                return PurgeProject(rootPath: proj.rootPath, kind: proj.kind, artifacts: remaining)
            }
            selectedArtifacts = Set(projects.flatMap { $0.artifacts.map(\.path) })
        }
    }

    var totalSelected: Int64 {
        projects.flatMap(\.artifacts)
            .filter { selectedArtifacts.contains($0.path) }
            .reduce(0) { $0 + $1.sizeBytes }
    }
}

struct PurgeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = PurgeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.projects.isEmpty && !vm.isScanning {
                emptyState
            } else {
                projectList
            }
            Divider()
            footer
        }
        .navigationTitle("Project Purge")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project Artifacts").font(.headline)
                Text("\(vm.roots.count) root(s) · \(vm.projects.count) project(s) found")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isScanning {
                ProgressView().controlSize(.small)
                Button("Stop") { vm.cancel() }
            } else {
                Button {
                    vm.scan()
                } label: { Label("Scan", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.roots.isEmpty)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No artifacts scanned yet")
            if vm.roots.isEmpty {
                Text("No project roots found. Configure `~/.config/mac-vulture/purge_paths`.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Scanning roots: \(vm.roots.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectList: some View {
        List {
            ForEach(vm.projects) { proj in
                Section {
                    ForEach(proj.artifacts) { art in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { vm.selectedArtifacts.contains(art.path) },
                                set: { on in
                                    if on { vm.selectedArtifacts.insert(art.path) }
                                    else { vm.selectedArtifacts.remove(art.path) }
                                }
                            )) {
                                HStack {
                                    Image(systemName: "shippingbox.fill").foregroundStyle(.tint)
                                    Text(art.target).font(.callout.monospaced())
                                    Spacer()
                                }
                            }
                            Text(ByteCountFormatter.string(fromByteCount: art.sizeBytes, countStyle: .file))
                                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { Reveal.inFinder(art.path) }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "folder.fill")
                        Text(proj.name).font(.headline)
                        Text(proj.kind).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: proj.totalBytes, countStyle: .file))
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Dry run", isOn: $appState.dryRunDefault)
            Spacer()
            Text("Selected: \(ByteCountFormatter.string(fromByteCount: vm.totalSelected, countStyle: .file))")
                .foregroundStyle(.secondary).monospacedDigit()
            Button {
                Task { await vm.trash(dryRun: appState.dryRunDefault) }
            } label: {
                Label(appState.dryRunDefault ? "Preview" : "Move to Trash",
                      systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedArtifacts.isEmpty || vm.isScanning)
        }
        .padding(12)
    }
}
