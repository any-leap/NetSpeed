import AppKit

final class LatencyChartSection: MenuSection {
    private let monitor: LatencyMonitor
    private let title: String
    private let lineColor: NSColor
    private weak var chartView: LatencyChartView?

    init(monitor: LatencyMonitor, title: String, lineColor: NSColor) {
        self.monitor = monitor
        self.title = title
        self.lineColor = lineColor
    }

    var structureSignature: String {
        monitor.history.count >= 2 ? "1" : "0"
    }

    /// 与上一章节（另一个 latency / network 图）合并展示，不需要分隔符
    var needsLeadingSeparator: Bool { false }

    func addItems(to menu: NSMenu) -> Bool {
        guard monitor.history.count >= 2 else { return false }
        let item = NSMenuItem()
        let view = LatencyChartView(
            history: monitor.history,
            maxHistory: monitor.maxHistory,
            current: monitor.current,
            title: title,
            lineColor: lineColor
        )
        item.view = view
        item.isEnabled = false
        chartView = view
        menu.addItem(item)
        return true
    }

    func refresh() {
        chartView?.update(history: monitor.history, current: monitor.current)
    }
}
