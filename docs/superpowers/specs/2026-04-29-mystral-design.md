# Mystral — macOS Fan Control for Apple Silicon

## Overview

Mystral is a native macOS menu bar app for controlling fan curves on Apple Silicon Macs (M1–M5). It reads temperature sensors and fan RPM via SMC, lets users define custom fan curves per profile, and runs as a persistent background service with a menu bar presence.

**Target:** macOS 14+ on Apple Silicon (M1, M2, M3, M4, M5).
**Distribution:** Open source on GitHub. Release DMGs use Developer ID signing when release credentials are available; local builds are ad-hoc signed.
**Languages:** English (default) + Italian localization.

## Architecture

```
Mystral.app
├── MystralApp            — App entry, lifecycle, menu bar setup
├── MenuBarManager        — NSStatusItem, configurable display
├── MainUI (SwiftUI)      — NavigationSplitView with sidebar
├── FanController         — Polling loop, applies active curve
├── ProfileManager        — Load/save profiles, preset management
├── SMCService            — Swift wrapper over SMC read/write
└── SMCHelper (LaunchDaemon + private IPC) — Privileged helper for fan write access
```

### Component Responsibilities

**MystralApp** — SwiftUI App with `@NSApplicationDelegateAdaptor`. Sets `LSUIElement = true` (no dock icon). Creates NSStatusItem and manages the main window lifecycle. Window close hides (not terminates).

**MenuBarManager** — Owns the NSStatusItem. Configurable display: icon only, icon + temperature, icon + RPM, icon + active profile name. Left click opens/focuses main window. Right click shows a context menu with quick profile switch.

**MainUI** — NavigationSplitView with sidebar:
- Dashboard: CPU/GPU temp overview, fan RPM gauges, active profile with quick switch
- Sensors: table of all SMC temperature sensors with live values and sparklines (~60s history)
- Fans: list of fans with current RPM, target RPM, percentage, manual override slider (overrides the active profile curve for that fan until profile is re-applied)
- Profiles: 4 fixed presets (locked) + up to 10 custom. Duplicate preset to create custom. Click profile opens curve editor.
- Settings: auto-start toggle, menu bar display config, polling interval (2s/5s/10s), language, reset defaults

**Curve Editor** — Embedded in profile editing view. Split layout:
- Left: Chart with draggable control points, linear interpolation between points. X-axis = temperature (°C), Y-axis = fan speed (% of max RPM).
- Right: Editable table of (temperature, RPM%) pairs. Bidirectional sync with chart.
- Dropdown to select which sensor drives the curve (default: CPU package average).
- Minimum 2 points, maximum 10 points per curve.

**FanController** — Runs a timer (configurable interval, default 2s). Each tick: reads relevant sensor temp → looks up active profile curve → interpolates target RPM% → writes to fans via SMCService. Exposes `currentReadings` as an `@Observable` for UI binding. Architecture includes a `ProfileActivationStrategy` protocol (manual-only implementation now, but ready for future schedule/app/temp-based auto-switch).

**ProfileManager** — Reads/writes JSON files in `~/Library/Application Support/Mystral/profiles/`. Preset profiles are bundled in the app bundle (read-only). Custom profiles are user-created. Each profile stores: id, name, icon, isPreset, fanCurve (array of temp→RPM% points), sensorKey (which sensor drives the curve).

**SMCService** — Swift class wrapping IOKit SMC calls. Methods:
- `getAllSensors() -> [Sensor]` — enumerate all temperature keys
- `readTemperature(key: String) -> Double` — read a sensor value
- `getAllFans() -> [Fan]` — enumerate fans
- `readFanSpeed(index: Int) -> Int` — read current RPM
- `setFanSpeed(index: Int, percentage: Double)` — set fan speed (via helper)
- `setFanMode(index: Int, mode: FanMode)` — auto or forced

**SMC Helper (LaunchDaemon)** — A root LaunchDaemon writes fan speed values to SMC. The app and helper exchange JSON files in a private per-user IPC directory. The helper validates the directory owner, permissions, command whitelist, finite numeric values, and a session heartbeat before applying commands. It restores automatic fan control after heartbeat loss, SMC errors, sleep, or termination.

## Data Model

