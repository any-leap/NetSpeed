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
    static let vpn = "VPN"
    static let vpnConnected = isChinese ? "已连接" : "Connected"
    static let vpnDisconnected = isChinese ? "未连接" : "Disconnected"
    static let vpnConnectAction = isChinese ? "连接 VPN" : "Connect VPN"
    static let vpnDisconnectAction = isChinese ? "断开 VPN" : "Disconnect VPN"
    static let ago = isChinese ? "前" : " ago"
    static let secondsAgo = isChinese ? "秒前重置" : "s ago"
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
