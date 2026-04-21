import AppKit

final class CPUSection: MenuSection {
    private let cpuMonitor: CPUMonitor
    private let actions: MenuActions
    private weak var headerItem: NSMenuItem?
    private weak var barItem: NSMenuItem?
    private var procItems: [NSMenuItem] = []

    init(cpuMonitor: CPUMonitor, actions: MenuActions) {
        self.cpuMonitor = cpuMonitor
        self.actions = actions
    }

    var structureSignature: String { "\(cpuMonitor.topProcesses.count)" }

    func addItems(to menu: NSMenu) -> Bool {
        let h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        headerItem = h

        let b = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        b.isEnabled = false
        menu.addItem(b)
        barItem = b

        procItems = []
        for _ in cpuMonitor.topProcesses {
            let item = NSMenuItem()
            let sub = NSMenu()
            let killItem = NSMenuItem(title: "", action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            killItem.target = actions
            sub.addItem(killItem)
            item.submenu = sub
            menu.addItem(item)
            procItems.append(item)
        }

        apply()
        return true
    }

    func refresh() { apply() }

    private func apply() {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let barFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let cpuStr = String(format: "%.1f%%", cpuMonitor.cpuUsage)
        headerItem?.attributedTitle = NSAttributedString(
            string: "\(L10n.cpu): \(cpuStr)", attributes: [.font: headerFont])

        let barWidth = 30
        let filled = Int(cpuMonitor.cpuUsage / 100.0 * Double(barWidth))
        let bar = String(repeating: "▓", count: min(filled, barWidth)) +
                  String(repeating: "░", count: max(barWidth - filled, 0))
        barItem?.attributedTitle = NSAttributedString(
            string: "  \(bar)", attributes: [.font: barFont])

        let procs = cpuMonitor.topProcesses
        for (i, proc) in procs.enumerated() where i < procItems.count {
            let cpuFmt = String(format: "%5.1f%%", proc.cpu)
            let title = "  \(cpuFmt)  \(proc.name)"
            let isAbnormal = cpuMonitor.sustainedPids.contains(proc.pid)
            let attrs: [NSAttributedString.Key: Any] = isAbnormal
                ? [.font: bodyFont, .foregroundColor: NSColor.systemRed]
                : [.font: bodyFont]
            procItems[i].attributedTitle = NSAttributedString(string: title, attributes: attrs)
            if let killItem = procItems[i].submenu?.items.first {
                killItem.title = "\(L10n.kill) \(proc.name) (PID \(proc.pid))"
                killItem.tag = proc.pid
            }
        }
    }
}
