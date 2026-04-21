import AppKit
import Foundation

/// 集中所有菜单动作的 `@objc` 方法。section 构造菜单项时把 `target` 指向本类。
final class MenuActions: NSObject {
    private let cpuMonitor: CPUMonitor
    private let trafficMonitor: TrafficMonitor
    private let vpnController: VPNController
    /// menu rebuild 回调（kill / resetTraffic 之后菜单要刷）
    var onNeedsRebuild: (() -> Void)?

    init(cpuMonitor: CPUMonitor,
         trafficMonitor: TrafficMonitor,
         vpnController: VPNController) {
        self.cpuMonitor = cpuMonitor
        self.trafficMonitor = trafficMonitor
        self.vpnController = vpnController
        super.init()
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
        onNeedsRebuild?()
    }

    @objc func resetTraffic() {
        trafficMonitor.reset()
        onNeedsRebuild?()
    }

    @objc func toggleVPN() {
        vpnController.toggle()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
