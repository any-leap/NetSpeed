import SwiftUI
import AppKit

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var netMonitor: NetMonitor
    private var cpuMonitor: CPUMonitor
    private var trafficMonitor: TrafficMonitor
    private var memMonitor: MemoryMonitor
    private var vpnMonitor: VPNMonitor
    private var latencyMonitorCN: LatencyMonitor
    private var latencyMonitorIntl: LatencyMonitor
    private let notifier = NotificationHelper()
    private var vpnController: VPNController!
    private var actions: MenuActions!
    private weak var latencyChartCN: LatencyChartView?
    private weak var latencyChartIntl: LatencyChartView?
    private var menu: NSMenu
    private var guardTimer: Timer?
    private var menuIsOpen = false
    private weak var chartView: ChartView?
    private weak var trafficRankView: TrafficRankView?
    private var liveRefreshers: [() -> Void] = []
    private var structureSignature: String = ""

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        netMonitor = NetMonitor()
        cpuMonitor = CPUMonitor()
        trafficMonitor = TrafficMonitor()
        memMonitor = MemoryMonitor()
        vpnMonitor = VPNMonitor()
        latencyMonitorCN = LatencyMonitor(name: "mainland", targets: [
            "https://www.baidu.com/favicon.ico",
            "https://www.taobao.com/favicon.ico",
            "https://www.qq.com/favicon.ico",
        ])
        latencyMonitorIntl = LatencyMonitor(name: "overseas", targets: [
            "https://www.gstatic.com/generate_204",
            "https://www.cloudflare.com/cdn-cgi/trace",
            "https://www.github.com/favicon.ico",
        ])
        menu = NSMenu()

        super.init()

        vpnController = VPNController(monitor: vpnMonitor, notifier: notifier)
        vpnController.onToggleCompleted = { [weak self] in
            self?.rebuildMenu()
        }

        actions = MenuActions(
            cpuMonitor: cpuMonitor,
            trafficMonitor: trafficMonitor,
            vpnController: vpnController
        )
        actions.onNeedsRebuild = { [weak self] in self?.rebuildMenu() }

        let latencyRefresh: () -> Void = { [weak self] in
            guard let self = self else { return }
            if self.menuIsOpen { self.refreshLiveViews() }
        }
        latencyMonitorCN.onUpdate = latencyRefresh
        latencyMonitorIntl.onUpdate = latencyRefresh
        latencyMonitorCN.start()
        latencyMonitorIntl.start()

        menu.delegate = self
        statusItem.menu = menu

        vpnMonitor.onDisconnect = { [weak self] in
            self?.notifier.send(
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
                self?.refreshLiveViews()
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

    private func refreshLiveViews() {
        trafficMonitor.update()
        if currentStructureSignature() != structureSignature {
            rebuildMenu()
            return
        }
        chartView?.update(
            downData: netMonitor.downHistory,
            upData: netMonitor.upHistory,
            downLabel: "↓ \(netMonitor.downSpeed)",
            upLabel: "↑ \(netMonitor.upSpeed)"
        )
        trafficRankView?.update(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
        latencyChartCN?.update(
            history: latencyMonitorCN.history,
            current: latencyMonitorCN.current
        )
        latencyChartIntl?.update(
            history: latencyMonitorIntl.history,
            current: latencyMonitorIntl.current
        )
        for r in liveRefreshers { r() }
    }

    private func currentStructureSignature() -> String {
        let vpn = vpnMonitor.status.connected ? "VC" : "VD"
        let vpnHasIP = (vpnMonitor.status.localIP != nil && vpnMonitor.status.interfaceName != nil) ? "1" : "0"
        let memCount = memMonitor.topProcesses.count
        let cpuCount = cpuMonitor.topProcesses.count
        let chartReady = netMonitor.downHistory.count >= 2 ? "1" : "0"
        let watchedAlive = watchedAliveMask()
        // abnormalCount and alertCount intentionally excluded — those sections
        // refresh on next menu open; changing them mid-open would force a rebuild/flash.
        let latencyCNReady = latencyMonitorCN.history.count >= 2 ? "1" : "0"
        let latencyIntlReady = latencyMonitorIntl.history.count >= 2 ? "1" : "0"
        return "\(vpn)\(vpnHasIP)|\(memCount)|\(cpuCount)|\(chartReady)|\(watchedAlive)|\(latencyCNReady)\(latencyIntlReady)"
    }

    private var cachedWatchedProcs: [TopProcess] = []
    private func watchedAliveMask() -> String {
        let procs = cpuMonitor.readTopProcesses(count: 500)
        cachedWatchedProcs = procs
        return cpuMonitor.watchedProcesses.map { name in
            procs.contains(where: { $0.name == name }) ? "1" : "0"
        }.joined()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        liveRefreshers = []
        structureSignature = currentStructureSignature()

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        // --- Latency Charts (Mainland / Overseas) ---
        if latencyMonitorCN.history.count >= 2 {
            let item = NSMenuItem()
            let view = LatencyChartView(
                history: latencyMonitorCN.history,
                maxHistory: latencyMonitorCN.maxHistory,
                current: latencyMonitorCN.current,
                title: L10n.latencyMainland,
                lineColor: .systemCyan
            )
            item.view = view
            item.isEnabled = false
            self.latencyChartCN = view
            menu.addItem(item)
        }

        if latencyMonitorIntl.history.count >= 2 {
            let item = NSMenuItem()
            let view = LatencyChartView(
                history: latencyMonitorIntl.history,
                maxHistory: latencyMonitorIntl.maxHistory,
                current: latencyMonitorIntl.current,
                title: L10n.latencyOverseas,
                lineColor: .systemPurple
            )
            item.view = view
            item.isEnabled = false
            self.latencyChartIntl = view
            menu.addItem(item)
        }

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
            self.chartView = chartView
            menu.addItem(chartItem)
        }

        // --- Watched processes (e.g. bird) ---
        menu.addItem(NSMenuItem.separator())
        let watchedProcs = cpuMonitor.readTopProcesses(count: 500)
        for name in cpuMonitor.watchedProcesses {
            let proc = watchedProcs.first { $0.name == name }
            let alive = proc != nil
            let status = alive ? "✓ \(name) \(L10n.running)" : "✗ \(name) \(L10n.notRunning)"
            let color: NSColor = alive ? .systemGreen : .systemRed
            let item = NSMenuItem(title: "  \(status)", action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: "  \(status)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: color,
            ])
            if let proc = proc {
                let sub = NSMenu()
                let restartLabel = L10n.isChinese ? "重启 \(name)" : "Restart \(name)"
                let killItem = NSMenuItem(title: restartLabel, action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
                killItem.target = actions
                killItem.tag = proc.pid
                sub.addItem(killItem)
                item.submenu = sub
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
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

            let speedFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            let speedItem = NSMenuItem()
            speedItem.isEnabled = false
            menu.addItem(speedItem)
            let totalItem = NSMenuItem()
            totalItem.isEnabled = false
            menu.addItem(totalItem)

            let applyVPNRows: () -> Void = { [weak self, weak speedItem, weak totalItem] in
                guard let self = self, let s = speedItem, let t = totalItem else { return }
                let v = self.vpnMonitor.status
                let sp = "  ↓ \(VPNMonitor.formatSpeed(self.vpnMonitor.speedIn))  ↑ \(VPNMonitor.formatSpeed(self.vpnMonitor.speedOut))"
                s.attributedTitle = NSAttributedString(string: sp, attributes: [
                    .font: speedFont, .foregroundColor: NSColor.secondaryLabelColor,
                ])
                let tt = "  ↓ \(VPNMonitor.formatBytes(v.bytesIn))  ↑ \(VPNMonitor.formatBytes(v.bytesOut))"
                t.attributedTitle = NSAttributedString(string: tt, attributes: [
                    .font: speedFont, .foregroundColor: NSColor.tertiaryLabelColor,
                ])
            }
            applyVPNRows()
            liveRefreshers.append(applyVPNRows)

            let disconnectLabel = L10n.vpnDisconnectAction
            let disconnectItem = NSMenuItem(title: disconnectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
            disconnectItem.target = actions
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
            let connectItem = NSMenuItem(title: connectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
            connectItem.target = actions
            connectItem.attributedTitle = NSAttributedString(string: "  \(connectLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemGreen,
            ])
            menu.addItem(connectItem)
        }

        // --- Traffic by Process ---
        menu.addItem(NSMenuItem.separator())

        let trafficHeader = addHeader("", font: headerFont)
        let applyTrafficHeader: () -> Void = { [weak self, weak trafficHeader] in
            guard let self = self, let h = trafficHeader else { return }
            let title: String
            if let resetTime = self.trafficMonitor.resetTime {
                let elapsed = Int(Date().timeIntervalSince(resetTime))
                title = "\(L10n.trafficByProcess)  (\(L10n.sinceDuration(elapsed)))"
            } else {
                title = L10n.trafficByProcess
            }
            h.attributedTitle = NSAttributedString(string: title, attributes: [.font: headerFont])
        }
        applyTrafficHeader()
        liveRefreshers.append(applyTrafficHeader)

        let rankItem = NSMenuItem()
        let rankView = TrafficRankView(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
        rankItem.view = rankView
        rankItem.isEnabled = false
        menu.addItem(rankItem)
        self.trafficRankView = rankView

        let resetItem = NSMenuItem(title: "  \(L10n.resetTraffic)", action: #selector(MenuActions.resetTraffic), keyEquivalent: "r")
        resetItem.target = actions
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemBlue,
        ]
        resetItem.attributedTitle = NSAttributedString(string: "  \(L10n.resetTraffic)", attributes: resetAttrs)
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // --- Memory ---
        let memHeader = addHeader("", font: headerFont)
        let memBarItem = addDisabledItem("", font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))
        let memDetailFont = NSFont.systemFont(ofSize: 10)
        let memDetailItem = NSMenuItem()
        memDetailItem.isEnabled = false
        menu.addItem(memDetailItem)

        var memProcItems: [NSMenuItem] = []
        for _ in memMonitor.topProcesses {
            let item = NSMenuItem()
            let sub = NSMenu()
            let killItem = NSMenuItem(title: "", action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            killItem.target = actions
            sub.addItem(killItem)
            item.submenu = sub
            menu.addItem(item)
            memProcItems.append(item)
        }

        let applyMem: () -> Void = { [weak self, weak memHeader, weak memBarItem, weak memDetailItem] in
            guard let self = self else { return }
            let mem = self.memMonitor.info
            let memUsed = MemoryMonitor.formatBytes(mem.used)
            let memTotal = MemoryMonitor.formatBytes(mem.total)
            let memPct = String(format: "%.0f%%", mem.usagePercent)
            memHeader?.attributedTitle = NSAttributedString(
                string: "\(L10n.memory): \(memUsed) / \(memTotal) (\(memPct))",
                attributes: [.font: headerFont])

            let memBarWidth = 30
            let memFilled = Int(mem.usagePercent / 100.0 * Double(memBarWidth))
            let memBar = String(repeating: "▓", count: min(memFilled, memBarWidth)) + String(repeating: "░", count: max(memBarWidth - memFilled, 0))
            memBarItem?.attributedTitle = NSAttributedString(
                string: "  \(memBar)",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)])

            let appMem = MemoryMonitor.formatBytes(mem.appMemory)
            let wiredMem = MemoryMonitor.formatBytes(mem.wired)
            let compMem = MemoryMonitor.formatBytes(mem.compressed)
            let detailStr = "  \(L10n.app): \(appMem)  \(L10n.wired): \(wiredMem)  \(L10n.compressed): \(compMem)"
            memDetailItem?.attributedTitle = NSAttributedString(string: detailStr, attributes: [
                .font: memDetailFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])

            let procs = self.memMonitor.topProcesses
            for (i, proc) in procs.enumerated() where i < memProcItems.count {
                let memStr = MemoryMonitor.formatBytes(proc.mem)
                let title = "  \(memStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(proc.name)"
                memProcItems[i].attributedTitle = NSAttributedString(string: title, attributes: [.font: bodyFont])
                if let killItem = memProcItems[i].submenu?.items.first {
                    killItem.title = "\(L10n.kill) \(proc.name) (PID \(proc.pid))"
                    killItem.tag = proc.pid
                }
            }
        }
        applyMem()
        liveRefreshers.append(applyMem)

        menu.addItem(NSMenuItem.separator())

        // --- CPU ---
        let cpuHeader = addHeader("", font: headerFont)
        let cpuBarItem = addDisabledItem("", font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))

        var cpuProcItems: [NSMenuItem] = []
        for _ in cpuMonitor.topProcesses {
            let item = NSMenuItem()
            let sub = NSMenu()
            let killItem = NSMenuItem(title: "", action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            killItem.target = actions
            sub.addItem(killItem)
            item.submenu = sub
            menu.addItem(item)
            cpuProcItems.append(item)
        }

        let applyCPU: () -> Void = { [weak self, weak cpuHeader, weak cpuBarItem] in
            guard let self = self else { return }
            let cpuStr = String(format: "%.1f%%", self.cpuMonitor.cpuUsage)
            cpuHeader?.attributedTitle = NSAttributedString(string: "\(L10n.cpu): \(cpuStr)", attributes: [.font: headerFont])
            let barWidth = 30
            let filled = Int(self.cpuMonitor.cpuUsage / 100.0 * Double(barWidth))
            let bar = String(repeating: "▓", count: min(filled, barWidth)) + String(repeating: "░", count: max(barWidth - filled, 0))
            cpuBarItem?.attributedTitle = NSAttributedString(
                string: "  \(bar)",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)])

            let procs = self.cpuMonitor.topProcesses
            for (i, proc) in procs.enumerated() where i < cpuProcItems.count {
                let cpuFmt = String(format: "%5.1f%%", proc.cpu)
                let title = "  \(cpuFmt)  \(proc.name)"
                let isAbnormal = self.cpuMonitor.sustainedPids.contains(proc.pid)
                let attrs: [NSAttributedString.Key: Any] = isAbnormal
                    ? [.font: bodyFont, .foregroundColor: NSColor.systemRed]
                    : [.font: bodyFont]
                cpuProcItems[i].attributedTitle = NSAttributedString(string: title, attributes: attrs)
                if let killItem = cpuProcItems[i].submenu?.items.first {
                    killItem.title = "\(L10n.kill) \(proc.name) (PID \(proc.pid))"
                    killItem.tag = proc.pid
                }
            }
        }
        applyCPU()
        liveRefreshers.append(applyCPU)

        // --- Abnormal processes (CPUGuard) ---
        if !cpuMonitor.abnormalProcesses.isEmpty {
            menu.addItem(NSMenuItem.separator())
            addHeader("⚠ \(L10n.abnormal) (\(Int(cpuMonitor.cpuThreshold))%+)", font: headerFont)

            for proc in cpuMonitor.abnormalProcesses {
                let cpuFmt = String(format: "%5.1f%%", proc.cpu)
                let title = "  \(cpuFmt)  \(proc.name)"

                let item = NSMenuItem(title: title, action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
                item.target = actions
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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(MenuActions.quit), keyEquivalent: "q")
        quitItem.target = actions
        menu.addItem(quitItem)
    }

    @discardableResult
    private func addHeader(_ title: String, font: NSFont) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
        return item
    }

    @discardableResult
    private func addDisabledItem(_ title: String, font: NSFont) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
        return item
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
