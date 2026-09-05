import AppKit
import IOKit

final class CaffeineSection: NSObject, MenuSection {
    private let monitor: CaffeineMonitor
    private var statusItem: NSMenuItem?
    private var toggleItem: NSMenuItem?

    init(monitor: CaffeineMonitor) { self.monitor = monitor }
    var structureSignature: String { "caffeine" }

    func addItems(to menu: NSMenu) -> Bool {
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(status)
        statusItem = status
        let toggle = NSMenuItem(title: L10n.caffeineToggle,
                                action: #selector(toggleCaffeine), keyEquivalent: "")
        toggle.target = self
        toggle.toolTip = L10n.caffeineExplanation
        menu.addItem(toggle)
        toggleItem = toggle
        refresh()
        return true
    }

    func refresh() {
        let state: String
        if monitor.isEnabled { state = L10n.caffeineOwn }
        else if let awake = monitor.systemIsAwake {
            state = awake ? L10n.caffeineExternal : L10n.caffeineOff
        } else { state = L10n.caffeineUnknown }
        statusItem?.title = "☕ " + state
        toggleItem?.state = monitor.isEnabled ? .on : .off
    }

    @objc private func toggleCaffeine() {
        let result = monitor.setEnabled(!monitor.isEnabled)
        refresh()
        if result != kIOReturnSuccess {
            let alert = NSAlert()
            alert.messageText = L10n.caffeineError
            alert.informativeText = "macOS: \(result)"
            alert.runModal()
        }
    }
}
