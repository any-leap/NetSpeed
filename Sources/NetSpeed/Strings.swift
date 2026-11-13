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

    // 关注进程告警（名单可在设置里改，文案不再假定是 iCloud 的 bird）
    static func watchedNotRunningAlert(_ name: String) -> String { isChinese ? "\(name) 未运行" : "\(name) is NOT running" }
    static func watchedNotRunningTitle(_ name: String) -> String { isChinese ? "关注进程未运行：\(name)" : "Watched process not running: \(name)" }
    static func watchedNotRunningMessage(_ name: String) -> String { isChinese ? "关注列表中的 \(name) 进程没有在运行。" : "\(name), on your watch list, is not running." }

    // 设置窗口
    static var settingsMenuItem: String { isChinese ? "设置…" : "Settings…" }
    static var settingsWindowTitle: String { isChinese ? "NetSpeed 设置" : "NetSpeed Settings" }
    static var settingsCPUSection: String { isChinese ? "CPU 告警" : "CPU Alerts" }
    static var settingsThreshold: String { isChinese ? "告警阈值" : "Alert threshold" }
    static var settingsThresholdHelp: String { isChinese ? "单个进程 CPU 占用超过此值即标为异常（多核可超过 100%）。" : "A process above this CPU usage is flagged as abnormal (can exceed 100% on multi-core)." }
    static var settingsSustained: String { isChinese ? "持续多久才通知" : "Notify after sustained for" }
    static func seconds(_ n: Int) -> String { isChinese ? "\(n) 秒" : "\(n)s" }
    static var settingsIgnored: String { isChinese ? "忽略的进程" : "Ignored processes" }
    static var settingsIgnoredHelp: String { isChinese ? "每行一个进程名，这些进程不做 CPU 告警。" : "One process name per line; never flagged for CPU." }
    static var settingsWatchedSection: String { isChinese ? "关注进程" : "Watched Processes" }
    static var settingsWatchedHelp: String { isChinese ? "每行一个进程名。进程消失时发通知，并在菜单顶部显示存活状态。留空则不关注。" : "One process name per line. Notifies when one disappears and shows its status at the top of the menu. Leave empty to disable." }
    static var settingsLatencySection: String { isChinese ? "延迟测速地址" : "Latency Targets" }
    static var settingsLatencyHelp: String { isChinese ? "每行一个 https 地址，每轮取最快的一个。必须是 https：TLS 握手绕不过 Clash TUN，才能测到真实延迟。" : "One https URL per line; the fastest one wins each round. Must be https so Clash TUN cannot short-circuit the measurement." }
    static func settingsInvalidURLs(_ list: [String]) -> String { (isChinese ? "以下地址无效，未保存：" : "Invalid, not saved: ") + list.joined(separator: ", ") }
    static var settingsNeedOneURL: String { isChinese ? "至少需要一个地址，未保存。" : "At least one URL is required; not saved." }
    static var settingsOpenVPNSection: String { "OpenVPN" }
    static var settingsOpenVPNConfig: String { isChinese ? "配置文件 (.ovpn)" : "Config (.ovpn)" }
    static var settingsOpenVPNAuth: String { isChinese ? "账号密码文件" : "Credentials file" }
    static var settingsOpenVPNHelp: String { isChinese ? "选了配置文件后，菜单里才会出现连接/断开按钮。" : "Connect/Disconnect appears in the menu once a config is set." }
    static var settingsNotSet: String { isChinese ? "未设置" : "Not set" }
    static var settingsChoose: String { isChinese ? "选择…" : "Choose…" }
    static var settingsClear: String { isChinese ? "清除" : "Clear" }
    static var settingsUseDefault: String { isChinese ? "用默认" : "Use Default" }
    static var settingsDefaultSuffix: String { isChinese ? "（默认）" : " (default)" }
    static var settingsMissingFile: String { isChinese ? "文件不存在" : "File not found" }
    static var settingsReset: String { isChinese ? "恢复默认" : "Restore Defaults" }
    static var settingsResetHelp: String { isChinese ? "恢复 CPU 告警、关注进程和测速地址的默认值（不动 OpenVPN）。" : "Restores CPU, watched-process and latency defaults (OpenVPN untouched)." }
    static var settingsLiveNote: String { isChinese ? "修改即时生效。" : "Changes apply immediately." }
}
