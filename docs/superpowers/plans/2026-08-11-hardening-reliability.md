# Mystral Hardening and Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the privileged helper and updater, fix the reviewed application bugs, and add regression coverage without changing the public fan-control model.

**Architecture:** Keep the existing LaunchDaemon and JSON command protocol. Move IPC to a private per-user directory, add session heartbeats, and make helper installation verify every privileged step. Gate automatic updates on repository URL validation and a strict code signature. Prefer Developer ID signing for public distribution. Fix the remaining state, persistence, sensor, history, CI and documentation defects in focused changes.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, XcodeGen, IOKit, `codesign`, Bash, GitHub Actions.

**Status:** Implemented and verified on 2026-08-11. Local DMGs remain ad-hoc signed until a Developer ID identity is supplied.

## Global Constraints

- Support macOS 14.0+ and Apple Silicon.
- Keep the current `SMCServiceProtocol` test seam.
- Keep profile JSON compatibility.
- Do not add third-party runtime dependencies.
- Do not use shared predictable `/tmp` paths for helper control or installation.
- Do not install an update without a valid strict code signature.
- Write tests before production changes for every behavior change.
- Do not create a branch or worktree in the shared personal repository.

---

### Task 1: Add failing security and lifecycle tests

**Files:**
- Modify: `MystralTests/SMCServiceTests.swift`
- Modify: `MystralTests/UpdateCheckerTests.swift`
- Modify: `MystralTests/SensorRegistryTests.swift`
- Modify: `MystralTests/AlertManagerTests.swift`
- Modify: `MystralTests/StressTesterTests.swift`
- Modify: `MystralTests/ProfileManagerTests.swift`
- Modify: `MystralTests/PowerMonitorTests.swift`
- Modify: `MystralTests/MenuBarTests.swift`
- Modify: `MystralTests/SettingsDefaultsTests.swift`

- [x] Add tests for private IPC paths, heartbeat timeout, command validation, trusted GitHub asset URLs, and rejection of ad-hoc bundle metadata.
- [x] Add tests for the `/Applications` installation-path policy and stale helper-plist detection.
- [x] Add tests for CPU-summary fallback, stopped-fan detection, invalid stress duration, failed profile writes, full settings reset, and five-minute history trimming.
- [x] Run the focused test targets and confirm the new tests fail for the current implementation.

Required test-facing interfaces:

- `SMCIPC.isSecureDirectory(path:expectedOwnerUID:) -> Bool`
- `SMCHelperMode.shouldRestoreForHeartbeat(lastHeartbeat:now:timeout:) -> Bool`
- `UpdateChecker.isTrustedReleaseURL(_:) -> Bool`
- `SensorRegistry.cpuMaximumTemperature(from:) -> Double`
- `AppSettings.reset(_:)`

Run:

```bash
xcodegen generate
xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -only-testing:MystralTests
```

Expected: existing tests pass and new regression tests fail for the missing behavior.

### Task 2: Implement secure IPC and helper session lease

**Files:**
- Create: `Mystral/Services/SMCIPC.swift`
- Modify: `Mystral/Services/SMCHelperMode.swift`
- Modify: `Mystral/Services/SMCProxyService.swift`
- Modify: `Mystral/Services/SMCService.swift`
- Modify: `Mystral/App/AppDelegate.swift`
- Modify: `Mystral/Services/FanController.swift`
- Modify: `MystralTests/SMCServiceTests.swift`

Interfaces:

- `SMCIPC.directoryPath`, `SMCIPC.dataPath`, `SMCIPC.commandDirectoryPath`, and `SMCIPC.pidPath` return paths below the per-user Application Support directory unless the helper plist provides `MYSTRAL_IPC_DIRECTORY`.
- `SMCIPC.prepareForApp() throws` creates and validates the app-owned directory.
- `SMCIPC.validateForHelper() -> Bool` validates the directory and expected UID from the helper environment.
- `SMCServiceProtocol.heartbeat() throws` is a no-op for direct SMC and a JSON command for the proxy.
- `SMCHelperMode.shouldRestoreForHeartbeat(lastHeartbeat:now:timeout:)` remains pure and hardware-independent.

