# 延迟监控图表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在菜单栏下拉内新增两个独立的延迟折线图（大陆直连链路 + 海外代理链路），通过 TCP connect 半握手计时，每 5 秒后台测量。

**Architecture:** 新增 `LatencyMonitor`（参数化：名字 + 目标列表）并实例化两份；每个实例用 `Timer` 每 5 秒触发一次，`DispatchGroup` 并发对 3 个目标做 TCP connect 探测，取最小 RTT 追加到 60 点滑动窗口。新增 `LatencyChartView` 单线图表（支持 nil 断点），在 `App.swift:rebuildMenu()` 顶端插入两个图表，沿用现有 `liveRefreshers` 机制做活刷新。

**Tech Stack:** Swift 5.9 · AppKit · `Network.framework` (`NWConnection`) · macOS 14+

**Spec:** `docs/superpowers/specs/2026-04-21-latency-chart-design.md`

**Verification style:** 项目无单元测试目标。每步用 `swift build` 检查语法/类型，整合完成后运行应用做 UI/运行时验证。

---

## File Structure

| 文件 | 动作 | 职责 |
|------|------|------|
| `Sources/NetSpeed/Strings.swift` | 修改 | 新增 `latencyMainland` / `latencyOverseas` 本地化字符串 |
| `Sources/NetSpeed/LatencyMonitor.swift` | 新建 | 延迟测量：定时器 + 并发探测 + 历史滑动窗口 |
| `Sources/NetSpeed/LatencyChartView.swift` | 新建 | 单线延迟图（支持 nil 断点） |
| `Sources/NetSpeed/App.swift` | 修改 | 实例化两个 monitor；在 `rebuildMenu()` 顶端加图表；接 `liveRefreshers`；更新 `currentStructureSignature()` |

---

## Task 1: 新增本地化字符串

**Files:**
- Modify: `Sources/NetSpeed/Strings.swift` (在 `network` 那一行附近追加)

- [ ] **Step 1: 编辑 `Sources/NetSpeed/Strings.swift`**

在 `static let network = ...` 下面一行插入：

```swift
    static let latencyMainland = isChinese ? "大陆延迟" : "Mainland Latency"
    static let latencyOverseas = isChinese ? "海外延迟" : "Overseas Latency"
```

- [ ] **Step 2: 编译验证**

运行:
```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`（无错误）

- [ ] **Step 3: 提交**

```bash
git add Sources/NetSpeed/Strings.swift
git commit -m "feat: add latency chart localization strings"
```

---

## Task 2: `LatencyMonitor` 骨架（结构体 + 滑动窗口）

**Files:**
- Create: `Sources/NetSpeed/LatencyMonitor.swift`

- [ ] **Step 1: 新建文件 `Sources/NetSpeed/LatencyMonitor.swift`**

写入全部内容：

```swift
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
```

- [ ] **Step 2: 编译验证**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: 提交**

```bash
git add Sources/NetSpeed/LatencyMonitor.swift
git commit -m "feat: scaffold LatencyMonitor with sliding-window history"
```

---

## Task 3: 单次 TCP 探测（`probe`）

**Files:**
- Modify: `Sources/NetSpeed/LatencyMonitor.swift`

- [ ] **Step 1: 在 `LatencyMonitor` 类内追加 `probe` 方法**

在 `appendResult` 之后添加：

```swift
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
```

- [ ] **Step 2: 编译验证**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

注意：此阶段 `probe` 尚未被调用，编译器可能警告 "never used" —— 这是正常的，Task 4 就会用上。

- [ ] **Step 3: 提交**

```bash
git add Sources/NetSpeed/LatencyMonitor.swift
git commit -m "feat: add TCP connect probe for LatencyMonitor"
```

---

## Task 4: 定时器 + 并发聚合

**Files:**
- Modify: `Sources/NetSpeed/LatencyMonitor.swift`

- [ ] **Step 1: 替换 `start()` 的空壳实现**

把 `func start() { /* 在后续 task 填充 */ }` 替换为：

```swift
    func start() {
        stop()
        tick()  // 立即跑一次，不用等 5 秒才出第一个数据点
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
```

