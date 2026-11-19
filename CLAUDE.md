# Mystral - Claude Code Notes

Mystral is a macOS menu bar app that controls fan curves and shows temperatures and power on Apple Silicon Macs. Swift 6, SwiftUI, no kernel extension. A root helper (the same binary run with `--smc-helper`) talks to the SMC; the app talks to the helper through files.

How the system works is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Read it before changing anything in `Mystral/Services`. Contributor-facing rules are in [CONTRIBUTING.md](CONTRIBUTING.md). Code, comments, commits and docs are in English.

## Build and Test

```bash
xcodegen generate            # after editing project.yml or adding/removing files
xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

- `project.yml` is the source of truth. `Mystral.xcodeproj` is committed and CI fails if regenerating it changes it, so commit both.
- **CI runs Xcode 16.4, which is stricter than newer Xcodes.** Before pushing, also run the tests with it when it is installed:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode-16.4.0.app/Contents/Developer xcodebuild test -project Mystral.xcodeproj -scheme Mystral -destination 'platform=macOS' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
  ```

  Known difference: Xcode 16 isolates every member of a SwiftUI `View` to the main actor, static ones included. Do not put helpers that tests or services call on a `View`; put them on the model or service they describe (as `HardwareInfo.CoreCounts.cpuDescription` does), or mark them `nonisolated`.
- CI also builds Debug and Release, lints `Info.plist`, the preset JSON files and the shell scripts, and requires 10% line coverage. Check a run with `gh run list --branch main` before calling work done.

## Never State What You Have Not Checked

This project has shipped wrong facts copied from code or other tools: a firmware-lock warning keyed on model identifiers no Mac has, sensor keys named after cores they do not belong to, core counts that were sensor counts.

- A claim about hardware (what a key measures, whether a chip supports something) needs evidence: a measurement on a real Mac, or agreement between independent projects. Say which one in the commit message.
- When the code and the README disagree with a measurement, the measurement wins.
- If something cannot be verified on the available Mac, say so in the commit and the changelog instead of implying it works everywhere.

## Sensors

`SensorRegistry.classify(_:chip:)` maps an SMC temperature key to a name and category. Rules, not a per-key table:

