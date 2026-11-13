import Foundation
import Darwin

struct TopProcess {
    let pid: Int
    let name: String
    let cpu: Double
}

struct AlertRecord {
    let time: String
    let message: String
}

class CPUMonitor {
    var cpuUsage: Double = 0
    var topProcesses: [TopProcess] = []

    // CPUGuard integration
    // 阈值、持续时长、忽略/关注名单来自设置窗口，每次读取即时生效。
    private let prefs: Preferences
    private let notifier = NotificationHelper()
    var cpuThreshold: Double { prefs.cpuThreshold }
    var sustainedSeconds: Int { prefs.sustainedSeconds }
    let alertCooldown: TimeInterval = 300
    var watchedProcesses: [String] { prefs.watchedProcesses }

    init(prefs: Preferences = .shared) {
        self.prefs = prefs
    }

    private var prevCPUInfo: host_cpu_load_info?
    private let lister = ProcessLister()
    private var sustainedCounts: [Int: Int] = [:]
    private var lastAlertTime: [String: Date] = [:]
    private(set) var recentAlerts: [AlertRecord] = []
    private(set) var abnormalProcesses: [TopProcess] = []
    /// PIDs that have been sustained above threshold
    var sustainedPids: Set<Int> { Set(sustainedCounts.keys) }

    func update() {
        cpuUsage = readCPUUsage()
        topProcesses = readTopProcesses(count: 5)
    }

    func guardCheck() {
        let allProcs = readTopProcesses(count: 200)
        var activePids: Set<Int> = []
        var abnormal: [TopProcess] = []
        let threshold = cpuThreshold
        let ignoredProcesses = Set(prefs.ignoredProcesses)
        let samplesNeeded = sustainedSeconds / 10

        for proc in allProcs {
            activePids.insert(proc.pid)
            if ignoredProcesses.contains(proc.name) { continue }

            if proc.cpu >= threshold {
                sustainedCounts[proc.pid, default: 0] += 1
                let count = sustainedCounts[proc.pid]!

                abnormal.append(proc)

                if count >= samplesNeeded {
                    if let lastTime = lastAlertTime[proc.name],
                       Date().timeIntervalSince(lastTime) < alertCooldown {
                        continue
                    }
                    let duration = count * 10
                    let msg = "\(proc.name) (PID \(proc.pid)) at \(String(format: "%.0f", proc.cpu))% for \(duration)s"
                    addAlert(msg)
                    sendNotification(
                        title: "CPU Guard: \(proc.name) \(String(format: "%.0f", proc.cpu))%",
                        message: "PID \(proc.pid) sustained high CPU for \(duration)s"
                    )
                    lastAlertTime[proc.name] = Date()
                }
            } else {
                sustainedCounts[proc.pid] = nil
            }
        }

        sustainedCounts = sustainedCounts.filter { activePids.contains($0.key) }
        abnormalProcesses = abnormal

        // Check watched processes (use pgrep instead of top-N list, since
        // low-CPU daemons like bird may not appear in the top 200)
        for name in watchedProcesses {
            let alive = isProcessRunning(name: name)
            if !alive {
                if lastAlertTime["__watch_\(name)"] == nil {
                    addAlert(L10n.watchedNotRunningAlert(name))
                    sendNotification(
                        title: L10n.watchedNotRunningTitle(name),
                        message: L10n.watchedNotRunningMessage(name)
                    )
                    lastAlertTime["__watch_\(name)"] = Date()
                }
            } else {
                lastAlertTime.removeValue(forKey: "__watch_\(name)")
            }
        }
    }

    private func addAlert(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let record = AlertRecord(time: formatter.string(from: Date()), message: message)
        recentAlerts.insert(record, at: 0)
        if recentAlerts.count > 20 { recentAlerts.removeLast() }
    }

    private func isProcessRunning(name: String) -> Bool {
        return lister.isProcessRunning(name: name)
    }

    private func sendNotification(title: String, message: String) {
        notifier.send(title: title, message: message)
    }

    // MARK: - CPU Reading

    private func readCPUUsage() -> Double {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let user = Double(cpuLoadInfo.cpu_ticks.0)
        let system = Double(cpuLoadInfo.cpu_ticks.1)
        let idle = Double(cpuLoadInfo.cpu_ticks.2)
        let nice = Double(cpuLoadInfo.cpu_ticks.3)

        if let prev = prevCPUInfo {
            let dUser = user - Double(prev.cpu_ticks.0)
            let dSystem = system - Double(prev.cpu_ticks.1)
            let dIdle = idle - Double(prev.cpu_ticks.2)
            let dNice = nice - Double(prev.cpu_ticks.3)
            let total = dUser + dSystem + dIdle + dNice
            prevCPUInfo = cpuLoadInfo
            return total > 0 ? ((dUser + dSystem + dNice) / total) * 100 : 0
        }

        prevCPUInfo = cpuLoadInfo
        return 0
    }

    func readTopProcesses(count: Int) -> [TopProcess] {
        return lister.topProcesses(limit: count)
    }
}
