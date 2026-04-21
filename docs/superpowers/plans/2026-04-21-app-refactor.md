# App.swift 重构：数据驱动菜单 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 663 行的 `StatusBarController` 拆成数据驱动的菜单章节 + 独立的 `VPNController` / `NotificationHelper` / `MenuActions`，行为完全不变。

**Architecture:** 每个菜单章节实现 `MenuSection` 协议（`structureSignature` / `addItems(to:)` / `refresh()`）。`MenuBuilder` 遍历 section 列表，自动在非空章节间插分隔符。`StatusBarController` 降级成协调器。

**Tech Stack:** Swift 5.9 · AppKit · Swift Package Manager · 无新依赖

**Spec:** `docs/superpowers/specs/2026-04-21-app-refactor-design.md`

**Verification style:** 每步 `swift build -c release` + `make reload` + 手动打开菜单确认没 regression。无单元测试（项目无测试 target，UI 测试 ROI 低）。

---

## File Structure

| 文件 | 动作 | 职责 |
|------|------|------|
| `Sources/NetSpeed/App.swift` | 大幅精简 | `StatusBarController`（协调器，≤ 120 行）+ `AppDelegate` + `@main` |
| `Sources/NetSpeed/NotificationHelper.swift` | 新建 | osascript 通知包装 |
| `Sources/NetSpeed/VPNController.swift` | 新建 | OpenVPN 连/断 + 配置文件 prompt |
| `Sources/NetSpeed/MenuBuilder.swift` | 新建 | `MenuSection` 协议 + `MenuBuilder` |
| `Sources/NetSpeed/MenuActions.swift` | 新建 | 所有 `@objc` 菜单动作（kill / quit / resetTraffic / toggleVPN） |
| `Sources/NetSpeed/Sections/LatencyChartSection.swift` | 新建 | 实例化两份 mainland / overseas |
| `Sources/NetSpeed/Sections/NetworkChartSection.swift` | 新建 | 网络速度图 |
| `Sources/NetSpeed/Sections/WatchedProcessesSection.swift` | 新建 | 被监控进程状态 |
| `Sources/NetSpeed/Sections/VPNSection.swift` | 新建 | VPN 状态 + 连断按钮 |
| `Sources/NetSpeed/Sections/TrafficRankSection.swift` | 新建 | 流量排行 + reset |
| `Sources/NetSpeed/Sections/MemorySection.swift` | 新建 | 内存 + top 5 进程 |
| `Sources/NetSpeed/Sections/CPUSection.swift` | 新建 | CPU + top 进程 |
| `Sources/NetSpeed/Sections/AbnormalProcessesSection.swift` | 新建 | CPUGuard 异常进程（条件） |
| `Sources/NetSpeed/Sections/RecentAlertsSection.swift` | 新建 | 最近告警（条件） |
| `Sources/NetSpeed/Sections/QuitSection.swift` | 新建 | Quit 按钮 |

SPM 5.3+ 自动递归扫描 target 目录，`Sections/` 子目录不用改 `Package.swift`。

---

## Task 1: 抽出 `NotificationHelper`

**Files:**
- Create: `Sources/NetSpeed/NotificationHelper.swift`
- Modify: `Sources/NetSpeed/App.swift`（删除 `sendNotification`，调用点改为 `notifier.send`）

### Step 1: 新建 `Sources/NetSpeed/NotificationHelper.swift`

```swift
import Foundation

final class NotificationHelper {
    func send(title: String, message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\" sound name \"Sosumi\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`

在 `StatusBarController` 的字段块（`private var latencyMonitorIntl: LatencyMonitor` 那行之后）加一行：

```swift
    private let notifier = NotificationHelper()
```

找到 `vpnMonitor.onDisconnect = { [weak self] in ... }` 块，把内部的 `self?.sendNotification(title:message:)` 改成 `self?.notifier.send(title:message:)`：

```swift
        vpnMonitor.onDisconnect = { [weak self] in
            self?.notifier.send(
                title: "VPN Disconnected",
                message: "OpenVPN connection has been lost"
            )
        }
```

然后**删除** `StatusBarController` 内的整个 `sendNotification(title:message:)` 私有方法（大约 10 行，从 `private func sendNotification(title: String, message: String) {` 到对应的 `}`）。

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make build
make reload
make logs
```

Expected: `Build complete!`（零警告）。菜单栏图标显示正常；断开 VPN 会弹通知（可 `/tmp/openvpn.log` 里手动触发 `killall openvpn` 测）。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/NotificationHelper.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract NotificationHelper from StatusBarController"
```

- [ ] 完成

---

## Task 2: 抽出 `VPNController`

**Files:**
- Create: `Sources/NetSpeed/VPNController.swift`
- Modify: `Sources/NetSpeed/App.swift`（删除 VPN 相关私有方法与 UserDefaults 常量）

### Step 1: 新建 `Sources/NetSpeed/VPNController.swift`

```swift
import AppKit
import Foundation

final class VPNController {
    private let monitor: VPNMonitor
    private let notifier: NotificationHelper

    private static let vpnConfigKey = "vpnConfigPath"
    private static let vpnAuthKey = "vpnAuthPath"

    /// 2 秒后触发一次 monitor.update() + 菜单刷新。
    /// 由 StatusBarController 注入（toggleVPN 之后需要刷菜单状态）。
    var onToggleCompleted: (() -> Void)?

    init(monitor: VPNMonitor, notifier: NotificationHelper) {
        self.monitor = monitor
        self.notifier = notifier
    }

    var isConnected: Bool { monitor.status.connected }

    func toggle() {
        if monitor.status.connected {
            disconnect()
        } else {
            connect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.monitor.update()
            self?.onToggleCompleted?()
        }
    }

    // MARK: - private

    private var vpnConfigPath: String? {
        UserDefaults.standard.string(forKey: Self.vpnConfigKey)
    }

    private var vpnAuthPath: String {
        UserDefaults.standard.string(forKey: Self.vpnAuthKey)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".openvpn-auth").path
    }

    private func disconnect() {
        let script = "do shell script \"killall openvpn\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func connect() {
        guard let configPath = vpnConfigPath ?? promptForConfig() else { return }
        let cfg = shellQuote(configPath)
        let auth = shellQuote(vpnAuthPath)
        let cmd = "/opt/homebrew/sbin/openvpn --daemon --log /tmp/openvpn.log --config \(cfg) --auth-user-pass \(auth)"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func promptForConfig() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Select OpenVPN config (.ovpn)"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: Self.vpnConfigKey)
        return url.path
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`：增加 `vpnController` 字段

在 `StatusBarController` 的字段块（之前加的 `notifier` 下面）加：

```swift
    private let vpnController: VPNController
```

注意：不能直接 `private let vpnController = VPNController(...)`，因为它依赖 `vpnMonitor` 和 `notifier`，需要在 `init` 里构造。

在 `init` 里，`vpnMonitor = VPNMonitor()` 之后**立刻**加：

```swift
        vpnController = VPNController(monitor: vpnMonitor, notifier: notifier)
```

Wait — `notifier` 是 `let notifier = NotificationHelper()`，可以直接在属性声明时赋值，所以上面 `vpnController` init 时 `notifier` 已经存在。但 `vpnMonitor` 是在 init body 里赋值的。解决办法：把 `vpnController` 也改成在 `super.init()` **之后**赋值，并改成 `var`（因为 init 前不能用 self）。

