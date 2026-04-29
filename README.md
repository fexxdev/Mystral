# Mystral

A native macOS menu bar app for controlling fan curves on Apple Silicon Macs.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1--M5-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **Menu bar presence** — always-on icon with configurable display (temperature, RPM, profile name)
- **Temperature sensors** — live readings from all SMC temperature sensors with sparkline history
- **Fan monitoring** — real-time RPM, target speed, and per-fan manual override
- **Fan curve editor** — drag-and-drop chart with synchronized editable table
- **Profiles** — 4 built-in presets (Silent, Balanced, Performance, Full Blast) + up to 10 custom profiles
- **Auto-start** — launch at login via macOS native login items
- **Localization** — English and Italian

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1, M2, M3, M4, M5)

## Installation

### Download

Download the latest `.dmg` from [Releases](https://github.com/fexxdev/Mystral/releases).

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/fexxdev/Mystral.git
cd Mystral
xcodegen generate
open Mystral.xcodeproj
```

Build and run in Xcode (Cmd+R).

## Usage

1. Mystral appears in the menu bar with a fan icon
2. **Left click** the icon to open the main window
3. **Right click** for quick profile switching
4. Go to **Profiles** to create custom fan curves
5. Go to **Settings** to configure auto-start and display options

## Preset Profiles

| Profile | Description |
|---------|-------------|
| Silent | Minimum fan noise, higher temperatures allowed |
| Balanced | Apple-like default curve |
| Performance | Aggressive cooling for heavy workloads |
| Full Blast | All fans at maximum speed |

## Privacy

Mystral runs entirely offline. No telemetry, no network access, no data collection.

## License

MIT — see [LICENSE](LICENSE).
