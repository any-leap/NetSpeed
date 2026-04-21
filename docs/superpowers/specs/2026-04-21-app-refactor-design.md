# App.swift 重构：数据驱动菜单 Design

**日期:** 2026-04-21
**状态:** Draft
**对应 Roadmap:** PR 3 / v0.4

## 目标

把 663 行的 `StatusBarController` 拆分成单一职责的组件，把菜单构建改成**数据驱动**——每个菜单章节变成一个实现 `MenuSection` 协议的独立类型。未来加新章节（例如 PR 5 的 Tunnel 章节）只需新增一个文件，不动 StatusBarController 或 MenuBuilder。

**纯重构：菜单外观、顺序、交互、刷新时机、signature 行为完全不变。**

## 约束

- 行为 100% 向后兼容（用户感知不到改动）
- `Sources/NetSpeed/App.swift` ≤ 120 行
- 每个 section 文件 ≤ 150 行
- `swift build -c release` 零警告
- 不加单元测试（UI 驱动测试 ROI 低，推迟）
- 不改依赖、不加新外部库

## 架构

### 新文件结构

```
Sources/NetSpeed/
├── App.swift                       # StatusBarController (协调器) + AppDelegate + @main
├── MenuBuilder.swift                # MenuSection 协议 + MenuBuilder
├── MenuActions.swift                # 集中所有菜单动作（kill / quit / resetTraffic 等）
├── VPNController.swift              # OpenVPN 进程管理（从 App.swift 抽出）
├── NotificationHelper.swift        # osascript 通知包装（从 App.swift 抽出）
└── Sections/
    ├── LatencyChartSection.swift    # 实例化两份：mainland / overseas
    ├── NetworkChartSection.swift
    ├── WatchedProcessesSection.swift
    ├── VPNSection.swift
    ├── TrafficRankSection.swift
    ├── MemorySection.swift
    ├── CPUSection.swift
    ├── AbnormalProcessesSection.swift
    ├── RecentAlertsSection.swift
    └── QuitSection.swift
```

SPM 5.3+ 自动递归扫描 target 目录；`Sections/` 子目录无需改 `Package.swift`。

### `MenuSection` 协议

```swift
protocol MenuSection: AnyObject {
    /// 变化会影响菜单结构的状态摘要。相同 signature 可原地 refresh；
    /// 不同 = 必须 rebuild。合并后即现有 `currentStructureSignature()` 的行为。
    var structureSignature: String { get }

    /// 追加本章节的菜单项到 menu。返回 true 表示本次有内容（MenuBuilder
    /// 会在章节前后放分隔符）；返回 false 表示空章节（无分隔符）。
    func addItems(to menu: NSMenu) -> Bool

    /// 菜单打开期间的原地刷新（不重建 NSMenuItem，只更新 attributedTitle
    /// / chart 数据等）。如果 signature 相同但数据变了，MenuBuilder 调用此方法。
    func refresh()
}
```

`AnyObject` 绑定是必须的：section 要在 `addItems` 里缓存 weak/strong 菜单项引用，供 `refresh` 更新。

### `MenuBuilder`

```swift
final class MenuBuilder {
    private let menu: NSMenu
    private let sections: [MenuSection]

    init(menu: NSMenu, sections: [MenuSection])

    /// 完全重建菜单：removeAllItems，按序遍历 sections，连续非空 section
    /// 之间插分隔符。签入/退出永不崩。
    func rebuild()

    /// 菜单打开期间调用：对每个 section 调 refresh()。
    func refresh()

    /// 拼接所有 section 的 structureSignature，"|" 分隔。
    var structureSignature: String { get }
}
```

MenuBuilder **不持有任何 monitor 引用**——只拿 section 列表和 NSMenu。所有数据流走 section 内部。

### `MenuActions`

