import Foundation

final class LatencyMonitor {
    struct Target {
        let url: URL
    }

    let name: String
    let targets: [Target]
    let maxHistory: Int

    private(set) var history: [Double?] = []
    private(set) var current: Double?

    var onUpdate: (() -> Void)?

    private var timer: Timer?
    private let session: URLSession

    init(name: String, targets: [String], maxHistory: Int = 60) {
        self.name = name
        self.targets = targets.compactMap { URL(string: $0).map(Target.init) }
        self.maxHistory = maxHistory

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 3.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    deinit {
        stop()
        session.invalidateAndCancel()
    }

    func start() {
        stop()
        tick()  // 立即跑一次，不用等 10 秒才出第一个数据点
        let t = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let group = DispatchGroup()
        var results: [Double] = []
        let lock = NSLock()

        for target in targets {
            group.enter()
            probe(target) { value in
                if let v = value {
                    lock.lock()
                    results.append(v)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let best = results.min()
            self.appendResult(best)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func appendResult(_ value: Double?) {
        history.append(value)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        current = value
        onUpdate?()
    }

    /// HTTP HEAD via shared URLSession. 连接复用：首次请求包含 TCP + TLS 握手，
    /// 之后 keepalive 的 HTTP HEAD 仅约 100 字节，测的是应用层 RTT。
    /// 相比裸 TLS 握手，流量降 ~100×；URLSession 自带浏览器指纹，不易被 DPI/WAF 识别。
    private func probe(_ target: Target, completion: @escaping (Double?) -> Void) {
        var request = URLRequest(url: target.url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = Date()
        let task = session.dataTask(with: request) { _, response, error in
            if error != nil || response == nil {
                completion(nil)
                return
            }
            let ms = Date().timeIntervalSince(start) * 1000.0
            completion(ms)
        }
        task.resume()
    }
}
