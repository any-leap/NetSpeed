import Foundation
import Network

final class LatencyMonitor {
    struct Target {
        let host: String
        let port: UInt16
    }

    let name: String
    let targets: [Target]
    let maxHistory: Int

    private(set) var history: [Double?] = []
    private(set) var current: Double?

    var onUpdate: (() -> Void)?

    private var timer: Timer?
    private let probeQueue = DispatchQueue(label: "netspeed.latency", qos: .utility)

    init(name: String, targets: [(String, UInt16)], maxHistory: Int = 60) {
        self.name = name
        self.targets = targets.map { Target(host: $0.0, port: $0.1) }
        self.maxHistory = maxHistory
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        tick()  // 立即跑一次，不用等 5 秒才出第一个数据点
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
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

    /// 对单个目标做 TCP 半握手计时。成功返回 RTT（ms），失败/超时返回 nil。
    /// completion 一定在 probeQueue 上回调，且至多一次。
    private func probe(_ target: Target, completion: @escaping (Double?) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: target.port) else {
            completion(nil)
            return
        }
        let host = NWEndpoint.Host(target.host)
        let conn = NWConnection(host: host, port: port, using: .tcp)
        let start = Date()
        var fired = false

        let fire: (Double?) -> Void = { value in
            if fired { return }
            fired = true
            conn.cancel()
            completion(value)
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let ms = Date().timeIntervalSince(start) * 1000.0
                fire(ms)
            case .failed, .cancelled:
                fire(nil)
            default:
                break
            }
        }

        conn.start(queue: probeQueue)

        probeQueue.asyncAfter(deadline: .now() + 2.0) {
            fire(nil)
        }
    }
}