- [x] Add app-side IPC directory creation and ownership/mode validation.
- [x] Pass IPC path and UID through the LaunchDaemon plist.
- [x] Reject unsafe helper IPC directories and keep command/data files inside the private directory.
- [x] Add heartbeat to `SMCServiceProtocol`, proxy, mock, and fan-controller tick.
- [x] Add helper startup restore, heartbeat timeout restore, SMC-error restore, and command-queue cleanup.
- [x] Make missing data unhealthy after the startup and wake grace periods, even when the helper PID exists.
- [x] Make auto-mode restoration report write failures instead of swallowing them.
- [x] Run the focused helper and SMC tests and confirm they pass.

### Task 3: Harden privileged helper installation

**Files:**
- Modify: `Mystral/App/AppDelegate.swift`
- Modify: `MystralTests/SMCServiceTests.swift`

Interfaces:

- `HelperDaemon.isAllowedExecutablePath(_:) -> Bool` rejects paths outside `/Applications` and unsafe bundle executables.
- `HelperDaemon.isInstalled(forExecutable:ipcDirectoryPath:) -> Bool` requires a secure root-owned helper tool, matching build metadata, IPC environment values, and a live `launchd` job.
- `HelperDaemon.install(executablePath:ipcDirectoryPath:) -> Bool` copies the helper to `/Library/PrivilegedHelperTools`, performs all privileged work in one verified command, and never writes a root script to a shared directory.

- [x] Remove staged `/tmp` plist and `/tmp` shell script creation.
- [x] Validate the application path is under `/Applications` and not group/world-writable; accept standard Finder ownership by root or the current user.
- [x] Copy the helper to a root-owned privileged tool path and refresh it when the helper build changes.
- [x] Generate the plist in memory and send it to the privileged command through Base64.
- [x] Run `launchctl bootstrap` before `enable`, then make `kickstart` and `print` failures visible.
- [x] Make installation status include the expected IPC configuration.
- [x] Make installation status reject a valid plist when the live `launchd` job is absent.
- [x] Treat a plist without the new IPC environment values as stale and replace it during upgrade.
- [x] Run the helper installation tests and the full unit suite.

### Task 4: Harden automatic updates

**Files:**
- Modify: `Mystral/Services/UpdateChecker.swift`
- Modify: `MystralTests/UpdateCheckerTests.swift`
- Modify: `Mystral/Views/SettingsView.swift`

Interfaces:

- `UpdateChecker.isTrustedReleaseURL(_:) -> Bool` accepts only the Mystral GitHub release asset host and path.
- `UpdateChecker.isValidBundleMetadata(at:currentVersion:) -> Bool` checks bundle identifier, package type, and version.
- `UpdateChecker.verifyCodeSignature(at:) throws` requires a strict valid signature. Developer ID authority is accepted when present.

- [x] Add strict GitHub repository URL validation.
- [x] Use unique private download and mount paths.
- [x] Validate bundle identifier, package type, and increasing version before replacement.
- [x] Verify the nested code signature and accept strict ad-hoc or Developer ID release builds.
- [x] Validate HTTP download responses.
- [x] Remove quarantine only after validation.
- [x] Clear completed update state and keep the release-page fallback.
- [x] Run update tests and the full test suite.

### Task 5: Fix settings and profile persistence

**Files:**
- Create: `Mystral/Services/AppSettings.swift`
- Modify: `Mystral/Views/SettingsView.swift`
- Modify: `Mystral/Services/ProfileManager.swift`
- Modify: `Mystral/Views/ProfilesView.swift`
- Modify: `MystralTests/ProfileManagerTests.swift`
- Create: `MystralTests/SettingsDefaultsTests.swift`

Interfaces:

