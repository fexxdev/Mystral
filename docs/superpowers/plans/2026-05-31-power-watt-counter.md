# Power (Watt) Counter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the computer's power draw in watts — total in the menu-bar, with a System/CPU/GPU breakdown in the live dropdown.

**Architecture:** One new in-app component `PowerMonitor` reads total system power from SMC key `PSTR` (read-only, no root) and CPU/GPU power from the private IOReport "Energy Model" channels. `MenuBarManager` owns it, samples it on its existing 2 s timer, and renders it. Nothing touches the root helper, the helper JSON pipeline, or fan control.

**Tech Stack:** Swift 6, AppKit/SwiftUI, XCTest, XcodeGen, IOKit (AppleSMC via existing `SMCKit`), private `libIOReport.dylib` (runtime-bound via `dlopen`).

**Verified empirically on the target machine (M3 Pro, Mac15,6):** SMC `PSTR` and IOReport "CPU Energy"/"GPU Energy" both read as a normal user (uid 501) while the root helper is running. IOReport energy channels report in mixed units (CPU in `mJ`, GPU in `nJ`) — unit-label normalization is mandatory.

---

## Build / Test commands (this project)

- Regenerate the Xcode project after adding/removing files (project uses explicit file refs, NOT synchronized groups):
  ```bash
  xcodegen generate
  ```
- Build:
  ```bash
  xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -destination 'platform=macOS' build
  ```
- Run all tests:
  ```bash
  xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS'
  ```
- Run a single test class (faster):
  ```bash
  xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -only-testing:MystralTests/IOReportPowerTests
  ```

> Whenever a task **creates** a new `.swift` file, run `xcodegen generate` before building/testing so the file is added to the target.

---

## File Structure

- **Create** `Mystral/Services/IOReportPower.swift` — runtime binding to `libIOReport.dylib`; subscribes to "Energy Model"; `sample()` returns CPU/GPU watts via energy-delta ÷ elapsed time. Holds the pure `energyToJoules(raw:unit:)` normalizer.
- **Create** `Mystral/Services/PowerMonitor.swift` — `@Observable @MainActor`; owns a read-only `SMCKit` (for `PSTR`) and an `IOReportPower`; exposes `totalWatts`/`cpuWatts`/`gpuWatts` and `sample()`.
- **Modify** `Mystral/MenuBar/MenuBarManager.swift` — two new `MenuBarDisplayMode` cases; pure watt formatters; own a `PowerMonitor`; sample it on the timer; render topbar title + two live-info rows.
- **Create** `MystralTests/IOReportPowerTests.swift` — unit tests for `energyToJoules`.
- **Modify** `MystralTests/MenuBarTests.swift` — fix `allCases` count, add `showsIcon` cases, add formatter tests.

No changes to `SettingsView` (its picker reads `MenuBarDisplayMode.allCases`), the helper, or `SMCProxyService`.

---

## Task 1: IOReport energy→joule normalizer (pure, TDD)

**Files:**
- Create: `Mystral/Services/IOReportPower.swift`
- Test: `MystralTests/IOReportPowerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MystralTests/IOReportPowerTests.swift`:

```swift
import XCTest
@testable import Mystral

final class IOReportPowerTests: XCTestCase {
    func testNanojoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000_000_000, unit: "nJ"), 1.0, accuracy: 1e-9)
    }

    func testMicrojoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000_000, unit: "uJ"), 1.0, accuracy: 1e-9)
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000, unit: "µJ"), 0.001, accuracy: 1e-9)
    }

    func testMillijoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000, unit: "mJ"), 1.0, accuracy: 1e-9)
    }

    func testJoulesDefault() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 5, unit: "J"), 5.0, accuracy: 1e-9)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 2_000, unit: "MJ"), 2.0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Create the file with the minimal pure function**

Create `Mystral/Services/IOReportPower.swift`:

```swift
import Foundation

