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
    private var prefsObserver: NSObjectProtocol?
    private var menuIsOpen = false
    private var networkChartSection: NetworkChartSection!
    private var watchedSection: WatchedProcessesSection!
    private var vpnSection: VPNSection!
    private var trafficRankSection: TrafficRankSection!
    private var memorySection: MemorySection!
    private var cpuSection: CPUSection!
    private var abnormalSection: AbnormalProcessesSection!
    private var alertsSection: RecentAlertsSection!
    private let caffeineMonitor = CaffeineMonitor()
    private var quotaMonitor = QuotaMonitor()
    private var quotaSection: QuotaSection!
    private var menuBuilder: MenuBuilder!
    private var savedSignature: String = ""

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        netMonitor = NetMonitor()
        cpuMonitor = CPUMonitor()
        trafficMonitor = TrafficMonitor()
        memMonitor = MemoryMonitor()
        vpnMonitor = VPNMonitor()
        let prefs = Preferences.shared
        latencyMonitorCN = LatencyMonitor(name: "mainland", targets: prefs.latencyTargetsCN)
        latencyMonitorIntl = LatencyMonitor(name: "overseas", targets: prefs.latencyTargetsIntl)
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
        vpnSection = VPNSection(monitor: vpnMonitor, vpnController: vpnController, actions: actions)
        trafficRankSection = TrafficRankSection(trafficMonitor: trafficMonitor, actions: actions)
        memorySection = MemorySection(memMonitor: memMonitor, actions: actions)
        cpuSection = CPUSection(cpuMonitor: cpuMonitor, actions: actions)
        abnormalSection = AbnormalProcessesSection(cpuMonitor: cpuMonitor, actions: actions)
        alertsSection = RecentAlertsSection(cpuMonitor: cpuMonitor)
        quotaSection = QuotaSection(monitor: quotaMonitor)

        menuBuilder = MenuBuilder(menu: menu, sections: [
            latencyChartCNSection,
            latencyChartIntlSection,
            networkChartSection,
            watchedSection,
            vpnSection,
            quotaSection,
            CaffeineSection(monitor: caffeineMonitor),
            trafficRankSection,
            memorySection,
            cpuSection,
            abnormalSection,
            alertsSection,
            quitSection,
        ])

        let latencyRefresh: () -> Void = { [weak self] in
            guard let self = self else { return }
            if self.menuIsOpen { self.refreshLiveViews() }
        }
        latencyMonitorCN.onUpdate = latencyRefresh
        latencyMonitorIntl.onUpdate = latencyRefresh
        latencyMonitorCN.start()
        latencyMonitorIntl.start()

        quotaMonitor.onUpdate = { [weak self] in
            guard let self = self else { return }
            if self.menuIsOpen { self.refreshLiveViews() }
        }
        quotaMonitor.start()

        // 设置窗口改了测速地址 → 下一轮起用新地址。CPU 相关设置由 CPUMonitor 每次直接读取。
        prefsObserver = NotificationCenter.default.addObserver(
            forName: Preferences.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.latencyMonitorCN.setTargets(prefs.latencyTargetsCN)
            self.latencyMonitorIntl.setTargets(prefs.latencyTargetsIntl)
        }

        menu.delegate = self
        statusItem.menu = menu

        vpnMonitor.onDisconnect = { [weak self] in
            self?.notifier.send(
                title: L10n.tunnelDisconnectedTitle,
                message: L10n.tunnelDisconnectedMessage
            )
        }

        netMonitor.onChange = { [weak self] in
            guard let self = self else { return }
            self.vpnMonitor.update()
            self.caffeineMonitor.update()
            self.updateLabel()
            // CPU/内存排行要遍历全部进程，只有菜单里看得到，菜单关着就不扫（CPU 异常告警有自己的 10 秒扫描）。
            if self.menuIsOpen {
                self.cpuMonitor.update()
                self.memMonitor.update()
                self.refreshLiveViews()
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
        caffeineMonitor.update()
        cpuMonitor.update()
        memMonitor.update()
        latencyMonitorCN.setFastPolling(true)
        latencyMonitorIntl.setFastPolling(true)
        trafficMonitor.update()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        latencyMonitorCN.setFastPolling(false)
        latencyMonitorIntl.setFastPolling(false)
    }

    private func refreshLiveViews() {
        trafficMonitor.update()
        if menuBuilder.structureSignature != savedSignature {
            rebuildMenu()
            return
        }
        menuBuilder.refresh()
    }

    private func rebuildMenu() {
        savedSignature = menuBuilder.structureSignature
        menuBuilder.rebuild()
    }

    deinit {
        guardTimer?.invalidate()
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        statusBar = StatusBarController()
    }

    /// 菜单栏应用不显示主菜单，但设置窗口里的文本框要靠它才能响应
    /// ⌘C/⌘V/⌘X/⌘A/⌘Z 和 ⌘W。
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }
}

// 纯 AppKit 入口，不用 SwiftUI App：SwiftUI 的 App 至少要一个 Scene，之前塞的空
// `Settings { EmptyView() }` 会被系统窗口恢复在开机/登录时弹出一个空白
// "NetSpeed Settings" 窗口。设置窗口改由菜单「设置…」按需创建，见 SettingsWindow.swift。
@main
enum NetSpeedMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