```swift
struct Profile: Codable, Identifiable {
    let id: UUID
    var name: String
    var icon: String          // SF Symbol name
    var isPreset: Bool
    var curvePoints: [CurvePoint]
    var sensorKey: String     // SMC key that drives this curve
}

struct CurvePoint: Codable {
    var temperature: Double   // °C
    var fanPercentage: Double // 0–100
}

struct Sensor: Identifiable {
    let id: String            // SMC key (e.g. "Tp09")
    let name: String          // Human-readable
    var temperature: Double
}

struct Fan: Identifiable {
    let id: Int               // Fan index
    let name: String
    var currentRPM: Int
    var targetRPM: Int
    var maxRPM: Int
    var mode: FanMode         // .auto or .forced
}

enum FanMode {
    case auto
    case forced
}
```

## Preset Profiles

| Profile      | Description                     | Curve                                          |
|-------------|----------------------------------|-------------------------------------------------|
| Silent       | Fans as low as possible          | 30°→10%, 50°→20%, 70°→40%, 85°→60%, 95°→80%   |
| Balanced     | Default Apple-like behavior      | 30°→15%, 50°→30%, 65°→50%, 80°→75%, 95°→100%  |
| Performance  | Aggressive cooling for workloads | 30°→25%, 45°→45%, 60°→70%, 75°→90%, 85°→100%  |
| Full Blast   | All fans at 100% always          | 0°→100%                                         |

## Auto-Start

Use `SMAppService.mainApp` (macOS 13+) to register as a login item. This is the modern replacement for LaunchAgents and works without a separate plist. Toggle in Settings.

## File Structure

```
Mystral/
├── Mystral.xcodeproj
├── Mystral/
│   ├── MystralApp.swift
│   ├── AppDelegate.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   ├── Localizable.xcstrings     — EN + IT
│   ├── MenuBar/
│   │   └── MenuBarManager.swift
│   ├── Views/
│   │   ├── MainView.swift         — NavigationSplitView
│   │   ├── DashboardView.swift
│   │   ├── SensorsView.swift
│   │   ├── FansView.swift
│   │   ├── ProfilesView.swift
│   │   ├── CurveEditorView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   ├── Profile.swift
│   │   ├── Sensor.swift
│   │   └── Fan.swift
│   ├── Services/
│   │   ├── AppSettings.swift
│   │   ├── SMCIPC.swift
│   │   ├── SMCHelperMode.swift
│   │   ├── SMCService.swift
│   │   ├── FanController.swift
│   │   └── ProfileManager.swift
│   ├── Utilities/
│   │   └── SMCKit.swift           — Low-level IOKit SMC bridge
│   └── Presets/
│       ├── silent.json
│       ├── balanced.json
│       ├── performance.json
│       └── fullblast.json
├── MystralTests/
├── README.md
├── LICENSE                        — MIT
└── .github/
    └── workflows/
        └── ci.yml                 — Generate, build, test, lint, and measure coverage
```

## SMC Access on Apple Silicon

Apple Silicon Macs expose SMC through `AppleSMC` IOService. Key differences from Intel:
- Temperature keys follow `Tp*` pattern (e.g., `Tp09` for CPU efficiency cores)
- Fan keys: `F0Ac` (actual speed), `F0Mn` (min), `F0Mx` (max), `F0Tg` (target)
- Writing fan target requires `F0Md` set to 1 (forced mode) first
- All M-series chips (M1–M5) use the same SMC interface, different key sets

The SMCService will enumerate available keys at startup rather than hardcoding, ensuring compatibility across chip generations.

## Security & Permissions

- **No App Sandbox** — needed for IOKit SMC access. Release DMGs require Developer ID signing before automatic updates can install them.
- **Privileged helper** — only fan control requires root. The LaunchDaemon accepts only validated JSON commands from the private IPC directory.
- **Network use is limited** — the app collects no telemetry. Optional update checks read GitHub Releases and accept only trusted, signed bundles.

## Future Architecture Hooks

The `ProfileActivationStrategy` protocol enables future auto-switching:
```swift
protocol ProfileActivationStrategy {
    func shouldActivate(profile: Profile, context: SystemContext) -> Bool
}
```
`SystemContext` will carry current temps, running apps, time of day. For v1, only `ManualActivationStrategy` is implemented.

## Out of Scope for v1

- Automatic profile switching (schedule, per-app, per-temperature)
- Widgets (macOS widgets can't write to SMC)
- Multiple fan curves per profile (one curve controls all fans proportionally)
- Sparkle auto-update (manual download from GitHub releases for v1)
- Fan speed notifications/alerts