- [ ] **Step 2: 在 `start` 下面追加 `tick` 方法**

```swift
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
```

关键点：
- `group.enter()` 在每个探测前；探测 completion 里 `group.leave()`
- `group.notify(queue: .main)` 保证 `appendResult`（写 history、触发 `onUpdate`）在主线程执行
- 所有探测都失败时 `results` 为空，`results.min()` 是 `nil` → 自然 append nil

- [ ] **Step 3: 编译验证**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 4: 提交**

```bash
git add Sources/NetSpeed/LatencyMonitor.swift
git commit -m "feat: periodic concurrent probing with min-RTT aggregation"
```

---

## Task 5: `LatencyChartView`

**Files:**
- Create: `Sources/NetSpeed/LatencyChartView.swift`

- [ ] **Step 1: 新建文件 `Sources/NetSpeed/LatencyChartView.swift`**

写入全部内容：

```swift
import AppKit

final class LatencyChartView: NSView {
    private var history: [Double?]
    private var currentValue: Double?
    private let maxHistory: Int
    private let title: String
    private let lineColor: NSColor

    init(history: [Double?], maxHistory: Int, current: Double?,
         title: String, lineColor: NSColor) {
        self.history = history
        self.currentValue = current
        self.maxHistory = maxHistory
        self.title = title
        self.lineColor = lineColor
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 90))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(history: [Double?], current: Double?) {
        self.history = history
        self.currentValue = current
        self.needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        let left: CGFloat = 8
        let right: CGFloat = 8
        let top: CGFloat = 20
        let bottom: CGFloat = 6
        let chartW = w - left - right
        let chartH = h - top - bottom

        let nonNil = history.compactMap { $0 }
        let maxVal = max(nonNil.max() ?? 100.0, 100.0)

        // 标题（左上）
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ]).draw(at: NSPoint(x: left, y: 4))

        // 当前值（右上）
        let valueStr: String
        if let c = currentValue {
            valueStr = String(format: "%.0f ms", c)
        } else {
            valueStr = "—"
        }
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let valueAttr = NSAttributedString(string: valueStr, attributes: valueAttrs)
        valueAttr.draw(at: NSPoint(x: w - right - valueAttr.size().width, y: 5))

        // 图区背景
        let chartRect = NSRect(x: left, y: top, width: chartW, height: chartH)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 3, yRadius: 3).fill()

        // 虚线网格
        let dashPattern: [CGFloat] = [2, 3]
        NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
        for i in 1...3 {
            let y = top + chartH * CGFloat(i) / 4.0
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: left, y: y))
            grid.line(to: NSPoint(x: left + chartW, y: y))
            grid.lineWidth = 0.5
            grid.setLineDash(dashPattern, count: 2, phase: 0)
            grid.stroke()
        }

        // 把 history 按 nil 切成若干连续非 nil 段
        let stepX = chartW / CGFloat(max(maxHistory - 1, 1))
        let startX = left + chartW - CGFloat(history.count - 1) * stepX

        var segments: [[NSPoint]] = []
        var currentSeg: [NSPoint] = []
        for (i, v) in history.enumerated() {
            let x = startX + CGFloat(i) * stepX
            if let val = v {
                let y = top + chartH - CGFloat(val / maxVal) * chartH
                currentSeg.append(NSPoint(x: x, y: max(top, min(top + chartH, y))))
            } else if !currentSeg.isEmpty {
                segments.append(currentSeg)
                currentSeg = []
            }
        }
        if !currentSeg.isEmpty { segments.append(currentSeg) }

        // 每段独立绘制平滑曲线
        lineColor.withAlphaComponent(0.9).setStroke()
        for seg in segments {
            guard let first = seg.first else { continue }
            let path = NSBezierPath()
            path.move(to: first)
            for i in 1..<seg.count {
                let prev = seg[i - 1]
                let curr = seg[i]
                let midX = (prev.x + curr.x) / 2
                path.curve(to: curr,
                           controlPoint1: NSPoint(x: midX, y: prev.y),
                           controlPoint2: NSPoint(x: midX, y: curr.y))
            }
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        // Y 轴刻度（max + 0）
        let scaleFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let scaleAttrs: [NSAttributedString.Key: Any] = [
            .font: scaleFont, .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        NSAttributedString(string: String(format: "%.0f ms", maxVal), attributes: scaleAttrs)
            .draw(at: NSPoint(x: left + 2, y: top + 1))
        NSAttributedString(string: "0", attributes: scaleAttrs)
            .draw(at: NSPoint(x: left + 2, y: top + chartH - 12))
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: 提交**

```bash
git add Sources/NetSpeed/LatencyChartView.swift
git commit -m "feat: add LatencyChartView with nil-segment gap rendering"
```

---

## Task 6: 集成到 `App.swift`

**Files:**
- Modify: `Sources/NetSpeed/App.swift`（多处）

### Step 1: 新增字段声明

在 `StatusBarController` 类中 `private var vpnMonitor: VPNMonitor` 下面一行插入：

```swift
    private var latencyMonitorCN: LatencyMonitor
    private var latencyMonitorIntl: LatencyMonitor
    private weak var latencyChartCN: LatencyChartView?
    private weak var latencyChartIntl: LatencyChartView?
