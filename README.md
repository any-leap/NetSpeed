# NetSpeed

A minimal macOS menu bar app that displays real-time upload and download speed in two lines.

## Features

- Two-line display in menu bar: ↑ upload / ↓ download
- Updates every 2 seconds
- Counts only physical interfaces (`en*`) to avoid double-counting with VPN/TUN
- Lightweight, no Dock icon, pure Swift

## Build

```bash
swift build -c release
```

## Install

```bash
# Auto-start on login
cp com.t3st.netspeed.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.t3st.netspeed.plist
```

## License

MIT
