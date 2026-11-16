# Changelog

All notable changes to Mystral are documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Simplified Chinese (zh-Hans) localization across all menus, views, alerts, settings, and sensor categories (thanks @huangyixin447).
- **Language** picker in Settings → General: System, English, Italiano or 简体中文. It sets Mystral's own language (the same setting as System Settings → Language & Region → Applications) and offers to restart, reopening on Settings.

### Fixed
- Settings captions, profile trigger labels, preset profile names, the update and export status lines, chart legends and a few counters were shown in English in every language; they now go through the string catalog.
- Italian: restored the parts of several Settings and Profiles explanations that were cut short.
- Removed the firmware-lock warning for M3/M4 Pro and Max MacBook Pros. Its model list used identifiers no Mac has (`MacBookPro20,x`, `MacBookPro21,x`), so it never appeared, and manual fan control does work on an M3 Pro (`Mac15,6`) running macOS 27.
- **Settings → Chip Detection → Fan control** now shows **Working** only while the fans are actually in forced mode under Mystral. It used to show **Working** for any fan with a speed range.
- CPU power no longer spikes to impossible values such as 1,900 W on macOS 27 (#4). On macOS 27 the CPU energy counter Mystral reads stops moving for long stretches and then delivers all the missed energy in one sample. That energy is now averaged over the whole time the counter stood still. A reading that is negative, above 500 W, or far above the Mac's total power is dropped.
- On macOS 27, CPU and GPU power are read from the AppleCLPC energy counters, which keep counting where the old source freezes. This covers the 17 Apple Silicon drivers known for macOS 27 (table ported from [macmon](https://github.com/vladkens/macmon), MIT). Other macOS versions and unknown chips keep the old source.
- While a CPU energy counter stands still, CPU power is shown as unavailable after 6 seconds instead of a false 0 W.
- A power reading is taken over at least half the polling interval, and the measurement restarts after the Mac wakes from sleep. A total system power reading above 1,500 W is ignored.
- The temperature charts no longer dip toward 0 °C. Readings outside 10–130 °C, such as unpopulated SMC rails at 1–3 °C, are ignored. A sensor that drops out for a few ticks keeps its history, and sensors with histories of different lengths are now lined up on their newest sample. They used to be lined up on their oldest, which put recent readings at the wrong time on the dashboard chart and in the menu bar mini graph.

## [1.1.7] — 2026-11-11

### Security
- Automatic updates now require an Ed25519 signature made with the Mystral release key, published as `Mystral-x.x.x.dmg.sig` next to the DMG. Access to the GitHub repository alone can no longer push an update that installs itself. Releases without a valid signature only open the release page.
- The downloaded app must carry exactly the version the signature covers.
- The helper install and the updater make `/Applications/Mystral.app` root-owned, so other programs running as your user cannot replace the binary the root helper is copied from. Updating Mystral therefore asks for your administrator password.
- The app is built with the hardened runtime.
- Administrator commands are escaped for both the shell and AppleScript in one shared place.
- CI runs with a read-only token and a pinned checkout action.

## [1.1.6] — 2026-11-11

### Security
- The root helper no longer has launchd write its stdout/stderr into the user-owned IPC directory. Existing installs are detected as stale and reinstalled once (one administrator prompt), and the old log files are then removed.
- The helper now reads, writes and deletes IPC files only through directory descriptors whose ownership and mode it has checked, with `O_NOFOLLOW`. Swapping the IPC or `commands` directory, or a file in them, for a symlink can no longer redirect root writes or deletions.
- Command files larger than 4 KB are ignored.

### Fixed
- The helper logged two stderr lines for every fan command and never rotated them, which grew the log file without bound. Successful commands are no longer logged; failures and rejections go to the unified log (`log show --predicate 'subsystem == "com.fexxdev.Mystral"'`).

## [1.1.5] — 2026-08-27

### Fixed
- Prevented a crash after wake when thermal or workspace notifications arrive off the main actor.
- Wake callbacks now reapply fan control on the main actor.

### Added
- Regression tests for thermal and screen-wake notifications delivered from a background queue.

## ⚠️ [1.1.4] — 2026-08-11 — MANUAL REINSTALL REQUIRED

> **IMPORTANT: Mystral 1.1.4 must be installed manually.** Download `Mystral-1.1.4.dmg`, replace `Mystral.app` in `/Applications`, and launch it. Do not use the in-app updater for this first installation. This bootstrap step is required for users coming from the affected 1.1.1 build.

### Fixed
- Restored strict update validation for trusted Mystral GitHub release DMGs.
- The updater now checks the bundle identifier, `APPL` package type, newer version, and strict ad-hoc or Developer ID code signatures before replacing the app.
- DMG mounting, signature checks, and app replacement remain asynchronous and have cleanup and timeout handling.

## [1.1.3] — 2026-08-11

### Fixed
- Release apps now declare the required `APPL` bundle type, so the built-in updater accepts their metadata.
- The updater accepts strict ad-hoc signatures from the repository build script and strict Developer ID signatures.
- DMG mounting, signature checks, and app replacement no longer block the main UI. Mounting and cleanup now have timeouts.
- Update downloads and temporary mount points are cleaned up after success or failure.

## [1.1.2] — 2026-08-11

### Added
- Private per-user IPC between the app and the privileged SMC helper.
- Automatic helper recovery after heartbeat loss, SMC errors, sleep, or termination.
- CI checks for project generation, Debug and Release builds, tests, coverage, plist and JSON validity, and shell syntax.

### Fixed
- The helper installer now uses valid macOS tool paths and verifies the live `launchd` job after installation.
- Helper installation now accepts standard user-owned apps copied into `/Applications` and runs a root-owned helper tool.
- The updater accepts only trusted GitHub DMGs with valid metadata and Developer ID signatures.
- Settings and profiles now reset and write transactionally. Sensor and history fallbacks are deterministic.
- The main sidebar and Profiles layout no longer reflow when navigating between sections.
- The sidebar toggle stays in one position and appears only once.

### Improved
- The main sidebar uses a fixed 200-point column. The Profiles sidebar uses a fixed 260-point column.
- The main window enforces a 1200-by-640-point minimum size for the Profiles editor.

## [1.1.1] — 2026-06-09

### Fixed
- Fans no longer keep spinning at the last forced speed while the Mac sleeps. On system sleep the helper hands fan control back to macOS automatic mode; your curve takes over again on wake ([#2](https://github.com/fexxdev/Mystral/issues/2)).

## [1.1.0] — 2026-06-01

### Added
- **Power monitoring**, with no extra permissions. Total system watts come from the SMC (`PSTR`), CPU and GPU watts from the IOReport energy model.
- Menu bar display modes **Icon + Power** and **Power Only**.
- Total, CPU and GPU watts in the live dropdown.
- A Dashboard **Power** section: total watts with a stacked CPU / GPU / Other bar, and a **Power — Last 5 Minutes** chart.

## [1.0.15] — 2026-05-29

### Fixed
- The SMC helper is now installed as a launchd **LaunchDaemon** with `KeepAlive`. macOS no longer reaps it every 20–40 minutes, it survives reboots, and the administrator password is asked only at first install. Manual restarts and helper reloads after an update no longer prompt.

## [1.0.14] — 2026-05-25

### Fixed
- Helper restarts could get stuck because the health check and the restart logic used different staleness thresholds (60 s and 120 s).

### Added
- After three failed restarts, the app retries every 12 hours instead of giving up.
- A **Restart Helper** button in the Dashboard banner.

## [1.0.13] — 2026-05-20

### Fixed
- The SMC helper crashed on macOS Tahoe before reaching Swift code, because the LLVM profiling runtime tried to write to `/`.
- The Sensors empty state used an SF Symbol that doesn't exist.

### Improved
- Dashboard, Sensors and Fans share the same empty-state style.

## [1.0.12] — 2026-05-19

### Added
- **In-app updater**: Settings → Updates downloads the new DMG with a progress bar, installs it and relaunches. It validates the version, rolls back if the install fails, and removes the quarantine attribute.

## [1.0.11] — 2026-05-19

### Fixed
- Unneeded administrator prompts during sleep and wake: the helper is no longer killed while its data file is briefly stale, as long as its process is alive. It also ignores `SIGHUP`.

## [1.0.10] — 2026-05-17

### Fixed
- Chip detection reads the chip name from `machdep.cpu.brand_string` instead of guessing from sensor counts, so every Apple Silicon chip is named correctly.
- CPU core sensors are counted by prefix, so new sensor keys are included.

### Improved
- The SMC export includes the `hw.model` identifier and the chip name.

## [1.0.9] — 2026-05-16

### Fixed
- **Helper killed by macOS power management**: the root SMC helper had no activity assertion, so macOS throttled/suspended its timer during display sleep (~10 min idle). This caused the data file to go stale, triggering a helper restart and repeated admin password prompts. The helper now holds a `latencyCritical` activity assertion and uses a tight timer leeway.
- **Spurious restart after wake**: waking from sleep always left the data file momentarily stale, racing against the staleness check. Added a 15-second grace period after wake in both the proxy service and the fan controller to let the helper resume before declaring it dead.
- **Infinite password prompt loop**: if the user cancelled the admin dialog or the binary was missing, the app would re-prompt every 30 seconds indefinitely. Now capped at 3 attempts before giving up.
- **Helper launch not verified**: the app trusted `NSAppleScript` success without confirming the process started. Now polls for PID file (up to 3s) after launch.
- **Stale SMC caches after wake**: IOKit key info cache was never invalidated after system sleep, risking stale reads. Added `notifyWake()` for both proxy and direct SMC modes.
- **Power source changes missed during dialogs**: `IOPSNotification` run loop source was on `.defaultMode` — now `.commonModes` so profile auto-switching reacts even during modal interactions.

### Improved
- Better observability in the helper: consecutive SMC read errors are counted and logged, with a recovery message when normal operation resumes.

## [1.0.7] — 2026-05-06

### Fixed
- The helper validates every command (fan index, percentage, mode) and rejects out-of-range values.
- Curve points are clamped to 0–120 °C and 0–100 %, empty profile names become "Untitled Profile", and curve interpolation handles overlapping points.
- The app stops queuing fan commands while the helper is down.
- A memory leak in the power-source callback of the auto-switcher.
- Stuck-fan alerts trigger below 100 RPM instead of only at 0.
- **Reset All Settings** now resets every setting.

### Improved
- SMC key info is cached, and redundant helper file reads are skipped.
- The manual fan slider is debounced, and the menu bar follows the configured polling interval.
- Release builds use whole-module optimisation.

## [1.0.6] — 2026-05-06

### Fixed
- **Helper crash on Debug builds**: the root helper's working directory was `/` (read-only on modern macOS), causing LLVM profiling to abort the process with `Failed to write file "default.profraw": Read-only file system`. Helper now sends profiling output to `/dev/null` and does not depend on its working directory.
- **Stale data after helper death**: when the SMC helper process died, the app silently showed frozen temperatures and queued fan commands that were never executed. `SMCProxyService` now detects missing or stale data files (>10 s) and throws `helperNotResponding`.
- **No automatic recovery**: added helper health monitoring with auto-restart after 3 consecutive failures (30 s cooldown). Orphaned command files are purged before restarting.

### Added
- **Helper status banner**: the Dashboard now shows a red warning when the SMC helper is unresponsive, so the user knows fan control is inactive instead of seeing frozen readings.

## [1.0.5] — 2026-05-06

### Added
- The menu bar dropdown shows CPU/GPU temperatures and every fan's RPM, and keeps updating while it is open. Left and right click both open it; **Open Mystral** opens the window.
- Mystral shows a Dock icon only while its window is open.
- Structured logging under the `com.fexxdev.Mystral` subsystem.

### Fixed
- Alert, auto-switch and update settings were not saved.
- Menu bar display mode changes did not apply.
- Timers stopped while the menu bar dropdown was open.
- Outdated helpers are detected by version and replaced.

## [1.0.2] — 2026-04-30

### Added
- **Update checker**: Settings → Updates shows current version, last-check time, and a "Check Now" button. Auto-check runs once per launch (and at most once per 24h) when enabled. New versions trigger a "Download Update" button that opens the GitHub release page.
- **Minimum fan speed** floor in Settings → Fan Behavior. Fans never drop below this %, regardless of curve — useful for keeping fans always spinning in summer.
- **Aggressive override** toggle (default on). Re-asserts forced fan mode and re-writes target speeds every tick to fight SMC firmware reverting your settings.
- **Firmware-lock warning** in Settings for M3/M4 Pro/Max MacBook Pro models where Apple firmware-locks manual fan control on macOS Sequoia+ (no third-party app can bypass this).
- **Sortable sensor columns**: click a column header in the Sensors view to sort by Key, Name, or Temperature.

### Changed
- Settings layout refactored for consistency: shared slider rows, locale-aware number formatting, firmware warning surfaced right below Chip Detection, and "Curve Behavior" renamed to "Fan Behavior".

### Fixed
- CI: unit-test runs no longer time out when the host app is launched under XCTest.

## [1.0.1] — 2026-04-30

### Added
- Menu bar display modes for **Temperature Only** and **RPM Only** (no icon).
- Configurable **temperature source** for the menu bar: CPU average, CPU max, GPU average, GPU max, or hottest sensor.

### Changed
- Menu bar icon now renders as a template image with explicit symbol configuration so it stays sharp on non-Retina external displays.

## [1.0.0] — 2026-04-30

Initial public release.

### Added
- Apple Silicon SMC fan control via Ftst unlock; manual % override, auto curves.
- Per-fan custom curves with fallback to a shared curve.
- Profiles with auto-switching triggers (power source, thermal state, frontmost app).
- 5-minute rolling sensor history chart (CPU max/avg, GPU max).
- Menu bar mini-graph + multiple display modes.
- High-temperature and fan-stuck notifications via `UNUserNotificationCenter`.
- 30-second built-in stress test with fan-response verification.
- EMA smoothing and deadband for curve output.
- SMC diagnostic export for unsupported chips.
- Custom app icon and ad-hoc-signed DMG installer.
