## GOT-001 [LaunchAgent] `kickstart` can keep a freshly signed binary blocked
### 症状
`make reload` 后 `launchctl list | grep netspeed` 显示 `-9 com.t3st.netspeed`，`launchctl print gui/$(id -u)/com.t3st.netspeed` 里出现 `last exit reason = OS_REASON_CODESIGNING` 和 `needs LWCR update`。
### 原因
`make build` 会重新 ad-hoc codesign `.build/release/NetSpeed`。只用 `launchctl kickstart -k` 重启旧 LaunchAgent job 时，launchd 可能继续使用旧的 lightweight code requirement 状态，不接受刚签过的新二进制。
### 恢复步骤
用完整重注册代替单纯 kickstart：

```bash
make stop && make start
```

`bootout` 后立刻 `bootstrap` 偶尔会撞到 launchd 尚未释放旧 job 的竞态，因此 `make reload` 已改为先 `bootout`，短暂等待，再 `bootstrap`。以后日常开发仍直接用 `make reload`。

#launchagent #codesign

## GOT-002 [CPUGuard] 验证告警时极易得到假阴性
### 症状
手工制造一个跑满 CPU 的进程验证 CPUGuard，观察不到任何告警，误以为功能坏了。

### 两个坑
1. **通知进程活得极短。** `NotificationHelper` 用 `Process()` 起 `/usr/bin/osascript` 发通知，存活约 100ms。用 `pgrep` 每秒轮询一次子进程几乎必然错过。要用 ~20ms 的紧密轮询，并且在同一份 `proc_bsdinfo` 快照里读 `pbi_comm` 取名字——等检测到再调 `proc_name` 时进程往往已经退出，只能拿到空字符串。
2. **告警有 300 秒 per-name 冷却。** `CPUMonitor.lastAlertTime` 按**进程名**（不是 PID）记冷却时间。同名进程反复测试时，第二次起会被静默 5 分钟。**每次验证都要换一个全新的进程名。**

另注意 `NetSpeed` 本身还会常驻 fork `nettop`（`TrafficMonitor`），按子进程判断告警时必须按名字过滤出 `osascript`。

### 可用的验证方法
跑满 CPU 的进程需持续 **30s**（阈值 50%，`guardCheck` 每 10s 一次、需连续 3 次）才会告警。用全新名字的忙等进程 + 20ms 轮询监视 NetSpeed 子进程，正常应在 T+30s 左右看到 `comm=osascript`。

#cpuguard #notification #testing
