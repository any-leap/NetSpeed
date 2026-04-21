import Foundation

struct VPNStatus {
    let connected: Bool
    let interfaceName: String?  // e.g. "utun6"
    let localIP: String?        // e.g. "10.3.3.4"
    let bytesIn: UInt64
    let bytesOut: UInt64
}

class VPNMonitor {
    private(set) var status = VPNStatus(connected: false, interfaceName: nil, localIP: nil, bytesIn: 0, bytesOut: 0)
    private var prevBytesIn: UInt64 = 0
    private var prevBytesOut: UInt64 = 0
    private(set) var speedIn: Double = 0   // bytes/sec
    private(set) var speedOut: Double = 0  // bytes/sec
    private var wasConnected = false
    var onDisconnect: (() -> Void)?

    func update(interval: TimeInterval = 2.0) {
        let iface = findVPNInterface()

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var localIP: String?

        if let iface = iface {
            let stats = readInterfaceStats(name: iface)
            bytesIn = stats.bytesIn
            bytesOut = stats.bytesOut
            localIP = getInterfaceIP(name: iface)
        }

        // Calculate speed
        if prevBytesIn > 0 {
            let dIn = bytesIn >= prevBytesIn ? bytesIn - prevBytesIn : 0
            let dOut = bytesOut >= prevBytesOut ? bytesOut - prevBytesOut : 0
            speedIn = Double(dIn) / interval
            speedOut = Double(dOut) / interval
        }
        prevBytesIn = bytesIn
        prevBytesOut = bytesOut

        let connected = iface != nil
        status = VPNStatus(
            connected: connected,
            interfaceName: iface,
            localIP: localIP,
            bytesIn: bytesIn,
            bytesOut: bytesOut
        )

        if wasConnected && !connected {
            onDisconnect?()
        }
        wasConnected = connected
    }

    // MARK: - Find active utun interface with a routable IP

    private func findVPNInterface() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("utun"),
               p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                // Has an IPv4 address — this is our VPN tunnel
                return name
            }
            ptr = p.pointee.ifa_next
        }
        return nil
    }

    // MARK: - Interface stats

    private func readInterfaceStats(name: String) -> (bytesIn: UInt64, bytesOut: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = ptr {
            let ifName = String(cString: p.pointee.ifa_name)
            if ifName == name, let data = p.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self)
                bytesIn += UInt64(networkData.pointee.ifi_ibytes)
                bytesOut += UInt64(networkData.pointee.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        return (bytesIn, bytesOut)
    }

    // MARK: - Get interface IP

    private func getInterfaceIP(name: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = ptr {
            let ifName = String(cString: p.pointee.ifa_name)
            if ifName == name,
               p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var addr = p.pointee.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(&addr,
                            socklen_t(addr.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                return String(cString: hostname)
            }
            ptr = p.pointee.ifa_next
        }
        return nil
    }

    // MARK: - Format

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
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