final class IOReportPower {
    /// Convert an IOReport energy counter (with its unit label) to joules.
    /// IOReport reports different units per channel (e.g. CPU in mJ, GPU in nJ).
    static func energyToJoules(raw: Int64, unit: String) -> Double {
        let u = unit.lowercased()
        if u.contains("nj") { return Double(raw) / 1e9 }
        if u.contains("uj") || u.contains("µj") { return Double(raw) / 1e6 }
        if u.contains("mj") { return Double(raw) / 1e3 }
        return Double(raw)
    }
}
```

- [ ] **Step 3: Regenerate project so the new files are in the target**

Run: `xcodegen generate`
Expected: `Created project at Mystral.xcodeproj`

- [ ] **Step 4: Run the test — expect PASS**

Run: `xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -only-testing:MystralTests/IOReportPowerTests`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Mystral/Services/IOReportPower.swift MystralTests/IOReportPowerTests.swift Mystral.xcodeproj
git commit -m "feat(power): add IOReport energy→joule normalizer"
```

---

## Task 2: Flesh out IOReportPower (dlopen + subscription + sample)

This is hardware-bound code (no unit test); verified by building and later by running the app. Replace the file body created in Task 1, keeping `energyToJoules` unchanged.

**Files:**
- Modify: `Mystral/Services/IOReportPower.swift`

- [ ] **Step 1: Replace the file with the full implementation**

```swift
import Foundation

/// Reads CPU and GPU power from the private IOReport "Energy Model" channels.
/// Bound at runtime via dlopen so we never link the private framework at build time.
/// All use is confined to the main actor by its owner (`PowerMonitor`).
final class IOReportPower {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSub = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<AnyObject>?
    private typealias CreateSamples = @convention(c) (AnyObject?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IterateFn = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Int32
    private typealias ChanStr = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleInt = @convention(c) (CFDictionary, Int32) -> Int64

    private let copyChannels: CopyChannels
    private let createSub: CreateSub
    private let createSamples: CreateSamples
    private let createDelta: CreateDelta
    private let iterate: IterateFn
    private let chanName: ChanStr
    private let getUnit: ChanStr
    private let simpleInt: SimpleInt

    private let subscription: AnyObject
    private let channels: CFMutableDictionary
    private var previous: CFDictionary?
    private var previousUptime: TimeInterval = 0

    init?() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func bind<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let cc = bind("IOReportCopyChannelsInGroup", CopyChannels.self),
              let cs = bind("IOReportCreateSubscription", CreateSub.self),
              let csa = bind("IOReportCreateSamples", CreateSamples.self),
              let cd = bind("IOReportCreateSamplesDelta", CreateDelta.self),
              let it = bind("IOReportIterate", IterateFn.self),
              let cn = bind("IOReportChannelGetChannelName", ChanStr.self),
              let gu = bind("IOReportChannelGetUnitLabel", ChanStr.self),
              let si = bind("IOReportSimpleGetIntegerValue", SimpleInt.self) else { return nil }
        copyChannels = cc; createSub = cs; createSamples = csa; createDelta = cd
        iterate = it; chanName = cn; getUnit = gu; simpleInt = si

        guard let chans = cc("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, chans) else { return nil }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = cs(nil, mut, &subbed, 0, nil)?.takeRetainedValue() else { return nil }
        channels = mut
        subscription = sub
    }

    /// Returns (cpu, gpu) watts. Components are nil when unavailable (e.g. the
    /// first call, before there is a previous sample to diff against).
    func sample() -> (cpu: Double?, gpu: Double?) {
        guard let current = createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return (nil, nil)
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = current; previousUptime = now }
        guard let prev = previous else { return (nil, nil) }
        let elapsed = now - previousUptime
        guard elapsed > 0,
              let delta = createDelta(prev, current, nil)?.takeRetainedValue() else { return (nil, nil) }

        var cpuJoules = 0.0, gpuJoules = 0.0
        var sawCPU = false, sawGPU = false
        _ = iterate(delta) { [self] channel in
            let name = (chanName(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let unit = (getUnit(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let raw = simpleInt(channel, 0)
            if name == "CPU Energy" {
                cpuJoules += IOReportPower.energyToJoules(raw: raw, unit: unit); sawCPU = true
            } else if name == "GPU Energy" {
                gpuJoules += IOReportPower.energyToJoules(raw: raw, unit: unit); sawGPU = true
            }
            return 0
        }
        return (sawCPU ? cpuJoules / elapsed : nil, sawGPU ? gpuJoules / elapsed : nil)
    }

    /// Convert an IOReport energy counter (with its unit label) to joules.
    /// IOReport reports different units per channel (e.g. CPU in mJ, GPU in nJ).
    static func energyToJoules(raw: Int64, unit: String) -> Double {
        let u = unit.lowercased()
        if u.contains("nj") { return Double(raw) / 1e9 }
        if u.contains("uj") || u.contains("µj") { return Double(raw) / 1e6 }
        if u.contains("mj") { return Double(raw) / 1e3 }
        return Double(raw)
    }
}
```

