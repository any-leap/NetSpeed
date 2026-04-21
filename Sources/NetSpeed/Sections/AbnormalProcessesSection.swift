import AppKit

final class AbnormalProcessesSection: MenuSection {
    private let cpuMonitor: CPUMonitor
    private let actions: MenuActions

    init(cpuMonitor: CPUMonitor, actions: MenuActions) {
        self.cpuMonitor = cpuMonitor
        self.actions = actions
    }

    /// 不纳入 signature（原代码注释：会导致打开菜单时闪烁，所以 mid-open 不感知）
    var structureSignature: String { "" }

    func addItems(to menu: NSMenu) -> Bool {
        let abnormal = cpuMonitor.abnormalProcesses
        guard !abnormal.isEmpty else { return false }

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerText = "⚠ \(L10n.abnormal) (\(Int(cpuMonitor.cpuThreshold))%+)"
        header.attributedTitle = NSAttributedString(string: headerText, attributes: [.font: headerFont])
        menu.addItem(header)

        for proc in abnormal {
            let cpuFmt = String(format: "%5.1f%%", proc.cpu)
            let title = "  \(cpuFmt)  \(proc.name)"
            let item = NSMenuItem(title: title, action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            item.target = actions
            item.tag = proc.pid
            let redAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: NSColor.systemRed,
            ]
            item.attributedTitle = NSAttributedString(string: title, attributes: redAttrs)
            menu.addItem(item)
        }
        return true
    }

    func refresh() {
        // 异常列表变化会等到下次菜单打开 rebuild 时更新
    }
}
