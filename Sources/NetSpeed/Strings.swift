import Foundation

struct L10n {
    static let isChinese: Bool = {
        let lang = Locale.preferredLanguages.first ?? ""
        return lang.hasPrefix("zh")
    }()

    static let network = isChinese ? "网络" : "Network"
    static let trafficByProcess = isChinese ? "流量排行" : "Traffic by Process"
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
        let m = seconds / 60
        let s = seconds % 60
        if isChinese {
            return "\(m)分\(s)秒前重置"
        } else {
            return "since \(m)m\(s)s ago"
        }
    }
}
