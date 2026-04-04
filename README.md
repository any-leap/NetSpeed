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

## Build

```bash
swift build -c release
```

## Install

```bash
# Link to PATH (optional, for CLI)
mkdir -p ~/bin
ln -sf $(pwd)/.build/release/NetSpeed ~/bin/netspeed

# Auto-start on login
cp com.t3st.netspeed.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.t3st.netspeed.plist
```

## License

MIT
