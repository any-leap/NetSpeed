# VPN → Tunnel 通用化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 NetSpeed 识别任何基于 utun 的 VPN（WireGuard / Clash Warp / Tunnelblick 等），不再 OpenVPN-only。OpenVPN 用户功能不变。

**Architecture:** VPNMonitor 去掉 `pgrep openvpn` 判断，连接状态只看 utun。VPNSection 获取 VPNController，根据 `.ovpn` 是否配过决定是否显示 Connect/Disconnect 按钮。面向用户的 "VPN" 字样改为 "Tunnel / 隧道"。

**Tech Stack:** Swift 5.9 · AppKit · 纯 refactor，不加新依赖

**Spec:** `docs/superpowers/specs/2026-04-21-tunnel-generalization-design.md`

**Verification:** 每步 `swift build -c release` 零警告 + 可选 `make reload` 视觉确认。

---

## File Structure

| 文件 | 动作 | 变动大小 |
|------|------|---------|
| `Sources/NetSpeed/VPNMonitor.swift` | Modify | -13 行（删 `isOpenVPNRunning()`） |
| `Sources/NetSpeed/VPNController.swift` | Modify | +4 行（加 `isOpenVPNConfigured`） |
| `Sources/NetSpeed/Strings.swift` | Modify | -5/+7 行（L10n 值更新 + 两个新常量） |
| `Sources/NetSpeed/Sections/VPNSection.swift` | Modify | ~+10 行净（按钮条件 + 签名） |
| `Sources/NetSpeed/App.swift` | Modify | ~+5/-3（构造参数、通知文案） |

---

## Task 1: `VPNMonitor` 去 OpenVPN 专属判断

**Files:**
- Modify: `Sources/NetSpeed/VPNMonitor.swift`

### Step 1: 编辑 `VPNMonitor.update()`

找到 `update(interval:)` 方法开头的两行：

```swift
    func update(interval: TimeInterval = 2.0) {
        let processRunning = isOpenVPNRunning()
        let iface = findVPNInterface()
```

删掉 `processRunning` 的赋值，保留 `iface`：

```swift
    func update(interval: TimeInterval = 2.0) {
        let iface = findVPNInterface()
```

### Step 2: 修改 `connected` 的计算

找到（当前在 line 45 附近）：

```swift
        let connected = processRunning && iface != nil
```

改成：

```swift
        let connected = iface != nil
```

### Step 3: 删除 `isOpenVPNRunning()` 方法

整块删除：

```swift
    // MARK: - Process check

    private func isOpenVPNRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "openvpn"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
```

### Step 4: 验证

```bash
swift build -c release 2>&1 | tail -3
```
Expected: `Build complete!`，零警告。

- [ ] 完成

### Step 5: Commit

```bash
git add Sources/NetSpeed/VPNMonitor.swift
git commit -m "refactor(vpn): detect any utun-based tunnel, not just OpenVPN"
```

- [ ] 完成

---

## Task 2: `VPNController` 加 `isOpenVPNConfigured` 公开属性

**Files:**
- Modify: `Sources/NetSpeed/VPNController.swift`

### Step 1: 编辑 `VPNController.swift`

找到类里已有的静态常量区（`private static let vpnConfigKey = "vpnConfigPath"` 附近）。在 `isConnected` 计算属性**后面**加：

```swift
    var isOpenVPNConfigured: Bool {
        UserDefaults.standard.string(forKey: Self.vpnConfigKey) != nil
    }
```

（现有的 `private var vpnConfigPath: String?` 也是读这个 key，可以复用它返回 `!= nil`，但为了公开属性清晰，直接写完整 UserDefaults 读取。）

### Step 2: 验证

```bash
swift build -c release 2>&1 | tail -3
```
Expected: `Build complete!`，会有 "never used" 警告也接受（Task 4 会用上）。

- [ ] 完成

### Step 3: Commit

```bash
git add Sources/NetSpeed/VPNController.swift
git commit -m "feat(vpn): expose isOpenVPNConfigured for UI gating"
```

- [ ] 完成

---

## Task 3: `Strings.swift` 更新 L10n 值 + 新增隧道断开通知常量

**Files:**
- Modify: `Sources/NetSpeed/Strings.swift`

### Step 1: 编辑 L10n 值

找到 `Strings.swift` 中这一段：