- Keys are grouped by prefix, with chip-specific exceptions (M1, M5 Pro/Max, M5/M6). The same key means different things on different chips.
- **Never name a key after one core** ("P-Core 4"). Clusters publish groups of probes, aggregates and maxima; no tool can tie a key to a core. A test enforces this.
- A group is CPU or GPU only if it warms under that load, and SSD, battery or board only if it does not. Evidence used so far: load tests on an M3 Pro, and the load recordings in dkorunic/iSMC (`internal/cmd/testdata/*-run.json`) for M1 Ultra, M3, M3 Pro/Max, M4, M4 Pro/Max, M5, M5 Pro/Max and M6.
- Unknown keys keep their key as name (`isRecognized` is false). Do not invent a label.
- Reference projects: exelban/stats, vladkens/macmon, metaspartan/mactop (MIT: data may be ported with a notice in `THIRD-PARTY-NOTICES.md`); dkorunic/iSMC and narugit/smctemp (GPL: read and test against them, copy nothing).
- Only `flt` and `sp78` SMC keys are temperatures. Readings outside 10–130 °C are dropped, and a CPU key at exactly 40.0 °C is a parked slot.
- CPU keys switch off and on within seconds on M4 Pro/Max (two banks of 51 keys; off means 40.0 °C or a value below 10 °C). `SensorHistoryStore` holds a key that just went off at its last live reading for about 10 s, filling up to the most keys that were live at once in that window. Never derive that count from held keys: the banks take turns every 2–6 s under light load, so it latches at both banks (seen on a real M4 Pro, issue #8). A held reading is not a new measurement: it counts as current for about 4 s (`Sensor.isStale` after), and while it is the hottest point the fan curve keeps its previous input instead of taking the sample in again. At idle the last reading before a gap is usually a burst peak, and repeating it raised the fans for 10 s on that Mac. Anything computed from "the CPU sensors" must tolerate the set changing from tick to tick; replay iSMC's `m4-pro-run.json` series when touching this.
- `Tpx…`/`Tex…` are per-die aggregates (CPU summary), not cluster sensors.
- The fan curve's default temperature is the hottest CPU point (`defaultDrivingTemperature`): the highest of `TCMz` and the cluster sensors, live or held. M5 and M6 have no `TCMz`, and on M4 Pro/Max `TCMz` alone drops 15–20 °C for a tick when the cluster switches off.
- Core counts and core types come from `sysctl` (`hw.nperflevels`, `hw.perflevelN.name`), never from sensor counts and never assumed to be P + E.

## Power

CPU/GPU watts come from IOReport: the AppleCLPC energy counters on macOS 27 (table ported from macmon, keyed by driver bundle, valid for macOS 27 only), the "Energy Model" group otherwise. When Apple ships a new major macOS, check macmon's `src/clpc.rs` for a new table before assuming the old one applies.

## Localization

All UI text is in `Mystral/Localizable.xcstrings` (English source, Italian, Simplified Chinese).

- Pass literals straight to SwiftUI (`Text("Fans")`); use `String(localized:)` for strings built in code. Do not add `String` overloads to helpers that take `LocalizedStringKey`: for a literal Swift picks the `String` one and the text silently stays in English.
- The catalog must match the code exactly. After changing UI strings, do a clean build and compare the `*.stringsdata` files under `Build/Intermediates.noindex/Mystral.build` with the catalog keys: nothing missing, nothing stale. Keys looked up only at runtime (enum `rawValue`s, preset names) are marked `"extractionState": "manual"`; number-only strings are `"shouldTranslate": false`.
- Write the catalog in Xcode's format: 2-space indent, `" : "` separators, sorted keys.
- A new language also needs a case in `AppLanguage`; `LocalizationTests` and `AppLanguageTests` fail otherwise.
- Chinese conventions: full-width punctuation （）：, 配置 for profile, 触发条件 for trigger, 启用 for activate, 你 not 您.

## Installing a Local Build

`/Applications/Mystral.app` is root-owned, so replacing it needs an administrator. Build Release exactly as `scripts/build-dmg.sh` does (ad-hoc sign with `--options runtime` and the entitlements file), then:

```bash
osascript -e 'quit app "Mystral"'
osascript -e 'do shell script "rm -rf /Applications/Mystral.app && /usr/bin/ditto <built app> /Applications/Mystral.app && chown -R root:wheel /Applications/Mystral.app" with administrator privileges'
open -a /Applications/Mystral.app
```

- While Mystral is quit the fans are on macOS automatic control. If the install is cancelled, reopen the app right away.
- The helper is reinstalled only when `CFBundleVersion` changes. To test helper-side changes (anything in `SMCService`, `SMCKit`, `SMCHelperMode`, `SMCIPC`) locally, set the built app's `CFBundleVersion` to a value such as `28.2` with PlistBuddy before signing. Never use the next release's integer, and never commit that change.
- After installing, check `~/Library/Application Support/Mystral/ipc/smc-data.json`: it is rewritten every 2 s, and each fan's `mode` returns to `1` (forced) within about 10 s.
- Screen capture and accessibility are usually not granted. To look at a view, render it off-screen in a temporary test (`NSHostingView` + `cacheDisplay`).

## Temporary Probes

To measure something on the real Mac, write a test named `ZZ…TmpTests.swift` that skips unless an environment variable is set, run it with `TEST_RUNNER_<NAME>=1 xcodebuild test -only-testing:MystralTests/<Class>`, then delete it and run `xcodegen generate`. Never commit a probe.

## Release Process

To build a release DMG with proper drag-and-drop layout (app + Applications symlink + README):

```bash
bash scripts/build-dmg.sh /tmp
```

Then upload to GitHub:

```bash
gh release create v<VERSION> /tmp/Mystral-<VERSION>.dmg /tmp/Mystral-<VERSION>.dmg.sig --title "v<VERSION>" --notes "..."
```

Do NOT create DMGs manually with `hdiutil` — always use `scripts/build-dmg.sh` which handles ad-hoc signing, Applications symlink, and the README.

Before a release, move the **Unreleased** entries in `CHANGELOG.md` under the new version.

## Version Bumping

Version is in `Mystral/Info.plist`:
- `CFBundleShortVersionString` — display version (e.g. 1.0.12)
- `CFBundleVersion` — build number (increment by 1 each release). A new build number is also what makes installed copies reinstall the helper.

## Update Signing Key

`build-dmg.sh` signs the DMG with the Ed25519 key stored in the login Keychain (service `com.fexxdev.Mystral.update-signing`) and fails if it is missing or does not match `UpdateSignature.publicKeyBase64`. Always upload the `.sig` next to the DMG: without it the in-app updater only links to the release page. Never print, commit or log the private key; `scripts/update-key.sh private` exists only for an offline backup.