改回法：

```swift
    private var vpnController: VPNController!
```

在 `super.init()` 之后加：

```swift
        vpnController = VPNController(monitor: vpnMonitor, notifier: notifier)
        vpnController.onToggleCompleted = { [weak self] in
            self?.rebuildMenu()
        }
```

- [ ] 完成

### Step 3: `App.swift`：改 `@objc toggleVPN()`

把原来 60+ 行的 `@objc func toggleVPN()` **替换**为一行转发：

```swift
    @objc func toggleVPN() {
        vpnController.toggle()
    }
```

- [ ] 完成

### Step 4: `App.swift`：删除无用字段和方法

删除以下内容（都已经搬到 `VPNController` 里）：

- `private static let vpnConfigKey = "vpnConfigPath"`
- `private static let vpnAuthKey = "vpnAuthPath"`
- `private var vpnConfigPath: String?` 计算属性
- `private var vpnAuthPath: String` 计算属性
- `private func promptForVPNConfig() -> String?`
- `private func shellQuote(_ s: String) -> String`

- [ ] 完成

### Step 5: 编译 + 验证

```bash
make reload
```

Expected: `Build complete!`。VPN 菜单按钮点"连接"会弹 OpenVPN 配置选择；已选过 `.ovpn` 再点"断开"会触发特权弹窗并断开。

- [ ] 完成

### Step 6: Commit

```bash
git add Sources/NetSpeed/VPNController.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract VPNController from StatusBarController"
```

- [ ] 完成

---

## Task 3: 定义 `MenuSection` 协议 + `MenuBuilder`（空壳）

**Files:**
- Create: `Sources/NetSpeed/MenuBuilder.swift`

### Step 1: 新建 `Sources/NetSpeed/MenuBuilder.swift`

```swift
import AppKit

/// 一个菜单章节。实现者负责自己的 NSMenuItem 生命周期（强引用 item，供 refresh 更新）。
protocol MenuSection: AnyObject {
    /// 变化会影响菜单结构的摘要。相同 = 可原地 refresh；不同 = 必须 rebuild。
    var structureSignature: String { get }

    /// 追加本章节的菜单项到 menu。返回 true 表示本次有内容（MenuBuilder
    /// 会在相邻非空章节间插分隔符）；false = 空章节（条件性章节常用）。
    func addItems(to menu: NSMenu) -> Bool

    /// 菜单打开期间的原地刷新。实现者用自己保存的 item 引用更新 title / color 等。
    func refresh()
}

extension MenuSection {
    /// 默认每个章节前都要分隔符。latency/network 等合并展示的章节可覆盖为 false。
    var needsLeadingSeparator: Bool { true }
}

final class MenuBuilder {
    private let menu: NSMenu
    private(set) var sections: [MenuSection]

    init(menu: NSMenu, sections: [MenuSection]) {
        self.menu = menu
        self.sections = sections
    }

    func rebuild() {
        menu.removeAllItems()
        var previousAdded = false
        for section in sections {
            if previousAdded && section.needsLeadingSeparator {
                menu.addItem(NSMenuItem.separator())
            }
            let added = section.addItems(to: menu)
            if added { previousAdded = true }
        }
    }

    func refresh() {
        for section in sections { section.refresh() }
    }

    var structureSignature: String {
        sections.map(\.structureSignature).joined(separator: "|")
    }
}
```

注意：`MenuSection` 协议中的 `needsLeadingSeparator` 放到 extension 里默认 `true`；个别 section 会覆盖为 `false`（latency / network chart 这三个紧挨着不要分隔符）。

- [ ] 完成

### Step 2: 编译验证（此时没人用它）

```bash
swift build -c release 2>&1 | tail -3
```

Expected: `Build complete!`（可能有 "unused" 警告，正常）。

- [ ] 完成

### Step 3: Commit

```bash
git add Sources/NetSpeed/MenuBuilder.swift
git commit -m "refactor: add MenuSection protocol and MenuBuilder scaffold"
```

- [ ] 完成

---

## Task 4: 抽出 `MenuActions`

**Files:**
- Create: `Sources/NetSpeed/MenuActions.swift`
- Modify: `Sources/NetSpeed/App.swift`（`@objc` 方法改成 MenuActions 调用）

### Step 1: 新建 `Sources/NetSpeed/MenuActions.swift`

```swift
import AppKit
import Foundation

/// 集中所有菜单动作的 `@objc` 方法。section 构造菜单项时把 `target` 指向本类。
final class MenuActions: NSObject {
    private let cpuMonitor: CPUMonitor
    private let trafficMonitor: TrafficMonitor
    private let vpnController: VPNController
    /// menu rebuild 回调（kill / resetTraffic 之后菜单要刷）
    var onNeedsRebuild: (() -> Void)?

    init(cpuMonitor: CPUMonitor,
         trafficMonitor: TrafficMonitor,
         vpnController: VPNController) {
        self.cpuMonitor = cpuMonitor
        self.trafficMonitor = trafficMonitor
        self.vpnController = vpnController
        super.init()
    }

    @objc func killProcess(_ sender: NSMenuItem) {
        let pid = sender.tag
        let result = kill(Int32(pid), SIGTERM)
        if result != 0 {
            let script = "do shell script \"kill \(pid)\" with administrator privileges"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
        cpuMonitor.update()
        onNeedsRebuild?()
    }

    @objc func resetTraffic() {
        trafficMonitor.reset()
        onNeedsRebuild?()
    }

    @objc func toggleVPN() {
        vpnController.toggle()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`：增加 `actions` 字段 + 创建

在 `StatusBarController` 字段块加：

```swift
    private var actions: MenuActions!
```

在 `super.init()` + `vpnController = VPNController(...)` 之后加：

```swift
        actions = MenuActions(
            cpuMonitor: cpuMonitor,
            trafficMonitor: trafficMonitor,
            vpnController: vpnController
        )
        actions.onNeedsRebuild = { [weak self] in self?.rebuildMenu() }
```

同时把之前 `vpnController.onToggleCompleted = { ... self?.rebuildMenu() }` 也改成：

```swift
        vpnController.onToggleCompleted = { [weak self] in self?.rebuildMenu() }
```

（已经是这样了，无需改。）

- [ ] 完成

### Step 3: 修改 `App.swift`：替换所有 `#selector` 目标

搜 `rebuildMenu()` 内所有引用 `self` 作为 `.target` 的地方（共 6 处），改成 `actions`：

`rebuildMenu()` 的**所有这些代码行**：
```swift
killItem.target = self
disconnectItem.target = self
connectItem.target = self
resetItem.target = self
killItem.target = self       // 出现 3 次：watched、memory、cpu
item.target = self           // abnormal processes 里的
quitItem.target = self
```

都改成：
```swift
killItem.target = actions
disconnectItem.target = actions
// ... 等等
```

同时 `#selector(killProcess(_:))` 等引用会自动通过 `actions` 的同名方法解析——**不用改 selector**（Swift 查找 `actions` 对象上的 `@objc killProcess:`）。

**具体替换清单**（`rebuildMenu()` 内）：

