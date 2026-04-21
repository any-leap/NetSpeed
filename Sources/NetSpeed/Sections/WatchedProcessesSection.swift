import AppKit

final class WatchedProcessesSection: MenuSection {
    private let cpuMonitor: CPUMonitor
    private let actions: MenuActions

    init(cpuMonitor: CPUMonitor, actions: MenuActions) {
        self.cpuMonitor = cpuMonitor
        self.actions = actions
    }

    var structureSignature: String {
        let procs = cpuMonitor.readTopProcesses(count: 500)
        return cpuMonitor.watchedProcesses.map { name in
            procs.contains(where: { $0.name == name }) ? "1" : "0"
        }.joined()
    }

    func addItems(to menu: NSMenu) -> Bool {
        guard !cpuMonitor.watchedProcesses.isEmpty else { return false }
        let procs = cpuMonitor.readTopProcesses(count: 500)
        for name in cpuMonitor.watchedProcesses {
            let proc = procs.first { $0.name == name }
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
        return true
    }

    func refresh() {
        // 存活状态变化 → structureSignature 变化 → rebuild，不走 refresh
    }
}
