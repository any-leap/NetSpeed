import Foundation

/// 订阅配额状态。数据来自外部记账工具（如 clashhub meterd）写出的
/// `~/.clashhub/status.json`；契约：文件不存在或超过 10 分钟未更新视为离线。
struct QuotaStatus: Codable {
    struct Subscription: Codable {
        let name: String
        let todayBytes: Int64
        let usedBytes: Int64?
        let totalBytes: Int64?
        let remainingPct: Double?
        let resetsMonthly: Bool?
        let expireAt: String?
    }

    let version: Int
    let updatedAt: String
    let subscriptions: [Subscription]
}

final class QuotaMonitor {
    private(set) var status: QuotaStatus?
    var onUpdate: (() -> Void)?

    static let statusURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".clashhub/status.json")

    private static let staleAfter: TimeInterval = 600
    private var timer: Timer?

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func start() {
        load()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.load()
        }
        // 菜单打开期间也要能刷新（NSMenu tracking 阻塞 .default mode）
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func load() {
        let new = Self.read()
        let changed = (new?.updatedAt != status?.updatedAt)
            || ((new == nil) != (status == nil))
        status = new
        if changed { onUpdate?() }
    }

    private static func read() -> QuotaStatus? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data, now: Date = Date()) -> QuotaStatus? {
        guard let parsed = try? JSONDecoder().decode(QuotaStatus.self, from: data),
              parsed.version == 1
        else { return nil }
        // 陈旧数据（meterd 没在跑）不如不显示
        guard let updated = isoParser.date(from: parsed.updatedAt) ?? ISO8601DateFormatter().date(from: parsed.updatedAt),
              now.timeIntervalSince(updated) < staleAfter
        else { return nil }
        return parsed
    }

    static func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0fG", gb) }
        if gb >= 1 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / 1_048_576)
    }
}
