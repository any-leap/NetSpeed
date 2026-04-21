import Foundation

struct TunnelInfo {
    let interfaceName: String       // e.g. "utun4"
    let localIP: String?
    let bytesIn: UInt64
    let bytesOut: UInt64
    let speedIn: Double             // bytes/sec, per-interface
    let speedOut: Double
}

struct VPNStatus {
    let tunnels: [TunnelInfo]

    var connected: Bool { !tunnels.isEmpty }

    // Backward-compat shortcuts — return the first tunnel's info so existing
    // callers (App.swift, structureSignature helpers) keep working.
    var primary: TunnelInfo? { tunnels.first }
    var interfaceName: String? { primary?.interfaceName }
    var localIP: String? { primary?.localIP }
    var bytesIn: UInt64 { primary?.bytesIn ?? 0 }
    var bytesOut: UInt64 { primary?.bytesOut ?? 0 }
}

class VPNMonitor {
    private(set) var status = VPNStatus(tunnels: [])

    // Per-interface byte counters from previous tick, keyed by interface name.
    private var prevBytes: [String: (in: UInt64, out: UInt64)] = [:]

    private var wasConnected = false
    var onDisconnect: (() -> Void)?

    func update(interval: TimeInterval = 2.0) {
        let ifaceNames = findAllVPNInterfaces()

        var tunnels: [TunnelInfo] = []
        for name in ifaceNames {
            let stats = readInterfaceStats(name: name)
            let ip = getInterfaceIP(name: name)

            var speedIn: Double = 0
            var speedOut: Double = 0
            if let prev = prevBytes[name] {
                let dIn = stats.bytesIn >= prev.in ? stats.bytesIn - prev.in : 0
                let dOut = stats.bytesOut >= prev.out ? stats.bytesOut - prev.out : 0
                speedIn = Double(dIn) / interval
                speedOut = Double(dOut) / interval
            }
            prevBytes[name] = (stats.bytesIn, stats.bytesOut)

            tunnels.append(TunnelInfo(
                interfaceName: name,
                localIP: ip,
                bytesIn: stats.bytesIn,
                bytesOut: stats.bytesOut,
                speedIn: speedIn,
                speedOut: speedOut
            ))
        }

        // Drop byte counters for interfaces that vanished (rare but possible on
        // disconnect) so a reconnected utun with the same name restarts clean.
        let currentSet = Set(ifaceNames)
        prevBytes = prevBytes.filter { currentSet.contains($0.key) }

        let connected = !tunnels.isEmpty
        status = VPNStatus(tunnels: tunnels)

        if wasConnected && !connected {
            onDisconnect?()
        }
        wasConnected = connected
    }

    // MARK: - Find all utun interfaces with IPv4

    private func findAllVPNInterfaces() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var result: [String] = []
        var seen: Set<String> = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("utun"),
               p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               !seen.contains(name) {
                result.append(name)
                seen.insert(name)
            }
            ptr = p.pointee.ifa_next
        }
        return result
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
