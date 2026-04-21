# CLAUDE.md — Project context for AI assistants

This file orients an AI assistant (Claude, Copilot, etc.) working in this repo. Read it before making changes.

## What this is

A macOS menu bar system monitor for Chinese developers working behind the GFW. Shows network speed, per-process traffic, CPU/memory, and **two latency charts** (mainland direct + overseas proxy) that work correctly even under Clash TUN mode.

Differentiator: unlike iStat Menus / Stats / MenuMeters, NetSpeed uses HTTP HEAD latency (measured via `URLSessionTaskMetrics`) instead of ICMP ping, which is broken by Clash TUN.

## Build & run

**Never** `swift run` for testing — the LaunchAgent expects the release binary at `.build/release/NetSpeed`. The dev loop is:

```bash
make reload   # build + ad-hoc sign + kickstart launchd
make logs     # see recent stderr
make tail     # follow stderr live
```

First-time setup: `make install` generates the user's LaunchAgent plist from `com.t3st.netspeed.plist.tpl` (substituting `__BINARY__` with the absolute path) and bootstraps it.

Ad-hoc codesigning is part of `make build`. Do not skip it — unsigned binaries get progressively more Gatekeeper-restricted in newer macOS versions.

## Source layout

```
Sources/NetSpeed/
├── App.swift              # StatusBarController (god class, slated to split)
├── Info.plist             # embedded via Package.swift linkerSettings
├── NetMonitor.swift       # network speed (2s poll via getifaddrs)
├── CPUMonitor.swift       # CPU + top processes (subprocess `top`)
├── MemoryMonitor.swift    # memory stats (host_statistics)
├── TrafficMonitor.swift   # per-process traffic (subprocess `nettop`)
├── VPNMonitor.swift       # OpenVPN status + launch/kill via AppleScript
├── LatencyMonitor.swift   # dual latency charts (HTTP HEAD + metrics)
├── ChartView.swift        # network up/down chart
├── LatencyChartView.swift # single-line chart with nil-gap rendering
├── TrafficRankView.swift  # two-column Live / Cumulative process traffic
└── Strings.swift          # isChinese ? "中文" : "English" pattern
```

## Architectural gotchas

### Info.plist embedding
`LSUIElement=true` is required to keep NetSpeed out of the Dock and Cmd+Tab. It lives in `Sources/NetSpeed/Info.plist` and is linker-embedded into the `__TEXT.__info_plist` section via `Package.swift`'s `unsafeFlags`. SPM executables have no native Info.plist support; this is the canonical workaround.

### Menu live refresh
`rebuildMenu()` destroys and recreates all menu items — expensive and causes flicker. To avoid rebuilding every 2s, `refreshLiveViews()` mutates view data in place and relies on `currentStructureSignature()` to detect *structural* changes (e.g., a process appeared or disappeared from a top-N list). **When you add a new conditional menu section, extend the signature** or the menu will silently go stale until the next user click.

### Timer run-loop modes
All timers that must fire while a menu is open **must** be added via `RunLoop.main.add(t, forMode: .common)`. `Timer.scheduledTimer(...)` uses `.default` which blocks during NSMenu tracking — latency charts would freeze every time the user opens the menu. `LatencyMonitor.start()` and `NetMonitor.init` get this right; new timers must too.

### Clash TUN considerations
- ICMP ping is hijacked in TUN mode — do not use for latency.
- Plain TCP connect is short-circuited by the local TUN netstack — measures ~0ms to localhost Clash, not the real peer.
- TLS handshake requires real-server certificate exchange and cannot be faked.
- HTTP requests via URLSession with `httpMaximumConnectionsPerHost` default + `URLSessionTaskMetrics.responseEndDate - requestStartDate` give pure app-layer RTT and sidestep the above entirely. This is the current approach.
- `connectionProxyDictionary = [:]` does NOT bypass TUN (TUN captures at network layer, not via system HTTP proxy).

## Menu bar icon troubleshooting

If the user reports the icon is "missing":
1. Check `launchctl list | grep netspeed` — if there's a PID, the process is fine.
2. Check iPhone Continuity / Dynamic Island — it can occlude the menu bar region.
3. Check Bartender / Ice / Hidden Bar — these can hide icons.
4. Only then suspect code — run `make tail` and see stderr.

Do not start reverting commits based on "icon gone" alone. We learned this the hard way.

## Coding conventions

- Chinese comments are fine and common; the codebase is bilingual.
- Prefer `private(set)` + `var onUpdate: (() -> Void)?` callback pattern for monitors (see existing monitors).
- UI state reads must be main-threaded. `LatencyMonitor`'s `group.notify(queue: .main)` pattern is the correct way to hop back after work on a utility queue.
- YAGNI: don't generalize `ChartView` / `LatencyChartView` until there's a third chart type.

## Roadmap (ordered by PR)

1. ✅ Ops hygiene: logs, Info.plist, codesign, CLAUDE.md
2. ✅ README overhaul + CI release pipeline (DMG auto-build)
3. ✅ Split `App.swift` — data-driven MenuSection protocol + MenuBuilder + 11 extracted sections + VPNController + NotificationHelper + MenuActions. App.swift 663 → 227 lines.
4. ✅ Generalize VPN monitor: any utun-based VPN → connected; Connect/Disconnect buttons only shown when user has configured `.ovpn`; user-facing "VPN" renamed to "Tunnel / 隧道" (class names kept as-is).
5. ✅ Replace `/bin/ps` and `/usr/bin/pgrep` with native libproc (ProcessLister wrapping `proc_listpids` / `proc_pidinfo`). CPUMonitor + MemoryMonitor share the implementation. Idle CPU footprint dropped ~15× (from ~4-6% to ~0.2-0.5%). `nettop` and `osascript` kept intentionally (private SPI risk / low ROI).
6. Homebrew cask submission (requires stable Releases)
