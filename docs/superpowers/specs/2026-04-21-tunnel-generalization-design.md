# VPN → Tunnel 通用化 Design

**日期:** 2026-04-21
**状态:** Draft
**对应 Roadmap:** PR 5 / v0.5

## 目标

把"VPN 监控"从 OpenVPN-specific 扩展成任何基于 utun 接口的 VPN（WireGuard、Clash Warp、Tunnelblick、Mullvad、etc.）。让没用 OpenVPN 的用户也能在菜单里看到隧道状态。OpenVPN 用户的功能保持不变。

## 核心改动

**连接判断**：从"OpenVPN 进程在跑 + utun 存在"改成"utun 存在（且有可路由 IP）"。

**控制按钮**：Connect / Disconnect 按钮**只在用户配过 `.ovpn` 时显示**——因为 NetSpeed 只会操作 OpenVPN，对其他 VPN 技术没有控制手段。

**文案**：面向用户的 "VPN" 字样改成 "Tunnel / 隧道"。类名（VPNMonitor 等）不改。

## UI 行为矩阵

| utun 连接 | `.ovpn` 配过 | 菜单显示 |
|---------|-----------|---------|
| ✅ | ❌ | Header "Tunnel: connected" + `utunX` + IP + 实时速度 + 累计流量 |
| ❌ | ❌ | Header "Tunnel: disconnected"（无按钮） |
| ✅ | ✅ | 同上 + **"Disconnect"** 按钮（红色） |
| ❌ | ✅ | Header "Tunnel: disconnected" + **"Connect"** 按钮（绿色） |

## 代码变动

### `VPNMonitor.swift`

- 删除 `isOpenVPNRunning()` 私有方法及其调用
- `update()` 里：`connected = iface != nil`（去掉 `processRunning && ...` 前缀）
- `onDisconnect` 仍在 `wasConnected && !connected` 时触发；语义从"OpenVPN 进程退出"变为"utun 消失"。通知文案走 L10n（新）

### `VPNController.swift`

新增一个公开计算属性：

```swift
var isOpenVPNConfigured: Bool {
    UserDefaults.standard.string(forKey: Self.vpnConfigKey) != nil
}
```

### `Sections/VPNSection.swift`

**构造器变更**：

```swift
init(monitor: VPNMonitor, vpnController: VPNController, actions: MenuActions)
```

**`addItems(to:)` 逻辑**：

- 始终显示 header（`L10n.tunnel + ": " + connected/disconnected`）和颜色
- 连接时显示 `utunX`、IP、speed、total bytes 三行（只读）
- `vpnController.isOpenVPNConfigured == true` 时，根据连接状态追加 Connect 或 Disconnect 按钮
- `isOpenVPNConfigured == false` 时不追加任何按钮

`structureSignature` 需要把 `isOpenVPNConfigured` 一起纳入（否则用户刚配完 `.ovpn` 不会立刻出现 Connect 按钮）：

```swift
var structureSignature: String {
    let conn = monitor.status.connected ? "TC" : "TD"
    let hasIP = (monitor.status.localIP != nil && monitor.status.interfaceName != nil) ? "1" : "0"
    let cfg = vpnController.isOpenVPNConfigured ? "c" : "u"
    return "\(conn)\(hasIP)\(cfg)"
}
```

### `App.swift`

在 VPNSection 实例化处多传一个参数：

```swift
vpnSection = VPNSection(monitor: vpnMonitor, vpnController: vpnController, actions: actions)
```

### `Strings.swift`

重命名以下 L10n 常量的**值**（key 不改，避免全仓库替换）：

| Key（不变） | 中文 | 英文 |
|-----|------|------|
| `vpn` | 隧道 | Tunnel |
| `vpnConnected` | 已连接 | Connected |
| `vpnDisconnected` | 未连接 | Disconnected |
| `vpnConnectAction` | 连接 OpenVPN | Connect OpenVPN |
| `vpnDisconnectAction` | 断开 OpenVPN | Disconnect OpenVPN |

连接/断开按钮的文案明确包含 "OpenVPN" 后缀——让用户清楚这个按钮只控制 OpenVPN，不影响其他 VPN 软件。

**`VPNMonitor.swift` 的通知文案**（`onDisconnect` 回调消息）：

原代码：

```swift
self?.notifier.send(
    title: "VPN Disconnected",
    message: "OpenVPN connection has been lost"
)
```

改成：

```swift
self?.notifier.send(
    title: L10n.isChinese ? "隧道已断开" : "Tunnel Disconnected",
    message: L10n.isChinese ? "utun 接口已消失" : "utun interface is down"
)
```

（或者：新增 `L10n.tunnelDisconnectedTitle` / `L10n.tunnelDisconnectedMessage` 常量。采用后者，和既有 L10n 模式一致。）

## Edge Cases

1. **OpenVPN 配过但 OpenVPN 进程其实没开**（用户用别的 VPN 连着）：
   - `isOpenVPNConfigured = true`, `connected = true`（因为有 utun）
   - 显示 "Disconnect" 按钮
   - 用户点了 → `killall openvpn` 无事发生（没 openvpn 进程）
   - utun 仍然存在（因为是其他 VPN 的），menu 不会变
   - 无害（但行为不完美）。考虑在未来 PR 里加"实际运行的 VPN 类型"检测。这版不做。

2. **连接瞬间 race**（utun 创建中，IP 尚未分配）：
   - `findVPNInterface()` 会因 IP 缺失返回 nil
   - `connected = false` 暂时
   - 下个 2s 轮询会正确识别
   - 无害

3. **多 utun 接口**（例如 Clash Warp + OpenVPN 同时开）：
   - `findVPNInterface()` 返回第一个 utun 的信息
   - 流量/IP 显示的是"某一个"的
   - 这是老 code 就有的行为；这版不改进

4. **用户配了 .ovpn 又想删除配置**：
   - 本 PR 不加 "Forget OpenVPN config" 按钮（YAGNI）
   - 用户可手动 `defaults delete com.t3st.netspeed vpnConfigPath`
   - 未来如做 Preferences UI，放那里

## 成功标准

- WireGuard / Clash Warp 用户打开菜单：看到 "Tunnel: connected" + utun 信息；**无** Connect/Disconnect 按钮
- 从未配 OpenVPN 的用户，断开时看 "Tunnel: disconnected"；**无** Connect 按钮
- OpenVPN 老用户：体验不变（按钮仍显示"连接/断开 OpenVPN"）
- `swift build -c release` 零警告
- 手动连断 WireGuard（或任何 utun VPN）→ 菜单状态 2s 内同步

## 非目标

- 不做 WireGuard 等其他 VPN 的启动/停止控制（需要各家自己的 IPC）
- 不做 Preferences UI 管理 .ovpn 配置（YAGNI）
- 不做多 utun 的聚合显示（YAGNI）
- 不改 VPNMonitor / VPNController / VPNSection 类名（纯内部代码，改了 diff 太大）
- 不保留旧 `isOpenVPNRunning` 作为 fallback（直接删）