```swift
    static let vpn = "VPN"
    static let vpnConnected = isChinese ? "已连接" : "Connected"
    static let vpnDisconnected = isChinese ? "未连接" : "Disconnected"
    static let vpnConnectAction = isChinese ? "连接 VPN" : "Connect VPN"
    static let vpnDisconnectAction = isChinese ? "断开 VPN" : "Disconnect VPN"
```

替换为：

```swift
    static let vpn = isChinese ? "隧道" : "Tunnel"
    static let vpnConnected = isChinese ? "已连接" : "Connected"
    static let vpnDisconnected = isChinese ? "未连接" : "Disconnected"
    static let vpnConnectAction = isChinese ? "连接 OpenVPN" : "Connect OpenVPN"
    static let vpnDisconnectAction = isChinese ? "断开 OpenVPN" : "Disconnect OpenVPN"
    static let tunnelDisconnectedTitle = isChinese ? "隧道已断开" : "Tunnel Disconnected"
    static let tunnelDisconnectedMessage = isChinese ? "utun 接口已消失" : "utun interface is down"
```

变动：
- `vpn` 值从 `"VPN"` 改成 `"隧道"` / `"Tunnel"`
- `vpnConnectAction` / `vpnDisconnectAction` 后缀从 `VPN` 改成 `OpenVPN`（让用户清楚这俩按钮只控制 OpenVPN）
- 新增 `tunnelDisconnectedTitle` / `tunnelDisconnectedMessage` 两个常量（Task 5 用）

### Step 2: 验证

```bash
swift build -c release 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] 完成

### Step 3: Commit

```bash
git add Sources/NetSpeed/Strings.swift
git commit -m "refactor(i18n): rename VPN → Tunnel in user-facing strings"
```

- [ ] 完成

---

## Task 4: `VPNSection` 使用 `VPNController`，条件显示按钮

**Files:**
- Modify: `Sources/NetSpeed/Sections/VPNSection.swift`

### Step 1: 更新构造器

找到现有的 `VPNSection` 声明：

```swift
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
```

替换为：

```swift
final class VPNSection: MenuSection {
    private let monitor: VPNMonitor
    private let vpnController: VPNController
    private let actions: MenuActions

    // 用于 refresh 原地更新（仅在 connected 状态下有值）
    private weak var speedItem: NSMenuItem?
    private weak var totalItem: NSMenuItem?

