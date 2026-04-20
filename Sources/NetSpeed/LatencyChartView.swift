import AppKit

final class LatencyChartView: NSView {
    private var history: [Double?]
    private var currentValue: Double?
    private let maxHistory: Int
    private let title: String
    private let lineColor: NSColor

    init(history: [Double?], maxHistory: Int, current: Double?,
         title: String, lineColor: NSColor) {
        self.history = history
        self.currentValue = current
        self.maxHistory = maxHistory
        self.title = title
        self.lineColor = lineColor
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 90))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(history: [Double?], current: Double?) {
        self.history = history
        self.currentValue = current
        self.needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        let left: CGFloat = 8
        let right: CGFloat = 8
        let top: CGFloat = 20
        let bottom: CGFloat = 6
        let chartW = w - left - right
        let chartH = h - top - bottom

        let nonNil = history.compactMap { $0 }
        let maxVal = max(nonNil.max() ?? 100.0, 100.0)

        // 标题（左上）
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ]).draw(at: NSPoint(x: left, y: 4))

        // 当前值（右上）
        let valueStr: String
        if let c = currentValue {
            valueStr = String(format: "%.0f ms", c)
        } else {
            valueStr = "—"
        }
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let valueAttr = NSAttributedString(string: valueStr, attributes: valueAttrs)
        valueAttr.draw(at: NSPoint(x: w - right - valueAttr.size().width, y: 5))

        // 图区背景
        let chartRect = NSRect(x: left, y: top, width: chartW, height: chartH)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 3, yRadius: 3).fill()

        // 虚线网格
        let dashPattern: [CGFloat] = [2, 3]
        NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
        for i in 1...3 {
            let y = top + chartH * CGFloat(i) / 4.0
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: left, y: y))
            grid.line(to: NSPoint(x: left + chartW, y: y))
            grid.lineWidth = 0.5
            grid.setLineDash(dashPattern, count: 2, phase: 0)
            grid.stroke()
        }

        // 把 history 按 nil 切成若干连续非 nil 段
        let stepX = chartW / CGFloat(max(maxHistory - 1, 1))
        let startX = left + chartW - CGFloat(history.count - 1) * stepX

        var segments: [[NSPoint]] = []
        var currentSeg: [NSPoint] = []
        for (i, v) in history.enumerated() {
            let x = startX + CGFloat(i) * stepX
            if let val = v {
                let y = top + chartH - CGFloat(val / maxVal) * chartH
                currentSeg.append(NSPoint(x: x, y: max(top, min(top + chartH, y))))
            } else if !currentSeg.isEmpty {
                segments.append(currentSeg)
                currentSeg = []
            }
        }
        if !currentSeg.isEmpty { segments.append(currentSeg) }

        // 每段独立绘制平滑曲线
        lineColor.withAlphaComponent(0.9).setStroke()
        for seg in segments {
            guard let first = seg.first else { continue }
            let path = NSBezierPath()
            path.move(to: first)
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let midX = (prev.x + curr.x) / 2
                path.curve(to: curr,
                           controlPoint1: NSPoint(x: midX, y: prev.y),
                           controlPoint2: NSPoint(x: midX, y: curr.y))
            }
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        // Y 轴刻度（max + 0）
        let scaleFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let scaleAttrs: [NSAttributedString.Key: Any] = [
            .font: scaleFont, .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        NSAttributedString(string: String(format: "%.0f ms", maxVal), attributes: scaleAttrs)
            .draw(at: NSPoint(x: left + 2, y: top + 1))
        NSAttributedString(string: "0", attributes: scaleAttrs)
            .draw(at: NSPoint(x: left + 2, y: top + chartH - 12))
    }
}
