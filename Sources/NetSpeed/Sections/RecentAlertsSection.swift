import AppKit

final class RecentAlertsSection: MenuSection {
    private let cpuMonitor: CPUMonitor

    init(cpuMonitor: CPUMonitor) {
        self.cpuMonitor = cpuMonitor
    }

    var structureSignature: String { "" }   // 不进 signature

    func addItems(to menu: NSMenu) -> Bool {
        let alerts = cpuMonitor.recentAlerts
        guard !alerts.isEmpty else { return false }

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let header = NSMenuItem(title: L10n.recentAlerts, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: L10n.recentAlerts, attributes: [.font: headerFont])
        menu.addItem(header)

        for alert in alerts.prefix(5) {
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
        return true
    }

    func refresh() {
        // 同 Abnormal：下次 rebuild 时同步
    }
}
