import AppKit

final class TrafficRankView: NSView {
    private var liveTop: [ProcessTraffic]
    private var cumulativeTop: [ProcessTraffic]

    func update(liveTop: [ProcessTraffic], cumulativeTop: [ProcessTraffic]) {
        self.liveTop = liveTop
        self.cumulativeTop = cumulativeTop
        self.needsDisplay = true
    }

    private let rowHeight: CGFloat = 28
    private let headerHeight: CGFloat = 16
    private let hPad: CGFloat = 12
    private let colGap: CGFloat = 12

    init(liveTop: [ProcessTraffic], cumulativeTop: [ProcessTraffic]) {
        self.liveTop = liveTop
        self.cumulativeTop = cumulativeTop
        let rows = max(max(liveTop.count, cumulativeTop.count), 1)
        let h = headerHeight + CGFloat(rows) * rowHeight + 4
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: h))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let colW = (w - hPad * 2 - colGap) / 2
        let leftX = hPad
        let rightX = hPad + colW + colGap

        let headerFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        NSAttributedString(string: L10n.trafficLive, attributes: headerAttrs)
            .draw(at: NSPoint(x: leftX, y: 0))
        NSAttributedString(string: L10n.trafficCumulative, attributes: headerAttrs)
            .draw(at: NSPoint(x: rightX, y: 0))

        // Separator line between columns
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        let sep = NSBezierPath()
        let sepX = hPad + colW + colGap / 2
        sep.move(to: NSPoint(x: sepX, y: headerHeight - 2))
        sep.line(to: NSPoint(x: sepX, y: bounds.height - 2))
        sep.lineWidth = 0.5
        sep.stroke()

        drawColumn(liveTop, x: leftX, width: colW, mode: .live)
        drawColumn(cumulativeTop, x: rightX, width: colW, mode: .cumulative)
    }

    private enum ColumnMode { case live, cumulative }

    private func drawColumn(_ items: [ProcessTraffic], x: CGFloat, width: CGFloat, mode: ColumnMode) {
        let nameFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        if items.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            NSAttributedString(string: L10n.noTraffic, attributes: attrs)
                .draw(at: NSPoint(x: x, y: headerHeight + 4))
            return
        }

        for (i, proc) in items.enumerated() {
            let rowY = headerHeight + CGFloat(i) * rowHeight

            let nameStr = NSAttributedString(string: proc.name, attributes: [
                .font: nameFont,
                .foregroundColor: NSColor.labelColor,
            ])
            let nameRect = NSRect(x: x, y: rowY, width: width, height: 14)
            nameStr.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            let valueStr: String
            let valueColor: NSColor
            switch mode {
            case .live:
                let inStr = TrafficMonitor.formatSpeed(proc.speedIn)
                let outStr = TrafficMonitor.formatSpeed(proc.speedOut)
                valueStr = "↓\(inStr)  ↑\(outStr)"
                valueColor = proc.speedTotal > 0 ? .systemGreen : .tertiaryLabelColor
            case .cumulative:
                let inStr = TrafficMonitor.formatBytes(proc.bytesIn)
                let outStr = TrafficMonitor.formatBytes(proc.bytesOut)
                valueStr = "↓\(inStr)  ↑\(outStr)"
                valueColor = .secondaryLabelColor
            }
            NSAttributedString(string: valueStr, attributes: [
                .font: valueFont,
                .foregroundColor: valueColor,
            ]).draw(at: NSPoint(x: x, y: rowY + 14))
        }
    }
}
