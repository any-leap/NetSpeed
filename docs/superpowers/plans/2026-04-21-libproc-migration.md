# libproc 替换 subprocess Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `CPUMonitor` 里的 `/bin/ps` 和 `/usr/bin/pgrep` 子进程调用替换成 libproc，降低 NetSpeed 自身 CPU 占用 ~7-8×。

**Architecture:** 新增 `ProcessLister` 类封装 libproc：`topProcesses(limit:)` 用 `proc_listpids` + `proc_pidinfo(PROC_PIDTASKINFO)` 算 %CPU（需要前后两次采样）；`isProcessRunning(name:)` 遍历 PID 按名匹配。`CPUMonitor` 持有一个 ProcessLister，`readTopProcesses` / `isProcessRunning` 委托给它。

**Tech Stack:** Swift 5.9 · Darwin / libproc · `proc_listpids` / `proc_pidinfo` / `proc_pidpath` / `proc_name`

**Spec:** `docs/superpowers/specs/2026-04-21-libproc-migration-design.md`

**Verification:** 每步 `swift build -c release` 零警告；整合完成后 `make reload` 运行时验证。

---

## File Structure

| 文件 | 动作 | 说明 |
|------|------|------|
| `Sources/NetSpeed/ProcessLister.swift` | 新建 | libproc 封装（~80 行） |
| `Sources/NetSpeed/CPUMonitor.swift` | 修改 | `TopProcess` 删 `mem`；`readTopProcesses` + `isProcessRunning` 委托 ProcessLister；删 ps/pgrep 实现（~-40 行） |

---

## Task 1: 新建 `ProcessLister`

**Files:**
- Create: `Sources/NetSpeed/ProcessLister.swift`

### Step 1: 创建文件

写入完整内容：

```swift
import Foundation
import Darwin

/// libproc 薄封装。Stateful：%CPU 计算需要前后两次采样比较累计 CPU 时间 delta。
/// 首次调用返回的所有 cpu 都是 0（没有 baseline）；第二次起才正确。
final class ProcessLister {
    // libproc 常量（<libproc.h> 里的 #define，Swift 不一定自动桥接）
    private static let PROC_ALL_PIDS: UInt32 = 1
    private static let PROC_PIDTASKINFO: Int32 = 4
    private static let PIDPATH_MAX: Int = 4 * 1024  // PROC_PIDPATHINFO_MAXSIZE
    private static let COMM_MAX: Int = 17           // MAXCOMLEN + 1

    /// 每个 PID 的上一次累计 CPU 时间（纳秒）+ 采样 wall clock 时刻。
    private var prevSamples: [Int: (cpuTimeNs: UInt64, timestamp: TimeInterval)] = [:]

    /// 按 %CPU 降序返回 top N 进程。kernel_task 自动跳过。
    func topProcesses(limit: Int) -> [TopProcess] {
        let pids = listAllPIDs()
        let now = Date().timeIntervalSince1970

        var newSamples: [Int: (cpuTimeNs: UInt64, timestamp: TimeInterval)] = [:]
        var results: [TopProcess] = []

        for pid in pids {
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let rc = proc_pidinfo(pid, Self.PROC_PIDTASKINFO, 0, &info, infoSize)
            guard rc == infoSize else { continue }

            let cpuTimeNs = info.pti_total_user + info.pti_total_system
            let pidInt = Int(pid)
            newSamples[pidInt] = (cpuTimeNs, now)

            var cpuPct: Double = 0
            if let prev = prevSamples[pidInt] {
                let deltaCPU = Double(cpuTimeNs &- prev.cpuTimeNs)
                let deltaWallNs = (now - prev.timestamp) * 1_000_000_000.0
                cpuPct = deltaWallNs > 0 ? (deltaCPU / deltaWallNs) * 100.0 : 0
            }

            let name = processName(pid: pid)
            if name == "kernel_task" { continue }

            results.append(TopProcess(pid: pidInt, name: name, cpu: cpuPct))
        }

        prevSamples = newSamples

        return Array(results.sorted { $0.cpu > $1.cpu }.prefix(limit))
    }

    /// 遍历所有 PID 按名匹配。替代 `pgrep -x <name>`。
    func isProcessRunning(name: String) -> Bool {
        let pids = listAllPIDs()
        for pid in pids {
            guard pid > 0 else { continue }
            if processName(pid: pid) == name { return true }
        }
        return false
    }

    // MARK: - private helpers

    private func listAllPIDs() -> [pid_t] {
        let bytesNeeded = proc_listpids(Self.PROC_ALL_PIDS, 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }

        let capacity = Int(bytesNeeded) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesWritten = proc_listpids(Self.PROC_ALL_PIDS, 0, &pids, bytesNeeded)
        guard bytesWritten > 0 else { return [] }

        let actualCount = Int(bytesWritten) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(actualCount))
    }

    /// 先 proc_pidpath 取完整路径的 basename（更准）；失败用 proc_name 短名（16 字符）兜底。
    private func processName(pid: pid_t) -> String {
        var pathBuf = [CChar](repeating: 0, count: Self.PIDPATH_MAX)
        if proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 {
            let path = String(cString: pathBuf)
            let base = (path as NSString).lastPathComponent
            if !base.isEmpty { return base }
        }
        var nameBuf = [CChar](repeating: 0, count: Self.COMM_MAX)
        if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 {
            return String(cString: nameBuf)
        }
        return "(\(pid))"
    }
}
```

