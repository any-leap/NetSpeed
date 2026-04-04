import SwiftUI
import AppKit

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private var netMonitor: NetMonitor
    private var cpuMonitor: CPUMonitor
    private var trafficMonitor: TrafficMonitor
    private var memMonitor: MemoryMonitor
    private var menu: NSMenu
    private var guardTimer: Timer?
    private var menuIsOpen = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        netMonitor = NetMonitor()
        cpuMonitor = CPUMonitor()
        trafficMonitor = TrafficMonitor()
        memMonitor = MemoryMonitor()
        menu = NSMenu()

        super.init()

        menu.delegate = self
        statusItem.menu = menu

        netMonitor.onChange = { [weak self] in
            self?.cpuMonitor.update()
            self?.memMonitor.update()
            self?.updateLabel()
            if self?.menuIsOpen == true {
                self?.rebuildMenu()
            }
        }

        // CPUGuard check every 10 seconds
        guardTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.cpuMonitor.guardCheck()
        }
    }

    // MARK: - Menu Bar Label (network speed only)

    private func updateLabel() {
        guard let button = statusItem.button else { return }

        let font = NSFont.systemFont(ofSize: 9, weight: .medium)

        // Fixed width based on widest possible value "999.9 MB/s"
        let maxSpeedStr = NSAttributedString(string: "999.9 KB/s", attributes: [.font: font])
        let arrowStr = NSAttributedString(string: "↑ ", attributes: [.font: font])
        let fixedWidth = arrowStr.size().width + maxSpeedStr.size().width

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 0
        paragraphStyle.maximumLineHeight = 11
        paragraphStyle.minimumLineHeight = 11

        let tab = NSTextTab(textAlignment: .right, location: fixedWidth)
        paragraphStyle.tabStops = [tab]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let upLine = "↑\t\(netMonitor.upSpeed)"
        let downLine = "↓\t\(netMonitor.downSpeed)"
        let text = "\(upLine)\n\(downLine)"
        let attrStr = NSMutableAttributedString(string: text, attributes: attrs)

        let w = ceil(fixedWidth) + 4
        let h: CGFloat = 22

        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocusFlipped(true)
        attrStr.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        image.unlockFocus()
        image.isTemplate = true

        button.image = image
        button.title = ""
    }

    // MARK: - Dropdown Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        cpuMonitor.update()
        trafficMonitor.update()
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        // --- Network Chart ---
        if let chartImage = renderChart() {
            let chartItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            chartItem.image = chartImage
            chartItem.isEnabled = false
            menu.addItem(chartItem)
        }

        // --- Traffic by Process ---
        menu.addItem(NSMenuItem.separator())

        // Header with reset button
        let trafficTitle: String
        if let resetTime = trafficMonitor.resetTime {
            let elapsed = Int(Date().timeIntervalSince(resetTime))
            trafficTitle = "\(L10n.trafficByProcess)  (\(L10n.sinceDuration(elapsed)))"
        } else {
            trafficTitle = L10n.trafficByProcess
        }
        addHeader(trafficTitle, font: headerFont)

        if trafficMonitor.topTraffic.isEmpty {
            addDisabledItem("  \(L10n.noTraffic)", font: NSFont.systemFont(ofSize: 11))
        }

        for proc in trafficMonitor.topTraffic {
            let inStr = TrafficMonitor.formatBytes(proc.bytesIn)
            let outStr = TrafficMonitor.formatBytes(proc.bytesOut)
            let title = "  \(proc.name)"
            let detail = "    ↓\(inStr)  ↑\(outStr)"

            let item = NSMenuItem(title: title, action: #selector(noop), keyEquivalent: "")
            item.target = self

            let full = NSMutableAttributedString()
            full.append(NSAttributedString(string: title + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            ]))
            full.append(NSAttributedString(string: detail, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            item.attributedTitle = full
            menu.addItem(item)
        }

        let resetItem = NSMenuItem(title: "  \(L10n.resetTraffic)", action: #selector(resetTraffic), keyEquivalent: "r")
        resetItem.target = self
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemBlue,
        ]
        resetItem.attributedTitle = NSAttributedString(string: "  \(L10n.resetTraffic)", attributes: resetAttrs)
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // --- Memory ---
        let mem = memMonitor.info
        let memUsed = MemoryMonitor.formatBytes(mem.used)
        let memTotal = MemoryMonitor.formatBytes(mem.total)
        let memPct = String(format: "%.0f%%", mem.usagePercent)
        addHeader("\(L10n.memory): \(memUsed) / \(memTotal) (\(memPct))", font: headerFont)

        let memBarWidth = 30
        let memFilled = Int(mem.usagePercent / 100.0 * Double(memBarWidth))
        let memBar = String(repeating: "▓", count: min(memFilled, memBarWidth)) + String(repeating: "░", count: max(memBarWidth - memFilled, 0))
        addDisabledItem("  \(memBar)", font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))

        let detailFont = NSFont.systemFont(ofSize: 10)
        let detailColor = NSColor.secondaryLabelColor
        let appMem = MemoryMonitor.formatBytes(mem.appMemory)
        let wiredMem = MemoryMonitor.formatBytes(mem.wired)
        let compMem = MemoryMonitor.formatBytes(mem.compressed)
        let detailStr = "  \(L10n.app): \(appMem)  \(L10n.wired): \(wiredMem)  \(L10n.compressed): \(compMem)"
        let detailItem = NSMenuItem(title: detailStr, action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        detailItem.attributedTitle = NSAttributedString(string: detailStr, attributes: [
            .font: detailFont, .foregroundColor: detailColor,
        ])
        menu.addItem(detailItem)

        // Top memory processes
        for proc in memMonitor.topProcesses {
            let memStr = MemoryMonitor.formatBytes(proc.mem)
            let title = "  \(memStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(proc.name)"

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: bodyFont])

            let sub = NSMenu()
            let killItem = NSMenuItem(title: "\(L10n.kill) \(proc.name) (PID \(proc.pid))", action: #selector(killProcess(_:)), keyEquivalent: "")
            killItem.target = self
            killItem.tag = proc.pid
            sub.addItem(killItem)
            item.submenu = sub

            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // --- CPU ---
        let cpuStr = String(format: "%.1f%%", cpuMonitor.cpuUsage)
        addHeader("\(L10n.cpu): \(cpuStr)", font: headerFont)

        let barWidth = 30
        let filled = Int(cpuMonitor.cpuUsage / 100.0 * Double(barWidth))
        let bar = String(repeating: "▓", count: min(filled, barWidth)) + String(repeating: "░", count: max(barWidth - filled, 0))
        addDisabledItem("  \(bar)", font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))

        for proc in cpuMonitor.topProcesses {
            let cpuFmt = String(format: "%5.1f%%", proc.cpu)
            let title = "  \(cpuFmt)  \(proc.name)"

            let isAbnormal = cpuMonitor.sustainedPids.contains(proc.pid)
            let attrs: [NSAttributedString.Key: Any] = isAbnormal
                ? [.font: bodyFont, .foregroundColor: NSColor.systemRed]
                : [.font: bodyFont]

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: attrs)

            let sub = NSMenu()
            let killItem = NSMenuItem(title: "\(L10n.kill) \(proc.name) (PID \(proc.pid))", action: #selector(killProcess(_:)), keyEquivalent: "")
            killItem.target = self
            killItem.tag = proc.pid
            sub.addItem(killItem)
            item.submenu = sub

            menu.addItem(item)
        }

        // --- Abnormal processes (CPUGuard) ---
        if !cpuMonitor.abnormalProcesses.isEmpty {
            menu.addItem(NSMenuItem.separator())
            addHeader("⚠ \(L10n.abnormal) (\(Int(cpuMonitor.cpuThreshold))%+)", font: headerFont)

            for proc in cpuMonitor.abnormalProcesses {
                let cpuFmt = String(format: "%5.1f%%", proc.cpu)
                let title = "  \(cpuFmt)  \(proc.name)"

                let item = NSMenuItem(title: title, action: #selector(killProcess(_:)), keyEquivalent: "")
                item.target = self
                item.tag = proc.pid

                let redAttrs: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: NSColor.systemRed,
                ]
                item.attributedTitle = NSAttributedString(string: title, attributes: redAttrs)
                menu.addItem(item)
            }
        }

        // --- Recent Alerts ---
        if !cpuMonitor.recentAlerts.isEmpty {
            menu.addItem(NSMenuItem.separator())
            addHeader(L10n.recentAlerts, font: headerFont)

            for alert in cpuMonitor.recentAlerts.prefix(5) {
                let title = "  [\(alert.time)] \(alert.message)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                let alertAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                item.attributedTitle = NSAttributedString(string: title, attributes: alertAttrs)
                menu.addItem(item)
            }
        }

        // --- Watched processes ---
        menu.addItem(NSMenuItem.separator())
        for name in cpuMonitor.watchedProcesses {
            let procs = cpuMonitor.readTopProcesses(count: 500)
            let proc = procs.first { $0.name == name }
            let alive = proc != nil
            let status = alive ? "✓ \(name) \(L10n.running)" : "✗ \(name) \(L10n.notRunning)"
            let color: NSColor = alive ? .systemGreen : .systemRed

            if alive, let proc = proc {
                let item = NSMenuItem(title: "  \(status)", action: nil, keyEquivalent: "")
                item.attributedTitle = NSAttributedString(string: "  \(status)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                ])
                let sub = NSMenu()
                let restartLabel = L10n.isChinese ? "重启 \(name)" : "Restart \(name)"
                let killItem = NSMenuItem(title: restartLabel, action: #selector(killProcess(_:)), keyEquivalent: "")
                killItem.target = self
                killItem.tag = proc.pid
                sub.addItem(killItem)
                item.submenu = sub
                menu.addItem(item)
            } else {
                let item = NSMenuItem(title: "  \(status)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(string: "  \(status)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                ])
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addHeader(_ title: String, font: NSFont) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
    }

    private func addDisabledItem(_ title: String, font: NSFont) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
    }

    @objc func noop() {}

    @objc func resetTraffic() {
        trafficMonitor.reset()
        rebuildMenu()
    }

    // MARK: - Chart

    private func renderChart() -> NSImage? {
        let downData = netMonitor.downHistory
        let upData = netMonitor.upHistory
        guard downData.count >= 2 else { return nil }

        let w: CGFloat = 260
        let h: CGFloat = 90
        let left: CGFloat = 8
        let right: CGFloat = 8
        let top: CGFloat = 24
        let bottom: CGFloat = 18

        let chartW = w - left - right
        let chartH = h - top - bottom

        let allValues = downData + upData
        let maxVal = max(allValues.max() ?? 1, 1024)

        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocusFlipped(true)

        // Title + legend row
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.labelColor]
        NSAttributedString(string: L10n.network, attributes: titleAttrs).draw(at: NSPoint(x: left, y: 4))

        // Legend: colored dots + labels
        let legendFont = NSFont.systemFont(ofSize: 9)
        let downLegend = NSMutableAttributedString()
        downLegend.append(NSAttributedString(string: "● ", attributes: [.font: legendFont, .foregroundColor: NSColor.systemCyan]))
        downLegend.append(NSAttributedString(string: "↓ \(netMonitor.downSpeed)", attributes: [.font: legendFont, .foregroundColor: NSColor.secondaryLabelColor]))

        let upLegend = NSMutableAttributedString()
        upLegend.append(NSAttributedString(string: "● ", attributes: [.font: legendFont, .foregroundColor: NSColor.systemOrange]))
        upLegend.append(NSAttributedString(string: "↑ \(netMonitor.upSpeed)", attributes: [.font: legendFont, .foregroundColor: NSColor.secondaryLabelColor]))

        let upLegendWidth = upLegend.size().width
        let downLegendWidth = downLegend.size().width
        upLegend.draw(at: NSPoint(x: w - right - upLegendWidth, y: 5))
        downLegend.draw(at: NSPoint(x: w - right - upLegendWidth - downLegendWidth - 10, y: 5))

        // Chart area background
        let chartRect = NSRect(x: left, y: top, width: chartW, height: chartH)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 3, yRadius: 3).fill()

        // Grid lines (dashed)
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

        // Smooth curve helper
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
            let stepX = chartW / CGFloat(max(netMonitor.maxHistory - 1, 1))
            let startX = left + chartW - CGFloat(count - 1) * stepX

            let line = smoothPath(data, startX: startX, stepX: stepX)

            // Fill
            let fill = line.copy() as! NSBezierPath
            let lastX = startX + CGFloat(count - 1) * stepX
            fill.line(to: NSPoint(x: lastX, y: top + chartH))
            fill.line(to: NSPoint(x: startX, y: top + chartH))
            fill.close()

            // Gradient fill
            fillColor.setFill()
            fill.fill()

            // Stroke
            strokeColor.setStroke()
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.stroke()
        }

        // Draw download first (behind), then upload
        drawSeries(downData, fillColor: NSColor.systemCyan.withAlphaComponent(0.12), strokeColor: NSColor.systemCyan.withAlphaComponent(0.9))
        drawSeries(upData, fillColor: NSColor.systemOrange.withAlphaComponent(0.12), strokeColor: NSColor.systemOrange.withAlphaComponent(0.7))

        // Scale labels
        let scaleFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let scaleAttrs: [NSAttributedString.Key: Any] = [.font: scaleFont, .foregroundColor: NSColor.tertiaryLabelColor]
        NSAttributedString(string: netMonitor.formatSpeed(maxVal), attributes: scaleAttrs).draw(at: NSPoint(x: left + 2, y: top + 1))
        NSAttributedString(string: "0", attributes: scaleAttrs).draw(at: NSPoint(x: left + 2, y: top + chartH - 12))

        // Time labels
        let timeAttrs: [NSAttributedString.Key: Any] = [.font: scaleFont, .foregroundColor: NSColor.tertiaryLabelColor]
        NSAttributedString(string: "60s ago", attributes: timeAttrs).draw(at: NSPoint(x: left, y: top + chartH + 3))
        let nowStr = NSAttributedString(string: "now", attributes: timeAttrs)
        nowStr.draw(at: NSPoint(x: left + chartW - nowStr.size().width, y: top + chartH + 3))

        image.unlockFocus()
        return image
    }

    @objc func killProcess(_ sender: NSMenuItem) {
        let pid = sender.tag
        let result = kill(Int32(pid), SIGTERM)
        if result != 0 {
            let script = "do shell script \"kill \(pid)\" with administrator privileges"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
        cpuMonitor.update()
        rebuildMenu()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    deinit {
        guardTimer?.invalidate()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
    }
}

@main
struct NetSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
