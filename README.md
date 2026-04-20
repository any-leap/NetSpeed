# NetSpeed

A lightweight macOS menu bar system monitor. Displays real-time network speed, CPU, memory, and process traffic — with built-in CPU anomaly detection and alerts.

## Features

**Menu Bar**
- Two-line display: ↑ upload / ↓ download speed
- Fixed width to prevent layout jumping
- Updates every 2 seconds

**Dropdown Menu**
- Network traffic chart (last 60 seconds, smooth curves)
- Per-process traffic ranking with reset support
- CPU usage with progress bar and top 5 processes
- Memory overview (used/total, app/wired/compressed) with top 5 processes
- Kill any process via submenu (supports sudo escalation)
- Watched process monitoring (e.g., `bird` for iCloud sync) with restart option

**CPU Guard (built-in)**
- Alerts via macOS notification when a process sustains >50% CPU for 30+ seconds
- Monitors critical processes (bird) and alerts if they crash
- Abnormal processes highlighted in red
- Recent alerts history in dropdown menu

**Localization**
- Auto-detects system language (Chinese / English)

## Build & Install

```bash
make install    # build, sign, install LaunchAgent, start
```

Other targets:

```bash
make reload     # rebuild + restart (dev loop)
make logs       # last 50 lines of stderr
make tail       # follow stderr live
make uninstall  # remove LaunchAgent
```

Logs are at `/tmp/netspeed.log` and `/tmp/netspeed.err`.

## License

MIT