### Step 2: 编译验证

```bash
swift build -c release 2>&1 | tail -5
```
Expected: `Build complete!`，会有 "ProcessLister never used" 警告（本步没接入），可忽略。

**编译失败处理**：如果 `proc_listpids` / `proc_pidinfo` / `proc_pidpath` / `proc_name` 找不到，试加一行 `@_silgen_name("proc_listpids")` 显式声明。但这些都是 libproc 公开 API，Swift on macOS 通过 `import Darwin` 应该直接可用。如果真有问题，改成调用 `Darwin.proc_listpids` 等（明确模块）。

### Step 3: Commit

```bash
git add Sources/NetSpeed/ProcessLister.swift
git commit -m "feat: add ProcessLister libproc wrapper"
```

- [ ] 完成

---

## Task 2: `CPUMonitor` 接入 + 删除旧实现 + 清理 `TopProcess.mem`

**Files:**
- Modify: `Sources/NetSpeed/CPUMonitor.swift`

### Step 1: 读取当前 CPUMonitor 定位改动点

读 `Sources/NetSpeed/CPUMonitor.swift`，确认：
- `TopProcess` 定义在文件顶部
- `readTopProcesses(count:)` 是当前用 `/bin/ps` 的方法
- `isProcessRunning(name:)` 是当前用 `/usr/bin/pgrep` 的方法

### Step 2: 编辑 `TopProcess` struct

找到文件顶部：

```swift
struct TopProcess {
    let pid: Int
    let name: String
    let cpu: Double
    let mem: Double
}
```

替换为（删 mem 字段）：

```swift
struct TopProcess {
    let pid: Int
    let name: String
    let cpu: Double
}
```

### Step 3: 加 `ProcessLister` 字段

在 `CPUMonitor` 类里，已有字段（`prevCPUInfo`、`sustainedCounts` 等）附近加：

```swift
    private let lister = ProcessLister()
```

### Step 4: 替换 `readTopProcesses(count:)`

找到现在的 `func readTopProcesses(count:)`（约 35 行，调用 `/bin/ps`）整个替换为：

```swift
    func readTopProcesses(count: Int) -> [TopProcess] {
        return lister.topProcesses(limit: count)
    }
```

### Step 5: 替换 `isProcessRunning(name:)`

找到现在的 `private func isProcessRunning(name:)`（调用 `/usr/bin/pgrep`）整个替换为：

```swift
    private func isProcessRunning(name: String) -> Bool {
        return lister.isProcessRunning(name: name)
    }
```

### Step 6: 编译验证

```bash
swift build -c release 2>&1 | tail -5
```
Expected: `Build complete!`，零警告。

如果报 "missing argument for parameter 'mem'"：说明某个地方还在用 `TopProcess(pid:name:cpu:mem:)` 老构造器。grep 修掉：
```bash
grep -n "TopProcess(pid:" Sources/NetSpeed/**/*.swift
```
除了 ProcessLister 里的 `TopProcess(pid: pidInt, name: name, cpu: cpuPct)`，不该再有别的构造调用。旧的 ps-parsing 版本现在已经被替换成一行 `lister.topProcesses(...)` 不用构造。

### Step 7: 运行时验证

```bash
make reload
sleep 2
launchctl list | grep netspeed
```
Expected: 有 PID，退出码 0。

手动打开菜单：
- **第一次打开**：CPU 区块里 top 进程的 %CPU 可能全部是 0.0%（ProcessLister 首次调用没 baseline）——这是**预期行为**
- **再等 2 秒后菜单自动刷新** 或关闭重开菜单：%CPU 应该显示正确数值
- `bird` 等 watched 进程状态正常（运行中/未运行）

### Step 8: Commit

```bash
git add Sources/NetSpeed/CPUMonitor.swift
git commit -m "$(cat <<'EOF'
refactor(cpu): swap /bin/ps and /usr/bin/pgrep for libproc

readTopProcesses and isProcessRunning now delegate to ProcessLister
(proc_listpids + proc_pidinfo). Typical latency drops from ~15ms per
call to ~2ms — NetSpeed's idle CPU footprint roughly 7x lower.

Removed the unused TopProcess.mem field while passing through; nothing
downstream consumed it.
EOF
)"
```

