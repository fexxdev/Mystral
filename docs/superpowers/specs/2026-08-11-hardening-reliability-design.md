# Mystral Hardening and Reliability SDD

**Date:** 2026-08-11  
**Status:** Approved for implementation  
**Scope:** Security, helper lifecycle, updater trust, persistence, UI correctness, tests, CI and documentation.

## Goal

Remove the release-blocking security and reliability risks found in the full project review. Preserve the current fan-control behavior on supported Macs.

## Current state

The app uses a persistent root LaunchDaemon. The user app sends JSON command files to the daemon. The files currently live in shared `/tmp`, and helper installation executes a staged root shell script from `/tmp`. The updater downloads a GitHub DMG and replaces the app without a trusted signature check.

## Design

### Privileged helper

Use a private IPC directory at `~/Library/Application Support/Mystral/ipc`. The app creates it with mode `0700`. The installed plist passes its absolute path and the user UID to the helper. The helper rejects missing, symlinked, foreign-owned, or group/world-accessible IPC directories.

On upgrade, an old plist without the IPC environment values is treated as stale. The installer bootstraps the new plist and stops the old LaunchDaemon before the app sends new commands. Legacy `/tmp` files are ignored and never executed.

Keep the existing JSON protocol, but validate every command before execution. Add a heartbeat command. The app sends one heartbeat per polling tick. The helper restores SMC auto mode when the session heartbeat expires, on startup, before sleep, on SIGTERM, or after repeated SMC failures. This protects the hardware after app crash or forced termination.

The proxy treats fresh data as the health signal. A live PID without a data file is not healthy after the startup grace period. This prevents a stuck helper from reporting empty, apparently valid state forever.

### Helper installation

Do not stage executable shell files in `/tmp`. Generate the plist in memory, encode it as Base64, and pass it to one short privileged shell command. Require the app executable to be inside `/Applications`, root-owned, and not group/world-writable. Require `launchctl bootstrap`, `kickstart`, and `print` to succeed.

### Updater

Accept only HTTPS release URLs for the Mystral GitHub repository. Validate the downloaded bundle identifier and version. Verify the bundle with `codesign --verify --deep --strict` and require a Developer ID signature before automatic replacement. Ad-hoc releases remain available through the release page, but the app does not install them automatically.

Use unique private temporary directories for the DMG and mount point. Validate the app before removing quarantine or replacing the installed bundle.

### Application correctness

Reset all persisted settings and in-memory managers. Make profile writes atomic and update memory only after a successful write. Surface profile operation errors. Use CPU summary sensors as fallback for alerts and stress tests. Detect fans from metadata, even when RPM is zero. Validate stress-test duration. Keep chart history at five minutes for every polling interval. Restart the menu-bar timer when the polling interval changes.

### Verification and release process

Add regression tests for each fixed behavior. Keep the existing hardware-independent test boundary. Add CI checks for generated-project builds, Release compilation without signing, shell syntax, ShellCheck, plist/JSON validation, and a minimum application coverage threshold. Make the DMG script use a configurable signing identity and fail on signing errors.

The CI coverage gate starts at 10% application line coverage. This is above the current 6.42% baseline and leaves room for the new hardware-independent tests.

Update README, changelog, and stale architecture notes. State that only update checks use the network and that ad-hoc builds require manual installation.

## Failure behavior

- Missing or unsafe IPC directory: helper exits and the app shows the helper error state.
- Failed helper installation: the app reports failure and retries only through the existing bounded policy.
- Expired heartbeat: helper clears queued commands, restores auto mode, and waits for a new session.
- Untrusted update: automatic installation stops with an actionable error; the release page remains available.
- Profile write failure: the in-memory list remains unchanged and the UI shows the error.

## Out of scope

- A full XPC or SMJobBless migration.
- New fan-control features.
- Automatic generation or storage of a private release-signing key.
- Changes to existing user profile JSON formats.

## Acceptance criteria

1. No root operation trusts a predictable shared `/tmp` script or plist.
2. The helper cannot continue forced fan control after a missing app heartbeat.
3. The updater refuses ad-hoc or invalid bundles.
4. All identified functional regressions have automated tests.
5. The full build and test suite pass with no project compiler warnings caused by the changes.
