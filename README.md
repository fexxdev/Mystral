# Mystral

A native macOS menu bar app for controlling fan curves on Apple Silicon Macs.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1--M5-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **Real fan control on Apple Silicon** — works on M1/M2/M3/M4 (uses the `Ftst` unlock to bypass `thermalmonitord`)
- **Menu bar presence** — always-on icon with configurable display: temperature, RPM, profile name, or a live mini-graph sparkline
- **Live dashboard** — Swift Charts 5-minute rolling history of CPU max/avg + GPU max
- **Fan curve editor** — drag-and-drop chart with synchronized editable table; per-fan curve overrides
- **Profiles** — 4 presets (Silent, Balanced, Performance, Full Blast) + up to 10 custom; inline rename, duplicate, delete
- **Auto-switch** — profiles can auto-activate based on power source (AC/Battery), thermal state, or frontmost app
- **Smoothing & hysteresis** — EMA-smoothed input temperatures + configurable deadband to eliminate fan hunting
- **Alerts** — optional notifications for high CPU temperature and fans that stop responding
- **30s stress test** — burns all CPU cores and verifies your fan curve actually reacts
- **Auto-start** — launch at login via macOS native login items
- **Localization** — English and Italian

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1, M2, M3, M4, M5)

## Installation

1. **Download** the latest `Mystral-x.x.x.dmg` from [Releases](https://github.com/fexxdev/Mystral/releases/latest).
2. **Open** the DMG and drag **Mystral.app** into the **Applications** folder.
3. **First launch:** right-click `Mystral.app` in `/Applications` → **Open** → click **Open** in the dialog.
   *(This step is needed because the app is not yet signed with a paid Apple Developer ID. Subsequent launches don't require it.)*
4. The app will ask for your password once per session to control the fans (no kernel extension required).

That's it. Profiles live in `~/Library/Application Support/Mystral`.

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/fexxdev/Mystral.git
cd Mystral
xcodegen generate
./scripts/build-dmg.sh        # produces dist/Mystral-x.x.x.dmg
# or for development:
open Mystral.xcodeproj
```

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