| 旧 | 新 |
|------|------|
| `killItem.target = self`（Watched procs 的 restart item） | `killItem.target = actions` |
| `disconnectItem.target = self`（VPN 断开） | `disconnectItem.target = actions` |
| `connectItem.target = self`（VPN 连接） | `connectItem.target = actions` |
| `resetItem.target = self`（Reset traffic） | `resetItem.target = actions` |
| `killItem.target = self`（Memory 的子菜单 kill） | `killItem.target = actions` |
| `killItem.target = self`（CPU 的子菜单 kill） | `killItem.target = actions` |
| `item.target = self`（Abnormal procs 的 kill） | `item.target = actions` |
| `quitItem.target = self` | `quitItem.target = actions` |

- [ ] 完成

### Step 4: 修改 `App.swift`：删除 StatusBarController 上的 `@objc` 方法

删除以下整个方法（它们已移到 `MenuActions`）：

- `@objc func killProcess(_ sender: NSMenuItem)`
- `@objc func resetTraffic()`
- `@objc func toggleVPN()`（已简化成一行，但现在连这行也删）
- `@objc func quit()`
- `@objc func noop()`（从来没被引用过，顺便删）

注意 `StatusBarController` 仍需要 `NSObject` + `NSMenuDelegate`（保留 `class StatusBarController: NSObject, NSMenuDelegate` 签名，以及 `menuWillOpen` / `menuDidClose`）。

- [ ] 完成

### Step 5: 编译 + 验证

```bash
make reload
```

Expected: `Build complete!`。打开菜单 → kill 任意进程、reset traffic、toggle VPN、quit 都能工作。

- [ ] 完成

### Step 6: Commit

```bash
git add Sources/NetSpeed/MenuActions.swift Sources/NetSpeed/App.swift
git commit -m "refactor: centralize @objc menu actions in MenuActions"
```

- [ ] 完成

---

## Task 5: 抽出 `QuitSection`（最简单，打通路径）

**Files:**
- Create: `Sources/NetSpeed/Sections/QuitSection.swift`
- Modify: `Sources/NetSpeed/App.swift`（`rebuildMenu()` 的 quit 块换成调用）

### Step 1: 创建目录 + 文件 `Sources/NetSpeed/Sections/QuitSection.swift`

```swift
import AppKit

final class QuitSection: MenuSection {
    private let actions: MenuActions

    init(actions: MenuActions) {
        self.actions = actions
    }

    var structureSignature: String { "Q" }

    func addItems(to menu: NSMenu) -> Bool {
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(MenuActions.quit), keyEquivalent: "q")
        quitItem.target = actions
        menu.addItem(quitItem)
        return true
    }

    func refresh() {
        // Quit 菜单无需刷新
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`：在 rebuildMenu 里换掉 quit 块

找到 `rebuildMenu()` 末尾的 quit 块：

```swift
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
```

替换为：

```swift
        menu.addItem(NSMenuItem.separator())
        _ = quitSection.addItems(to: menu)
```

在 `StatusBarController` 字段块加：

```swift
    private var quitSection: QuitSection!
```

在 `init()` 的 `actions = MenuActions(...)` 之后加：

```swift
        quitSection = QuitSection(actions: actions)
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: `Build complete!`。打开菜单，Quit 在底部，点击能退出。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/QuitSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract QuitSection"
```

- [ ] 完成

---

## Task 6: 抽出 `LatencyChartSection`（两实例）

**Files:**
- Create: `Sources/NetSpeed/Sections/LatencyChartSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/LatencyChartSection.swift`

```swift
import AppKit

final class LatencyChartSection: MenuSection {
    private let monitor: LatencyMonitor
    private let title: String
    private let lineColor: NSColor
    private weak var chartView: LatencyChartView?

    init(monitor: LatencyMonitor, title: String, lineColor: NSColor) {
        self.monitor = monitor
        self.title = title
        self.lineColor = lineColor
    }

    var structureSignature: String {
        monitor.history.count >= 2 ? "1" : "0"
    }

    /// 与上一章节（另一个 latency / network 图）合并展示，不需要分隔符
    var needsLeadingSeparator: Bool { false }

    func addItems(to menu: NSMenu) -> Bool {
        guard monitor.history.count >= 2 else { return false }
        let item = NSMenuItem()
        let view = LatencyChartView(
            history: monitor.history,
            maxHistory: monitor.maxHistory,
            current: monitor.current,
            title: title,
            lineColor: lineColor
        )
        item.view = view
        item.isEnabled = false
        chartView = view
        menu.addItem(item)
        return true
    }

    func refresh() {
        chartView?.update(history: monitor.history, current: monitor.current)
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`：创建两个 section 实例 + 替换两个图块

在 `StatusBarController` 字段块加（替换掉 `private weak var latencyChartCN: LatencyChartView?` 和 `latencyChartIntl`）：

```swift
    private var latencyChartCNSection: LatencyChartSection!
    private var latencyChartIntlSection: LatencyChartSection!
```

**删除**：
```swift
    private weak var latencyChartCN: LatencyChartView?
    private weak var latencyChartIntl: LatencyChartView?
```

在 `init()` 的 `quitSection = QuitSection(...)` 之后加：

```swift
        latencyChartCNSection = LatencyChartSection(
            monitor: latencyMonitorCN,
            title: L10n.latencyMainland,
            lineColor: .systemCyan
        )
        latencyChartIntlSection = LatencyChartSection(
            monitor: latencyMonitorIntl,
            title: L10n.latencyOverseas,
            lineColor: .systemPurple
        )
```

在 `rebuildMenu()` 中，**删除**：

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

用这个代替：

```swift
        // --- Latency Charts (Mainland / Overseas) ---
        _ = latencyChartCNSection.addItems(to: menu)
        _ = latencyChartIntlSection.addItems(to: menu)
```

在 `refreshLiveViews()` 中，**删除**：

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

用这个代替：

```swift
        latencyChartCNSection.refresh()
        latencyChartIntlSection.refresh()
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: `Build complete!`。菜单顶部的两个延迟图外观和行为完全一样；打开菜单过几秒能看到数据刷新。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/LatencyChartSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract LatencyChartSection"
```

- [ ] 完成

---

## Task 7: 抽出 `NetworkChartSection`

**Files:**
- Create: `Sources/NetSpeed/Sections/NetworkChartSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/NetworkChartSection.swift`

```swift
import AppKit

final class NetworkChartSection: MenuSection {
    private let monitor: NetMonitor
    private weak var chartView: ChartView?

    init(monitor: NetMonitor) {
        self.monitor = monitor
    }

    var structureSignature: String {
        monitor.downHistory.count >= 2 ? "1" : "0"
    }

    var needsLeadingSeparator: Bool { false }  // 与 latency 图合并展示

    func addItems(to menu: NSMenu) -> Bool {
        guard monitor.downHistory.count >= 2 else { return false }
        let chartItem = NSMenuItem()
        let view = ChartView(
            downData: monitor.downHistory,
            upData: monitor.upHistory,
            maxHistory: monitor.maxHistory,
            downLabel: "↓ \(monitor.downSpeed)",
            upLabel: "↑ \(monitor.upSpeed)",
            title: L10n.network,
            formatMax: { [weak monitor] v in monitor?.formatSpeed(v) ?? "" }
        )
        chartItem.view = view
        chartItem.isEnabled = false
        chartView = view
        menu.addItem(chartItem)
        return true
    }

    func refresh() {
        chartView?.update(
            downData: monitor.downHistory,
            upData: monitor.upHistory,
            downLabel: "↓ \(monitor.downSpeed)",
            upLabel: "↑ \(monitor.upSpeed)"
        )
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`

