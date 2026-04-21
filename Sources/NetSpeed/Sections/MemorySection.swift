import AppKit

final class MemorySection: MenuSection {
    private let memMonitor: MemoryMonitor
    private let actions: MenuActions
    private weak var headerItem: NSMenuItem?
    private weak var barItem: NSMenuItem?
    private weak var detailItem: NSMenuItem?
    private var procItems: [NSMenuItem] = []

    init(memMonitor: MemoryMonitor, actions: MenuActions) {
        self.memMonitor = memMonitor
        self.actions = actions
    }

    var structureSignature: String { "\(memMonitor.topProcesses.count)" }

    func addItems(to menu: NSMenu) -> Bool {
        let h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        headerItem = h

        let b = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        b.isEnabled = false
        menu.addItem(b)
        barItem = b

        let d = NSMenuItem()
        d.isEnabled = false
        menu.addItem(d)
        detailItem = d

        procItems = []
        for _ in memMonitor.topProcesses {
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
        let memDetailFont = NSFont.systemFont(ofSize: 10)

        let mem = memMonitor.info
        let memUsed = MemoryMonitor.formatBytes(mem.used)
        let memTotal = MemoryMonitor.formatBytes(mem.total)
        let memPct = String(format: "%.0f%%", mem.usagePercent)
        headerItem?.attributedTitle = NSAttributedString(
            string: "\(L10n.memory): \(memUsed) / \(memTotal) (\(memPct))",
            attributes: [.font: headerFont])

        let memBarWidth = 30
        let memFilled = Int(mem.usagePercent / 100.0 * Double(memBarWidth))
        let memBar = String(repeating: "▓", count: min(memFilled, memBarWidth)) +
                     String(repeating: "░", count: max(memBarWidth - memFilled, 0))
        barItem?.attributedTitle = NSAttributedString(
            string: "  \(memBar)",
            attributes: [.font: barFont])

        let appMem = MemoryMonitor.formatBytes(mem.appMemory)
        let wiredMem = MemoryMonitor.formatBytes(mem.wired)
        let compMem = MemoryMonitor.formatBytes(mem.compressed)
        let detailStr = "  \(L10n.app): \(appMem)  \(L10n.wired): \(wiredMem)  \(L10n.compressed): \(compMem)"
        detailItem?.attributedTitle = NSAttributedString(string: detailStr, attributes: [
            .font: memDetailFont, .foregroundColor: NSColor.secondaryLabelColor,
        ])

        let procs = memMonitor.topProcesses
        for (i, proc) in procs.enumerated() where i < procItems.count {
            let memStr = MemoryMonitor.formatBytes(proc.mem)
            let title = "  \(memStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(proc.name)"
            procItems[i].attributedTitle = NSAttributedString(string: title, attributes: [.font: bodyFont])
            if let killItem = procItems[i].submenu?.items.first {
                killItem.title = "\(L10n.kill) \(proc.name) (PID \(proc.pid))"
                killItem.tag = proc.pid
            }
        }
    }
}