- `AppSettings.reset(_ defaults: UserDefaults)` removes every resettable key, including alert, auto-switch, update, monitoring, and menu-bar keys.
- `ProfileManager.saveCustomProfile(_:)` changes `customProfiles` only after the atomic write succeeds.
- `ProfileManager.deleteCustomProfile(id:)` changes `customProfiles` only after deletion succeeds or the file is already absent.

- [x] Centralize all resettable UserDefaults keys.
- [x] Reset manager state and UI state for alerts, auto-switch, updates, monitoring, and menu-bar settings.
- [x] Write profile data before changing memory.
- [x] Treat deletion as successful only after the file operation succeeds or the file is already absent.
- [x] Show profile operation failures in the UI.
- [x] Run persistence and settings tests.

### Task 6: Fix sensor, alert, stress-test, and history behavior

**Files:**
- Modify: `Mystral/Services/SensorRegistry.swift`
- Modify: `Mystral/Services/AlertManager.swift`
- Modify: `Mystral/Services/StressTester.swift`
- Modify: `Mystral/Models/Sensor.swift`
- Modify: `Mystral/Services/PowerMonitor.swift`
- Modify: `Mystral/Services/FanController.swift`
- Modify: `Mystral/Views/SettingsView.swift`
- Modify: `Mystral/MenuBar/MenuBarManager.swift`
- Modify: `MystralTests/SensorRegistryTests.swift`
- Modify: `MystralTests/AlertManagerTests.swift`
- Modify: `MystralTests/StressTesterTests.swift`
- Modify: `MystralTests/SensorTests.swift`
- Modify: `MystralTests/PowerMonitorTests.swift`
- Modify: `MystralTests/MenuBarTests.swift`

Interfaces:

- `SensorRegistry.cpuMaximumTemperature(from:)` uses core sensors first, then `TCMz`, then `TCMb`.
- `Sensor.recordTemperature(_:maxHistory:)` retains only the requested rolling sample count.
- `PowerMonitor.sample(maxHistory:)` applies the same rolling-window limit to power history.
- `Notification.Name.pollingIntervalChanged` restarts the menu-bar timer after settings change.

- [x] Use CPU summary sensors as fallback for alerts and stress testing.
- [x] Report fan availability from detected fan metadata, not current RPM.
- [x] Reject non-positive and excessive stress-test durations.
- [x] Trim sensor and power history to five minutes for 2, 5, and 10 second polling.
- [x] Restart the menu-bar timer when polling interval changes.
- [x] Run focused functional tests.

### Task 7: Clean warnings, CI, build script, and documentation

**Files:**
- Modify: `Mystral/Services/SMCService.swift`
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/build-dmg.sh`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-04-29-mystral-design.md`
- Modify: `Mystral/Views/MainView.swift`
- Modify: `Mystral/Views/ProfilesView.swift`
- Modify: `MystralTests/ViewConstructionTests.swift`

- [x] Fix the unused `try?` result warning.
- [x] Add CI checks for ShellCheck, plist/JSON validation, unsigned Debug/Release build, tests, and a 10% application coverage gate.
- [x] Store the test result bundle and run `xcrun xccov view --report --json` to reject application line coverage below `0.10`.
- [x] Allow a configured Developer ID identity in the DMG script and fail on signing errors.
- [x] Document optional update network access and ad-hoc manual installation.
- [x] Align version and architecture documentation with the implemented code.
- [x] Keep both sidebar widths fixed and use one custom toggle in a stable toolbar position.
- [x] Keep the main window at least 1200 by 640 points so Profiles does not force column negotiation.
- [x] Run all static checks.

### Task 8: Full verification and review

**Files:**
- Verify: all changed files and generated Xcode project.

- [x] Run `xcodegen generate`.
- [x] Run full Debug build.
- [x] Run full Release build with signing disabled.
- [x] Run the complete test suite with coverage.
- [x] Run ShellCheck, Bash syntax, plist validation, JSON validation, secret scan, and `git diff --check`.
- [x] Inspect the final diff for scope, security regressions, and unused code.
- [x] Report any remaining limitation, especially the need for a real Developer ID release identity.
