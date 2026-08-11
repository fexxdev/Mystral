# Mystral

A native macOS menu bar app for controlling fan curves on Apple Silicon Macs.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1--M5-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

<img width="1036" height="680" alt="Snapzy_2026-05-17_13-18-57_926" src="https://github.com/user-attachments/assets/8f58606a-a3d3-4066-ae61-1c5e6805ccfe" />

<img width="1036" height="680" alt="Snapzy_2026-05-17_13-19-06_819" src="https://github.com/user-attachments/assets/fa2aecbc-c29f-4630-ace3-084b726111cf" />

<img width="1036" height="680" alt="Snapzy_2026-05-17_13-19-10_545" src="https://github.com/user-attachments/assets/6adad4a6-1347-4c5d-a233-18e07653a2f8" />

<img width="1036" height="680" alt="Snapzy_2026-05-17_13-19-14_198" src="https://github.com/user-attachments/assets/046d4514-0c96-4686-8a03-f6c6191086f4" />

<img width="1036" height="680" alt="Snapzy_2026-05-17_13-19-18_730" src="https://github.com/user-attachments/assets/0f5b0c45-2cc2-41db-b9db-3d320f2b2a79" />


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
3. **First launch:** Developer ID releases open normally. Ad-hoc builds need a right-click on `Mystral.app` in `/Applications`, then **Open**, then **Open** again in the dialog.
4. The app asks for your password to install its root-owned launchd helper. It asks again only when the helper build changes. It does not need a kernel extension.

The built-in updater accepts strictly code-signed release DMGs. Developer ID signing is recommended for public distribution; the repository script creates strict ad-hoc builds when no identity is configured.

That's it. Profiles live in `~/Library/Application Support/Mystral`.

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/fexxdev/Mystral.git
cd Mystral
xcodegen generate
./scripts/build-dmg.sh        # ad-hoc DMG in dist/Mystral-x.x.x.dmg
# for a Developer ID release:
MYSTRAL_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
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

Mystral collects no telemetry or usage data. It checks GitHub Releases only when update checks are enabled.

## License

MIT — see [LICENSE](LICENSE).
