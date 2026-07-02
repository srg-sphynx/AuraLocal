import Foundation
import Combine
import Darwin

/// Background poller for hardware telemetry: whole-machine CPU utilization,
/// physical memory allocation, unified-memory pressure (approximated from the
/// VM page stats) and this process's footprint as a proxy for model residency.
@MainActor
final class TelemetryService: ObservableObject {
    @Published private(set) var snapshot = TelemetrySnapshot()

    private var timer: Task<Void, Never>?
    private var prevCPU: host_cpu_load_info?
    private var cpuHistory: [Double] = Array(repeating: 0, count: 48)
    private var memHistory: [Double] = Array(repeating: 0, count: 48)

    init() {
        snapshot.coreCount = ProcessInfo.processInfo.activeProcessorCount
        snapshot.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        snapshot.history = cpuHistory
        snapshot.memHistory = memHistory
    }

    func start(interval: TimeInterval = 1.5) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() { timer?.cancel() }

    private func sample() {
        let cpu = readCPUUsage()
        let mem = readMemory()
        let app = readAppMemory()

        cpuHistory.removeFirst()
        cpuHistory.append(cpu)
        memHistory.removeFirst()
        memHistory.append(mem.total > 0 ? mem.used / mem.total : 0)

        var s = snapshot
        s.cpuUsage = cpu
        s.memoryUsed = mem.used
        s.memoryTotal = mem.total
        s.memoryPressure = mem.pressure
        s.swapUsed = mem.swap
        s.appMemory = app
        s.history = cpuHistory
        s.memHistory = memHistory
        snapshot = s
    }

    // MARK: - CPU (host_statistics, delta between samples)

    private func readCPUUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.cpuUsage }

        defer { prevCPU = info }
        guard let prev = prevCPU else { return 0 }

        let userD = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let sysD  = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idleD = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let niceD = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let busy = userD + sysD + niceD
        let total = busy + idleD
        return total > 0 ? min(1, busy / total) : 0
    }

    // MARK: - Memory (vm_statistics64 + sysctl)

    private func readMemory() -> (used: Double, total: Double, pressure: Double, swap: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = Double(pageSize)

        guard result == KERN_SUCCESS else { return (0, total, 0, 0) }

        let active = Double(stats.active_count) * ps
        let wired = Double(stats.wire_count) * ps
        let compressed = Double(stats.compressor_page_count) * ps
        // "App + wired + compressed" approximates macOS Activity Monitor's memory used.
        let used = active + wired + compressed
        let free = Double(stats.free_count) * ps

        // Unified-memory pressure: weighting of wired+compressed against total, plus
        // a free-headroom penalty — mirrors the OS memory-pressure signal heuristically.
        let pressure = min(1, (wired + compressed) / total + max(0, (total * 0.10 - free) / total))

        let swap = readSwapUsed()
        return (used, total, pressure, swap)
    }

    private func readSwapUsed() -> Double {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let res = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        return res == 0 ? Double(xsw.xsu_used) : 0
    }

    // MARK: - This process footprint (proxy for model "VRAM"/residency)

    private func readAppMemory() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint)
    }
}
