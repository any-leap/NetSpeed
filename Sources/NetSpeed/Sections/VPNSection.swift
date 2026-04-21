import AppKit

final class VPNSection: MenuSection {
    private let monitor: VPNMonitor
    private let vpnController: VPNController
    private let actions: MenuActions

    // 用于 refresh 原地更新（仅在 connected 状态下有值）
    private weak var speedItem: NSMenuItem?
    private weak var totalItem: NSMenuItem?

    init(monitor: VPNMonitor, vpnController: VPNController, actions: MenuActions) {
        self.monitor = monitor
        self.vpnController = vpnController
        self.actions = actions
    }

    var structureSignature: String {
        let conn = monitor.status.connected ? "TC" : "TD"
        let hasIP = (monitor.status.localIP != nil && monitor.status.interfaceName != nil) ? "1" : "0"
        let cfg = vpnController.isOpenVPNConfigured ? "c" : "u"
        return "\(conn)\(hasIP)\(cfg)"
    }

    func addItems(to menu: NSMenu) -> Bool {
        let vpn = monitor.status
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        speedItem = nil
        totalItem = nil

        if vpn.connected {
            let header = "\(L10n.vpn): \(L10n.vpnConnected)"
            addHeader(header, font: headerFont, to: menu)

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

            if vpnController.isOpenVPNConfigured {
                let disconnectLabel = L10n.vpnDisconnectAction
                let disconnectItem = NSMenuItem(title: disconnectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
                disconnectItem.target = actions
                disconnectItem.attributedTitle = NSAttributedString(string: "  \(disconnectLabel)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemRed,
                ])
                menu.addItem(disconnectItem)
            }
        } else {
            let header = "\(L10n.vpn): \(L10n.vpnDisconnected)"
            let item = NSMenuItem(title: header, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(string: header, attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.systemRed,
            ])
            menu.addItem(item)

            if vpnController.isOpenVPNConfigured {
                let connectLabel = L10n.vpnConnectAction
                let connectItem = NSMenuItem(title: connectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
                connectItem.target = actions
                connectItem.attributedTitle = NSAttributedString(string: "  \(connectLabel)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemGreen,
                ])
                menu.addItem(connectItem)
            }
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