> Note on CF memory: `Copy`/`Create` calls are +1 → `takeRetainedValue()`; `Get` accessors (`...GetChannelName`, `...GetUnitLabel`) are +0 → `takeUnretainedValue()`. The parenthesized `(…?.takeUnretainedValue()).map { $0 as String }` bridges the optional `CFString` to `String` — the parens are required so `.map` applies to the optional, not to the non-optional `CFString` from `takeUnretainedValue()`.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`, no concurrency/Sendable errors.

- [ ] **Step 3: Run the full test suite (ensure nothing broke)**

Run: `xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -only-testing:MystralTests/IOReportPowerTests`
Expected: PASS (the 5 normalizer tests still pass against the moved function).

- [ ] **Step 4: Commit**

```bash
git add Mystral/Services/IOReportPower.swift
git commit -m "feat(power): read CPU/GPU watts from IOReport Energy Model"
```

---

## Task 3: PowerMonitor

**Files:**
- Create: `Mystral/Services/PowerMonitor.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

/// Reads instantaneous power: total system power from SMC `PSTR`, and CPU/GPU
/// power from IOReport. All reads are user-level (no root). Sampled once per
/// menu-bar timer tick by `MenuBarManager`.
@Observable
@MainActor
final class PowerMonitor {
    private(set) var totalWatts: Double?
    private(set) var cpuWatts: Double?
    private(set) var gpuWatts: Double?

    private let smc: SMCKit?
    private let ioreport: IOReportPower?

    init() {
        let kit = SMCKit()
        var opened: SMCKit?
        do { try kit.open(); opened = kit } catch { opened = nil }
        smc = opened
        ioreport = IOReportPower()
    }

    func sample() {
        if let smc, let watts = try? smc.readFloat(key: "PSTR"), watts > 0 {
            totalWatts = watts
        } else {
            totalWatts = nil
        }
        let reading = ioreport?.sample() ?? (nil, nil)
        cpuWatts = reading.cpu
        gpuWatts = reading.gpu
    }
}
```

- [ ] **Step 2: Regenerate project**

Run: `xcodegen generate`
Expected: `Created project at Mystral.xcodeproj`

- [ ] **Step 3: Build**

Run: `xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Mystral/Services/PowerMonitor.swift Mystral.xcodeproj
git commit -m "feat(power): add PowerMonitor (PSTR total + IOReport CPU/GPU)"
```

---

## Task 4: Menu-bar display modes + watt formatters (TDD)

**Files:**
- Modify: `Mystral/MenuBar/MenuBarManager.swift` (enum at lines 11-26; add `nonisolated static` formatters to the class)
- Modify: `MystralTests/MenuBarTests.swift`

- [ ] **Step 1: Update tests first**

In `MystralTests/MenuBarTests.swift`, change the count assertion:

```swift
    func testAllCasesCount() {
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 9)
    }
```

Add these test methods to the same class:

```swift
    func testShowsIconForPowerModes() {
        XCTAssertTrue(MenuBarDisplayMode.iconAndPower.showsIcon)
        XCTAssertFalse(MenuBarDisplayMode.powerOnly.showsIcon)
    }

    func testFormatTotalWatts() {
        XCTAssertEqual(MenuBarManager.formatTotalWatts(nil), "-- W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(0), "-- W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(38.4), "38 W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(44.6), "45 W")
    }

    func testFormatPowerBreakdown() {
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 17.2, gpu: 4.1), "CPU 17 W  ·  GPU 4 W")
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 17.0, gpu: nil), "CPU 17 W")
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: nil, gpu: 4.0), "GPU 4 W")
        XCTAssertNil(MenuBarManager.formatPowerBreakdown(cpu: nil, gpu: nil))
    }
