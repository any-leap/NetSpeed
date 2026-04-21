import AppKit

final class TrafficRankSection: MenuSection {
    private let trafficMonitor: TrafficMonitor
    private let actions: MenuActions
    private weak var headerItem: NSMenuItem?
    private weak var rankView: TrafficRankView?

    init(trafficMonitor: TrafficMonitor, actions: MenuActions) {
        self.trafficMonitor = trafficMonitor
        self.actions = actions
    }

    var structureSignature: String { "T" }   // 内容动态，但结构稳定

    func addItems(to menu: NSMenu) -> Bool {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        headerItem = h
        applyHeader()

        let rankItem = NSMenuItem()
        let view = TrafficRankView(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
        rankItem.view = view
        rankItem.isEnabled = false
        menu.addItem(rankItem)
        rankView = view

        let resetItem = NSMenuItem(title: "  \(L10n.resetTraffic)", action: #selector(MenuActions.resetTraffic), keyEquivalent: "r")
        resetItem.target = actions
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemBlue,
        ]
        resetItem.attributedTitle = NSAttributedString(string: "  \(L10n.resetTraffic)", attributes: resetAttrs)
        menu.addItem(resetItem)

        _ = headerFont  // keep constant used; silence potential unused warning
        return true
    }

    func refresh() {
        applyHeader()
        rankView?.update(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
    }

    private func applyHeader() {
        guard let h = headerItem else { return }
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let title: String
        if let resetTime = trafficMonitor.resetTime {
            let elapsed = Int(Date().timeIntervalSince(resetTime))
            title = "\(L10n.trafficByProcess)  (\(L10n.sinceDuration(elapsed)))"
        } else {
            title = L10n.trafficByProcess
        }
        h.attributedTitle = NSAttributedString(string: title, attributes: [.font: headerFont])
    }
}
