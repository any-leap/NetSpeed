import AppKit
import Foundation

final class VPNController {
    private let monitor: VPNMonitor
    private let notifier: NotificationHelper

    private static let vpnConfigKey = "vpnConfigPath"
    private static let vpnAuthKey = "vpnAuthPath"

    /// 2 秒后触发一次 monitor.update() + 菜单刷新。
    /// 由 StatusBarController 注入（toggleVPN 之后需要刷菜单状态）。
    var onToggleCompleted: (() -> Void)?

    init(monitor: VPNMonitor, notifier: NotificationHelper) {
        self.monitor = monitor
        self.notifier = notifier
    }

    var isConnected: Bool { monitor.status.connected }

    var isOpenVPNConfigured: Bool {
        UserDefaults.standard.string(forKey: Self.vpnConfigKey) != nil
    }

    func toggle() {
        if monitor.status.connected {
            disconnect()
        } else {
            connect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.monitor.update()
            self?.onToggleCompleted?()
        }
    }

    // MARK: - private

    private var vpnConfigPath: String? {
        UserDefaults.standard.string(forKey: Self.vpnConfigKey)
    }

    private var vpnAuthPath: String {
        UserDefaults.standard.string(forKey: Self.vpnAuthKey)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".openvpn-auth").path
    }

    private func disconnect() {
        let script = "do shell script \"killall openvpn\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func connect() {
        guard let configPath = vpnConfigPath ?? promptForConfig() else { return }
        let cfg = shellQuote(configPath)
        let auth = shellQuote(vpnAuthPath)
        let cmd = "/opt/homebrew/sbin/openvpn --daemon --log /tmp/openvpn.log --config \(cfg) --auth-user-pass \(auth)"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func promptForConfig() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Select OpenVPN config (.ovpn)"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: Self.vpnConfigKey)
        return url.path
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
