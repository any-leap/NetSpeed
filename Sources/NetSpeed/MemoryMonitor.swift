import Foundation
import Darwin

struct MemoryInfo {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var appMemory: UInt64 = 0    // active + inactive
    var wired: UInt64 = 0
    var compressed: UInt64 = 0

    var usagePercent: Double {
        total > 0 ? Double(used) / Double(total) * 100 : 0
    }

    var pressure: String {
        let pct = usagePercent
        if pct < 70 { return "Normal" }
        if pct < 85 { return "Warning" }
        return "Critical"
    }
}

struct MemProcess {
    let pid: Int
    let name: String
    let mem: UInt64  // RSS in bytes
}

class MemoryMonitor {
    var info = MemoryInfo()
    var topProcesses: [MemProcess] = []
    private let lister = ProcessLister()

    func update() {
        info = readMemoryInfo()
        topProcesses = lister.topMemoryProcesses(limit: 5)
    }

    private func readMemoryInfo() -> MemoryInfo {
        var info = MemoryInfo()

        // Total RAM
        var size = MemoryLayout<UInt64>.size
        var totalMem: UInt64 = 0
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)
        info.total = totalMem

        // VM statistics
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return info }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let inactive = UInt64(vmStats.inactive_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let free = UInt64(vmStats.free_count) * pageSize

        info.appMemory = active + inactive
        info.wired = wired
        info.compressed = compressed
        info.free = free
        info.used = active + wired + compressed
        return info
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 * 1024 {
            return String(format: "%.1f KB", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", b / 1024 / 1024)
        } else {
            return String(format: "%.2f GB", b / 1024 / 1024 / 1024)
        }
    }
}
