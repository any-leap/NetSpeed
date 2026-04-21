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
    private var quitSection: QuitSection!
    private var latencyChartCNSection: LatencyChartSection!
    private var latencyChartIntlSection: LatencyChartSection!
    private var menu: NSMenu
    private var guardTimer: Timer?
    private var menuIsOpen = false
    private var networkChartSection: NetworkChartSection!
    private var watchedSection: WatchedProcessesSection!
    private var vpnSection: VPNSection!
    private var trafficRankSection: TrafficRankSection!
    private var memorySection: MemorySection!
    private var cpuSection: CPUSection!
    private var abnormalSection: AbnormalProcessesSection!
    private var alertsSection: RecentAlertsSection!
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

        quitSection = QuitSection(actions: actions)

        latencyChartCNSection = LatencyChartSection(
            monitor: latencyMonitorCN,
            title: L10n.latencyMainland,
            lineColor: .systemCyan
        )
        latencyChartIntlSection = LatencyChartSection(
            monitor: latencyMonitorIntl,
            title: L10n.latencyOverseas,
            lineColor: .systemPurple
        )
        networkChartSection = NetworkChartSection(monitor: netMonitor)
        watchedSection = WatchedProcessesSection(cpuMonitor: cpuMonitor, actions: actions)
        vpnSection = VPNSection(monitor: vpnMonitor, actions: actions)
        trafficRankSection = TrafficRankSection(trafficMonitor: trafficMonitor, actions: actions)
        memorySection = MemorySection(memMonitor: memMonitor, actions: actions)
        cpuSection = CPUSection(cpuMonitor: cpuMonitor, actions: actions)
        abnormalSection = AbnormalProcessesSection(cpuMonitor: cpuMonitor, actions: actions)
        alertsSection = RecentAlertsSection(cpuMonitor: cpuMonitor)

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
        networkChartSection.refresh()
        trafficRankSection.refresh()
        memorySection.refresh()
        cpuSection.refresh()
        latencyChartCNSection.refresh()
        latencyChartIntlSection.refresh()
        vpnSection.refresh()
        for r in liveRefreshers { r() }
    }

    private func currentStructureSignature() -> String {
        let memCount = memMonitor.topProcesses.count
        let cpuCount = cpuMonitor.topProcesses.count
        let chartReady = netMonitor.downHistory.count >= 2 ? "1" : "0"
        let watchedAlive = watchedSection.structureSignature
        // abnormalCount and alertCount intentionally excluded — those sections
        // refresh on next menu open; changing them mid-open would force a rebuild/flash.
        let latencyCNReady = latencyMonitorCN.history.count >= 2 ? "1" : "0"
        let latencyIntlReady = latencyMonitorIntl.history.count >= 2 ? "1" : "0"
        return "\(vpnSection.structureSignature)|\(memCount)|\(cpuCount)|\(chartReady)|\(watchedAlive)|\(latencyCNReady)\(latencyIntlReady)"
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        liveRefreshers = []
        structureSignature = currentStructureSignature()

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        // --- Latency Charts (Mainland / Overseas) ---
        _ = latencyChartCNSection.addItems(to: menu)
        _ = latencyChartIntlSection.addItems(to: menu)

        // --- Network Chart ---
        _ = networkChartSection.addItems(to: menu)

        // --- Watched processes ---
        menu.addItem(NSMenuItem.separator())
        _ = watchedSection.addItems(to: menu)

        // --- VPN Status ---
        menu.addItem(NSMenuItem.separator())
        _ = vpnSection.addItems(to: menu)

        // --- Traffic by Process ---
        menu.addItem(NSMenuItem.separator())
        _ = trafficRankSection.addItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        // --- Memory ---
        _ = memorySection.addItems(to: menu)

        menu.addItem(NSMenuItem.separator())

        // --- CPU ---
        _ = cpuSection.addItems(to: menu)

        // --- Abnormal processes (CPUGuard) ---
        if !cpuMonitor.abnormalProcesses.isEmpty {
            menu.addItem(NSMenuItem.separator())
            _ = abnormalSection.addItems(to: menu)
        }

        // --- Recent Alerts ---
        if !cpuMonitor.recentAlerts.isEmpty {
            menu.addItem(NSMenuItem.separator())
            _ = alertsSection.addItems(to: menu)
        }

        menu.addItem(NSMenuItem.separator())
        _ = quitSection.addItems(to: menu)
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
