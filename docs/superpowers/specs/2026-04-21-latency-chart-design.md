# 延迟监控图表 Design

**日期:** 2026-04-21
**状态:** Draft

## 目标

在菜单栏应用中新增两个延迟监控图表，分别反映**大陆直连链路**和**海外代理链路**的实时健康状况。
使用场景：Clash TUN 模式下 ICMP ping 不可靠，需要一种低开销、准确的延迟信号。

## 约束与决策

- **测量方式**：TCP connect 半握手计时（SYN → SYN-ACK）。建连即断，无数据流量。
- **不用 ICMP**：Clash TUN 模式会劫持 ICMP，结果不反映真实链路。
- **不用 HTTP**：多余的 TLS 握手 + HTTP 请求会放大测量、增加消耗。
- **使用域名**：OS 层 DNS 缓存，首次探测稍慢（含解析），之后为纯 TCP RTT；与真实浏览体验一致。
- **3 服务器并发取最小 RTT**：降低单点抖动，代表"网络当前能达到的最佳延迟"。

## 目标服务器

### 大陆组（mainland）
- `www.baidu.com:443`
- `www.taobao.com:443`
- `www.qq.com:443`

### 海外组（overseas）
- `www.google.com:443`
- `www.cloudflare.com:443`
- `www.github.com:443`

## 组件设计

### `LatencyMonitor`（新文件 `Sources/NetSpeed/LatencyMonitor.swift`）

**职责：** 周期性发起 TCP connect 探测，维护滑动窗口历史。

**参数化初始化：**
```swift
LatencyMonitor(
    name: String,                          // 用于日志/调试，例如 "mainland"
    targets: [(host: String, port: UInt16)]
)
```

**对外接口：**
- `var current: Double?` — 最近一次测量（ms），nil 表示全部 fail
- `var history: [Double?]` — 滑动窗口，长度等于 `maxHistory`，新值 append，超长时 removeFirst
- `let maxHistory: Int = 60` — 5 分钟（60 × 5s）
- `var onUpdate: (() -> Void)?` — 每次测量完成后回调（用于通知 UI 刷新）

**行为：**
- 启动时立即开始一个 `Timer.scheduledTimer(withTimeInterval: 5, repeats: true)`
- 每个 tick：并发发起 N 个探测（`DispatchGroup` 或 Swift concurrency），收集结果，取最小值追加到 history
- 所有探测均失败 → append nil
- 单个探测使用 `NWConnection`，超时 2 秒，`state == .ready` 时记下耗时并 cancel

**单次 TCP 探测实现细节：**
- 使用 `Network.framework` 的 `NWConnection(host:port:using: .tcp)`
- 在 `stateUpdateHandler` 中：
  - `.ready`：计算 `Date().timeIntervalSince(startTime) * 1000` 为 ms，`cancel()`，回调成功
  - `.failed(_)` / `.cancelled`：回调失败（如果未回调过）
- 独立 `DispatchQueue.global(qos: .utility)` 上运行，避免阻塞 main queue
- 2 秒 `DispatchQueue.asyncAfter` 超时：如果此时仍未 ready，cancel 连接并回调失败

**实例化（两份，在 `StatusBarController.init`）：**
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

### `LatencyChartView`（新文件 `Sources/NetSpeed/LatencyChartView.swift`）

**职责：** 单线、支持 nil 断点的延迟图表。样式与 `ChartView` 保持视觉一致。

**初始化参数：**
```swift
init(
    history: [Double?],
    maxHistory: Int,
    current: Double?,
    title: String,
    lineColor: NSColor
)
```

**更新接口：**
```swift
func update(history: [Double?], current: Double?)
```

**渲染规则：**
- 尺寸与 `ChartView` 一致（260×90，`autoresizingMask = [.width]`）
- 标题在左上，当前值（如 `28 ms` 或 `—`）在右上
- Y 轴：`max(history.compactMap{$0}.max() ?? 100, 100)`（底限 100ms 避免贴顶）
- X 轴：60 点宽度，右对齐到 "now"
- nil 处理：把 history 按 nil 切成若干连续段，每段独立绘制平滑曲线；nil 位置为空白
- 配色：
  - 大陆：`NSColor.systemCyan`
  - 海外：`NSColor.systemPurple`

### 集成到 `App.swift`

