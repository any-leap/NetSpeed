import Foundation

/// 用户可调的设置，存在 UserDefaults。默认值就是以前写死在代码里的值，
/// 没打开过设置窗口的用户行为不变。写入后发 `didChange`，监视器据此即时生效。
final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("NetSpeedPreferencesDidChange")

    enum Key {
        static let cpuThreshold = "cpuThreshold"
        static let sustainedSeconds = "cpuSustainedSeconds"
        static let ignoredProcesses = "cpuIgnoredProcesses"
        static let watchedProcesses = "watchedProcesses"
        static let latencyTargetsCN = "latencyTargetsMainland"
        static let latencyTargetsIntl = "latencyTargetsOverseas"
        // 这两个 key 是 VPNController 原有的，名字不能改。
        static let openVPNConfigPath = "vpnConfigPath"
        static let openVPNAuthPath = "vpnAuthPath"
    }

    static let defaultCPUThreshold: Double = 50
    static let cpuThresholdRange: ClosedRange<Double> = 10...400
    static let defaultSustainedSeconds = 30
    /// CPU 守卫每 10 秒采样一次，持续时间只能是 10 的倍数且至少 10。
    static let sustainedSecondsRange: ClosedRange<Int> = 10...600
    static let sustainedSecondsStep = 10
    static let defaultIgnoredProcesses = [
        "WindowServer", "kernel_task", "Claude", "claude",
        "Spotlight", "mds", "mds_stores", "mdworker", "NetSpeed",
    ]
    static let defaultWatchedProcesses = ["bird"]
    static let defaultLatencyTargetsCN = [
        "https://www.baidu.com/favicon.ico",
        "https://www.taobao.com/favicon.ico",
        "https://www.qq.com/favicon.ico",
    ]
    static let defaultLatencyTargetsIntl = [
        "https://www.gstatic.com/generate_204",
        "https://www.cloudflare.com/cdn-cgi/trace",
        "https://www.github.com/favicon.ico",
    ]
    static var defaultOpenVPNAuthPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openvpn-auth").path
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - CPU 告警

    var cpuThreshold: Double {
        get {
            guard defaults.object(forKey: Key.cpuThreshold) != nil else { return Self.defaultCPUThreshold }
            return Self.clampThreshold(defaults.double(forKey: Key.cpuThreshold))
        }
        set { write(Self.clampThreshold(newValue), Key.cpuThreshold) }
    }

    var sustainedSeconds: Int {
        get {
            guard defaults.object(forKey: Key.sustainedSeconds) != nil else { return Self.defaultSustainedSeconds }
            return Self.clampSustained(defaults.integer(forKey: Key.sustainedSeconds))
        }
        set { write(Self.clampSustained(newValue), Key.sustainedSeconds) }
    }

    var ignoredProcesses: [String] {
        get { defaults.stringArray(forKey: Key.ignoredProcesses) ?? Self.defaultIgnoredProcesses }
        set { write(Self.normalizeList(newValue), Key.ignoredProcesses) }
    }

    var watchedProcesses: [String] {
        get { defaults.stringArray(forKey: Key.watchedProcesses) ?? Self.defaultWatchedProcesses }
        set { write(Self.normalizeList(newValue), Key.watchedProcesses) }
    }

    // MARK: - 延迟测速

    var latencyTargetsCN: [String] {
        get { storedTargets(Key.latencyTargetsCN) ?? Self.defaultLatencyTargetsCN }
        set { writeTargets(newValue, Key.latencyTargetsCN) }
    }

    var latencyTargetsIntl: [String] {
        get { storedTargets(Key.latencyTargetsIntl) ?? Self.defaultLatencyTargetsIntl }
        set { writeTargets(newValue, Key.latencyTargetsIntl) }
    }

    // MARK: - OpenVPN

    var openVPNConfigPath: String? {
        get { defaults.string(forKey: Key.openVPNConfigPath) }
        set {
            if let v = newValue, !v.isEmpty { write(v, Key.openVPNConfigPath) } else { remove(Key.openVPNConfigPath) }
        }
    }

    /// nil = 用默认的 ~/.openvpn-auth
    var openVPNAuthPath: String? {
        get { defaults.string(forKey: Key.openVPNAuthPath) }
        set {
            if let v = newValue, !v.isEmpty { write(v, Key.openVPNAuthPath) } else { remove(Key.openVPNAuthPath) }
        }
    }

    /// 恢复 CPU 和延迟设置的默认值。OpenVPN 路径是用户选的文件，不在此列。
    func resetMonitoringDefaults() {
        for key in [Key.cpuThreshold, Key.sustainedSeconds, Key.ignoredProcesses,
                    Key.watchedProcesses, Key.latencyTargetsCN, Key.latencyTargetsIntl] {
            defaults.removeObject(forKey: key)
        }
        notify()
    }

    // MARK: - 解析与校验（UI 和测试共用）

    /// 按换行或逗号拆分，去首尾空白、去空行、去重（保留首次出现的顺序）。
    static func parseList(_ text: String) -> [String] {
        normalizeList(text.components(separatedBy: CharacterSet(charactersIn: ",\n")))
    }

    static func normalizeList(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 测速目标必须是带主机名的 https URL：HTTP HEAD + TLS 才能穿过 Clash TUN 测到真实 RTT。
    static func isValidLatencyTarget(_ s: String) -> Bool {
        guard let url = URL(string: s), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// 返回不合法的行；空数组表示全部合法。
    static func invalidLatencyTargets(_ items: [String]) -> [String] {
        items.filter { !isValidLatencyTarget($0) }
    }

    static func clampThreshold(_ v: Double) -> Double {
        min(max(v.rounded(), cpuThresholdRange.lowerBound), cpuThresholdRange.upperBound)
    }

    static func clampSustained(_ v: Int) -> Int {
        let stepped = Int((Double(v) / Double(sustainedSecondsStep)).rounded()) * sustainedSecondsStep
        return min(max(stepped, sustainedSecondsRange.lowerBound), sustainedSecondsRange.upperBound)
    }

    // MARK: - private

    private func storedTargets(_ key: String) -> [String]? {
        guard let list = defaults.stringArray(forKey: key) else { return nil }
        let valid = Self.normalizeList(list).filter(Self.isValidLatencyTarget)
        return valid.isEmpty ? nil : valid
    }

    /// 只接受非空且全部合法的列表，否则保持原值（UI 负责提示错误）。
    private func writeTargets(_ list: [String], _ key: String) {
        let normalized = Self.normalizeList(list)
        guard !normalized.isEmpty, Self.invalidLatencyTargets(normalized).isEmpty else { return }
        write(normalized, key)
    }

    private func write(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        notify()
    }

    private func remove(_ key: String) {
        defaults.removeObject(forKey: key)
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