```swift
final class MenuActions: NSObject {
    weak var statusBarController: StatusBarController?   // 用于 quit

    init(cpuMonitor: CPUMonitor, trafficMonitor: TrafficMonitor,
         vpnController: VPNController, notifier: NotificationHelper)

    @objc func kill(_ sender: NSMenuItem)         // sender.tag = pid
    @objc func quit()
    @objc func resetTraffic()
    @objc func toggleVPN()                         // 委托 vpnController
}
```

集中所有 `@objc` 菜单动作。section 在构造菜单项时把 `target = menuActions`、`action = #selector(...)` 设上。

为什么单独拆一个类：
- 现在动作零散分布在 StatusBarController 各处
- `@objc` 方法需要 `NSObject` 基类
- 把动作从 section 里剥离，section 变成"只渲染 + 更新"的纯视图逻辑
- 未来加动作（例如 Preferences 菜单）只改 `MenuActions`

### `VPNController`

```swift
final class VPNController {
    init(monitor: VPNMonitor, notifier: NotificationHelper)

    var isConnected: Bool { get }                   // 委托 monitor

    func toggle()                                   // 连/断分流
    private func connect()                          // 原 promptForConfig + 启动 openvpn
    private func disconnect()                      // 原 killall openvpn
}
```

把 `toggleVPN`、`promptForVPNConfig`、`shellQuote`、auth path 常量、UserDefaults key 全部集中。StatusBarController 降级到只调用 `vpnController.toggle()`。

### `NotificationHelper`

```swift
final class NotificationHelper {
    func send(title: String, message: String)       // osascript display notification
}
```

一个方法，5-10 行。

### `StatusBarController`（重构后）

职责缩到：
1. 创建 `NSStatusItem`、`NSMenu`、所有 monitors
2. 创建 `NotificationHelper`、`VPNController`、`MenuActions`
3. 实例化所有 sections，注入到 `MenuBuilder`
4. 桥接 `netMonitor.onChange` → 判断 signature → `rebuild` / `refresh`
5. 桥接 `latencyMonitor*.onUpdate` → 同上
6. 渲染 status bar label（速度图标）
7. `menuWillOpen` / `menuDidClose` 事件

目标行数：≤ 120 行。

## 数据流（不变）

```
Timer 2s tick (NetMonitor)
        ↓
netMonitor.onChange → main thread
        ↓
StatusBarController:
   cpuMonitor.update()
   memMonitor.update()
   vpnMonitor.update()
   updateLabel()
   if menuIsOpen:
     new = menuBuilder.structureSignature
     if new != savedSignature:
         menuBuilder.rebuild()
         savedSignature = new
     else:
         menuBuilder.refresh()

Timer 5s tick (LatencyMonitor × 2)
        ↓
latencyMonitor.onUpdate → main thread
        ↓
（同上 signature 逻辑）
```

## Signature 映射（每个 section 贡献的 structureSignature）

完全复现现有 `currentStructureSignature()` 的行为，散到各 section：

| 原 signature 位 | 新贡献者 | 值 |
|---------------|---------|---|
| `VC`/`VD` + `vpnHasIP` | `VPNSection` | `"VC1"` / `"VD0"` 等 |
| `memCount` | `MemorySection` | `"\(topProcesses.count)"` |
| `cpuCount` | `CPUSection` | `"\(topProcesses.count)"` |
| `chartReady` | `NetworkChartSection` | `"1"` / `"0"` |
| `watchedAlive` | `WatchedProcessesSection` | bitmap, e.g. `"10"` |
| `latencyCNReady` | `LatencyChartSection(mainland)` | `"1"` / `"0"` |
| `latencyIntlReady` | `LatencyChartSection(overseas)` | `"1"` / `"0"` |

`MenuBuilder.structureSignature` = `sections.map(\.structureSignature).joined(separator: "|")`。

## Section 菜单项生命周期

每个 section 对需要 refresh 的菜单项使用 `private var` **强引用**（NSMenu 也强引用，无循环——move 菜单项后 NSMenu 替换引用）。

