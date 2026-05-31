# Power (Watt) Counter — Design

**Date:** 2026-05-31
**Status:** Approved (design)

## Goal

Show the power the computer is consuming, in watts:

1. A new **topbar display option** (menu-bar) showing total system power.
2. Power added to the **live info dropdown** as a total with a CPU/GPU breakdown.

## Empirical findings (verified on this machine, MacBook Pro Mac15,6 / Apple M3 Pro)

SMC and IOReport reads both work **as a normal user (uid 501)**, while the root helper is running — so power reading needs **no root and no helper changes**.

- **Total system power:** SMC key `PSTR` (`flt`, watts). Tracks load (idle ~38 W → CPU load ~45 W). This is "the watts the computer is consuming" (whole machine).
- **Per-component CPU/GPU power is NOT cleanly available via SMC** on M3 Pro (`PHPC` is SoC/package, `PG0C` looks like GPU, no clean CPU key).
- **IOReport** (private dylib `/usr/lib/libIOReport.dylib`) exposes the "Energy Model" group with aggregate channels **`CPU Energy`** and **`GPU Energy`** (the same source asitop/macmon/stats use). Reading works without root.
  - **Units differ per channel** (verified: `CPU Energy` reported in `mJ`, `GPU Energy` in `nJ`). Unit-label normalization is mandatory.
  - These are accumulating energy counters → power = (energy delta) ÷ (elapsed time between two samples).

## Architecture

One new in-app component. Nothing in this feature touches the root helper, the helper JSON pipeline (`SMCHelperMode`/`SMCProxyService`), or fan control.

### `PowerMonitor` — `Mystral/Services/PowerMonitor.swift`

`@Observable @MainActor final class PowerMonitor`. Owns the two read sources and exposes:

```swift
private(set) var totalWatts: Double?   // SMC PSTR
private(set) var cpuWatts: Double?     // IOReport "CPU Energy"
private(set) var gpuWatts: Double?     // IOReport "GPU Energy"

func sample()                          // refresh all three; call once per timer tick
```

- **Total:** its own read-only `SMCKit` connection (reuse existing class). Reads `PSTR` each `sample()`. On any failure → `totalWatts = nil`.
- **CPU/GPU:** an `IOReportPower` helper (below). On any failure → `cpuWatts`/`gpuWatts = nil`.
- No new timer: `MenuBarManager` already runs a timer at `fanController.pollingInterval` (2 s). It calls `powerMonitor.sample()` at the start of each tick. The 2 s window makes the energy-derived power naturally averaged.
- First `sample()` produces no CPU/GPU value (no previous IOReport sample for a delta) → those stay `nil` for one tick.

Ownership: `MenuBarManager` is the only consumer (topbar + live info), so it creates and owns the `PowerMonitor`.

### `IOReportPower` — `Mystral/Services/IOReportPower.swift`

Thin wrapper that `dlopen`s `/usr/lib/libIOReport.dylib` and binds the needed symbols at runtime (avoids build-time linkage to a private framework; robust across SDKs). Symbols: `IOReportCopyChannelsInGroup`, `IOReportCreateSubscription`, `IOReportCreateSamples`, `IOReportCreateSamplesDelta`, `IOReportIterate`, `IOReportChannelGetGroup`, `IOReportChannelGetChannelName`, `IOReportChannelGetUnitLabel`, `IOReportSimpleGetIntegerValue`.

- On init: copy "Energy Model" channels, create the subscription once, keep the subscription + mutable channels.
- `sample() -> (cpu: Double?, gpu: Double?)`: take a fresh sample; if a previous sample exists, build the delta, iterate channels, sum `CPU Energy` and `GPU Energy`, normalize energy to joules by the channel's unit label, divide by measured elapsed seconds → watts. Store the new sample + timestamp as previous.
- Elapsed time measured with `ProcessInfo.processInfo.systemUptime` (monotonic).
- CoreFoundation memory handled via `Unmanaged.takeRetainedValue()` on the create/copy calls.
- If `dlopen`/symbol bind/subscription fails → wrapper is inert and `sample()` returns `(nil, nil)`.

#### Energy unit normalization (pure, testable)

```
joules(rawValue, unitLabel):
  lower = unitLabel.lowercased
  contains "nj" -> raw / 1e9
  contains "uj"/"µj" -> raw / 1e6
  contains "mj" -> raw / 1e3
  else (J) -> raw
watts = joules / elapsedSeconds
```

## Topbar

`MenuBarManager.MenuBarDisplayMode` gains two cases, mirroring the temperature/RPM cases:

- `.iconAndPower = "Icon + Power"` → fan icon + `38 W`
- `.powerOnly = "Power Only"` → `38 W`

Changes:
- `showsIcon`: `.iconAndPower` → true, `.powerOnly` → false.
- `updateStatusItem()`: new cases set `button.title = prefix + powerString()`.
- `powerString()`: `totalWatts` rounded → `"38 W"`; `nil`/non-positive → `"-- W"`.

`SettingsView` "Display mode" picker uses `MenuBarDisplayMode.allCases`, so the new modes appear automatically. The temperature-source sub-picker stays gated to temperature modes (power needs no sub-source). No other settings changes; rawValue round-trip in load/reset already handles new cases.

## Live info dropdown

In `showContextMenu()` / `updateContextMenuItems()`, add power rows right after the CPU/GPU temperature rows and before the fan rows:

```
Power   38 W
CPU 17 W  ·  GPU 4 W
```

- Row 1 (total) shown when `totalWatts != nil`.
- Row 2 (breakdown) shown when at least one of `cpuWatts`/`gpuWatts` is available; missing component omitted from the string.
- Rows are disabled info items (same style as the existing CPU/GPU/fan readouts). The breakdown is kept on its own secondary line to avoid colliding with the existing `CPU …° avg` temperature row.

Items are created in `showContextMenu()` and their titles refreshed in `updateContextMenuItems()`, consistent with `liveCpuItem`/`liveGpuItem`/`liveFanItems`.

## Testing

- Pure-function unit tests (no hardware): `MenuBarDisplayMode.showsIcon` for the two new cases; `powerString()` formatting (value vs `nil`); IOReport energy→watt normalization across `mJ`/`uJ`/`nJ`/`J`.
- Hardware paths (SMC `PSTR`, IOReport subscription) verified by running the app and observing the topbar + dropdown.

## Out of scope (YAGNI)

- Power in `DashboardView` or other views (not requested).
- ANE/DRAM/other rails; per-core breakdown.
- Historical power graph; EMA smoothing (the 2 s sampling window is already smooth — revisit only if jittery).
- Any helper/root or `SMCProxyService` changes.

## Risks

- **IOReport is a private API** — undocumented, could change in a future macOS. Mitigated: it's runtime-bound via `dlopen` (failure is graceful, only the CPU/GPU breakdown disappears), the app is unsandboxed and distributed outside the App Store, and the **total (PSTR) is independent** and remains if IOReport breaks.
- A second read-only AppleSMC connection in-app alongside the helper's connection — verified to coexist (probe ran as uid 501 while the helper was active).
