# Changelog

All notable changes to Mystral are documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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

## [1.0.6] — 2026-05-06

### Fixed
- **Helper crash on Debug builds**: the root helper's working directory was `/` (read-only on modern macOS), causing LLVM profiling to abort the process with `Failed to write file "default.profraw": Read-only file system`. Helper now sends profiling output to `/dev/null` and does not depend on its working directory.
- **Stale data after helper death**: when the SMC helper process died, the app silently showed frozen temperatures and queued fan commands that were never executed. `SMCProxyService` now detects missing or stale data files (>10 s) and throws `helperNotResponding`.
- **No automatic recovery**: added helper health monitoring with auto-restart after 3 consecutive failures (30 s cooldown). Orphaned command files are purged before restarting.

### Added
- **Helper status banner**: the Dashboard now shows a red warning when the SMC helper is unresponsive, so the user knows fan control is inactive instead of seeing frozen readings.

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