字段块加：
```swift
    private var networkChartSection: NetworkChartSection!
```

**删除**：
```swift
    private weak var chartView: ChartView?
```

init 中加：
```swift
        networkChartSection = NetworkChartSection(monitor: netMonitor)
```

`rebuildMenu()` 里，**删除**整块：
```swift
        // --- Network Chart ---
        if netMonitor.downHistory.count >= 2 {
            let chartItem = NSMenuItem()
            let chartView = ChartView(
                downData: netMonitor.downHistory,
                upData: netMonitor.upHistory,
                maxHistory: netMonitor.maxHistory,
                downLabel: "↓ \(netMonitor.downSpeed)",
                upLabel: "↑ \(netMonitor.upSpeed)",
                title: L10n.network,
                formatMax: { [weak self] v in self?.netMonitor.formatSpeed(v) ?? "" }
            )
            chartItem.view = chartView
            chartItem.isEnabled = false
            self.chartView = chartView
            menu.addItem(chartItem)
        }
```

用这个代替：
```swift
        // --- Network Chart ---
        _ = networkChartSection.addItems(to: menu)
```

`refreshLiveViews()` 里，**删除**：
```swift
        chartView?.update(
            downData: netMonitor.downHistory,
            upData: netMonitor.upHistory,
            downLabel: "↓ \(netMonitor.downSpeed)",
            upLabel: "↑ \(netMonitor.upSpeed)"
        )
```

用这个代替：
```swift
        networkChartSection.refresh()
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: 菜单里网络速度图依然正常，数据每 2s 刷。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/NetworkChartSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract NetworkChartSection"
```

- [ ] 完成

---

## Task 8: 抽出 `WatchedProcessesSection`

**Files:**
- Create: `Sources/NetSpeed/Sections/WatchedProcessesSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/WatchedProcessesSection.swift`

```swift
import AppKit

final class WatchedProcessesSection: MenuSection {
    private let cpuMonitor: CPUMonitor
    private let actions: MenuActions

    init(cpuMonitor: CPUMonitor, actions: MenuActions) {
        self.cpuMonitor = cpuMonitor
        self.actions = actions
    }

    var structureSignature: String {
        let procs = cpuMonitor.readTopProcesses(count: 500)
        return cpuMonitor.watchedProcesses.map { name in
            procs.contains(where: { $0.name == name }) ? "1" : "0"
        }.joined()
    }

    func addItems(to menu: NSMenu) -> Bool {
        guard !cpuMonitor.watchedProcesses.isEmpty else { return false }
        let procs = cpuMonitor.readTopProcesses(count: 500)
        for name in cpuMonitor.watchedProcesses {
            let proc = procs.first { $0.name == name }
            let alive = proc != nil
            let status = alive ? "✓ \(name) \(L10n.running)" : "✗ \(name) \(L10n.notRunning)"
            let color: NSColor = alive ? .systemGreen : .systemRed
            let item = NSMenuItem(title: "  \(status)", action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: "  \(status)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: color,
            ])
            if let proc = proc {
                let sub = NSMenu()
                let restartLabel = L10n.isChinese ? "重启 \(name)" : "Restart \(name)"
                let killItem = NSMenuItem(title: restartLabel, action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
                killItem.target = actions
                killItem.tag = proc.pid
                sub.addItem(killItem)
                item.submenu = sub
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
        }
        return true
    }

    func refresh() {
        // 每个被监控进程的存活状态变化会改 structureSignature → rebuild 不走 refresh。
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`

字段块加：
```swift
    private var watchedSection: WatchedProcessesSection!
```

init 中加：
```swift
        watchedSection = WatchedProcessesSection(cpuMonitor: cpuMonitor, actions: actions)
```

`rebuildMenu()` 里，**删除**：
```swift
        // --- Watched processes (e.g. bird) ---
        menu.addItem(NSMenuItem.separator())
        let watchedProcs = cpuMonitor.readTopProcesses(count: 500)
        for name in cpuMonitor.watchedProcesses {
            // ... 全部
            menu.addItem(item)
        }
```

用这个代替：
```swift
        // --- Watched processes ---
        menu.addItem(NSMenuItem.separator())
        _ = watchedSection.addItems(to: menu)
```

**注意**：原来 `currentStructureSignature()` 里有个 `watchedAliveMask()` 的 `cachedWatchedProcs` 缓存，新 section 的 `structureSignature` 没缓存——会导致每次 signature 计算多调用一次 `readTopProcesses(count: 500)`。没事，`readTopProcesses` 本来就是拿来调用的；而且 refreshLiveViews 频率是 2s 一次。如果以后发现性能问题，可以在 section 内加缓存。

把 StatusBarController 里的 `cachedWatchedProcs` 和 `watchedAliveMask()` 方法都**删除**（放在 `currentStructureSignature()` 调用处下面那两个方法）。

**注意**：`currentStructureSignature()` 里的 `watchedAliveMask()` 调用改成直接计算：

```swift
    private func currentStructureSignature() -> String {
        let vpn = vpnMonitor.status.connected ? "VC" : "VD"
        let vpnHasIP = (vpnMonitor.status.localIP != nil && vpnMonitor.status.interfaceName != nil) ? "1" : "0"
        let memCount = memMonitor.topProcesses.count
        let cpuCount = cpuMonitor.topProcesses.count
        let chartReady = netMonitor.downHistory.count >= 2 ? "1" : "0"
        let watchedAlive = watchedSection.structureSignature
        let latencyCNReady = latencyChartCNSection.structureSignature
        let latencyIntlReady = latencyChartIntlSection.structureSignature
        return "\(vpn)\(vpnHasIP)|\(memCount)|\(cpuCount)|\(chartReady)|\(watchedAlive)|\(latencyCNReady)\(latencyIntlReady)"
    }
```

同时把 `watchedAliveMask()` 和 `cachedWatchedProcs` 那两行也**删除**。

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: 菜单中 Watched Processes 段（bird 等）显示正常，存活/崩溃标记正确，右键能重启。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/WatchedProcessesSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract WatchedProcessesSection"
```

- [ ] 完成

---

## Task 9: 抽出 `VPNSection`

**Files:**
- Create: `Sources/NetSpeed/Sections/VPNSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/VPNSection.swift`

```swift
import AppKit

final class VPNSection: MenuSection {
    private let monitor: VPNMonitor
    private let actions: MenuActions

    // 用于 refresh 原地更新（仅在 connected 状态下有值）
    private weak var speedItem: NSMenuItem?
    private weak var totalItem: NSMenuItem?

    init(monitor: VPNMonitor, actions: MenuActions) {
        self.monitor = monitor
        self.actions = actions
    }

    var structureSignature: String {
        let conn = monitor.status.connected ? "VC" : "VD"
        let hasIP = (monitor.status.localIP != nil && monitor.status.interfaceName != nil) ? "1" : "0"
        return "\(conn)\(hasIP)"
    }