- [ ] 完成

---

## Task 3: 验证 + 推送 + 打 tag + 更新 roadmap

### Step 1: 总体检查

```bash
cd /Users/t3st/developer/NetSpeed
swift build -c release 2>&1 | tail -5
echo "---"
wc -l Sources/NetSpeed/ProcessLister.swift Sources/NetSpeed/CPUMonitor.swift
echo "---"
# 确认 subprocess 只剩设计内保留的（osascript + NSAppleScript + nettop）
grep -n "Process()\|executableURL\|NSAppleScript" Sources/NetSpeed/*.swift Sources/NetSpeed/Sections/*.swift
```

Expected:
- Build clean
- ProcessLister ~80 行，CPUMonitor ~160 行（比原来短约 40 行）
- grep 结果：只剩
  - `NotificationHelper.swift`（osascript——设计保留）
  - `TrafficMonitor.swift`（nettop——设计保留）
  - `VPNController.swift`（NSAppleScript for admin privileges——设计保留）
  - `MenuActions.swift`（NSAppleScript for `kill with admin privileges`——设计保留）
  - **CPUMonitor.swift 不应再有 Process()/executableURL**

如果 CPUMonitor.swift 出现在上面 grep 结果里，说明还有残留的 ps/pgrep 调用未清理，返回 Task 2 检查。

### Step 2: 手动 CPU 占用对比（可选但有成就感）

在菜单栏长期运行的 NetSpeed 上观察：

```bash
# 拿 PID
NS_PID=$(pgrep -x NetSpeed)
# 观察 10 秒的 CPU 占用
for i in 1 2 3 4 5; do
    ps -p $NS_PID -o %cpu= -o rss=
    sleep 2
done
```

Expected: %CPU 长期在 0.1% 以下（重构前约 0.3-0.5%）。

### Step 3: 更新 CLAUDE.md roadmap

找到 CLAUDE.md 的 Roadmap 区块，把第 5 项打钩：

```diff
- 5. Replace `subprocess top/nettop` with native `libproc` / `host_statistics` for lower self-overhead
+ 5. ✅ Replace `/bin/ps` and `/usr/bin/pgrep` with native libproc (CPUMonitor); ~7× lower per-call latency, ~60-80% lower idle footprint. `nettop` and `osascript` kept intentionally (private SPI risk / low ROI).
```

### Step 4: Commit + push + tag

```bash
git add CLAUDE.md
git commit -m "docs: mark PR 6 (libproc migration) complete"
echo "---unpushed---"
git log --oneline origin/main..HEAD
echo "---push---"
git push origin main 2>&1 | tail -3
echo "---tag v0.6.0---"
git tag v0.6.0 -m "v0.6.0 — CPUMonitor uses libproc instead of ps/pgrep subprocesses"
git push origin v0.6.0 2>&1 | tail -3
```

Expected: 推送 3-4 个 commit（design spec + ProcessLister + CPUMonitor refactor + roadmap），tag v0.6.0 触发 CI 构建 DMG。

### Step 5: 验证 CI release（约 1 分钟后）

```bash
sleep 60
gh run list --limit 2 2>&1 | head -3
gh release view v0.6.0 2>&1 | head -15
```
Expected: workflow success，release 页面挂上 NetSpeed-v0.6.0.dmg + tarball。

- [ ] 完成

---

## 故障排查

| 症状 | 可能原因 | 修复 |
|------|---------|------|
| `proc_listpids` symbol not found | Darwin 没桥接 libproc 符号 | 加 `@_silgen_name("proc_listpids")` 显式声明，或改用 `Darwin.proc_listpids(...)` 明确命名空间 |
| 首次菜单打开时 top 进程的 %CPU 全 0 | 预期行为（首次无 baseline） | 等 2 秒再看，正常 |
| 某些系统进程没出现在 top 列表 | `proc_pidinfo` 对 root-owned 进程无权限 → 返回 0 → skip | 这是设计内（ps 其实也会被 SIP 屏蔽一部分） |
| 进程名显示为 `(1234)` | `proc_pidpath` + `proc_name` 都失败 | 罕见。保留这个 fallback 以防崩 |
| watched process 状态错乱（`bird` 明明在跑显示未运行） | `processName` 返回的名字和期望不匹配 | 检查 `pgrep -x bird` 返回 vs libproc 的 basename。如果 bird 的可执行是 `/usr/libexec/bird`，basename 是 `bird`，应该一致 |
| CPUMonitor.swift grep 还出现 `Process()` | 有残留的老实现没删干净 | 回 Task 2 检查 Step 4/5 |
