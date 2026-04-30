# Changelog

All notable changes to Mystral are documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
