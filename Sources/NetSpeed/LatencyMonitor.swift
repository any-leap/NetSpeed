import Foundation

final class LatencyMonitor: NSObject, URLSessionTaskDelegate {
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

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 3.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Metrics delivered via delegate before the task's completion handler;
    // consumed there to compute a clean HTTP round-trip.
    private var pendingMetrics: [Int: URLSessionTaskMetrics] = [:]
    private let metricsLock = NSLock()

    init(name: String, targets: [String], maxHistory: Int = 60) {
        self.name = name
        self.targets = targets.compactMap { URL(string: $0).map(Target.init) }
        self.maxHistory = maxHistory
        super.init()
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

    // URLSessionTaskDelegate: fires before the task's completion handler.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        metricsLock.lock()
        pendingMetrics[task.taskIdentifier] = metrics
        metricsLock.unlock()
    }

    /// HTTP HEAD via shared URLSession. Uses URLSessionTaskMetrics to extract
    /// pure HTTP round-trip (responseEndDate − requestStartDate), which excludes
    /// TCP/TLS handshake. This gives stable readings regardless of whether the
    /// underlying connection is reused, and avoids measuring Clash TUN's local
    /// short-circuited handshake.
    private func probe(_ target: Target, completion: @escaping (Double?) -> Void) {
        var request = URLRequest(url: target.url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        var capturedTask: URLSessionDataTask?
        capturedTask = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self, let task = capturedTask else {
                completion(nil)
                return
            }

            self.metricsLock.lock()
            let metrics = self.pendingMetrics.removeValue(forKey: task.taskIdentifier)
            self.metricsLock.unlock()

            if error != nil || response == nil {
                completion(nil)
                return
            }

            guard let tx = metrics?.transactionMetrics.last,
                  let reqStart = tx.requestStartDate,
                  let resEnd = tx.responseEndDate else {
                completion(nil)
                return
            }

            let ms = resEnd.timeIntervalSince(reqStart) * 1000.0
            completion(ms)
        }
        capturedTask?.resume()
    }
}
