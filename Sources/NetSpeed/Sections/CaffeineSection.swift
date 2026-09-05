import AppKit
import IOKit

final class CaffeineSection: NSObject, MenuSection, NSMenuItemValidation {
    private let monitor: CaffeineMonitor
    private var statusItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private let lidMonitor = LidSleepMonitor()
    private var lidItem: NSMenuItem?

    init(monitor: CaffeineMonitor) {
        self.monitor = monitor
        super.init()
        lidMonitor.onUpdate = { [weak self] in self?.refresh() }
        lidMonitor.onError = { detail in
            let alert = NSAlert()
            alert.messageText = L10n.lidError
            alert.informativeText = detail
            alert.runModal()
        }
    }
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
        let lid = NSMenuItem(title: L10n.lidToggle,
                             action: #selector(toggleLidSleep), keyEquivalent: "")
        lid.target = self
        lid.toolTip = L10n.lidExplanation
        menu.addItem(lid)
        lidItem = lid
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
        switch lidMonitor.phase {
        case .idle:
            lidItem?.title = lidMonitor.recoveryNeeded ? L10n.lidRecovery : L10n.lidToggle
            lidItem?.state = lidMonitor.systemSleepDisabled == true ? .on : .off
            lidItem?.isEnabled = lidMonitor.systemSleepDisabled != nil || lidMonitor.recoveryNeeded
            if lidMonitor.systemSleepDisabled == nil && !lidMonitor.recoveryNeeded {
                lidItem?.title = L10n.lidUnknown
            }
        case .authorizing:
            lidItem?.title = L10n.lidAuthorizing
            lidItem?.state = .mixed
            lidItem?.isEnabled = false
        case .active:
            lidItem?.title = L10n.lidActive
            lidItem?.state = .on
            lidItem?.isEnabled = true
        case .stopping, .recovering:
            lidItem?.title = L10n.lidRestoring
            lidItem?.state = .mixed
            lidItem?.isEnabled = false
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(toggleLidSleep) else { return true }
        switch lidMonitor.phase {
        case .idle: return lidMonitor.systemSleepDisabled != nil || lidMonitor.recoveryNeeded
        case .active: return true
        case .authorizing, .stopping, .recovering: return false
        }
    }

    @objc private func toggleLidSleep() {
        if lidMonitor.phase == .active {
            lidMonitor.stop()
        } else if lidMonitor.recoveryNeeded {
            // This is a global setting of unknown ownership, so make its scope explicit.
            let alert = NSAlert()
            alert.messageText = L10n.lidRecovery
            alert.informativeText = L10n.lidRecoveryExplanation
            alert.addButton(withTitle: L10n.lidRestoreButton)
            alert.addButton(withTitle: L10n.lidCancel)
            if alert.runModal() == .alertFirstButtonReturn { lidMonitor.recover() }
        } else {
            lidMonitor.start()
        }
        refresh()
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
