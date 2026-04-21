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

    /// 每个 PID 的上一次累计 CPU 时间（纳秒）+ 采样 wall clock 时刻。
    private var prevSamples: [Int: (cpuTimeNs: UInt64, timestamp: TimeInterval)] = [:]

    /// 按 %CPU 降序返回 top N 进程。kernel_task 自动跳过。
    func topProcesses(limit: Int) -> [TopProcess] {
        let pids = listAllPIDs()
        let now = Date().timeIntervalSince1970

        var newSamples: [Int: (cpuTimeNs: UInt64, timestamp: TimeInterval)] = [:]
        var results: [TopProcess] = []

        for pid in pids {
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let rc = proc_pidinfo(pid, Self.PROC_PIDTASKINFO, 0, &info, infoSize)
            guard rc == infoSize else { continue }

            let cpuTimeNs = info.pti_total_user + info.pti_total_system
            let pidInt = Int(pid)
            newSamples[pidInt] = (cpuTimeNs, now)

            var cpuPct: Double = 0
            if let prev = prevSamples[pidInt] {
                let deltaCPU = Double(cpuTimeNs &- prev.cpuTimeNs)
                let deltaWallNs = (now - prev.timestamp) * 1_000_000_000.0
                cpuPct = deltaWallNs > 0 ? (deltaCPU / deltaWallNs) * 100.0 : 0
            }

            let name = processName(pid: pid)
            if name == "kernel_task" { continue }

            results.append(TopProcess(pid: pidInt, name: name, cpu: cpuPct))
        }

        prevSamples = newSamples

        return Array(results.sorted { $0.cpu > $1.cpu }.prefix(limit))
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
