import Foundation
import Darwin

/// libproc 薄封装。Stateful：%CPU 计算需要前后两次采样比较累计 CPU 时间 delta。
/// 首次调用返回的所有 cpu 都是 0（没有 baseline）；第二次起才正确。
final class ProcessLister {
    // libproc 常量（<libproc.h> 里的 #define，Swift 不一定自动桥接）
    private static let PROC_ALL_PIDS: UInt32 = 1
    private static let PROC_PIDTASKINFO: Int32 = 4
    private static let PIDPATH_MAX: Int = 4 * 1024  // PROC_PIDPATHINFO_MAXSIZE
    private static let COMM_MAX: Int = 17           // MAXCOMLEN + 1

    /// mach absolute time tick → 纳秒的换算系数。
    ///
    /// `proc_taskinfo.pti_total_user/pti_total_system` 的单位是 **mach absolute time tick**，
    /// 不是纳秒（内核里由 `task_info(TASK_ABSOLUTETIME_INFO)` 填充）。Intel Mac 上 timebase
    /// 恰好是 1/1，两者数值相等，所以当成纳秒用不会暴露问题；Apple Silicon 上是 125/3
    /// ≈ 41.667 ns/tick，直接当纳秒会把所有进程 %CPU **低报约 41.7 倍**
    /// （活动监视器 1200% → 这里显示 29%），并让 CPUGuard 的 50% 阈值永远不可能触发。
    private let nsPerTick: Double = {
        var tb = mach_timebase_info_data_t()
        guard mach_timebase_info(&tb) == KERN_SUCCESS, tb.denom != 0 else { return 1.0 }
        return Double(tb.numer) / Double(tb.denom)
    }()

    /// 两次真实采样之间的最小间隔。
    ///
    /// `topProcesses` 有多个调用点、频率各不相同（`update()` 2s、`guardCheck()` 10s、
    /// 菜单打开时 `WatchedProcessesSection.structureSignature` 每 2s 各一次）。它们共用
    /// 同一份 `prevSamples`，若不做节流，后一次调用会把前一次刚写入的 baseline 冲掉，
    /// 采样窗口缩到几毫秒 → %CPU 剧烈跳动。窗口内的重复调用直接复用上次结果。
    private static let minSampleInterval: TimeInterval = 1.0

    /// 每个 PID 的上一次累计 CPU 时间（mach ticks）+ 采样 wall clock 时刻。
    private var prevSamples: [Int: (cpuTicks: UInt64, timestamp: TimeInterval)] = [:]
    /// 上一次采样的完整结果（已按 %CPU 降序），供节流窗口内的调用按 limit 切片复用。
    private var cachedResults: [TopProcess] = []
    private var lastSampleTime: TimeInterval = 0

    /// 由累计 CPU tick 增量和墙钟间隔算出 %CPU。与 `top` / 活动监视器同口径：
    /// 多核累加，满载 N 核即 N×100%。
    static func cpuPercent(deltaTicks: UInt64, deltaWallSeconds: Double, nsPerTick: Double) -> Double {
        guard deltaWallSeconds > 0 else { return 0 }
        let deltaCPUNs = Double(deltaTicks) * nsPerTick
        return deltaCPUNs / (deltaWallSeconds * 1_000_000_000.0) * 100.0
    }

    /// 按 %CPU 降序返回 top N 进程。kernel_task 自动跳过。
    func topProcesses(limit: Int) -> [TopProcess] {
        let now = Date().timeIntervalSince1970
        guard now - lastSampleTime >= Self.minSampleInterval else {
            return Array(cachedResults.prefix(limit))
        }

        let pids = listAllPIDs()
        var newSamples: [Int: (cpuTicks: UInt64, timestamp: TimeInterval)] = [:]
        var results: [TopProcess] = []

        for pid in pids {
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let rc = proc_pidinfo(pid, Self.PROC_PIDTASKINFO, 0, &info, infoSize)
            guard rc == infoSize else { continue }

            let cpuTicks = info.pti_total_user + info.pti_total_system
            let pidInt = Int(pid)
            newSamples[pidInt] = (cpuTicks, now)

            var cpuPct: Double = 0
            if let prev = prevSamples[pidInt] {
                cpuPct = Self.cpuPercent(
                    deltaTicks: cpuTicks &- prev.cpuTicks,
                    deltaWallSeconds: now - prev.timestamp,
                    nsPerTick: nsPerTick
                )
            }

            let name = processName(pid: pid)
            if name == "kernel_task" { continue }

            results.append(TopProcess(pid: pidInt, name: name, cpu: cpuPct))
        }

        prevSamples = newSamples
        cachedResults = results.sorted { $0.cpu > $1.cpu }
        lastSampleTime = now

        return Array(cachedResults.prefix(limit))
    }

    /// 按 RSS 降序返回 top N 进程。无状态（不需要像 CPU 那样的前后采样）。
    /// kernel_task / NetSpeed 自动跳过（与原 ps 版本行为一致）。
    func topMemoryProcesses(limit: Int) -> [MemProcess] {
        let pids = listAllPIDs()
        var results: [MemProcess] = []

        for pid in pids {
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let rc = proc_pidinfo(pid, Self.PROC_PIDTASKINFO, 0, &info, infoSize)
            guard rc == infoSize else { continue }

            let name = processName(pid: pid)
            if name == "kernel_task" || name == "NetSpeed" { continue }

            results.append(MemProcess(pid: Int(pid), name: name, mem: info.pti_resident_size))
        }

        return Array(results.sorted { $0.mem > $1.mem }.prefix(limit))
    }

    /// 遍历所有 PID 按名匹配。替代 `pgrep -x <name>`。
    func isProcessRunning(name: String) -> Bool {
        let pids = listAllPIDs()
        for pid in pids {
            guard pid > 0 else { continue }
            if processName(pid: pid) == name { return true }
        }
        return false
    }

    // MARK: - private helpers

    private func listAllPIDs() -> [pid_t] {
        let bytesNeeded = proc_listpids(Self.PROC_ALL_PIDS, 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }

        let capacity = Int(bytesNeeded) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesWritten = proc_listpids(Self.PROC_ALL_PIDS, 0, &pids, bytesNeeded)
        guard bytesWritten > 0 else { return [] }

        let actualCount = Int(bytesWritten) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(actualCount))
    }

    /// 先 proc_pidpath 取完整路径的 basename（更准）；失败用 proc_name 短名（16 字符）兜底。
    private func processName(pid: pid_t) -> String {
        var pathBuf = [CChar](repeating: 0, count: Self.PIDPATH_MAX)
        if proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 {
            let path = String(cString: pathBuf)
            let base = (path as NSString).lastPathComponent
            if !base.isEmpty { return base }
        }
        var nameBuf = [CChar](repeating: 0, count: Self.COMM_MAX)
        if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 {
            return String(cString: nameBuf)
        }
        return "(\(pid))"
    }
}
