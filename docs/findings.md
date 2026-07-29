## FIND-001 [Tunnel] Clash TUN can mask OpenVPN control state
- 日期：2026-07-07
- 现象：Clash TUN 存在时，即使 OpenVPN 进程已断开，菜单仍可能停留在 "Tunnel: 已连接" 分支，只显示 "Disconnect OpenVPN"，看不到 "Connect OpenVPN"。
- 根因/机制：`VPNMonitor` 的 Tunnel 展示状态按任意带 IPv4 的 `utun` 接口判断；Clash TUN 也会创建 `utun`。OpenVPN 控制按钮如果复用这个状态，就会把 Clash/WireGuard 等非 OpenVPN 隧道误当成 OpenVPN 连接状态。
- 证据/复现：`ifconfig` 可同时看到 Clash TUN 的 `utun1024` 和 OpenVPN 的 `utun6`；`Sources/NetSpeed/VPNMonitor.swift` 只按 `utun` 收集隧道，`Sources/NetSpeed/Sections/VPNSection.swift` 原先按 `monitor.status.connected` 切换按钮。
- #tunnel #openvpn #clash-tun

## FIND-002 [CPU] `proc_taskinfo` 的 CPU 时间单位是 mach tick，不是纳秒
- 日期：2026-07-29
- 现象：活动监视器显示某 node 进程 1200%，NetSpeed 菜单只显示「30%几」。整机 CPU 百分比正常，只有单进程百分比偏低。
- 根因/机制：`proc_taskinfo.pti_total_user / pti_total_system` 由内核 `task_info(TASK_ABSOLUTETIME_INFO)` 填充，单位是 **mach absolute time tick**，不是纳秒。`ProcessLister` 直接把它当纳秒做 delta 除以墙钟纳秒。Intel Mac 的 mach timebase 是 1/1，两者数值相等所以不暴露；Apple Silicon 是 **125/3 ≈ 41.667 ns/tick**，导致所有单进程 %CPU 被系统性低报约 41.7 倍（1200 ÷ 41.667 = 28.8，正好是「30%几」）。
- 影响面：`CPUMonitor.cpuThreshold = 50.0` 的 CPUGuard 完全失效——进程要真跑到 2083% 才可能触发，而 14 核机器物理上限只有 1400%，即告警一次都不会响。跑满 CPU 的失控进程不会再通知用户，直接表现为续航损失。整机百分比走 `host_statistics` 的 tick 差值，不受影响，所以问题被掩盖了。
- 引入版本：10f538f（`/bin/ps` → libproc 重构）。此前 `ps` 直接输出百分比，不涉及单位换算。
- 证据/复现：8 线程忙等进程，`top` 实测 798.3%，旧算法算出 19.2%，按 timebase 修正后 799.9%。修复后端到端验证：跑满进程持续 30s，NetSpeed 在 T+29.9s fork 出 `osascript` 发出告警。
- 修复：`ProcessLister` 读一次 `mach_timebase_info` 得到 `nsPerTick`，换算后再算百分比；口径与 `top`／活动监视器一致（多核累加，满载 N 核 = N×100%）。
- #cpu #libproc #apple-silicon #cpuguard

## FIND-003 [CPU] `topProcesses` 的多调用点会互相冲掉采样 baseline
- 日期：2026-07-29
- 现象：菜单打开时进程 CPU% 读数剧烈跳动。
- 根因/机制：`ProcessLister.topProcesses` 是有状态的（靠前后两次累计 CPU 时间求 delta），但有 4 个不同频率的调用点共用同一份 `prevSamples`：`CPUMonitor.update()`（2s）、`guardCheck()`（10s）、以及菜单打开时 `WatchedProcessesSection` 的 `structureSignature` 和 `addItems`。每次调用都会覆盖 baseline，后一次调用的采样窗口可能只剩几毫秒，delta 噪声被放大成巨大百分比误差。
- 修复：加 1 秒最小采样间隔，窗口内的重复调用直接复用上次的完整排序结果按 limit 切片。顺带省掉了菜单打开时每 2s 一次的全量 `proc_pidpath` 遍历（top 500）。
- #cpu #libproc #sampling