```

- [ ] 完成

### Step 2: 在 `init()` 里实例化两个 monitor

在 `vpnMonitor = VPNMonitor()` 下面一行插入：

```swift
        latencyMonitorCN = LatencyMonitor(name: "mainland", targets: [
            ("www.baidu.com", 443),
            ("www.taobao.com", 443),
            ("www.qq.com", 443),
        ])
        latencyMonitorIntl = LatencyMonitor(name: "overseas", targets: [
            ("www.google.com", 443),
            ("www.cloudflare.com", 443),
            ("www.github.com", 443),
        ])
```

- [ ] 完成

### Step 3: 在 `super.init()` 之后挂回调并启动

找到现有的 `vpnMonitor.onDisconnect = { ... }` 代码块上方，在 `super.init()` 之后、`menu.delegate = self` 之前插入：

```swift
        let latencyRefresh: () -> Void = { [weak self] in
            guard let self = self else { return }
            if self.menuIsOpen { self.refreshLiveViews() }
        }
        latencyMonitorCN.onUpdate = latencyRefresh
        latencyMonitorIntl.onUpdate = latencyRefresh
        latencyMonitorCN.start()
        latencyMonitorIntl.start()
```

（`onUpdate` 本身已经在 main queue 上被调用，所以这里不需要再 `DispatchQueue.main.async`。）

- [ ] 完成

### Step 4: 在 `rebuildMenu()` 顶部插入两个图表

定位 `rebuildMenu()` 方法里的这段代码：

```swift
        // --- Network Chart ---
        if netMonitor.downHistory.count >= 2 {
```

在 `// --- Network Chart ---` **之前**插入：

```swift
        // --- Latency Charts (Mainland / Overseas) ---
        if latencyMonitorCN.history.count >= 2 {
            let item = NSMenuItem()
            let view = LatencyChartView(
                history: latencyMonitorCN.history,
                maxHistory: latencyMonitorCN.maxHistory,
                current: latencyMonitorCN.current,
                title: L10n.latencyMainland,
                lineColor: .systemCyan
            )
            item.view = view
            item.isEnabled = false
            self.latencyChartCN = view
            menu.addItem(item)
        }

        if latencyMonitorIntl.history.count >= 2 {
            let item = NSMenuItem()
            let view = LatencyChartView(
                history: latencyMonitorIntl.history,
                maxHistory: latencyMonitorIntl.maxHistory,
                current: latencyMonitorIntl.current,
                title: L10n.latencyOverseas,
                lineColor: .systemPurple
            )
            item.view = view
            item.isEnabled = false
            self.latencyChartIntl = view
            menu.addItem(item)
        }

```

- [ ] 完成

### Step 5: 在 `refreshLiveViews()` 里刷新图表

找到 `refreshLiveViews()` 方法：

```swift
    private func refreshLiveViews() {
        trafficMonitor.update()
        if currentStructureSignature() != structureSignature {
            rebuildMenu()
            return
        }
        chartView?.update(
            ...
        )
        trafficRankView?.update(
            ...
        )
        for r in liveRefreshers { r() }
    }
```

在 `trafficRankView?.update(...)` 那一段**之后**、`for r in liveRefreshers` **之前**插入：

```swift
        latencyChartCN?.update(
            history: latencyMonitorCN.history,
            current: latencyMonitorCN.current
        )
        latencyChartIntl?.update(
            history: latencyMonitorIntl.history,
            current: latencyMonitorIntl.current
        )
```

- [ ] 完成

### Step 6: 更新 `currentStructureSignature()`

找到方法末尾的 return 语句：

```swift
        return "\(vpn)\(vpnHasIP)|\(memCount)|\(cpuCount)|\(chartReady)|\(watchedAlive)"
```

替换为：

```swift
        let latencyCNReady = latencyMonitorCN.history.count >= 2 ? "1" : "0"
        let latencyIntlReady = latencyMonitorIntl.history.count >= 2 ? "1" : "0"
        return "\(vpn)\(vpnHasIP)|\(memCount)|\(cpuCount)|\(chartReady)|\(watchedAlive)|\(latencyCNReady)\(latencyIntlReady)"
```

- [ ] 完成

### Step 7: 编译验证

```bash
swift build 2>&1 | tail -10
```
Expected: `Build complete!`（无错误）

如果报错：多半是某处字段名拼错或位置错。对照这个 task 的代码检查。

- [ ] 完成

### Step 8: 运行时验证

```bash
swift run 2>&1 | tail -20
```

应用启动后：
1. 状态栏应该出现 `↑ ↓` 速度数字（现有功能）
2. 等约 10 秒（让 monitor 累积至少 2 个数据点）
3. 点开菜单栏图标
4. 最顶上应该能看到 **Mainland Latency** 图表（青色），右上角显示 `XX ms`
5. 下面紧跟 **Overseas Latency** 图表（紫色）
6. 再下面是原有的 Network 图表 + 其他内容
7. 保持菜单打开 10-20 秒，观察图表随时间添加新数据点（曲线向左滚动、出现新数据）

验证通过 → 继续下一步。如果图表一直不出现：关菜单等 30 秒再开，让 history 填满到 >=2。

- [ ] 完成

### Step 9: 提交

```bash
git add Sources/NetSpeed/App.swift
git commit -m "feat: integrate mainland/overseas latency charts into menu"
```

---

## 整体验证清单

完成所有 task 后，做一次端到端检查：

- [ ] 菜单顶部有两个延迟图表：Mainland Latency（青色）+ Overseas Latency（紫色）
- [ ] 每个图表右上角显示当前 RTT（如 `23 ms` 或断网时的 `—`）
- [ ] 两个图表下面是原有的 Network 速度图表（布局未错乱）
- [ ] 打开菜单保持不动，约 5 秒后能看到图表追加新数据点
- [ ] 测试断网场景（关 WiFi 后等 10 秒）：两个图应该都显示断点
- [ ] 菜单关闭状态下应用仍在后台测量（再打开时 history 是连续的）
- [ ] 数值合理：大陆图通常 10-40ms，海外图通常 100-300ms（走代理）

---

## 故障排查

| 症状 | 可能原因 |
|------|----------|
| 图表从不出现 | `onUpdate` 回调未触发 / Timer 没跑 → 检查 `start()` 是否被调用、RunLoop mode 是否 `.common` |
| 图表只显示一次就不更新 | `refreshLiveViews` 里没调用 `update` / `weak` 引用被释放 → 确认 `latencyChartCN/Intl` 的 weak 赋值在 `rebuildMenu` 里 |
| 每次打开菜单都闪 | `currentStructureSignature` 没包含 latency ready 标志 → 对照 Task 6 Step 6 |
| 所有值永远是 `—` | 所有 target 都 fail。换 `nc -zv www.baidu.com 443` 在终端验证网络 |
| 大陆图值很高（>100ms） | Clash 规则把 .cn 也代理了 → 用户应该检查 Clash 配置。这不是代码 bug |