**新增字段：**
```swift
private var latencyMonitorCN: LatencyMonitor
private var latencyMonitorIntl: LatencyMonitor
private weak var latencyChartCN: LatencyChartView?
private weak var latencyChartIntl: LatencyChartView?
```

**`init` 中挂接回调：**
```swift
latencyMonitorCN.onUpdate = { [weak self] in
    if self?.menuIsOpen == true { self?.refreshLiveViews() }
}
latencyMonitorIntl.onUpdate = { ... 同上 ... }
```

**`rebuildMenu()` 顶部新增（在现有网络图之前）：**

```
if latencyMonitorCN.history.count >= 2 {
    // 添加 LatencyChartView 菜单项，保存 weak 引用到 latencyChartCN
}
if latencyMonitorIntl.history.count >= 2 {
    // 添加 LatencyChartView 菜单项，保存 weak 引用到 latencyChartIntl
}
// 现有 "--- Network Chart ---" 代码保持不变
```

**`refreshLiveViews()` 增加：**
```swift
latencyChartCN?.update(history: latencyMonitorCN.history, current: latencyMonitorCN.current)
latencyChartIntl?.update(history: latencyMonitorIntl.history, current: latencyMonitorIntl.current)
```

**`currentStructureSignature()` 增加：**
延迟图就绪标志（`history.count >= 2 ? "1" : "0"`），各一位，防止从"未就绪"跳到"就绪"时闪烁。

### i18n

在 `Strings.swift` 新增：
- `latencyMainland` → "大陆延迟" / "Mainland Latency"
- `latencyOverseas` → "海外延迟" / "Overseas Latency"
- `ms` 单位直接字面量，不做本地化

## 菜单布局（最终）

```
┌────────────────────────────────────┐
│ Mainland Latency      28 ms        │  ← 新增
│ [line chart, 5 min]                │
├────────────────────────────────────┤
│ Overseas Latency     182 ms        │  ← 新增
│ [line chart, 5 min]                │
├────────────────────────────────────┤
│ Network               ↓ X   ↑ Y    │  ← 原有
│ [line chart]                       │
├────────────────────────────────────┤
│ Watched processes / VPN / ...      │
└────────────────────────────────────┘
```

## 生命周期

- 两个 `LatencyMonitor` 随 `StatusBarController.init()` 一起启动，伴随应用整个生命周期
- 定时器**永不停止**（菜单关闭也继续），保证打开菜单时立即有完整历史
- 图表只在菜单打开时重绘（通过 `liveRefreshers` / `onUpdate` → `refreshLiveViews` 链路）

## 失败处理

| 场景 | 行为 |
|------|------|
| 单个 target 超时 | 该 target 不贡献结果 |
| 单个 target DNS 失败 | 同上 |
| 单个 target TCP RST | 同上 |
| 3 个 target 全部失败 | history append nil，图表断线 |
| 连续多次 nil | 图表显示为一段空白 |
| `current = nil` 时的标签 | 显示 `—`（短横杠） |

## 消耗估算

| 项 | 数值 |
|----|------|
| 单次探测包量 | 3（SYN）+ 3（SYN-ACK）+ 3（RST）≈ 9 个小包 |
| 单次探测字节 | ≈ 540 B |
| 每分钟（两组 × 12 次） | ≈ 13 KB |
| 每天 | ≈ 18 MB |
| CPU 开销 | 每 5 秒 ms 级（NWConnection 异步） |

结论：可忽略。

## 非目标 / YAGNI

- **不做**：手动触发按钮、服务器列表可配置 UI、探测协议切换（TCP/UDP/ICMP 选择）、探测频率可调 UI
- **不做**：历史持久化（重启丢失 OK，本身就是实时信号）
- **不做**：把延迟值显示到菜单栏标签（菜单栏空间紧张，仅菜单内显示）
- **未来可考虑**（不在本期）：右键菜单编辑服务器列表；延迟超阈值告警通知

## 验证标准

- 正常网络：大陆图稳定在 10-40ms，海外图显示代理节点真实延迟（典型 100-300ms）
- 断网场景：几次测量后两个图都显示断线
- Clash 切换代理节点：海外图能明显反映变化，大陆图基本不受影响（验证两个信号独立）
- 菜单打开 / 关闭：定时器和图表历史不受影响
- 打开菜单时无 UI 闪烁（structure signature 稳定）
