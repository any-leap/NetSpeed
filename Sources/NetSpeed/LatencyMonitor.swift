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

    func start() { /* 在后续 task 填充 */ }
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
}
