# Quiet Fans on Sleep — Design

**Date:** 2026-06-08
**Status:** Approved (design)
**Issue:** #2 — "There's no need for the fan to spin when it's hibernating"

## Goal

When the Mac goes to **system sleep**, fans should stop whining. Today they keep
spinning at whatever speed Mystral last forced, because the SMC firmware retains
the forced fan mode + commanded RPM while the app's poll loop is suspended.

Fix: on sleep, **hand fan control back to macOS auto mode** so the firmware idles
the fans the way it normally would during sleep. On wake, Mystral re-applies its
curve (already handled).

## Root cause (verified by reading the code)

- `FanController` (app, `@MainActor`, 2 s `Timer`) forces fan mode
  (`setForcedMode(forced: true)`) and writes curve-driven speeds each tick.
- The app cannot write the SMC itself — only the **root helper daemon**
  (`SMCHelperMode`, a KeepAlive LaunchDaemon) can. The app sends commands to the
  helper via JSON files in `/tmp/mystral-cmds`, which the helper drains on its own
  2 s `DispatchSource` timer.
- On system sleep both timers are suspended. The SMC keeps honoring the last
  `setForcedMode(true)` + last `setFanSpeed`, so the fan holds that RPM → whine.
- Wake is already handled: `FanController.handleWake` (`didWakeNotification`)
  resets `forcedModeSet = false` and grants a 15 s helper grace, so the next tick
  re-asserts forced mode + curve.
- There is **no `willSleep` handling anywhere** today.

## Why the helper (not the app) must do this — chosen approach

Restoring auto mode means an SMC write, and only the helper can write the SMC.
Two ways to trigger it:

- **App-driven (rejected):** app observes `NSWorkspace.willSleepNotification` →
  writes a `setForcedMode(false)` command file → helper drains it on its 2 s
  timer. Racy: the system can sleep before the helper polls, and the stale command
  then applies on *wake*, fighting `handleWake`. The file queue is too slow/unordered
  for sleep transitions.
- **Helper-driven via IOKit (chosen):** the helper registers with
  `IORegisterForSystemPower` and, on `kIOMessageSystemWillSleep`, restores auto
  mode **in-process** (no file round-trip) before acking the power change. The SMC
  owner does the write directly, synchronously, inside the pre-sleep window. This
  is the same operation the helper's existing `SIGTERM` handler already performs.

Behavior is **always-on** — no setting, no UI. Quieting fans during sleep is
unambiguously correct.

## Architecture

All changes are confined to **`Mystral/Services/SMCHelperMode.swift`** (plus a
test-only mock extension). No app-side, `SMCProxyService`, or UI changes.

### 1. Shared "restore auto" helper

Factor the auto-restore logic (currently inline in the `SIGTERM` handler) into one
testable function and use it from both the `SIGTERM` path and the new sleep path:

```swift
static func restoreAutoMode(smc: SMCServiceProtocol) {
    let count = (try? smc.getAllFans().count) ?? 2
    try? smc.setForcedMode(fanCount: count, forced: false)
}
```

Takes the protocol type so the existing `MockSMCService` can drive it in tests.
Concrete `SMCService` (used by the helper) conforms to `SMCServiceProtocol`.

### 2. IOKit system-power registration

`import IOKit.pwr_mgt` (for `IORegisterForSystemPower`/`IOAllowPowerChange`/
`IONotificationPortSetDispatchQueue`) and `import IOKit` (for the `kIOMessage*`
constants from `IOMessage.h`).

In `run()`, after the SMC is opened and the dispatch `queue` is created, register
for power notifications and bind delivery to the **same `queue`** the helper's
timer uses, so the callback is serialized with `processCommands`/SMC reads (no
concurrent SMC access):

```swift
var notifyPort: IONotificationPortRef?
var notifier: io_object_t = 0
let rootPort = IORegisterForSystemPower(nil, &notifyPort, mystralPowerCallback, &notifier)
if rootPort != 0, let notifyPort {
    rootPowerPort = rootPort                       // static, read by the C callback
    powerSMC = smc                                 // static, read by the C callback
    IONotificationPortSetDispatchQueue(notifyPort, queue)
    // notifyPort / notifier retained for process lifetime (run() never returns)
} else {
    logger.error("SMCHelper — IORegisterForSystemPower failed; sleep auto-restore disabled")
}
```

