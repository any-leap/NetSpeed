import Foundation

struct L10n {
    static let isChinese: Bool = {
        let lang = Locale.preferredLanguages.first ?? ""
        return lang.hasPrefix("zh")
    }()

    static let network = isChinese ? "网络流量" : "Network Traffic"
    static let latencyMainland = isChinese ? "大陆延迟" : "Mainland Latency"
    static let latencyOverseas = isChinese ? "海外延迟" : "Overseas Latency"
    static let trafficByProcess = isChinese ? "流量排行" : "Traffic by Process"
    static let trafficLive = isChinese ? "实时" : "Live"
    static let trafficCumulative = isChinese ? "累计" : "Total"
    static let resetTraffic = isChinese ? "重置流量" : "Reset Traffic"
    static let noTraffic = isChinese ? "暂无流量记录" : "No traffic recorded"
    static let sinceAgo = isChinese ? "前重置" : " ago"
    static let cpu = "CPU"
    static let memory = isChinese ? "内存" : "Memory"
    static let topCPU = isChinese ? "CPU 排行" : "Top CPU Processes"
    static let topMemory = isChinese ? "内存排行" : "Top Memory"
    static let abnormal = isChinese ? "异常进程" : "Abnormal"
    static let recentAlerts = isChinese ? "最近告警" : "Recent Alerts"
    static let running = isChinese ? "运行中" : "running"
    static let notRunning = isChinese ? "未运行" : "NOT running"
    static let quit = isChinese ? "退出" : "Quit"
    static let kill = isChinese ? "结束" : "Kill"
    static let app = isChinese ? "应用" : "App"
    static let wired = isChinese ? "固定" : "Wired"
    static let compressed = isChinese ? "压缩" : "Compressed"
    static let vpn = isChinese ? "隧道" : "Tunnel"
    static let vpnConnected = isChinese ? "已连接" : "Connected"
    static let vpnDisconnected = isChinese ? "未连接" : "Disconnected"
    static let vpnConnectAction = isChinese ? "连接 OpenVPN" : "Connect OpenVPN"
    static let vpnDisconnectAction = isChinese ? "断开 OpenVPN" : "Disconnect OpenVPN"
    static let tunnelDisconnectedTitle = isChinese ? "隧道已断开" : "Tunnel Disconnected"
    static let tunnelDisconnectedMessage = isChinese ? "utun 接口已消失" : "utun interface is down"
    static let ago = isChinese ? "前" : " ago"
    static let secondsAgo = isChinese ? "秒前重置" : "s ago"
    static let quotaTitle = isChinese ? "订阅配额" : "Subscription Quota"
    static let quotaToday = isChinese ? "今日" : "today"
    static let quotaRemaining = isChinese ? "剩" : "left"
    static let quotaMonthly = isChinese ? "·月重置" : "·monthly"
    static let pressure_normal = isChinese ? "正常" : "Normal"
    static let pressure_warning = isChinese ? "警告" : "Warning"
    static let pressure_critical = isChinese ? "危险" : "Critical"

    static func sinceDuration(_ seconds: Int) -> String {
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if isChinese {
            let body: String
            if d > 0 { body = "\(d)天\(h)小时" }
            else if h > 0 { body = "\(h)小时\(m)分" }
            else if m > 0 { body = "\(m)分\(s)秒" }
            else { body = "\(s)秒" }
            return "\(body)前重置"
        } else {
            let body: String
            if d > 0 { body = "\(d)d\(h)h" }
            else if h > 0 { body = "\(h)h\(m)m" }
            else if m > 0 { body = "\(m)m\(s)s" }
            else { body = "\(s)s" }
            return "since \(body) ago"
        }
    }
}


extension L10n {
    static var caffeineToggle: String { isChinese ? "保持唤醒（NetSpeed）" : "Keep Awake (NetSpeed)" }
    static var caffeineOwn: String { isChinese ? "咖啡因：已开启 · NetSpeed" : "Caffeine: On · NetSpeed" }
    static var caffeineExternal: String { isChinese ? "咖啡因：其他 App / 系统保持唤醒" : "Caffeine: Other app / system keeping awake" }
    static var caffeineOff: String { isChinese ? "咖啡因：未开启" : "Caffeine: Off" }
    static var caffeineUnknown: String { isChinese ? "咖啡因：状态读取失败" : "Caffeine: Status unavailable" }
    static var caffeineError: String { isChinese ? "无法切换保持唤醒" : "Could not toggle Keep Awake" }
    static var caffeineExplanation: String { isChinese ? "防止闲置休眠，屏幕仍可熄灭；不阻止合盖休眠。退出 NetSpeed 后失效；不影响其他 App 的防休眠。" : "Prevents idle system sleep; display may sleep. Does not prevent lid-close sleep. Ends when NetSpeed quits. Other apps are unaffected." }
    static var lidToggle: String { isChinese ? "合盖保持运行（最多 2 小时）…" : "Keep Running with Lid Closed (up to 2h)…" }
    static var lidActive: String { isChinese ? "合盖保持运行：已开启（点击关闭）" : "Lid Closed: Keeping Awake (Click to Stop)" }
    static var lidAuthorizing: String { isChinese ? "合盖保持运行：正在授权…" : "Lid Closed: Authorizing…" }
    static var lidRestoring: String { isChinese ? "合盖保持运行：正在恢复睡眠…" : "Lid Closed: Restoring Sleep…" }
    static var lidUnknown: String { isChinese ? "合盖保持运行：状态读取失败" : "Lid Closed: Status Unavailable" }
    static var lidExplanation: String { isChinese ? "需要管理员授权，全局禁用系统睡眠。关闭、退出或达到 2 小时后恢复；电池供电降至 20% 时恢复。合盖仍耗电发热，请保持通风。" : "Requires administrator authorization; disables system sleep globally. Restores on stop, app exit, after 2 hours, or at 20% on battery power. Keep the Mac ventilated." }
    static var lidRecovery: String { isChinese ? "恢复系统睡眠…" : "Restore System Sleep…" }
    static var lidRecoveryExplanation: String { isChinese ? "检测到系统禁用睡眠或上次会话遗留状态。恢复会关闭全局防休眠设置，也可能影响其他工具设置的合盖模式。" : "System sleep is disabled or a previous session needs recovery. Restoring clears the global setting, which may affect closed-lid modes enabled by other tools." }
    static var lidRestoreButton: String { isChinese ? "恢复睡眠" : "Restore Sleep" }
    static var lidCancel: String { isChinese ? "取消" : "Cancel" }
    static var lidError: String { isChinese ? "无法切换合盖保持运行" : "Could Not Change Closed-Lid Mode" }

}
