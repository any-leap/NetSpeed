import SwiftUI
import AppKit

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var netMonitor: NetMonitor
    private var cpuMonitor: CPUMonitor
    private var trafficMonitor: TrafficMonitor
    private var memMonitor: MemoryMonitor
    private var vpnMonitor: VPNMonitor
    private var menu: NSMenu
    private var guardTimer: Timer?
    private var menuIsOpen = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        netMonitor = NetMonitor()
        cpuMonitor = CPUMonitor()
        trafficMonitor = TrafficMonitor()
        memMonitor = MemoryMonitor()
        vpnMonitor = VPNMonitor()
        menu = NSMenu()

        super.init()

        menu.delegate = self
        statusItem.menu = menu

        vpnMonitor.onDisconnect = { [weak self] in
            self?.sendNotification(
                title: "VPN Disconnected",
                message: "OpenVPN connection has been lost"
            )
        }

        netMonitor.onChange = { [weak self] in
            self?.cpuMonitor.update()
            self?.memMonitor.update()
            self?.vpnMonitor.update()
            self?.updateLabel()
            if self?.menuIsOpen == true {
                self?.rebuildMenu()
            }
        }

        // CPUGuard check every 10 seconds
        guardTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.cpuMonitor.guardCheck()
        }
    }

    // MARK: - Menu Bar Label (network speed only)

    private func updateLabel() {
        guard let button = statusItem.button else { return }

        let font = NSFont.systemFont(ofSize: 9, weight: .medium)

        // Fixed width based on widest possible value "999.9 MB/s"
        let maxSpeedStr = NSAttributedString(string: "999.9 KB/s", attributes: [.font: font])
        let arrowStr = NSAttributedString(string: "↑ ", attributes: [.font: font])
        let fixedWidth = arrowStr.size().width + maxSpeedStr.size().width

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 0
        paragraphStyle.maximumLineHeight = 11
        paragraphStyle.minimumLineHeight = 11

        let tab = NSTextTab(textAlignment: .right, location: fixedWidth)
        paragraphStyle.tabStops = [tab]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let upLine = "↑\t\(netMonitor.upSpeed)"
        let downLine = "↓\t\(netMonitor.downSpeed)"
        let text = "\(upLine)\n\(downLine)"
        let attrStr = NSMutableAttributedString(string: text, attributes: attrs)

        let w = ceil(fixedWidth) + 4
        let h: CGFloat = 22

        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocusFlipped(true)
        attrStr.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        image.unlockFocus()
        image.isTemplate = true

        button.image = image
        button.title = ""
    }

    // MARK: - Dropdown Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        cpuMonitor.update()
        trafficMonitor.update()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        // --- Network Chart ---
        if netMonitor.downHistory.count >= 2 {
            let chartItem = NSMenuItem()
            let chartView = ChartView(
                downData: netMonitor.downHistory,
                upData: netMonitor.upHistory,
                maxHistory: netMonitor.maxHistory,
                downLabel: "↓ \(netMonitor.downSpeed)",
                upLabel: "↑ \(netMonitor.upSpeed)",
                title: L10n.network,
                formatMax: { [weak self] v in self?.netMonitor.formatSpeed(v) ?? "" }
            )
            chartItem.view = chartView
            chartItem.isEnabled = false
            menu.addItem(chartItem)
        }

        // --- VPN Status ---
        menu.addItem(NSMenuItem.separator())
        let vpn = vpnMonitor.status
        if vpn.connected {
            let vpnHeader = "\(L10n.vpn): \(L10n.vpnConnected)"
            addHeader(vpnHeader, font: headerFont)

            if let ip = vpn.localIP, let iface = vpn.interfaceName {
                let detailStr = "  \(iface)  \(ip)"
                let item = NSMenuItem(title: detailStr, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(string: detailStr, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.systemGreen,
                ])
                menu.addItem(item)
            }

            let speedStr = "  ↓ \(VPNMonitor.formatSpeed(vpnMonitor.speedIn))  ↑ \(VPNMonitor.formatSpeed(vpnMonitor.speedOut))"
            let speedItem = NSMenuItem(title: speedStr, action: nil, keyEquivalent: "")
            speedItem.isEnabled = false
            speedItem.attributedTitle = NSAttributedString(string: speedStr, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            menu.addItem(speedItem)

            let totalStr = "  ↓ \(VPNMonitor.formatBytes(vpn.bytesIn))  ↑ \(VPNMonitor.formatBytes(vpn.bytesOut))"
            let totalItem = NSMenuItem(title: totalStr, action: nil, keyEquivalent: "")
            totalItem.isEnabled = false
            totalItem.attributedTitle = NSAttributedString(string: totalStr, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
            menu.addItem(totalItem)

            let disconnectLabel = L10n.vpnDisconnectAction
            let disconnectItem = NSMenuItem(title: disconnectLabel, action: #selector(toggleVPN), keyEquivalent: "")
            disconnectItem.target = self
            disconnectItem.attributedTitle = NSAttributedString(string: "  \(disconnectLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemRed,
            ])
            menu.addItem(disconnectItem)
        } else {
            let vpnHeader = "\(L10n.vpn): \(L10n.vpnDisconnected)"
            let item = NSMenuItem(title: vpnHeader, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(string: vpnHeader, attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.systemRed,
            ])
            menu.addItem(item)

            let connectLabel = L10n.vpnConnectAction
            let connectItem = NSMenuItem(title: connectLabel, action: #selector(toggleVPN), keyEquivalent: "")
            connectItem.target = self
            connectItem.attributedTitle = NSAttributedString(string: "  \(connectLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemGreen,
            ])
            menu.addItem(connectItem)
        }

        // --- Traffic by Process ---
        menu.addItem(NSMenuItem.separator())

        // Header with reset button
        let trafficTitle: String
        if let resetTime = trafficMonitor.resetTime {
            let elapsed = Int(Date().timeIntervalSince(resetTime))
            trafficTitle = "\(L10n.trafficByProcess)  (\(L10n.sinceDuration(elapsed)))"
        } else {
            trafficTitle = L10n.trafficByProcess
        }
        addHeader(trafficTitle, font: headerFont)

        if trafficMonitor.topTraffic.isEmpty {
            addDisabledItem("  \(L10n.noTraffic)", font: NSFont.systemFont(ofSize: 11))
        }

        for proc in trafficMonitor.topTraffic {
            let inStr = TrafficMonitor.formatBytes(proc.bytesIn)
            let outStr = TrafficMonitor.formatBytes(proc.bytesOut)
            let title = "  \(proc.name)"
            let detail = "    ↓\(inStr)  ↑\(outStr)"

            let item = NSMenuItem(title: title, action: #selector(noop), keyEquivalent: "")
            item.target = self

            let full = NSMutableAttributedString()
            full.append(NSAttributedString(string: title + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            ]))
            full.append(NSAttributedString(string: detail, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            item.attributedTitle = full
            menu.addItem(item)
        }

        let resetItem = NSMenuItem(title: "  \(L10n.resetTraffic)", action: #selector(resetTraffic), keyEquivalent: "r")
        resetItem.target = self
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemBlue,
        ]
        resetItem.attributedTitle = NSAttributedString(string: "  \(L10n.resetTraffic)", attributes: resetAttrs)
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // --- Memory ---
        let mem = memMonitor.info
        let memUsed = MemoryMonitor.formatBytes(mem.used)
        let memTotal = MemoryMonitor.formatBytes(mem.total)
        let memPct = String(format: "%.0f%%", mem.usagePercent)
        addHeader("\(L10n.memory): \(memUsed) / \(memTotal) (\(memPct))", font: headerFont)

        let memBarWidth = 30
        let memFilled = Int(mem.usagePercent / 100.0 * Double(memBarWidth))
        let memBar = String(repeating: "▓", count: min(memFilled, memBarWidth)) + String(repeating: "░", count: max(memBarWidth - memFilled, 0))
        addDisabledItem("  \(memBar)", font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))

        let detailFont = NSFont.systemFont(ofSize: 10)
        let detailColor = NSColor.secondaryLabelColor
        let appMem = MemoryMonitor.formatBytes(mem.appMemory)
        let wiredMem = MemoryMonitor.formatBytes(mem.wired)
        let compMem = MemoryMonitor.formatBytes(mem.compressed)
        let detailStr = "  \(L10n.app): \(appMem)  \(L10n.wired): \(wiredMem)  \(L10n.compressed): \(compMem)"
        let detailItem = NSMenuItem(title: detailStr, action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        detailItem.attributedTitle = NSAttributedString(string: detailStr, attributes: [
            .font: detailFont, .foregroundColor: detailColor,
        ])
        menu.addItem(detailItem)

        // Top memory processes
        for proc in memMonitor.topProcesses {
            let memStr = MemoryMonitor.formatBytes(proc.mem)
            let title = "  \(memStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(proc.name)"

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: bodyFont])

            let sub = NSMenu()
            let killItem = NSMenuItem(title: "\(L10n.kill) \(proc.name) (PID \(proc.pid))", action: #selector(killProcess(_:)), keyEquivalent: "")
            killItem.target = self
            killItem.tag = proc.pid
            sub.addItem(killItem)
            item.submenu = sub

            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // --- CPU ---
        let cpuStr = String(format: "%.1f%%", cpuMonitor.cpuUsage)
        addHeader("\(L10n.cpu): \(cpuStr)", font: headerFont)

        let barWidth = 30
        let filled = Int(cpuMonitor.cpuUsage / 100.0 * Double(barWidth))
        let bar = String(repeating: "▓", count: min(filled, barWidth)) + String(repeating: "░", count: max(barWidth - filled, 0))
        addDisabledItem("  \(bar)", font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))

        for proc in cpuMonitor.topProcesses {
            let cpuFmt = String(format: "%5.1f%%", proc.cpu)
            let title = "  \(cpuFmt)  \(proc.name)"

            let isAbnormal = cpuMonitor.sustainedPids.contains(proc.pid)
            let attrs: [NSAttributedString.Key: Any] = isAbnormal
                ? [.font: bodyFont, .foregroundColor: NSColor.systemRed]
                : [.font: bodyFont]

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: attrs)

            let sub = NSMenu()
            let killItem = NSMenuItem(title: "\(L10n.kill) \(proc.name) (PID \(proc.pid))", action: #selector(killProcess(_:)), keyEquivalent: "")
            killItem.target = self
            killItem.tag = proc.pid
            sub.addItem(killItem)
            item.submenu = sub

            menu.addItem(item)
        }

        // --- Abnormal processes (CPUGuard) ---
        if !cpuMonitor.abnormalProcesses.isEmpty {
            menu.addItem(NSMenuItem.separator())
            addHeader("⚠ \(L10n.abnormal) (\(Int(cpuMonitor.cpuThreshold))%+)", font: headerFont)

            for proc in cpuMonitor.abnormalProcesses {
                let cpuFmt = String(format: "%5.1f%%", proc.cpu)
                let title = "  \(cpuFmt)  \(proc.name)"

                let item = NSMenuItem(title: title, action: #selector(killProcess(_:)), keyEquivalent: "")
                item.target = self
                item.tag = proc.pid

                let redAttrs: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: NSColor.systemRed,
                ]
                item.attributedTitle = NSAttributedString(string: title, attributes: redAttrs)
                menu.addItem(item)
            }
        }

        // --- Recent Alerts ---
        if !cpuMonitor.recentAlerts.isEmpty {
            menu.addItem(NSMenuItem.separator())
            addHeader(L10n.recentAlerts, font: headerFont)

            for alert in cpuMonitor.recentAlerts.prefix(5) {
                let title = "  [\(alert.time)] \(alert.message)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                let alertAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                item.attributedTitle = NSAttributedString(string: title, attributes: alertAttrs)
                menu.addItem(item)
            }
        }

        // --- Watched processes ---
        menu.addItem(NSMenuItem.separator())
        for name in cpuMonitor.watchedProcesses {
            let procs = cpuMonitor.readTopProcesses(count: 500)
            let proc = procs.first { $0.name == name }
            let alive = proc != nil
            let status = alive ? "✓ \(name) \(L10n.running)" : "✗ \(name) \(L10n.notRunning)"
            let color: NSColor = alive ? .systemGreen : .systemRed

            if alive, let proc = proc {
                let item = NSMenuItem(title: "  \(status)", action: nil, keyEquivalent: "")
                item.attributedTitle = NSAttributedString(string: "  \(status)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                ])
                let sub = NSMenu()
                let restartLabel = L10n.isChinese ? "重启 \(name)" : "Restart \(name)"
                let killItem = NSMenuItem(title: restartLabel, action: #selector(killProcess(_:)), keyEquivalent: "")
                killItem.target = self
                killItem.tag = proc.pid
                sub.addItem(killItem)
                item.submenu = sub
                menu.addItem(item)
            } else {
                let item = NSMenuItem(title: "  \(status)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(string: "  \(status)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                ])
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addHeader(_ title: String, font: NSFont) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
    }

    private func addDisabledItem(_ title: String, font: NSFont) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
    }

    @objc func noop() {}

    @objc func resetTraffic() {
        trafficMonitor.reset()
        rebuildMenu()
    }

    // MARK: - Chart (see ChartView class)

    @objc func killProcess(_ sender: NSMenuItem) {
        let pid = sender.tag
        let result = kill(Int32(pid), SIGTERM)
        if result != 0 {
            let script = "do shell script \"kill \(pid)\" with administrator privileges"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
        cpuMonitor.update()
        rebuildMenu()
    }

    private static let vpnConfigKey = "vpnConfigPath"
    private static let vpnAuthKey = "vpnAuthPath"

    private var vpnConfigPath: String? {
        UserDefaults.standard.string(forKey: Self.vpnConfigKey)
    }

    private var vpnAuthPath: String {
        UserDefaults.standard.string(forKey: Self.vpnAuthKey)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".openvpn-auth").path
    }

    private func promptForVPNConfig() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Select OpenVPN config (.ovpn)"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: Self.vpnConfigKey)
        return url.path
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @objc func toggleVPN() {
        if vpnMonitor.status.connected {
            let script = "do shell script \"killall openvpn\" with administrator privileges"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        } else {
            guard let configPath = vpnConfigPath ?? promptForVPNConfig() else { return }
            let cfg = shellQuote(configPath)
            let auth = shellQuote(vpnAuthPath)
            let cmd = "/opt/homebrew/sbin/openvpn --daemon --log /tmp/openvpn.log --config \(cfg) --auth-user-pass \(auth)"
            let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.vpnMonitor.update()
            self?.rebuildMenu()
        }
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

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    deinit {
        guardTimer?.invalidate()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
    }
}

@main
struct NetSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
