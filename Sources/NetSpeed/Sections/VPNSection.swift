import AppKit

final class VPNSection: MenuSection {
    private let monitor: VPNMonitor
    private let vpnController: VPNController
    private let actions: MenuActions

    // 每个 tunnel 一行 speed / 一行 total 的引用，用于 refresh 原地更新。
    private struct TunnelRow {
        let interfaceName: String
        let speedItem: NSMenuItem
        let totalItem: NSMenuItem
    }
    private var rows: [TunnelRow] = []

    init(monitor: VPNMonitor, vpnController: VPNController, actions: MenuActions) {
        self.monitor = monitor
        self.vpnController = vpnController
        self.actions = actions
    }

    var structureSignature: String {
        let conn = monitor.status.connected ? "TC" : "TD"
        let ifaces = monitor.status.tunnels.map(\.interfaceName).joined(separator: ",")
        let cfg = vpnController.isOpenVPNConfigured ? "c" : "u"
        return "\(conn)[\(ifaces)]\(cfg)"
    }

    func addItems(to menu: NSMenu) -> Bool {
        let vpn = monitor.status
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        rows = []

        if vpn.connected {
            let header = "\(L10n.vpn): \(L10n.vpnConnected)"
            addHeader(header, font: headerFont, to: menu)

            for tunnel in vpn.tunnels {
                addTunnelBlock(tunnel: tunnel, to: menu)
            }

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

    // MARK: - helpers

    private func addTunnelBlock(tunnel: TunnelInfo, to menu: NSMenu) {
        if let ip = tunnel.localIP {
            let detailStr = "  \(tunnel.interfaceName)  \(ip)"
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

        rows.append(TunnelRow(
            interfaceName: tunnel.interfaceName,
            speedItem: sItem,
            totalItem: tItem
        ))
    }

    private func applyRows() {
        let speedFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let tunnelsByName = Dictionary(uniqueKeysWithValues: monitor.status.tunnels.map { ($0.interfaceName, $0) })

        for row in rows {
            guard let tunnel = tunnelsByName[row.interfaceName] else { continue }

            let sp = "  ↓ \(VPNMonitor.formatSpeed(tunnel.speedIn))  ↑ \(VPNMonitor.formatSpeed(tunnel.speedOut))"
            row.speedItem.attributedTitle = NSAttributedString(string: sp, attributes: [
                .font: speedFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])

            let tt = "  ↓ \(VPNMonitor.formatBytes(tunnel.bytesIn))  ↑ \(VPNMonitor.formatBytes(tunnel.bytesOut))"
            row.totalItem.attributedTitle = NSAttributedString(string: tt, attributes: [
                .font: speedFont, .foregroundColor: NSColor.tertiaryLabelColor,
            ])
        }
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