    init(monitor: VPNMonitor, vpnController: VPNController, actions: MenuActions) {
        self.monitor = monitor
        self.vpnController = vpnController
        self.actions = actions
    }
```

### Step 2: 更新 `structureSignature`

原来的：

```swift
    var structureSignature: String {
        let conn = monitor.status.connected ? "VC" : "VD"
        let hasIP = (monitor.status.localIP != nil && monitor.status.interfaceName != nil) ? "1" : "0"
        return "\(conn)\(hasIP)"
    }
```

改成（把 OpenVPN 配置状态也纳入 signature，确保配完 `.ovpn` 后菜单立刻显示 Connect 按钮）：

```swift
    var structureSignature: String {
        let conn = monitor.status.connected ? "TC" : "TD"
        let hasIP = (monitor.status.localIP != nil && monitor.status.interfaceName != nil) ? "1" : "0"
        let cfg = vpnController.isOpenVPNConfigured ? "c" : "u"
        return "\(conn)\(hasIP)\(cfg)"
    }
```

（"VC/VD" 改成 "TC/TD" 只是为了语义一致——Tunnel Connected / Disconnected。功能上无差别。）

### Step 3: 重写 `addItems(to:)`

原来这个方法 60 行，里面分 `vpn.connected` 的 `if/else` 分别硬编码 Connect/Disconnect 按钮。需要改成按钮只在 `isOpenVPNConfigured == true` 时追加。完整替换方法体：

```swift
    func addItems(to menu: NSMenu) -> Bool {
        let vpn = monitor.status
        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

        speedItem = nil
        totalItem = nil

        if vpn.connected {
            let header = "\(L10n.vpn): \(L10n.vpnConnected)"
            addHeader(header, font: headerFont, to: menu)

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

            if vpnController.isOpenVPNConfigured {
                let disconnectLabel = L10n.vpnDisconnectAction
                let disconnectItem = NSMenuItem(title: disconnectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
                disconnectItem.target = actions
                disconnectItem.attributedTitle = NSAttributedString(string: "  \(disconnectLabel)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemRed,
                ])
                menu.addItem(disconnectItem)
            }
        } else {
            let header = "\(L10n.vpn): \(L10n.vpnDisconnected)"
            let item = NSMenuItem(title: header, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(string: header, attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.systemRed,
            ])
            menu.addItem(item)

            if vpnController.isOpenVPNConfigured {
                let connectLabel = L10n.vpnConnectAction
                let connectItem = NSMenuItem(title: connectLabel, action: #selector(MenuActions.toggleVPN), keyEquivalent: "")
                connectItem.target = actions
                connectItem.attributedTitle = NSAttributedString(string: "  \(connectLabel)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemGreen,
                ])
                menu.addItem(connectItem)
            }
        }
        return true
    }
```

变动点：
- `connected` 分支：把 `let disconnectLabel = ... menu.addItem(disconnectItem)` 整块包进 `if vpnController.isOpenVPNConfigured { ... }`
- `disconnected` 分支：同样，`let connectLabel = ... menu.addItem(connectItem)` 包进条件块
- 其他（header、iface/IP 显示、speed/total items、applyRows）不变

### Step 4: 验证

```bash
swift build -c release 2>&1 | tail -5
```
Expected: `Build complete!`。

此时会编译错——因为 App.swift 还在用旧的两参数构造器。下一步 Task 5 修它。

临时忽略这个错误继续到 Task 5 ——或者合并 Task 4+5 在一个 commit 里（推荐合并，但为了 task 粒度清晰分开）。

**替代方案**：先把 Task 5 做完再编译验证。如果做成一次性 commit，在 Task 4 step 4 处先跳过编译，Task 5 step 3 处验证。

实际执行建议：**Task 4 和 Task 5 合并成一个 commit**，Task 5 最后统一编译验证和提交。下面 Task 5 的 commit message 会覆盖这两部分。

### Step 5: 不提交，继续 Task 5

- [ ] 完成 Task 4 编辑（不 commit，等 Task 5 一起）

---

## Task 5: `App.swift` 更新 VPNSection 构造 + 通知文案

**Files:**
- Modify: `Sources/NetSpeed/App.swift`

### Step 1: 更新 VPNSection 实例化

找到 `App.swift` 的 `init()` 里这一行：

```swift
        vpnSection = VPNSection(monitor: vpnMonitor, actions: actions)
```

改成：

```swift
        vpnSection = VPNSection(monitor: vpnMonitor, vpnController: vpnController, actions: actions)
```

### Step 2: 更新断开通知文案

找到 `App.swift` 的 `init()` 里这段（通常在 `menu.delegate = self` 之后，`netMonitor.onChange` 之前）：

```swift
        vpnMonitor.onDisconnect = { [weak self] in
            self?.notifier.send(
                title: "VPN Disconnected",
                message: "OpenVPN connection has been lost"
            )
        }
```

改成使用新的 L10n 常量：

```swift
        vpnMonitor.onDisconnect = { [weak self] in
            self?.notifier.send(
                title: L10n.tunnelDisconnectedTitle,
                message: L10n.tunnelDisconnectedMessage
            )
        }
```

### Step 3: 编译验证

```bash
swift build -c release 2>&1 | tail -5
```
Expected: `Build complete!`，零警告（包括 Task 4 改动的编译也一起通过）。

- [ ] 完成

### Step 4: 运行时验证

```bash
make reload
sleep 2
launchctl list | grep netspeed
```
Expected: 进程有 PID，退出码 0（或 -15 如果上次被 kickstart -k 杀过，正常）。

菜单上看到：
- **如果你电脑连着 VPN**（任何类型）→ 菜单显示 "Tunnel: 已连接" + utun 信息 + 速度流量
- **如果没连 VPN**，且你之前**没**配过 `.ovpn` → 只显示 "Tunnel: 未连接"，**无** Connect 按钮
- **如果没连 VPN**，但你之前配过 `.ovpn` → "Tunnel: 未连接" + "连接 OpenVPN" 按钮
- 对应断开：如果配过 `.ovpn`，显示 "断开 OpenVPN"；没配过，仅显示状态无按钮

- [ ] 完成

### Step 5: Commit（覆盖 Task 4+5）

```bash
git add Sources/NetSpeed/Sections/VPNSection.swift Sources/NetSpeed/App.swift
git commit -m "feat(vpn): condition Connect/Disconnect buttons on OpenVPN configuration

VPNSection now takes VPNController and hides its action buttons when
the user hasn't configured an .ovpn file. Non-OpenVPN users (WireGuard,
Clash Warp, etc.) see read-only tunnel status without a misleading
control they can't actually use.

