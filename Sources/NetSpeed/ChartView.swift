import AppKit

final class ChartView: NSView {
    private var downData: [Double]
    private var upData: [Double]
    private let maxHistory: Int
    private var downLabel: String
    private var upLabel: String
    private let title: String
    private let formatMax: (Double) -> String

    func update(downData: [Double], upData: [Double], downLabel: String, upLabel: String) {
        self.downData = downData
        self.upData = upData
        self.downLabel = downLabel
        self.upLabel = upLabel
        self.needsDisplay = true
    }

    init(downData: [Double], upData: [Double], maxHistory: Int,
         downLabel: String, upLabel: String, title: String,
         formatMax: @escaping (Double) -> String) {
        self.downData = downData
        self.upData = upData
        self.maxHistory = maxHistory
        self.downLabel = downLabel
        self.upLabel = upLabel
        self.title = title
        self.formatMax = formatMax
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 90))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        let left: CGFloat = 8
        let right: CGFloat = 8
        let top: CGFloat = 24
        let bottom: CGFloat = 18
        let chartW = w - left - right
        let chartH = h - top - bottom

        let allValues = downData + upData
        let maxVal = max(allValues.max() ?? 1, 1024)

        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.labelColor]
        NSAttributedString(string: title, attributes: titleAttrs).draw(at: NSPoint(x: left, y: 4))

        let legendFont = NSFont.systemFont(ofSize: 9)
        let downLegend = NSMutableAttributedString()
        downLegend.append(NSAttributedString(string: "● ", attributes: [.font: legendFont, .foregroundColor: NSColor.systemCyan]))
        downLegend.append(NSAttributedString(string: downLabel, attributes: [.font: legendFont, .foregroundColor: NSColor.secondaryLabelColor]))

        let upLegend = NSMutableAttributedString()
        upLegend.append(NSAttributedString(string: "● ", attributes: [.font: legendFont, .foregroundColor: NSColor.systemOrange]))
        upLegend.append(NSAttributedString(string: upLabel, attributes: [.font: legendFont, .foregroundColor: NSColor.secondaryLabelColor]))

        let upLegendWidth = upLegend.size().width
        let downLegendWidth = downLegend.size().width
        upLegend.draw(at: NSPoint(x: w - right - upLegendWidth, y: 5))
        downLegend.draw(at: NSPoint(x: w - right - upLegendWidth - downLegendWidth - 10, y: 5))

        let chartRect = NSRect(x: left, y: top, width: chartW, height: chartH)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 3, yRadius: 3).fill()

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

        func smoothPath(_ data: [Double], startX: CGFloat, stepX: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            var points: [NSPoint] = []
            for (i, val) in data.enumerated() {
                let x = startX + CGFloat(i) * stepX
                let y = top + chartH - CGFloat(val / maxVal) * chartH
                points.append(NSPoint(x: x, y: max(top, min(top + chartH, y))))
            }
            guard let first = points.first else { return path }
            path.move(to: first)
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                let midX = (prev.x + curr.x) / 2
                path.curve(to: curr, controlPoint1: NSPoint(x: midX, y: prev.y), controlPoint2: NSPoint(x: midX, y: curr.y))
            }
            return path
        }

        func drawSeries(_ data: [Double], fillColor: NSColor, strokeColor: NSColor) {
            let count = data.count
            let stepX = chartW / CGFloat(max(maxHistory - 1, 1))
            let startX = left + chartW - CGFloat(count - 1) * stepX
            let line = smoothPath(data, startX: startX, stepX: stepX)
            let fill = line.copy() as! NSBezierPath
            let lastX = startX + CGFloat(count - 1) * stepX
            fill.line(to: NSPoint(x: lastX, y: top + chartH))
            fill.line(to: NSPoint(x: startX, y: top + chartH))
            fill.close()
            fillColor.setFill()
            fill.fill()
            strokeColor.setStroke()
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.stroke()
        }

        drawSeries(downData, fillColor: NSColor.systemCyan.withAlphaComponent(0.12), strokeColor: NSColor.systemCyan.withAlphaComponent(0.9))
        drawSeries(upData, fillColor: NSColor.systemOrange.withAlphaComponent(0.12), strokeColor: NSColor.systemOrange.withAlphaComponent(0.7))

        let scaleFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let scaleAttrs: [NSAttributedString.Key: Any] = [.font: scaleFont, .foregroundColor: NSColor.tertiaryLabelColor]
        NSAttributedString(string: formatMax(maxVal), attributes: scaleAttrs).draw(at: NSPoint(x: left + 2, y: top + 1))
        NSAttributedString(string: "0", attributes: scaleAttrs).draw(at: NSPoint(x: left + 2, y: top + chartH - 12))

        let timeAttrs: [NSAttributedString.Key: Any] = [.font: scaleFont, .foregroundColor: NSColor.tertiaryLabelColor]
        NSAttributedString(string: "60s ago", attributes: timeAttrs).draw(at: NSPoint(x: left, y: top + chartH + 3))
        let nowStr = NSAttributedString(string: "now", attributes: timeAttrs)
        nowStr.draw(at: NSPoint(x: left + chartW - nowStr.size().width, y: top + chartH + 3))
    }
}
