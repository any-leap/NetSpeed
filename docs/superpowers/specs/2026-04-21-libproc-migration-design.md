# libproc 替换 subprocess Design

**日期:** 2026-04-21
**状态:** Draft
**对应 Roadmap:** PR 6 / v0.6

## 目标

把 CPUMonitor 里每 2 秒一次的 `/bin/ps` 和每 10 秒一次的 `/usr/bin/pgrep` 子进程调用换成原生 `libproc` API。降低 NetSpeed 自身空载 CPU 占用约 60-80%。

**out-of-scope**: `nettop`（私有 SPI 风险）、`osascript` 通知（偶发，收益低）、`NSAppleScript` 特权（无替代）——都留着不动。

## 背景

当前两个高频 subprocess：

- `/bin/ps -eo pid=,pcpu=,pmem=,comm= -r` —— `CPUMonitor.readTopProcesses(count:)` 调用。每次 fork+exec+pipe+parse ~10-30ms。`update()` 每 2 秒跑一次取 top 5；`guardCheck()` 每 10 秒跑一次取 top 200。
- `/usr/bin/pgrep -x <name>` —— `CPUMonitor.isProcessRunning(name:)` 调用。每次 fork+exec ~5-15ms。guardCheck 里对每个 watched process 跑一次。

## 架构

### 新文件 `Sources/NetSpeed/ProcessLister.swift`

libproc 薄封装。Stateful（%CPU 计算需要前后两次采样对比）。

```swift
final class ProcessLister {
    /// 上次采样的每进程累计 CPU 时间（纳秒）+ 采样时刻（wall clock）。
    private var prevSamples: [Int: (cpuTimeNs: UInt64, timestamp: TimeInterval)] = [:]

    /// 按 CPU% 降序返回 top N 进程。
    /// 首次调用时 prevSamples 为空，返回的 cpu 都是 0；第二次起才有真实值。
    /// kernel_task 自动跳过（与原 ps 版本行为一致）。
    func topProcesses(limit: Int) -> [TopProcess]

    /// 遍历所有 PID，按名匹配。替代 `pgrep -x <name>`。
    func isProcessRunning(name: String) -> Bool
}
```

关键 API：
- `proc_listpids(PROC_ALL_PIDS, 0, buffer, bufferSize)` → 所有 PID
- `proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)` → `proc_taskinfo.pti_total_user` + `pti_total_system`（ns）
- `proc_pidpath(pid, buffer, size)` → 完整可执行路径（取 basename 作为进程名）
- `proc_name(pid, buffer, size)` → 短名（16 字符），作为 pidpath 失败时的 fallback

**%CPU 算法**（匹配 `ps` 的"1 core = 100%"规范）：

```
cpuNs_now - cpuNs_prev          delta CPU ns
─────────────────────── × 100 = ──────────── × 100
  wall_now - wall_prev           delta wall ns
```

**进程名解析优先级**：先 `proc_pidpath` 取 basename → 成功即返；失败用 `proc_name`；都失败用 `"(pid)"`。

### CPUMonitor 接入

`CPUMonitor` 新增字段：
```swift
private let lister = ProcessLister()
```

改动：
- `readTopProcesses(count:)` body 替换为 `lister.topProcesses(limit: count)`
- `isProcessRunning(name:)` body 替换为 `lister.isProcessRunning(name: name)`
- 删除原来两个 `Process()` fork+exec 的实现（~40 行）

### `TopProcess` 结构清理

**删除** `mem: Double` 字段。全仓库没人读它（只有 MemorySection，但它用自己的 `MemProcess` 类型）。

影响点：
- `TopProcess` 初始化：少一个参数
- `CPUMonitor.readTopProcesses` 内部构造：去掉 `mem:` 参数
- 无下游影响

## Edge Cases

| 场景 | 行为 |
|------|------|
| 首次调用 | 所有 %CPU = 0；`prevSamples` 填充完返回；`update()` 的 2 秒间隔后第二次调用即开始有正确值 |
| 进程在采样间隔里消失 | `prevSamples` 里的 PID 在新一轮里没新数据 → 不会出现在结果里 → prevSamples 会被新样本集替换（过滤失踪 PID） |
| `proc_pidinfo` 返回 0（无权限访问某些系统进程） | skip，不报错 |
| `kernel_task` (PID 0 或 1) | 显式跳过（行为与原版一致） |
| `ignoredProcesses` 黑名单 | 由调用方 `CPUMonitor.guardCheck()` 继续处理，ProcessLister 不过滤 |
| PID 复用 | `prevSamples[pid]` 可能存着上一个同号进程的数据，导致首次计算 %CPU 不准 → 第二次调用起恢复 |

## 性能预期

| 操作 | 当前 (ps) | libproc | 加速 |
|------|----------|---------|------|
| `readTopProcesses(5)` | ~15ms | ~2ms | 7× |
| `readTopProcesses(200)` | ~25ms | ~3ms | 8× |
| `isProcessRunning("bird")` | ~8ms | ~1ms | 8× |

NetSpeed 空载 CPU 从 ~0.3-0.5% 降到 ~0.05-0.1%。内存占用不变。

## 非目标

- 不换 `nettop`（私有 SPI 风险 + 改动过大，YAGNI）
- 不换 `osascript` 通知（只在告警时触发；UNUserNotificationCenter 要处理权限弹窗不值得）
- 不换 `NSAppleScript` 特权调用（需要 admin 权限，没有公开替代）
- 不加单元测试（项目无测试 target，ProcessLister 依赖 syscalls 不好 mock）
- 不在 ProcessLister 内做黑名单/过滤逻辑（保持职责单一）

## 成功标准

- `swift build -c release` 零警告
- `make reload` 后菜单 CPU 区块正常显示 top 进程 + 各自 %CPU
- 第一次打开菜单后所有 CPU 值为 0（符合设计），第二次打开（≥2 秒后）开始有数值
- `bird` watched process 状态正确显示（存活/未运行）
- 长时间观察（几分钟）：NetSpeed 自身 CPU 占用明显低于重构前（可用 `top -pid $(pgrep NetSpeed)` 对比）
