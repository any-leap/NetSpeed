import Foundation
import Darwin

struct TopProcess {
    let pid: Int
    let name: String
    let cpu: Double
    let mem: Double
}

struct AlertRecord {
    let time: String
    let message: String
}

class CPUMonitor {
    var cpuUsage: Double = 0
    var topProcesses: [TopProcess] = []

    // CPUGuard integration
    let cpuThreshold: Double = 50.0
    let sustainedSeconds: Int = 30
    let alertCooldown: TimeInterval = 300
    let ignoredProcesses: Set<String> = [
        "WindowServer", "kernel_task", "Claude", "claude",
        "Spotlight", "mds", "mds_stores", "mdworker", "NetSpeed",
    ]
    let watchedProcesses: [String] = ["bird"]

    private var prevCPUInfo: host_cpu_load_info?
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

        for proc in allProcs {
            activePids.insert(proc.pid)
            if ignoredProcesses.contains(proc.name) { continue }

            if proc.cpu >= cpuThreshold {
                sustainedCounts[proc.pid, default: 0] += 1
                let count = sustainedCounts[proc.pid]!

                abnormal.append(proc)

                if count >= sustainedSeconds / 10 {
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

        // Check watched processes
        for name in watchedProcesses {
            let alive = allProcs.contains { $0.name == name }
            if !alive {
                if lastAlertTime["__watch_\(name)"] == nil {
                    addAlert("\(name) is NOT running — iCloud sync may be affected")
                    sendNotification(
                        title: "CPU Guard: \(name) not running",
                        message: "\(name) process is not running. iCloud sync may be affected."
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

    private func sendNotification(title: String, message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\" sound name \"Sosumi\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
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
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid=,pcpu=,pmem=,comm=", "-r"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [TopProcess] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { continue }

            let fullPath = String(parts[3])
            let name = (fullPath as NSString).lastPathComponent

            if name == "kernel_task" { continue }

            results.append(TopProcess(pid: pid, name: name, cpu: cpu, mem: mem))
            if results.count >= count { break }
        }
        return results
    }
}
