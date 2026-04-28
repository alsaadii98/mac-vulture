import Foundation
import Darwin

public actor SystemMetrics: MetricsProvider {
    private var prevCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    public init() {}

    public func snapshot() async -> StatusSnapshot {
        let cpu = sampleCPU()
        let mem = sampleMemory()
        let disk = DiskInfo.forVolume()
        let battery = sampleBattery()
        let procs = sampleTopProcesses(limit: 8)
        return StatusSnapshot(cpu: cpu, memory: mem, disk: disk, battery: battery, topProcesses: procs)
    }

    // MARK: CPU

    private func sampleCPU() -> CPUSample {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p -> kern_return_t in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rb in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rb, &count)
            }
        }
        guard result == KERN_SUCCESS else { return CPUSample(usagePercent: 0, coreCount: cores) }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        defer { prevCPUTicks = (user, system, idle, nice) }
        guard let prev = prevCPUTicks else { return CPUSample(usagePercent: 0, coreCount: cores) }
        let dUser = user &- prev.user
        let dSystem = system &- prev.system
        let dIdle = idle &- prev.idle
        let dNice = nice &- prev.nice
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return CPUSample(usagePercent: 0, coreCount: cores) }
        let busy = Double(dUser + dSystem + dNice)
        return CPUSample(usagePercent: 100.0 * busy / Double(total), coreCount: cores)
    }

    // MARK: Memory

    private func sampleMemory() -> MemorySample {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { p -> kern_return_t in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rb in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rb, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemorySample(totalBytes: total, usedBytes: 0, pressurePercent: 0)
        }
        let pageSize = Int64(vm_kernel_page_size)
        let active = Int64(stats.active_count) * pageSize
        let wired = Int64(stats.wire_count) * pageSize
        let compressed = Int64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let pressure = total > 0 ? 100.0 * Double(used) / Double(total) : 0
        return MemorySample(totalBytes: total, usedBytes: used, pressurePercent: pressure)
    }

    // MARK: Top processes

    private func sampleTopProcesses(limit: Int) -> [ProcessSample] {
        let maxPids = 4096
        let bufSize = Int(maxPids) * MemoryLayout<pid_t>.size
        let buffer = UnsafeMutablePointer<pid_t>.allocate(capacity: maxPids)
        defer { buffer.deallocate() }
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer, Int32(bufSize)) / Int32(MemoryLayout<pid_t>.size)
        guard count > 0 else { return [] }

        var results: [ProcessSample] = []
        for i in 0..<Int(count) {
            let pid = buffer[i]
            guard pid > 0 else { continue }
            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let r = withUnsafeMutablePointer(to: &info) { ptr in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, infoSize)
            }
            guard r == infoSize else { continue }

            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_name(pid, &nameBuf, UInt32(MAXPATHLEN))
            let name = String(cString: nameBuf)
            let mem = Int64(info.pti_resident_size)
            // CPU usage as ratio of total task time over wall clock — coarse.
            let cpuTicks = Double(info.pti_total_user + info.pti_total_system) / 1_000_000_000.0
            let cpu = cpuTicks // raw seconds; UI shows resident memory primarily
            results.append(ProcessSample(pid: pid, name: name.isEmpty ? "pid \(pid)" : name,
                                         cpuPercent: cpu, memoryBytes: mem))
        }
        return results.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit).map { $0 }
    }

    // MARK: Battery

    private func sampleBattery() -> BatterySample {
        #if canImport(IOKit)
        let infoTask = Process()
        // Fallback: parse `pmset -g batt` since IOKit private headers are heavy.
        infoTask.launchPath = "/usr/bin/pmset"
        infoTask.arguments = ["-g", "batt"]
        let pipe = Pipe()
        infoTask.standardOutput = pipe
        infoTask.standardError = Pipe()
        do {
            try infoTask.run()
            infoTask.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else {
                return BatterySample(percent: nil, isCharging: false, timeToFullMin: nil, timeRemainingMin: nil)
            }
            return parseBattery(out)
        } catch {
            return BatterySample(percent: nil, isCharging: false, timeToFullMin: nil, timeRemainingMin: nil)
        }
        #else
        return BatterySample(percent: nil, isCharging: false, timeToFullMin: nil, timeRemainingMin: nil)
        #endif
    }

    nonisolated private func parseBattery(_ out: String) -> BatterySample {
        // example: "-InternalBattery-0 (id=...) 76%; discharging; 4:21 remaining"
        let lower = out.lowercased()
        var percent: Int?
        if let r = out.range(of: #"(\d+)%"#, options: .regularExpression) {
            percent = Int(out[r].trimmingCharacters(in: CharacterSet(charactersIn: "%")))
        }
        let charging = lower.contains("charging") && !lower.contains("not charging") && !lower.contains("discharging")
        var minutes: Int?
        if let r = out.range(of: #"(\d+):(\d+) remaining"#, options: .regularExpression) {
            let parts = out[r].split(separator: " ").first?.split(separator: ":") ?? []
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                minutes = h * 60 + m
            }
        }
        return BatterySample(percent: percent, isCharging: charging,
                             timeToFullMin: charging ? minutes : nil,
                             timeRemainingMin: charging ? nil : minutes)
    }
}
