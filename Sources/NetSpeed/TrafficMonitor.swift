import Foundation

struct ProcessTraffic {
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    var total: UInt64 { bytesIn + bytesOut }
}

class TrafficMonitor {
    private(set) var topTraffic: [ProcessTraffic] = []
    private var baseline: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private(set) var resetTime: Date? = nil

    func update() {
        let raw = readRaw()

        // Apply baseline
        var adjusted: [String: ProcessTraffic] = [:]
        for (name, traffic) in raw {
            let base = baseline[name] ?? (0, 0)
            let adjIn = traffic.bytesIn > base.bytesIn ? traffic.bytesIn - base.bytesIn : 0
            let adjOut = traffic.bytesOut > base.bytesOut ? traffic.bytesOut - base.bytesOut : 0
            if adjIn == 0 && adjOut == 0 { continue }
            adjusted[name] = ProcessTraffic(name: name, bytesIn: adjIn, bytesOut: adjOut)
        }

        topTraffic = adjusted.values
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { $0 }
    }

    func reset() {
        let raw = readRaw()
        baseline = [:]
        for (name, traffic) in raw {
            baseline[name] = (traffic.bytesIn, traffic.bytesOut)
        }
        resetTime = Date()
        topTraffic = []
    }

    private func readRaw() -> [String: ProcessTraffic] {
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

        var results: [String: ProcessTraffic] = [:]

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
                results[name] = ProcessTraffic(
                    name: name,
                    bytesIn: existing.bytesIn + bytesIn,
                    bytesOut: existing.bytesOut + bytesOut
                )
            } else {
                results[name] = ProcessTraffic(name: name, bytesIn: bytesIn, bytesOut: bytesOut)
            }
        }
        return results
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