```swift
final class MemorySection: MenuSection {
    private let memMonitor: MemoryMonitor
    private var headerItem: NSMenuItem?
    private var barItem: NSMenuItem?
    private var detailItem: NSMenuItem?
    private var procItems: [NSMenuItem] = []

    var structureSignature: String { "\(memMonitor.topProcesses.count)" }

    func addItems(to menu: NSMenu) -> Bool {
        let h = NSMenuItem(...); menu.addItem(h); headerItem = h
        let b = NSMenuItem(...); menu.addItem(b); barItem = b
        let d = NSMenuItem(...); menu.addItem(d); detailItem = d
        procItems = memMonitor.topProcesses.map { ... }
        procItems.forEach(menu.addItem)
        apply()
        return true
    }

    func refresh() { apply() }

    private func apply() {
        headerItem?.attributedTitle = ...
        barItem?.attributedTitle = ...
        for (i, proc) in memMonitor.topProcesses.enumerated() where i < procItems.count {
            procItems[i].attributedTitle = ...
        }
    }
}
```

section 初始化时通常只拿 monitor 引用（不拿 MenuActions，除非需要）；`MenuActions` 由需要动作的 section（CPU/memory 有 kill 子菜单、VPN 有 toggle、quit section 有 quit）注入。

## 迁移步骤（一个 PR，多个 commit，每步应用都能跑）

1. **Extract `NotificationHelper`** — 独立、最简单
2. **Extract `VPNController`** — 把 VPN 逻辑整块搬出
3. **定义 `MenuSection` 协议 + 空 `MenuBuilder`** — 只加新类型
4. **创建 `MenuActions`** — 从 StatusBarController 抠出 `@objc` 方法
5. **逐个转 section** — 每个是一个 commit：
   - 先 `QuitSection`（打通 MenuBuilder rebuild 路径）
   - 然后 `LatencyChartSection`、`NetworkChartSection`、`TrafficRankSection`
   - 然后 `MemorySection`、`CPUSection`
   - 然后 `VPNSection`、`WatchedProcessesSection`
   - 最后 `AbnormalProcessesSection`、`RecentAlertsSection`
6. **切换 signature 逻辑** — StatusBarController 删除本地 `currentStructureSignature`，改调 `menuBuilder.structureSignature`
7. **清理 App.swift** — 删除全部 dead code，确认 ≤ 120 行

## 风险 + 缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| Section 的 item 引用被释放导致 refresh 无效 | 中 | 强引用（NSMenu 本身也强引用，无循环） |
| 打开菜单瞬间闪烁 | 中 | 每步转换后手动 `make reload` + 开菜单多次 |
| VPN AppleScript 特权弹窗链路断裂 | 低 | `NSAppleScript` 调用原逻辑搬到 `VPNController.toggle()`，不重写 |
| Timer 生命周期断裂 | 低 | Timer 仍归 StatusBarController，不挪 |
| `menuIsOpen` / `structureSignature` 状态读写时机 | 中 | MenuBuilder 提供清晰接口，StatusBarController 单线程（main）控制决策 |

## 非目标

- 不改菜单文案、顺序、颜色、行为（**纯重构**）
- 不加单元测试（以后单独 PR 决定要不要加）
- 不做 VPN 通用化（PR 5）
- 不换 subprocess 为 libproc（PR 6）
- 不加 Preferences UI
- 不拆 View 类型（ChartView/LatencyChartView/TrafficRankView 保持原样）

## 成功标准

- `swift build -c release` 零警告、零错误
- `make reload` 后菜单所有章节外观、顺序、文案、颜色、交互完全一致
- `Sources/NetSpeed/App.swift` ≤ 120 行
- 每个 Section 文件 ≤ 150 行
- 代码量总体持平或略增（≤ +300 行）——多出的都是显式接口/protocol 样板
- 打开/关闭菜单 10 次无闪烁
- VPN 连/断、kill 进程、reset traffic、quit 都正常
