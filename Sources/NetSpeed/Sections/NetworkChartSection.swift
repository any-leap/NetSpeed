import AppKit

final class NetworkChartSection: MenuSection {
    private let monitor: NetMonitor
    private weak var chartView: ChartView?

    init(monitor: NetMonitor) {
        self.monitor = monitor
    }

    var structureSignature: String {
        monitor.downHistory.count >= 2 ? "1" : "0"
    }

    var needsLeadingSeparator: Bool { false }  // 与 latency 图合并展示

    func addItems(to menu: NSMenu) -> Bool {
        guard monitor.downHistory.count >= 2 else { return false }
        let chartItem = NSMenuItem()
        let view = ChartView(
            downData: monitor.downHistory,
            upData: monitor.upHistory,
            maxHistory: monitor.maxHistory,
            downLabel: "↓ \(monitor.downSpeed)",
            upLabel: "↑ \(monitor.upSpeed)",
            title: L10n.network,
            formatMax: { [weak monitor] v in monitor?.formatSpeed(v) ?? "" }
        )
        chartItem.view = view
        chartItem.isEnabled = false
        chartView = view
        menu.addItem(chartItem)
        return true
    }

    func refresh() {
        chartView?.update(
            downData: monitor.downHistory,
            upData: monitor.upHistory,
            downLabel: "↓ \(monitor.downSpeed)",
            upLabel: "↑ \(monitor.upSpeed)"
        )
    }
}
