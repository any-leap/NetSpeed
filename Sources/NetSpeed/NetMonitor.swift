import Foundation

struct NetStats {
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
}

class NetMonitor: ObservableObject {
    @Published var downSpeed: String = "—"
    @Published var upSpeed: String = "—"
    var onChange: (() -> Void)?

    /// History for chart (last 60s, 2s interval = 30 points)
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []
    let maxHistory = 30

    private var lastStats = NetStats()
    private var timer: Timer?
    private let interval: TimeInterval = 2.0

    init() {
        lastStats = readStats()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func update() {
        let current = readStats()
        let dIn = current.bytesIn >= lastStats.bytesIn ? current.bytesIn - lastStats.bytesIn : 0
        let dOut = current.bytesOut >= lastStats.bytesOut ? current.bytesOut - lastStats.bytesOut : 0

        let perSecIn = Double(dIn) / interval
        let perSecOut = Double(dOut) / interval

        DispatchQueue.main.async {
            self.downSpeed = self.formatSpeed(perSecIn)
            self.upSpeed = self.formatSpeed(perSecOut)

            self.downHistory.append(perSecIn)
            self.upHistory.append(perSecOut)
            if self.downHistory.count > self.maxHistory {
                self.downHistory.removeFirst()
                self.upHistory.removeFirst()
            }

            self.onChange?()
        }

        lastStats = current
    }

    private func readStats() -> NetStats {
        var stats = NetStats()

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return stats }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            // Only count physical interfaces to avoid double-counting with VPN/TUN
            if name.hasPrefix("en") {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    stats.bytesIn += UInt64(networkData.pointee.ifi_ibytes)
                    stats.bytesOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return stats
    }

    func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / 1024 / 1024)
        } else {
            return String(format: "%.2f GB/s", bytesPerSec / 1024 / 1024 / 1024)
        }
    }

    deinit {
        timer?.invalidate()
    }
}
