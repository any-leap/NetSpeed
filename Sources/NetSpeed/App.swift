import SwiftUI
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private var monitor: NetMonitor

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        monitor = NetMonitor()

        setupMenu()

        monitor.onChange = { [weak self] in
            self?.updateLabel()
        }
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }

        let upLine = "↑ \(monitor.upSpeed)"
        let downLine = "↓ \(monitor.downSpeed)"

        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineSpacing = 0
        paragraphStyle.maximumLineHeight = 11
        paragraphStyle.minimumLineHeight = 11

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let text = "\(upLine)\n\(downLine)"
        let attrStr = NSMutableAttributedString(string: text, attributes: attrs)

        // Measure width from the longer line
        let upAttr = NSAttributedString(string: upLine, attributes: attrs)
        let downAttr = NSAttributedString(string: downLine, attributes: attrs)
        let maxWidth = max(upAttr.size().width, downAttr.size().width)
        let w = ceil(maxWidth) + 2
        let h: CGFloat = 22

        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocusFlipped(true)
        // Two lines: each 11pt high, centered in 22pt
        attrStr.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        image.unlockFocus()
        image.isTemplate = true

        button.image = image
        button.title = ""
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit NetSpeed", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
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