The disconnect notification now uses generic 'utun interface is down'
wording instead of OpenVPN-specific copy."
```

- [ ] 完成

---

## Task 6: 整体验证 + Push + Roadmap 更新

**Files:**
- Modify: `CLAUDE.md`（roadmap 打钩）

### Step 1: 最终编译检查

```bash
swift build -c release 2>&1 | tail -5
wc -l Sources/NetSpeed/VPNMonitor.swift Sources/NetSpeed/VPNController.swift Sources/NetSpeed/Sections/VPNSection.swift Sources/NetSpeed/Strings.swift
```

Expected:
- `Build complete!`（零警告）
- `VPNMonitor.swift` 减了约 13 行
- `VPNController.swift` 多了约 4 行
- `VPNSection.swift` 多了约 10 行
- `Strings.swift` 多了约 2 行

- [ ] 完成

### Step 2: 端到端手动回归（菜单）

`make reload` 之后打开菜单，验证：

- [ ] "VPN" 文字改成 "Tunnel / 隧道"
- [ ] 连着状态：显示 "Tunnel: 已连接" + utun 接口 + IP + 速度 + 累计流量
- [ ] 如果你配过 `.ovpn` 且 OpenVPN 连着：显示 "断开 OpenVPN" 按钮
- [ ] 点 "断开 OpenVPN"：触发特权弹窗，断掉 OpenVPN → 菜单 2s 内更新为断开状态
- [ ] 如果 `.ovpn` 没配过且没连任何 VPN：只看到 "Tunnel: 未连接"，**无** Connect 按钮
- [ ] 断线通知文案从 "VPN Disconnected / OpenVPN connection has been lost" 改成 "Tunnel Disconnected / utun interface is down"（实验方法：手动 `killall openvpn` 或关闭其他 VPN app，约 2 秒后应收到系统通知）

### Step 3: 更新 CLAUDE.md roadmap

找到 CLAUDE.md 的 Roadmap 块，把第 4 项打钩：

```diff
- 4. Generalize VPN monitor: drop OpenVPN-specific process detection; show status for any `utun` interface. Connect/Disconnect button becomes opt-in (only shown when user configures a `.ovpn`). Rename section "Tunnel".
+ 4. ✅ Generalize VPN monitor: any utun → connected; Connect/Disconnect opt-in based on .ovpn config; section renamed "Tunnel" (user-facing only, class names unchanged).
```

- [ ] 完成

### Step 4: Commit + Push

```bash
git add CLAUDE.md
git commit -m "docs: mark PR 5 (Tunnel generalization) complete"
git log --oneline origin/main..HEAD | head -10
git push origin main 2>&1 | tail -3
```

Expected: 5-6 个 commits 推上去：
1. refactor(vpn): detect any utun-based tunnel, not just OpenVPN
2. feat(vpn): expose isOpenVPNConfigured for UI gating
3. refactor(i18n): rename VPN → Tunnel in user-facing strings
4. feat(vpn): condition Connect/Disconnect buttons on OpenVPN configuration
5. docs: mark PR 5 (Tunnel generalization) complete

- [ ] 完成

### Step 5: Tag v0.5.0（可选，现在或后续）

如果想立刻打 release：

```bash
git tag v0.5.0 -m "v0.5.0 — Tunnel generalization: works with any utun-based VPN"
git push origin v0.5.0
```

CI 会自动构建 DMG 上传 Release 页面。

- [ ] 完成（或推迟到后续累积）

---

## 故障排查

| 症状 | 可能原因 | 修复 |
|------|---------|------|
| 连着 VPN 但菜单显示"未连接" | `findVPNInterface()` 没抓到 utun | 检查是否有 utun 接口用 `AF_INET` 地址。某些 IPv6-only 隧道需要扩展检测 |
| 没配 `.ovpn` 但还是看到 Connect 按钮 | `isOpenVPNConfigured` 返回 true（UserDefaults 有残留） | `defaults delete com.t3st.netspeed vpnConfigPath` |
| 用 WireGuard 连着时菜单显示 "OpenVPN" 字样 | 按钮文案共用 L10n | 这是设计决定——按钮只对 OpenVPN 有效。如果用户没配 `.ovpn` 就看不到按钮，无歧义 |
| 断开 VPN 没触发通知 | `wasConnected && !connected` 逻辑未命中 | 检查 `VPNMonitor.update()` 的状态跃迁 |
