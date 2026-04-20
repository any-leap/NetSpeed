<div align="center">

# NetSpeed

[![GitHub stars](https://img.shields.io/github/stars/any-leap/NetSpeed?style=social)](https://github.com/any-leap/NetSpeed/stargazers)
[![Release](https://img.shields.io/github/v/release/any-leap/NetSpeed?include_prereleases)](https://github.com/any-leap/NetSpeed/releases/latest)
[![License](https://img.shields.io/github/license/any-leap/NetSpeed)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

**Open-source macOS menu bar system monitor — the first one that reports honest latency under Clash TUN mode.**

![NetSpeed menu screenshot](docs/screenshot-menu.png)

[Install](#install) · [Features](#features) · [Why NetSpeed?](#why-netspeed) · [中文](README_zh.md)

</div>

## Why NetSpeed?

Every macOS system monitor uses ICMP `ping` for latency. Clash's TUN mode hijacks ICMP — so your "3 ms to Google" is a **lie**. Worse, plain TCP connect latency is also short-circuited by the TUN netstack: it measures the handshake with your local Clash, not the real server.

NetSpeed measures true end-to-end HTTP round-trip via Apple's `URLSessionTaskMetrics` (`responseEndDate − requestStartDate`). You get two independent charts:

- **Mainland Latency** — health of your direct (non-proxied) link to CN sites
- **Overseas Latency** — health of your proxy node to international sites

If either spikes, you know exactly which link is broken.

## Features

- 📊 **Fixed-width speed** — `↑ up / ↓ down` in the menu bar, no layout jumpy
- 🌏 **Dual latency charts** — Mainland (Baidu/Taobao/QQ) + Overseas (gstatic `/generate_204`, Cloudflare, GitHub), 5-min rolling window
- 🏆 **Per-process traffic** — Live + Cumulative ranked columns, reset anytime
- 🖥 **CPU & Memory** — top-5 processes each, kill from submenu
- 🚨 **CPU Guard** — notifies you when a process sustains high CPU; watches critical processes (e.g. `bird`) and alerts if they crash
- 🔐 **OpenVPN control** — connect / disconnect from menu (optional, only shown once configured)
- 🌍 **Bilingual UI** — auto-switch between 中文 and English based on system language
- 💧 **Minimal footprint** — ~15 MB RAM, <0.5% CPU idle, ~30 MB/day network for all latency probes

## Comparison

|                                      | NetSpeed | iStat Menus | Stats | MenuMeters |
| ------------------------------------ | :------: | :---------: | :---: | :--------: |
| Open-source                          |    ✅    |      ❌     |   ✅  |     ✅     |
| Free                                 |    ✅    | 💰 US$12    |   ✅  |     ✅     |
| Honest latency under Clash TUN       |    ✅    |      ❌     |   ❌  |     ❌     |
| Mainland / Overseas latency separate |    ✅    |      ❌     |   ❌  |     ❌     |
| Per-process traffic (live + total)   |    ✅    |      ✅     |   ❌  |     ❌     |
| CPU-anomaly notifications            |    ✅    |      ❌     |   ❌  |     ❌     |
| OpenVPN connect/disconnect           |    ✅    |      ❌     |   ❌  |     ❌     |

## Install

Requires **macOS 14+** and Swift 5.9 (ships with Xcode Command Line Tools).

```bash
git clone https://github.com/any-leap/NetSpeed.git
cd NetSpeed
make install
```

`make install` builds the release binary, ad-hoc codesigns it, generates your user LaunchAgent (pointing at the absolute path of the cloned directory), and starts it. The icon appears in your menu bar immediately.

> Pre-built `.dmg` will be attached to [Releases](https://github.com/any-leap/NetSpeed/releases) once v0.2.0 is tagged.

### Development

```bash
make reload   # rebuild + restart in place
make tail     # follow stderr live
make logs     # last 50 lines of stderr
make stop / make start / make uninstall
```

Logs go to `/tmp/netspeed.log` and `/tmp/netspeed.err`.

### Heads-up

- Don't relocate the cloned directory after `make install` — the LaunchAgent plist holds an absolute path. If you must move it, re-run `make install`.
- Ad-hoc signing is enough to run locally; the Release DMG will ship the same signature until proper notarization is set up. You may need to right-click → *Open* the first time macOS sees it.

## Architecture

See [CLAUDE.md](CLAUDE.md) for:

- Build flow and the reason `make reload` is preferred over `swift run`
- Why `LSUIElement=true` is embedded via linker flags (SPM limitation workaround)
- Menu live-refresh signature pattern (avoids flicker on every update)
- Timer run-loop mode gotcha (must be `.common` to fire while menu is open)
- Clash TUN caveats that shaped the latency measurement approach

## Roadmap

- [x] v0.2: dual latency charts, ops hygiene (logs, codesign, Info.plist)
- [ ] v0.3: README overhaul + CI release pipeline (this doc)
- [ ] v0.4: split monolithic `App.swift` into `MenuBuilder` / `VPNController` / `NotificationHelper`
- [ ] v0.5: generalize VPN monitor — detect any `utun` interface, OpenVPN-specific controls opt-in, rename section to "Tunnel"
- [ ] v0.6: replace `subprocess top/nettop` with native `libproc` / `host_statistics`
- [ ] v1.0: Homebrew cask submission

## Contributing

Issues and PRs welcome. If you're reading this before opening one, please also skim [CLAUDE.md](CLAUDE.md) — it documents the non-obvious architectural decisions.

## License

[MIT](LICENSE)
