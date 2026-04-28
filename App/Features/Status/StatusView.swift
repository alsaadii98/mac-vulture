import SwiftUI
import MacVultureCore

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var snapshot: StatusSnapshot?
    private let metrics = SystemMetrics()
    private var task: Task<Void, Never>?

    func start() {
        stop()
        task = Task { [self] in
            // prime CPU delta
            _ = await metrics.snapshot()
            try? await Task.sleep(nanoseconds: 200_000_000)
            while !Task.isCancelled {
                let snap = await metrics.snapshot()
                self.snapshot = snap
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct StatusView: View {
    @StateObject private var vm = StatusViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("System Status").font(.largeTitle.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    cpuCard
                    memoryCard
                    diskCard
                    batteryCard
                }
                processesCard
            }
            .padding(20)
        }
        .navigationTitle("Status")
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var cpuCard: some View {
        MetricCard(title: "CPU", icon: "cpu") {
            if let s = vm.snapshot?.cpu {
                BigGauge(value: s.usagePercent, max: 100, suffix: "%")
                Text("\(s.coreCount) cores").font(.caption).foregroundStyle(.secondary)
            } else {
                placeholder()
            }
        }
    }

    private var memoryCard: some View {
        MetricCard(title: "Memory", icon: "memorychip") {
            if let m = vm.snapshot?.memory {
                BigGauge(value: m.pressurePercent, max: 100, suffix: "%")
                let used = ByteCountFormatter.string(fromByteCount: m.usedBytes, countStyle: .memory)
                let total = ByteCountFormatter.string(fromByteCount: m.totalBytes, countStyle: .memory)
                Text("\(used) / \(total)").font(.caption).foregroundStyle(.secondary)
            } else { placeholder() }
        }
    }

    private var diskCard: some View {
        MetricCard(title: "Disk", icon: "internaldrive") {
            if let d = vm.snapshot?.disk {
                BigGauge(value: (1 - d.freeFraction) * 100, max: 100, suffix: "%")
                let free = ByteCountFormatter.string(fromByteCount: d.freeBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: d.totalBytes, countStyle: .file)
                Text("\(free) free of \(total)").font(.caption).foregroundStyle(.secondary)
            } else { placeholder() }
        }
    }

    private var batteryCard: some View {
        MetricCard(title: "Battery", icon: "bolt.batteryblock") {
            if let b = vm.snapshot?.battery, let pct = b.percent {
                BigGauge(value: Double(pct), max: 100, suffix: "%")
                Text(b.isCharging ? "Charging" : "On battery").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No battery").font(.title3).foregroundStyle(.secondary)
                Text(" ").font(.caption)
            }
        }
    }

    private var processesCard: some View {
        MetricCard(title: "Top Processes", icon: "list.bullet.rectangle") {
            if let procs = vm.snapshot?.topProcesses {
                ForEach(procs) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: p.memoryBytes, countStyle: .memory))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } else { placeholder() }
        }
    }

    @ViewBuilder
    private func placeholder() -> some View {
        Text("—").font(.title)
        Text(" ").font(.caption)
    }
}

struct MetricCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(.tint)
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BigGauge: View {
    let value: Double
    let max: Double
    let suffix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(format: "%.0f", value)).font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(suffix).foregroundStyle(.secondary)
        }
    }
}