    func addItems(to menu: NSMenu) -> Bool {
        let vpn = monitor.status
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        speedItem = nil
        totalItem = nil

        if vpn.connected {
            let vpnHeader = "\(L10n.vpn): \(L10n.vpnConnected)"
            addHeader(vpnHeader, font: headerFont, to: menu)

            if let ip = vpn.localIP, let iface = vpn.interfaceName {
                let detailStr = "  \(iface)  \(ip)"
                let item = NSMenuItem(title: detailStr, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(string: detailStr, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.systemGreen,
                ])
                menu.addItem(item)
            }

            let sItem = NSMenuItem()
            sItem.isEnabled = false
            menu.addItem(sItem)
            let tItem = NSMenuItem()
            tItem.isEnabled = false
            menu.addItem(tItem)
            speedItem = sItem
            totalItem = tItem
            applyRows()

            let disconnectLabel = L10n.vpnDisconnectAction
            let disconnectItem = NSMenuItem(title: disconnectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
            disconnectItem.target = actions
            disconnectItem.attributedTitle = NSAttributedString(string: "  \(disconnectLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemRed,
            ])
            menu.addItem(disconnectItem)
        } else {
            let vpnHeader = "\(L10n.vpn): \(L10n.vpnDisconnected)"
            let item = NSMenuItem(title: vpnHeader, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(string: vpnHeader, attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.systemRed,
            ])
            menu.addItem(item)

            let connectLabel = L10n.vpnConnectAction
            let connectItem = NSMenuItem(title: connectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
            connectItem.target = actions
            connectItem.attributedTitle = NSAttributedString(string: "  \(connectLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.systemGreen,
            ])
            menu.addItem(connectItem)
        }
        return true
    }

    func refresh() {
        applyRows()
    }

