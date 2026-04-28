import SwiftUI
import MacVultureCore

@MainActor
final class FooterBarViewModel: ObservableObject {
    @Published var snapshot: StatusSnapshot?
    @Published var topProcsExpanded: Bool = false
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct FooterBar: View {
    @StateObject private var vm = FooterBarViewModel()
    @State private var showProcesses = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            HStack(spacing: 14) {
                MiniMetric(
                    icon: "cpu",
                    label: "CPU",
                    value: vm.snapshot.map { String(format: "%.0f%%", $0.cpu.usagePercent) } ?? "—",
                    tint: cpuTint
                )
                Divider().frame(height: 22)
                MiniMetric(
                    icon: "memorychip",
                    label: "Memory",
                    value: vm.snapshot.map { String(format: "%.0f%%", $0.memory.pressurePercent) } ?? "—",
                    tint: memTint
                )
                Divider().frame(height: 22)
                MiniMetric(
                    icon: "internaldrive",
                    label: "Disk",
                    value: vm.snapshot?.disk.map { String(format: "%.0f%%", (1 - $0.freeFraction) * 100) } ?? "—",
                    tint: .secondary
                )
                Divider().frame(height: 22)
                MiniMetric(
                    icon: "bolt.batteryblock",
                    label: "Battery",
                    value: batteryValue,
                    tint: batteryTint
                )
                Spacer()
                Button {
                    showProcesses.toggle()
                } label: {
                    Label("Top processes", systemImage: showProcesses ? "chevron.down" : "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(red: 0.10, green: 0.11, blue: 0.12))

            if showProcesses, let procs = vm.snapshot?.topProcesses {
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    ForEach(procs.prefix(6)) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.caption).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: p.memoryBytes, countStyle: .memory))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(red: 0.10, green: 0.11, blue: 0.12))
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var cpuTint: Color {
        guard let p = vm.snapshot?.cpu.usagePercent else { return .secondary }
        if p > 80 { return .red }
        if p > 60 { return .orange }
        return .green
    }

    private var memTint: Color {
        guard let p = vm.snapshot?.memory.pressurePercent else { return .secondary }
        if p > 90 { return .red }
        if p > 75 { return .orange }
        return .green
    }

    private var batteryValue: String {
        guard let b = vm.snapshot?.battery, let p = b.percent else { return "—" }
        return "\(p)%" + (b.isCharging ? " ⚡" : "")
    }

    private var batteryTint: Color {
        guard let b = vm.snapshot?.battery, let p = b.percent else { return .secondary }
        if !b.isCharging && p < 20 { return .red }
        if !b.isCharging && p < 40 { return .orange }
        return .green
    }
}

private struct MiniMetric: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).font(.caption)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}
