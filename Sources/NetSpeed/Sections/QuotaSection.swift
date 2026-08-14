import AppKit

/// 订阅配额区块：展示外部记账工具（clashhub 等）导出的各订阅余量与今日用量。
/// 条件区块——状态文件缺失/陈旧时整段隐藏。
final class QuotaSection: MenuSection {
    private let monitor: QuotaMonitor

    private struct Row {
        let name: String
        let item: NSMenuItem
    }
    private var rows: [Row] = []

    init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    var structureSignature: String {
        guard let s = monitor.status else { return "Q0" }
        return "Q[" + s.subscriptions.map(\.name).joined(separator: ",") + "]"
    }

    func addItems(to menu: NSMenu) -> Bool {
        guard let status = monitor.status, !status.subscriptions.isEmpty else {
            rows = []
            return false
        }

        let header = NSMenuItem(title: L10n.quotaTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: L10n.quotaTitle, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ])
        menu.addItem(header)

        rows = status.subscriptions.map { sub in
            let item = NSMenuItem()
            item.isEnabled = false
            menu.addItem(item)
            return Row(name: sub.name, item: item)
        }
        applyRows()
        return true
    }

    func refresh() {
        applyRows()
    }

    private func applyRows() {
        guard let status = monitor.status else { return }
        let byName = Dictionary(uniqueKeysWithValues: status.subscriptions.map { ($0.name, $0) })
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let nameWidth = status.subscriptions.map { $0.name.count }.max() ?? 8

        for row in rows {
            guard let sub = byName[row.name] else { continue }
            let name = row.name.padding(toLength: max(nameWidth, row.name.count), withPad: " ", startingAt: 0)
            let today = "\(L10n.quotaToday) \(QuotaMonitor.formatGB(sub.todayBytes))"

            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: "  \(name)  ", attributes: [
                .font: font, .foregroundColor: NSColor.labelColor,
            ]))

            if let pct = sub.remainingPct, let used = sub.usedBytes, let total = sub.totalBytes {
                let color: NSColor = pct < 15 ? .systemRed : (pct < 30 ? .systemOrange : .systemGreen)
                line.append(NSAttributedString(
                    string: String(format: "%5.1f%% \(L10n.quotaRemaining)", pct),
                    attributes: [.font: font, .foregroundColor: color]
                ))
                var detail = "  \(QuotaMonitor.formatGB(used))/\(QuotaMonitor.formatGB(total))"
                if sub.resetsMonthly == true { detail += " \(L10n.quotaMonthly)" }
                line.append(NSAttributedString(string: detail, attributes: [
                    .font: font, .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
                line.append(NSAttributedString(string: "   \(today)", attributes: [
                    .font: font, .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            } else {
                line.append(NSAttributedString(string: today, attributes: [
                    .font: font, .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }
            row.item.attributedTitle = line
        }
    }
}
