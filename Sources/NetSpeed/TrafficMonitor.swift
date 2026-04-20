import Foundation

struct ProcessTraffic {
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    let speedIn: Double   // bytes/sec
    let speedOut: Double  // bytes/sec
    var total: UInt64 { bytesIn + bytesOut }
    var speedTotal: Double { speedIn + speedOut }
}

class TrafficMonitor {
    private(set) var topByCumulative: [ProcessTraffic] = []
    private(set) var topByLive: [ProcessTraffic] = []
    private var baseline: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var prevRaw: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var prevUpdate: Date? = nil
    private(set) var resetTime: Date? = nil

    func update() {
        let raw = readRaw()
        let now = Date()
        let dt = prevUpdate.map { now.timeIntervalSince($0) } ?? 0

        var adjusted: [ProcessTraffic] = []
        for (name, traffic) in raw {
            let base = baseline[name] ?? (0, 0)
            let adjIn = traffic.bytesIn > base.bytesIn ? traffic.bytesIn - base.bytesIn : 0
            let adjOut = traffic.bytesOut > base.bytesOut ? traffic.bytesOut - base.bytesOut : 0

            var speedIn = 0.0
            var speedOut = 0.0
            if dt > 0, let prev = prevRaw[name] {
                let dIn = traffic.bytesIn > prev.bytesIn ? traffic.bytesIn - prev.bytesIn : 0
                let dOut = traffic.bytesOut > prev.bytesOut ? traffic.bytesOut - prev.bytesOut : 0
                speedIn = Double(dIn) / dt
                speedOut = Double(dOut) / dt
            }

            if adjIn == 0 && adjOut == 0 && speedIn == 0 && speedOut == 0 { continue }
            adjusted.append(ProcessTraffic(name: name, bytesIn: adjIn, bytesOut: adjOut, speedIn: speedIn, speedOut: speedOut))
        }

        topByCumulative = Array(adjusted.sorted { $0.total > $1.total }.prefix(5))
        topByLive = Array(adjusted.sorted { $0.speedTotal > $1.speedTotal }.prefix(5))

        prevRaw = raw
        prevUpdate = now
    }

    func reset() {
        let raw = readRaw()
        baseline = [:]
        for (name, traffic) in raw {
            baseline[name] = (traffic.bytesIn, traffic.bytesOut)
        }
        resetTime = Date()
        topByCumulative = []
        topByLive = []
    }

    private func readRaw() -> [String: (bytesIn: UInt64, bytesOut: UInt64)] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-l", "1", "-J", "bytes_in,bytes_out", "-n", "-x"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return [:] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var results: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }

            let fullName = String(parts[0])
            guard let bytesIn = UInt64(parts[parts.count - 2]),
                  let bytesOut = UInt64(parts[parts.count - 1]) else { continue }

            if bytesIn == 0 && bytesOut == 0 { continue }

            let name: String
            if let dotRange = fullName.range(of: ".", options: .backwards),
               let _ = Int(fullName[dotRange.upperBound...]) {
                name = String(fullName[..<dotRange.lowerBound])
            } else {
                name = fullName
            }

            if let existing = results[name] {
                results[name] = (bytesIn: existing.bytesIn + bytesIn, bytesOut: existing.bytesOut + bytesOut)
            } else {
                results[name] = (bytesIn: bytesIn, bytesOut: bytesOut)
            }
        }
        return results
    }

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1 {
            return "0 B/s"
        } else if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.1f MB/s", bytesPerSec / 1024 / 1024)
        }
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return "\(bytes) B"
        } else if b < 1024 * 1024 {
            return String(format: "%.1f KB", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", b / 1024 / 1024)
        } else {
            return String(format: "%.2f GB", b / 1024 / 1024 / 1024)
        }
    }
}