`IORegisterForSystemPower`'s callback is a C function pointer and cannot capture
context, so the bits it needs are held in file-scope static storage on
`SMCHelperMode`, set once in `run()`. They are `fileprivate` (not `private`) so the
same-file C callback can read them, and `nonisolated(unsafe)` because the project
builds in **Swift 6 language mode** (mutable statics are otherwise rejected as
nonisolated global shared mutable state). Safe here: written once at startup, read
only from the callback, which runs on the helper's serial `queue`:

```swift
nonisolated(unsafe) fileprivate static var rootPowerPort: io_connect_t = 0
nonisolated(unsafe) fileprivate static var powerSMC: SMCServiceProtocol?
```

### 3. The callback (C-compatible, file-private free function)

```swift
private func mystralPowerCallback(_ refcon: UnsafeMutableRawPointer?,
                                  _ service: io_service_t,
                                  _ messageType: UInt32,
                                  _ messageArgument: UnsafeMutableRawPointer?) {
    switch messageType {
    case UInt32(kIOMessageCanSystemSleep):
        // We never veto idle sleep — must ack promptly or sleep is delayed 30 s.
        IOAllowPowerChange(SMCHelperMode.rootPowerPort, Int(bitPattern: messageArgument))
    case UInt32(kIOMessageSystemWillSleep):
        if let smc = SMCHelperMode.powerSMC { SMCHelperMode.restoreAutoMode(smc: smc) }
        IOAllowPowerChange(SMCHelperMode.rootPowerPort, Int(bitPattern: messageArgument))
    default:
        break   // kIOMessageSystemHasPoweredOn: app's handleWake re-applies the curve
    }
}
```

`rootPowerPort` and `powerSMC` are `fileprivate static` on `SMCHelperMode` so the
same-file free function can read them; `restoreAutoMode` is `static` (default
internal) and likewise reachable.

### Wake path — unchanged

On `kIOMessageSystemHasPoweredOn` the helper does nothing. The app's existing
`handleWake` resets `forcedModeSet`, grants the 15 s grace, and the next 2 s tick
re-asserts forced mode + writes curve speeds. A brief (≤2 s) auto-mode window right
after wake is harmless. If the app isn't running, nothing was forced anyway, so
there's nothing to re-apply.

## Testing

- **Unit (no hardware):** extend `MockSMCService` to record forced-mode calls
  (`lastForcedModeForced`, `lastForcedModeFanCount`), then assert
  `SMCHelperMode.restoreAutoMode(smc:)` calls `setForcedMode(fanCount: 2, forced: false)`
  for the 2-fan mock. This covers the actual sleep response logic.
- **Manual:** run the app with a forced curve, sleep the Mac, confirm the fan
  spins down (or audibly quiets); wake and confirm the curve re-engages within one
  tick. IOKit registration / callback delivery verified by Console logs.

## Out of scope (YAGNI)

- Any user setting / toggle for the behavior.
- Forcing a fixed minimum RPM during sleep (rejected in favor of firmware auto).
- Explicit IOKit teardown (`IODeregisterForSystemPower`/`IOServiceClose`) — the
  helper holds the registration for its whole life; process exit reclaims it.
- Display-only sleep — only full system sleep (`kIOMessageSystemWillSleep`) is
  handled; the curve should keep running while the display alone sleeps.

## Risks

- **`IORegisterForSystemPower` registration fails** → logged, and the helper
  behaves exactly as today (no regression). Graceful degradation.
- **Must always `IOAllowPowerChange`** for both `kIOMessageCanSystemSleep` and
  `kIOMessageSystemWillSleep`, or sleep is delayed ~30 s. Both paths ack
  unconditionally.
- **Concurrency:** the callback shares the helper's serial `queue` with the timer,
  so SMC access stays serialized.
