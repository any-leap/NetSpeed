import AppKit

final class VPNSection: MenuSection {
    private let monitor: VPNMonitor
    private let actions: MenuActions

    // 用于 refresh 原地更新（仅在 connected 状态下有值）
    private weak var speedItem: NSMenuItem?
    private weak var totalItem: NSMenuItem?

    init(monitor: VPNMonitor, actions: MenuActions) {
        self.monitor = monitor
        self.actions = actions
    }

    var structureSignature: String {
        let conn = monitor.status.connected ? "VC" : "VD"
        let hasIP = (monitor.status.localIP != nil && monitor.status.interfaceName != nil) ? "1" : "0"
        return "\(conn)\(hasIP)"
    }

    func addItems(to menu: NSMenu) -> Bool {
        let vpn = monitor.status
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        speedItem = nil
        totalItem = nil

        if vpn.connected {
            let vpnHeader = "\(L10n.vpn): \(L10n.vpnConnected)"
            addHeader(vpnHeader, font: headerFont, to: menu)

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

            let sItem = NSMenuItem()
            sItem.isEnabled = false
            menu.addItem(sItem)
            let tItem = NSMenuItem()
            tItem.isEnabled = false
            menu.addItem(tItem)
            speedItem = sItem
            totalItem = tItem
            applyRows()

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
        return true
    }

    func refresh() {
        applyRows()
    }

    private func applyRows() {
        guard let s = speedItem, let t = totalItem else { return }
        let speedFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let v = monitor.status
        let sp = "  ↓ \(VPNMonitor.formatSpeed(monitor.speedIn))  ↑ \(VPNMonitor.formatSpeed(monitor.speedOut))"
        s.attributedTitle = NSAttributedString(string: sp, attributes: [
            .font: speedFont, .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let tt = "  ↓ \(VPNMonitor.formatBytes(v.bytesIn))  ↑ \(VPNMonitor.formatBytes(v.bytesOut))"
        t.attributedTitle = NSAttributedString(string: tt, attributes: [
            .font: speedFont, .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    @discardableResult
    private func addHeader(_ title: String, font: NSFont, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
        return item
    }
}