```

- [ ] **Step 2: Run tests — expect FAIL (won't compile: missing cases/methods)**

Run: `xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -only-testing:MystralTests/MenuBarTests`
Expected: FAIL — `type 'MenuBarDisplayMode' has no member 'iconAndPower'` etc.

- [ ] **Step 3: Add the enum cases**

In `Mystral/MenuBar/MenuBarManager.swift`, add two cases to `MenuBarDisplayMode` (after `case miniGraph`):

```swift
    case iconAndPower = "Icon + Power"
    case powerOnly = "Power Only"
```

Update `showsIcon` to include them:

```swift
    var showsIcon: Bool {
        switch self {
        case .iconOnly, .iconAndTemperature, .iconAndRPM, .iconAndProfile, .iconAndPower: return true
        case .temperatureOnly, .rpmOnly, .miniGraph, .powerOnly: return false
        }
    }
```

- [ ] **Step 4: Add the pure formatters to `MenuBarManager`**

Add these `nonisolated static` methods inside the `MenuBarManager` class (e.g. just below `infoItem(_:)`):

```swift
    nonisolated static func formatTotalWatts(_ watts: Double?) -> String {
        guard let w = watts, w > 0 else { return "-- W" }
        return "\(Int(w.rounded())) W"
    }

    nonisolated static func formatPowerBreakdown(cpu: Double?, gpu: Double?) -> String? {
        var parts: [String] = []
        if let c = cpu, c >= 0 { parts.append("CPU \(Int(c.rounded())) W") }
        if let g = gpu, g >= 0 { parts.append("GPU \(Int(g.rounded())) W") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
```

- [ ] **Step 5: Run tests — expect PASS**

Run: `xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -only-testing:MystralTests/MenuBarTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Mystral/MenuBar/MenuBarManager.swift MystralTests/MenuBarTests.swift
git commit -m "feat(power): add Power menu-bar modes and watt formatters"
```

---

## Task 5: Render total power in the menu-bar title

**Files:**
- Modify: `Mystral/MenuBar/MenuBarManager.swift` (add `powerMonitor`; sample on timer; new title cases)

- [ ] **Step 1: Add the PowerMonitor property**

In `MenuBarManager`, alongside the other stored properties (e.g. after `private var liveProfileItems: [NSMenuItem] = []`):

```swift
    private let powerMonitor = PowerMonitor()
```

- [ ] **Step 2: Sample power on the existing timer**

In `startUpdating()`, add the sample call at the top of the timer closure, before `syncFromDefaults()`:

```swift
    private func startUpdating() {
        let timer = Timer(timeInterval: fanController.pollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.powerMonitor.sample()
                self?.syncFromDefaults()
                self?.updateStatusItem()
                self?.updateContextMenuItems()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }
```

- [ ] **Step 3: Add a `powerString()` helper and render it**

Add next to `temperatureString()` / `rpmString()`:

```swift
    private func powerString() -> String {
        Self.formatTotalWatts(powerMonitor.totalWatts)
    }
```

In `updateStatusItem()`, add a case to the `switch displayMode` (after the `.iconAndProfile` case, before `.miniGraph`):

```swift
        case .iconAndPower, .powerOnly:
            button.title = prefix + powerString()
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED` (switch is exhaustive — all 9 cases handled).

- [ ] **Step 5: Manual verification**

Build and launch the app, then in Settings set Display mode to **Icon + Power**.
Expected: within ~2 s the menu-bar shows e.g. `🌀 38 W`, updating every 2 s. **Power Only** shows `38 W` with no icon.

```bash
xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -destination 'platform=macOS' build
# Launch the built .app (path printed by xcodebuild, under DerivedData/.../Build/Products/Debug/Mystral.app)
open -a "$(xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -showBuildSettings -destination 'platform=macOS' 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')"
```

- [ ] **Step 6: Commit**

```bash
git add Mystral/MenuBar/MenuBarManager.swift
git commit -m "feat(power): show total system watts in the menu-bar title"
```

---

## Task 6: Power rows in the live dropdown

**Files:**
- Modify: `Mystral/MenuBar/MenuBarManager.swift` (`showContextMenu()`, `updateContextMenuItems()`, item properties)

- [ ] **Step 1: Add item properties**

Alongside `liveCpuItem` / `liveGpuItem` (around lines 45-48):

```swift
    private var livePowerItem: NSMenuItem?
    private var livePowerBreakdownItem: NSMenuItem?
```

- [ ] **Step 2: Create the rows in `showContextMenu()`**

Insert immediately AFTER the `liveGpuItem` block and BEFORE `liveFanItems = []`:

```swift
        if powerMonitor.totalWatts != nil {
            let item = Self.infoItem("")
            livePowerItem = item
            menu.addItem(item)
        }
        if powerMonitor.cpuWatts != nil || powerMonitor.gpuWatts != nil {
            let item = Self.infoItem("")
            livePowerBreakdownItem = item
            menu.addItem(item)
        }
```

At the END of `showContextMenu()`, where the other live item refs are cleared, add:

```swift
        livePowerItem = nil
        livePowerBreakdownItem = nil
```

- [ ] **Step 3: Refresh the row titles in `updateContextMenuItems()`**

Add after the `liveGpuItem` update block (before the fan-items loop):

```swift
        if let item = livePowerItem, let w = powerMonitor.totalWatts {
            item.title = "Power  \(Int(w.rounded())) W"
        }
        if let item = livePowerBreakdownItem,
           let text = Self.formatPowerBreakdown(cpu: powerMonitor.cpuWatts, gpu: powerMonitor.gpuWatts) {
            item.title = text
        }
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project Mystral.xcodeproj -scheme Mystral -configuration Debug -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Manual verification**

Launch the app, wait ~3 s (so IOReport has a second sample), click the menu-bar icon.
Expected: the dropdown shows, below the CPU/GPU temperature rows and above the fans:
```
Power  38 W
CPU 17 W  ·  GPU 4 W
```
Run a CPU load (e.g. `yes > /dev/null &` ×N, then `kill`) and reopen — the CPU watts and total should rise and fall.

- [ ] **Step 6: Run the full test suite**

Run: `xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS'`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Mystral/MenuBar/MenuBarManager.swift
git commit -m "feat(power): add System/CPU/GPU watt rows to the live dropdown"
```

---

## Self-Review

**Spec coverage:**
- Topbar option → Tasks 4 (modes) + 5 (render). ✓
- Live info total + CPU/GPU breakdown → Task 6. ✓
- Total via SMC `PSTR` → Task 3. ✓
- CPU/GPU via IOReport "Energy Model" with unit normalization → Tasks 1 + 2. ✓
- No helper/root/`SMCProxyService`/`SettingsView` changes → respected (no task touches them). ✓
- Graceful degradation (nil when unavailable) → `PowerMonitor.sample()` nils, conditional rows, `-- W`. ✓
- Tests for pure functions → Tasks 1 (normalizer) + 4 (formatters, showsIcon, count). ✓

**Type consistency:** `IOReportPower.energyToJoules(raw:unit:)`, `IOReportPower.init?()`/`sample() -> (cpu:gpu:)`, `PowerMonitor.totalWatts/cpuWatts/gpuWatts/sample()`, `MenuBarManager.formatTotalWatts(_:)`/`formatPowerBreakdown(cpu:gpu:)`/`powerString()`, `MenuBarDisplayMode.iconAndPower`/`.powerOnly`, `livePowerItem`/`livePowerBreakdownItem` — all referenced consistently across tasks.

**Placeholder scan:** none — every code step shows complete code; every command has expected output.

**Note for the executor:** `xcodegen generate` modifies `Mystral.xcodeproj`; commit it together with the new files (Tasks 1 and 3 do this). Tasks that only modify existing files don't need a regen.