    private func applyRows() {
        guard let s = speedItem, let t = totalItem else { return }
        let speedFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let v = monitor.status
        let sp = "  ↓ \(VPNMonitor.formatSpeed(monitor.speedIn))  ↑ \(VPNMonitor.formatSpeed(monitor.speedOut))"
        s.attributedTitle = NSAttributedString(string: sp, attributes: [
            .font: speedFont, .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let tt = "  ↓ \(VPNMonitor.formatBytes(v.bytesIn))  ↑ \(VPNMonitor.formatBytes(v.bytesOut))"
        t.attributedTitle = NSAttributedString(string: tt, attributes: [
            .font: speedFont, .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    @discardableResult
    private func addHeader(_ title: String, font: NSFont, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        menu.addItem(item)
        return item
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`

字段块加：
```swift
    private var vpnSection: VPNSection!
```

init 中加（`watchedSection = ...` 之后）：
```swift
        vpnSection = VPNSection(monitor: vpnMonitor, actions: actions)
```

`rebuildMenu()` 里，**删除**整块（从 `// --- VPN Status ---` 到对应的 `}` 末尾，包含 `else` 分支，共约 70 行）。

用这个代替：
```swift
        // --- VPN Status ---
        menu.addItem(NSMenuItem.separator())
        _ = vpnSection.addItems(to: menu)
```

在 `refreshLiveViews()` 里加（在 latency 的 refresh 之后）：
```swift
        vpnSection.refresh()
```

同时**删除** refreshLiveViews 里 `for r in liveRefreshers { r() }` 下面的所有相关代码，但先检查 `liveRefreshers` 是否还被其他 section 引用（本 PR 还没做完，保留 `liveRefreshers` 逻辑）。具体：在 refreshLiveViews 里找到原 VPN 那个 `applyVPNRows` 相关的 liveRefreshers 操作。由于 `applyVPNRows` 是在 rebuildMenu 里 `liveRefreshers.append(applyVPNRows)`，这段 `append` 会随删除 VPN 块一起删除——不需要额外操作。

**更新 `currentStructureSignature()`** —— 把 vpn 和 vpnHasIP 的计算改成：

```swift
        let vpnSig = vpnSection.structureSignature   // 返回 "VC1" / "VD0" 等
```

把原来的 `let vpn = ...` + `let vpnHasIP = ...` + `"\(vpn)\(vpnHasIP)|..."` 改成用 `vpnSig` 开头：

```swift
    private func currentStructureSignature() -> String {
        let memCount = memMonitor.topProcesses.count
        let cpuCount = cpuMonitor.topProcesses.count
        let chartReady = netMonitor.downHistory.count >= 2 ? "1" : "0"
        let watchedAlive = watchedSection.structureSignature
        let latencyCNReady = latencyChartCNSection.structureSignature
        let latencyIntlReady = latencyChartIntlSection.structureSignature
        return "\(vpnSection.structureSignature)|\(memCount)|\(cpuCount)|\(chartReady)|\(watchedAlive)|\(latencyCNReady)\(latencyIntlReady)"
    }
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: VPN 未连接时显示"未连接"+"连接"按钮；已连接时显示 IP/接口/实时上下行速度/累计字节+"断开"按钮。行为跟重构前一样。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/VPNSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract VPNSection"
```

- [ ] 完成

---

## Task 10: 抽出 `TrafficRankSection`

**Files:**
- Create: `Sources/NetSpeed/Sections/TrafficRankSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/TrafficRankSection.swift`

```swift
import AppKit

final class TrafficRankSection: MenuSection {
    private let trafficMonitor: TrafficMonitor
    private let actions: MenuActions
    private weak var headerItem: NSMenuItem?
    private weak var rankView: TrafficRankView?

    init(trafficMonitor: TrafficMonitor, actions: MenuActions) {
        self.trafficMonitor = trafficMonitor
        self.actions = actions
    }

    var structureSignature: String { "T" }   // 不影响结构，只影响内容

    func addItems(to menu: NSMenu) -> Bool {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        headerItem = h
        applyHeader()

        let rankItem = NSMenuItem()
        let view = TrafficRankView(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
        rankItem.view = view
        rankItem.isEnabled = false
        menu.addItem(rankItem)
        rankView = view

        let resetItem = NSMenuItem(title: "  \(L10n.resetTraffic)", action: #selector(MenuActions.resetTraffic), keyEquivalent: "r")
        resetItem.target = actions
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemBlue,
        ]
        resetItem.attributedTitle = NSAttributedString(string: "  \(L10n.resetTraffic)", attributes: resetAttrs)
        menu.addItem(resetItem)

        _ = headerFont  // silence unused warning if it happens
        return true
    }

    func refresh() {
        applyHeader()
        rankView?.update(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
    }

    private func applyHeader() {
        guard let h = headerItem else { return }
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let title: String
        if let resetTime = trafficMonitor.resetTime {
            let elapsed = Int(Date().timeIntervalSince(resetTime))
            title = "\(L10n.trafficByProcess)  (\(L10n.sinceDuration(elapsed)))"
        } else {
            title = L10n.trafficByProcess
        }
        h.attributedTitle = NSAttributedString(string: title, attributes: [.font: headerFont])
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`

字段块加：
```swift
    private var trafficRankSection: TrafficRankSection!
```

**删除**：
```swift
    private weak var trafficRankView: TrafficRankView?
```

init 中加：
```swift
        trafficRankSection = TrafficRankSection(trafficMonitor: trafficMonitor, actions: actions)
```

`rebuildMenu()` 里，**删除** Traffic 整块（从 `// --- Traffic by Process ---` 到 `menu.addItem(NSMenuItem.separator())` 之前，约 35 行）。

用这个代替：
```swift
        // --- Traffic by Process ---
        menu.addItem(NSMenuItem.separator())
        _ = trafficRankSection.addItems(to: menu)
```

`refreshLiveViews()` 里，**删除**：
```swift
        trafficRankView?.update(
            liveTop: trafficMonitor.topByLive,
            cumulativeTop: trafficMonitor.topByCumulative
        )
```

用这个代替（放在 vpnSection.refresh() 后）：
```swift
        trafficRankSection.refresh()
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: Traffic 区块显示正常，实时/累计双栏，点 "Reset Traffic" 能重置。打开菜单 2-3s 后观察数据变化刷新。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/TrafficRankSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract TrafficRankSection"
```

- [ ] 完成

---

## Task 11: 抽出 `MemorySection`

**Files:**
- Create: `Sources/NetSpeed/Sections/MemorySection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/MemorySection.swift`

```swift
import AppKit

final class MemorySection: MenuSection {
    private let memMonitor: MemoryMonitor
    private let actions: MenuActions
    private weak var headerItem: NSMenuItem?
    private weak var barItem: NSMenuItem?
    private weak var detailItem: NSMenuItem?
    private var procItems: [NSMenuItem] = []

    init(memMonitor: MemoryMonitor, actions: MenuActions) {
        self.memMonitor = memMonitor
        self.actions = actions
    }

    var structureSignature: String { "\(memMonitor.topProcesses.count)" }

    func addItems(to menu: NSMenu) -> Bool {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let barFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        headerItem = h

        let b = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        b.isEnabled = false
        menu.addItem(b)
        barItem = b
        _ = barFont

        let d = NSMenuItem()
        d.isEnabled = false
        menu.addItem(d)
        detailItem = d

        procItems = []
        for _ in memMonitor.topProcesses {
            let item = NSMenuItem()
            let sub = NSMenu()
            let killItem = NSMenuItem(title: "", action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            killItem.target = actions
            sub.addItem(killItem)
            item.submenu = sub
            menu.addItem(item)
            procItems.append(item)
        }

        apply()
        _ = headerFont
        return true
    }

    func refresh() { apply() }

    private func apply() {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let barFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let memDetailFont = NSFont.systemFont(ofSize: 10)

        let mem = memMonitor.info
        let memUsed = MemoryMonitor.formatBytes(mem.used)
        let memTotal = MemoryMonitor.formatBytes(mem.total)
        let memPct = String(format: "%.0f%%", mem.usagePercent)
        headerItem?.attributedTitle = NSAttributedString(
            string: "\(L10n.memory): \(memUsed) / \(memTotal) (\(memPct))",
            attributes: [.font: headerFont])

        let memBarWidth = 30
        let memFilled = Int(mem.usagePercent / 100.0 * Double(memBarWidth))
        let memBar = String(repeating: "▓", count: min(memFilled, memBarWidth)) +
                     String(repeating: "░", count: max(memBarWidth - memFilled, 0))
        barItem?.attributedTitle = NSAttributedString(
            string: "  \(memBar)",
            attributes: [.font: barFont])

        let appMem = MemoryMonitor.formatBytes(mem.appMemory)
        let wiredMem = MemoryMonitor.formatBytes(mem.wired)
        let compMem = MemoryMonitor.formatBytes(mem.compressed)
        let detailStr = "  \(L10n.app): \(appMem)  \(L10n.wired): \(wiredMem)  \(L10n.compressed): \(compMem)"
        detailItem?.attributedTitle = NSAttributedString(string: detailStr, attributes: [
            .font: memDetailFont, .foregroundColor: NSColor.secondaryLabelColor,
        ])

        let procs = memMonitor.topProcesses
        for (i, proc) in procs.enumerated() where i < procItems.count {
            let memStr = MemoryMonitor.formatBytes(proc.mem)
            let title = "  \(memStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(proc.name)"
            procItems[i].attributedTitle = NSAttributedString(string: title, attributes: [.font: bodyFont])
            if let killItem = procItems[i].submenu?.items.first {
                killItem.title = "\(L10n.kill) \(proc.name) (PID \(proc.pid))"
                killItem.tag = proc.pid
            }
        }
    }
}
```

- [ ] 完成

### Step 2: 修改 `App.swift`

字段块加：
```swift
    private var memorySection: MemorySection!
```

init 中加：
```swift
        memorySection = MemorySection(memMonitor: memMonitor, actions: actions)
```

`rebuildMenu()` 里，**删除**整块 Memory（从 `// --- Memory ---` 到 `liveRefreshers.append(applyMem)` 的位置，约 60 行）。

用这个代替：
```swift
        // --- Memory ---
        _ = memorySection.addItems(to: menu)
```

`refreshLiveViews()` 里，在 trafficRankSection.refresh() 之后加：
```swift
        memorySection.refresh()
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: Memory 区块显示正常（header + bar + detail + top 5 进程），可从子菜单 kill。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/MemorySection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract MemorySection"
```

- [ ] 完成

---

## Task 12: 抽出 `CPUSection`

**Files:**
- Create: `Sources/NetSpeed/Sections/CPUSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/CPUSection.swift`

```swift
import AppKit

final class CPUSection: MenuSection {
    private let cpuMonitor: CPUMonitor
    private let actions: MenuActions
    private weak var headerItem: NSMenuItem?
    private weak var barItem: NSMenuItem?
    private var procItems: [NSMenuItem] = []

    init(cpuMonitor: CPUMonitor, actions: MenuActions) {
        self.cpuMonitor = cpuMonitor
        self.actions = actions
    }

    var structureSignature: String { "\(cpuMonitor.topProcesses.count)" }

    func addItems(to menu: NSMenu) -> Bool {
        let h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        h.isEnabled = false
        menu.addItem(h)
        headerItem = h

        let b = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        b.isEnabled = false
        menu.addItem(b)
        barItem = b

        procItems = []
        for _ in cpuMonitor.topProcesses {
            let item = NSMenuItem()
            let sub = NSMenu()
            let killItem = NSMenuItem(title: "", action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            killItem.target = actions
            sub.addItem(killItem)
            item.submenu = sub
            menu.addItem(item)
            procItems.append(item)
        }

        apply()
        return true
    }

    func refresh() { apply() }

    private func apply() {
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let barFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let cpuStr = String(format: "%.1f%%", cpuMonitor.cpuUsage)
        headerItem?.attributedTitle = NSAttributedString(
            string: "\(L10n.cpu): \(cpuStr)", attributes: [.font: headerFont])

        let barWidth = 30
        let filled = Int(cpuMonitor.cpuUsage / 100.0 * Double(barWidth))
        let bar = String(repeating: "▓", count: min(filled, barWidth)) +
                  String(repeating: "░", count: max(barWidth - filled, 0))
        barItem?.attributedTitle = NSAttributedString(
            string: "  \(bar)", attributes: [.font: barFont])

        let procs = cpuMonitor.topProcesses
        for (i, proc) in procs.enumerated() where i < procItems.count {
            let cpuFmt = String(format: "%5.1f%%", proc.cpu)
            let title = "  \(cpuFmt)  \(proc.name)"
            let isAbnormal = cpuMonitor.sustainedPids.contains(proc.pid)
            let attrs: [NSAttributedString.Key: Any] = isAbnormal
                ? [.font: bodyFont, .foregroundColor: NSColor.systemRed]
                : [.font: bodyFont]
            procItems[i].attributedTitle = NSAttributedString(string: title, attributes: attrs)
            if let killItem = procItems[i].submenu?.items.first {
                killItem.title = "\(L10n.kill) \(proc.name) (PID \(proc.pid))"
                killItem.tag = proc.pid
            }
        }
    }
}
```

注意：CPU section **不需要**前导分隔符（原代码里 CPU 和 Memory 之间用 `menu.addItem(NSMenuItem.separator())` 手动加；Memory 完了才是 CPU）。但我们的 MenuBuilder 默认每章节前加分隔符，所以保持默认就对。

- [ ] 完成

### Step 2: 修改 `App.swift`

字段块加：
```swift
    private var cpuSection: CPUSection!
```

init 中加：
```swift
        cpuSection = CPUSection(cpuMonitor: cpuMonitor, actions: actions)
```

`rebuildMenu()` 里，**删除** CPU 整块（从 `// --- CPU ---` 到 `liveRefreshers.append(applyCPU)` 的位置）。同时**删除**前面的 `menu.addItem(NSMenuItem.separator())`（现在 memorySection 已经存在时，CPU 前面的分隔符稍后 MenuBuilder 会管；本 task 手动保留）。

用这个代替：
```swift
        menu.addItem(NSMenuItem.separator())
        // --- CPU ---
        _ = cpuSection.addItems(to: menu)
```

`refreshLiveViews()` 里，在 memorySection.refresh() 之后加：
```swift
        cpuSection.refresh()
```

- [ ] 完成

### Step 3: 编译 + 验证

```bash
make reload
```

Expected: CPU 区块显示正常（%用量 + bar + top 进程，异常进程红色标注），子菜单能 kill。

- [ ] 完成

### Step 4: Commit

```bash
git add Sources/NetSpeed/Sections/CPUSection.swift Sources/NetSpeed/App.swift
git commit -m "refactor: extract CPUSection"
```

- [ ] 完成

---

## Task 13: 抽出 `AbnormalProcessesSection` + `RecentAlertsSection`

两个条件章节，都只在非空时出现。一次搞定。

**Files:**
- Create: `Sources/NetSpeed/Sections/AbnormalProcessesSection.swift`
- Create: `Sources/NetSpeed/Sections/RecentAlertsSection.swift`
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 新建 `Sources/NetSpeed/Sections/AbnormalProcessesSection.swift`

```swift
import AppKit

final class AbnormalProcessesSection: MenuSection {
    private let cpuMonitor: CPUMonitor
    private let actions: MenuActions

    init(cpuMonitor: CPUMonitor, actions: MenuActions) {
        self.cpuMonitor = cpuMonitor
        self.actions = actions
    }

    /// abnormalCount 不纳入 signature（原代码注释说明：会导致打开菜单时闪烁）
    var structureSignature: String { "" }

    func addItems(to menu: NSMenu) -> Bool {
        let abnormal = cpuMonitor.abnormalProcesses
        guard !abnormal.isEmpty else { return false }

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerText = "⚠ \(L10n.abnormal) (\(Int(cpuMonitor.cpuThreshold))%+)"
        header.attributedTitle = NSAttributedString(string: headerText, attributes: [.font: headerFont])
        menu.addItem(header)

        for proc in abnormal {
            let cpuFmt = String(format: "%5.1f%%", proc.cpu)
            let title = "  \(cpuFmt)  \(proc.name)"
            let item = NSMenuItem(title: title, action: #selector(MenuActions.killProcess(_:)), keyEquivalent: "")
            item.target = actions
            item.tag = proc.pid
            let redAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: NSColor.systemRed,
            ]
            item.attributedTitle = NSAttributedString(string: title, attributes: redAttrs)
            menu.addItem(item)
        }
        return true
    }

    func refresh() {
        // 异常列表变化会触发 rebuild（structureSignature 为空但内容变化时我们不 refresh，等下次菜单打开 rebuild）
    }
}
```

- [ ] 完成

### Step 2: 新建 `Sources/NetSpeed/Sections/RecentAlertsSection.swift`

```swift
import AppKit

final class RecentAlertsSection: MenuSection {
    private let cpuMonitor: CPUMonitor

    init(cpuMonitor: CPUMonitor) {
        self.cpuMonitor = cpuMonitor
    }

    var structureSignature: String { "" }   // 同 abnormal：不进 signature

    func addItems(to menu: NSMenu) -> Bool {
        let alerts = cpuMonitor.recentAlerts
        guard !alerts.isEmpty else { return false }

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let header = NSMenuItem(title: L10n.recentAlerts, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: L10n.recentAlerts, attributes: [.font: headerFont])
        menu.addItem(header)

        for alert in alerts.prefix(5) {
            let title = "  [\(alert.time)] \(alert.message)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            let alertAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            item.attributedTitle = NSAttributedString(string: title, attributes: alertAttrs)
            menu.addItem(item)
        }
        return true
    }

    func refresh() {
        // 文案不会在菜单打开期间变；打开就是快照，关了下次再 rebuild
    }
}
```

- [ ] 完成

### Step 3: 修改 `App.swift`

字段块加：
```swift
    private var abnormalSection: AbnormalProcessesSection!
    private var alertsSection: RecentAlertsSection!
```

init 中加：
```swift
        abnormalSection = AbnormalProcessesSection(cpuMonitor: cpuMonitor, actions: actions)
        alertsSection = RecentAlertsSection(cpuMonitor: cpuMonitor)
```

`rebuildMenu()` 里，**删除**整块 abnormal 和整块 recent alerts（加起来约 40 行）。

用这两行代替：
```swift
        // --- Abnormal processes (CPUGuard) ---
        _ = abnormalSection.addItems(to: menu)

        // --- Recent Alerts ---
        _ = alertsSection.addItems(to: menu)
```

这两个 section 使用默认的 `needsLeadingSeparator = true`，会在非空时自己加分隔符。但注意：**我们的 MenuBuilder 还没启用**（现在手动管 separator），所以这里要手动加条件 separator。

正确做法（在 `rebuildMenu()` 里）：

```swift
        if !cpuMonitor.abnormalProcesses.isEmpty {
            menu.addItem(NSMenuItem.separator())
            _ = abnormalSection.addItems(to: menu)
        }

        if !cpuMonitor.recentAlerts.isEmpty {
            menu.addItem(NSMenuItem.separator())
            _ = alertsSection.addItems(to: menu)
        }
```

（这两个 section 的 `addItems` 内部也会判空，但这里手动包外层是为了控制 separator。等 Task 14 切到 MenuBuilder 就不用这个了。）

- [ ] 完成

### Step 4: 编译 + 验证

```bash
make reload
```

Expected: 没有异常进程时无对应章节；手动跑 `yes >/dev/null &` 让某进程 CPU 飙到 50%+，约 30 秒后 abnormal 章节出现；alert 通知弹了之后 Recent Alerts 章节出现。

可选测法（不用真触发）：在 CPUMonitor 里临时把 threshold 降到 5%，鼠标动几下菜单就有 abnormal 了——测完记得改回来。

- [ ] 完成

### Step 5: Commit

```bash
git add Sources/NetSpeed/Sections/AbnormalProcessesSection.swift \
        Sources/NetSpeed/Sections/RecentAlertsSection.swift \
        Sources/NetSpeed/App.swift
git commit -m "refactor: extract AbnormalProcessesSection and RecentAlertsSection"
```

- [ ] 完成

---

## Task 14: 启用 `MenuBuilder`，清理 `App.swift`

现在所有 section 都抽出来了，`rebuildMenu()` 实际上只是在按序调用 `section.addItems(to: menu)`。最后一步：把这个序列化挪到 `MenuBuilder`，把 StatusBarController 瘦到 ≤ 120 行。

**Files:**
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 在 `init()` 里创建 `MenuBuilder`

在所有 section 实例化**之后**加：

```swift
        menuBuilder = MenuBuilder(menu: menu, sections: [
            latencyChartCNSection,
            latencyChartIntlSection,
            networkChartSection,
            watchedSection,
            vpnSection,
            trafficRankSection,
            memorySection,
            cpuSection,
            abnormalSection,
            alertsSection,
            quitSection,
        ])
```

字段块加：
```swift
    private var menuBuilder: MenuBuilder!
```

- [ ] 完成

### Step 2: 替换 `rebuildMenu()` 整个方法

原来的 `rebuildMenu()` 现在只剩分隔符和对 section 的调用。整个替换为：

```swift
    private func rebuildMenu() {
        structureSignature = menuBuilder.structureSignature
        menuBuilder.rebuild()
    }
```

注意：MenuBuilder 内部已经处理了 `menu.removeAllItems()` 和分隔符插入。

- [ ] 完成

### Step 3: 替换 `refreshLiveViews()` 整个方法

```swift
    private func refreshLiveViews() {
        trafficMonitor.update()
        if menuBuilder.structureSignature != structureSignature {
            rebuildMenu()
            return
        }
        menuBuilder.refresh()
    }
```

- [ ] 完成

### Step 4: 替换 `currentStructureSignature()`

**删除**原来的 `currentStructureSignature()`（大约 13 行）。`menuBuilder.structureSignature` 直接替代了它。

- [ ] 完成

### Step 5: 删除无用字段和 helpers

删除 StatusBarController 里：
- `private var liveRefreshers: [() -> Void] = []`
- `private var structureSignature: String = ""`（保留！rebuildMenu 仍需要它缓存，但改成 `private var savedSignature: String = ""`——顺便重命名以匹配新语义）

等等，结构 signature 仍然需要保存用来比对。保留但改名：

```swift
    private var savedSignature: String = ""
```

然后 `rebuildMenu()` 的第一行改成 `savedSignature = menuBuilder.structureSignature`。

`refreshLiveViews` 的比对也改 `savedSignature`：
```swift
    private func refreshLiveViews() {
        trafficMonitor.update()
        if menuBuilder.structureSignature != savedSignature {
            rebuildMenu()
            return
        }
        menuBuilder.refresh()
    }
```

**其他可删**：
- `addHeader(_:font:)` — section 内部自己实现了，StatusBarController 不需要
- `addDisabledItem(_:font:)` — 同上

- [ ] 完成

### Step 6: 编译 + 验证

```bash
make reload
```

Expected: 所有章节显示顺序、间距、分隔符完全一致（MenuBuilder 会自动在非空 section 之间插分隔符；latency 和 network chart 因为 `needsLeadingSeparator = false` 不插）。

**反复打开菜单 10 次**，观察：
- 无闪烁（signature 命中时 refresh，不命中时 rebuild）
- 所有交互（kill、reset、VPN、quit）正常

如果有视觉 regression：很可能是某个 section 的 `needsLeadingSeparator` 设反了，或者是某个章节的内部手动 separator 没删干净（例如 Traffic / Memory / CPU 前原来有 `menu.addItem(NSMenuItem.separator())` 要删掉）。

- [ ] 完成

### Step 7: Commit

```bash
git add Sources/NetSpeed/App.swift
git commit -m "refactor: switch StatusBarController to MenuBuilder"
```

- [ ] 完成

---

## Task 15: 最终验证 + 收尾

### Step 1: 检查 App.swift 行数

```bash
wc -l Sources/NetSpeed/App.swift
```

Expected: **≤ 120 行**。如果超出：检查有没有忘删的 helper 方法、旧字段、或重复代码。

- [ ] 完成

### Step 2: 检查每个 section 行数

```bash
wc -l Sources/NetSpeed/Sections/*.swift | sort -n
```

Expected: 每个 ≤ 150 行。

- [ ] 完成

### Step 3: 零警告编译

```bash
swift build -c release 2>&1 | tail -20
```

Expected: `Build complete!`，无 warning。

如有 warning：
- "unused variable" — 在相关 section 里删掉
- "retain cycle" 风险（比如 action closure 忘了 weak self） — 加 `[weak self]`

- [ ] 完成

### Step 4: 手动回归测试清单

`make reload` 后挨个试：

- [ ] 菜单栏图标显示（`↑ ↓ 速度`）
- [ ] 打开菜单：看到从上到下：两个延迟图、网络图、(分隔符)、Watched 进程、(分隔符)、VPN 状态、(分隔符)、流量排行、(分隔符)、内存、(分隔符)、CPU、(分隔符)、Quit
- [ ] 打开菜单后保持 10 秒，观察图表/数值滚动刷新（无闪烁）
- [ ] 重复开关菜单 5 次（应快速无闪）
- [ ] 点 "Reset Traffic" 能重置
- [ ] 从 CPU 进程子菜单选一个 "Kill process X"：进程终止，菜单刷
- [ ] VPN 区点"连接"弹 OpenVPN 配置选择；选一个正确的 `.ovpn` 后能连上
- [ ] VPN 区点"断开"能断开
- [ ] 点 Quit 正常退出；重新 `make start` 能重启

- [ ] 完成

### Step 5: 推送所有提交

```bash
git log --oneline origin/main..HEAD
```

Expected: 应有约 13-15 个 commit 全部是 "refactor:" 前缀。

```bash
git push origin main
```

- [ ] 完成

### Step 6: 更新 CLAUDE.md 的 roadmap

```bash
```

Edit `CLAUDE.md`, 把 PR 3 / v0.4 的复选框打上：

```diff
- - [ ] v0.4: split monolithic `App.swift` into `MenuBuilder` / `VPNController` / `NotificationHelper`
+ - [x] v0.4: split monolithic `App.swift` into `MenuBuilder` / `VPNController` / `NotificationHelper`
```

```bash
git add CLAUDE.md
git commit -m "docs: mark PR 3 (App.swift refactor) complete in roadmap"
git push origin main
```

- [ ] 完成

---

## 故障排查

| 症状 | 可能原因 | 修复 |
|------|---------|------|
| 菜单打开但某 section 缺失 | 该 section 的 `addItems` 返回了 false 但应返回 true | 检查 `structureSignature` 和条件判断 |
| 图表数据不刷新 | section 的 weak ref 被释放 / refresh 未被调用 | 看 MenuBuilder.refresh 是否遍历；section 里的 weak → 改成持有 |
| 打开菜单闪一下 | 某 section 的 signature 在 rebuild/refresh 间变化 | 统一 signature 来源（确保 addItems 和 refresh 用同一份 data snapshot） |
| 分隔符位置不对 | `needsLeadingSeparator` 设错 | latency/network 章节应为 `false`；其他 `true` |
| VPN toggle 菜单不刷新 | `vpnController.onToggleCompleted` 未设 | init 里 `vpnController.onToggleCompleted = { self?.rebuildMenu() }` |
| Kill 进程后菜单没刷 | `actions.onNeedsRebuild` 未设 | init 里 `actions.onNeedsRebuild = { self?.rebuildMenu() }` |
