# Contributing to Mystral

Thanks for helping out! Bug reports, chip support data, translations and code are all welcome.

## Development setup

You need:
- macOS 14+ with Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Apple Silicon Mac to exercise the SMC paths on real hardware

```bash
git clone https://github.com/fexxdev/Mystral.git
cd Mystral
xcodegen generate
open Mystral.xcodeproj
```

`project.yml` is the source of truth for the project. `Mystral.xcodeproj` is committed, but CI regenerates it and fails if the result differs, so run `xcodegen generate` after changing `project.yml` or adding/removing files, and commit both.

## Project layout

| Path | Contents |
|---|---|
| `Mystral/App` | App delegate, helper install, window lifecycle |
| `Mystral/MenuBar` | Status item, display modes, live dropdown |
| `Mystral/Views` | SwiftUI views: Dashboard, Sensors, Fans, Profiles, curve editor, Settings |
| `Mystral/Services` | SMC access, root helper mode and IPC, fan controller, power monitor, profiles, alerts, updater |
| `Mystral/Models` | Profiles, curves, fans, sensors |
| `Mystral/Presets` | The four built-in profiles (JSON) |
| `Mystral/Localizable.xcstrings` | String catalog for every language |
| `MystralTests` | Unit tests |
| `scripts` | Release DMG build, update-signing key tools |
| `docs/superpowers` | Design specs and implementation plans for larger features |

## Running tests

```bash
xcodebuild test \
  -project Mystral.xcodeproj \
  -scheme Mystral \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

CI ([`ci.yml`](.github/workflows/ci.yml)) also builds Debug and Release, lints `Info.plist`, the preset JSON files and the shell scripts, and requires at least 10% line coverage.

## Debugging

The app and the helper log to the unified log:

```bash
log stream --predicate 'subsystem == "com.fexxdev.Mystral"' --level debug
```

## Translations

All UI text lives in `Mystral/Localizable.xcstrings`. Mystral ships English (source), Italian and Simplified Chinese.

To add a language:
1. Open the project in Xcode, select `Localizable.xcstrings`, click **+** and pick the language.
2. Translate every string. Keep format specifiers (`%@`, `%lld`); when the word order changes, use positional ones (`%1$@`, `%2$lld`).
3. Run `xcodegen generate`. XcodeGen picks the new language up from the catalog and adds it to the project's known regions.
4. Run the tests and check the app with `-AppleLanguages '(xx)'` in the scheme's launch arguments.

Writing new UI code:
- Pass string literals straight to SwiftUI (`Text("Fans")`, `Button("Retry")`): they are looked up automatically.
- For a `String` built in code, use `String(localized: "…")`.
- Don't add `String` overloads to helpers that take `LocalizedStringKey`. For literals Swift picks the `String` one, and the text silently stays in English.
- Text that is only looked up at runtime (enum `rawValue`s, preset names) must be in the catalog with **Manual** extraction, and covered in `LocalizationTests`.

The build extracts strings from Swift (`SWIFT_EMIT_LOC_STRINGS`), so Xcode adds new keys to the catalog when you build in the IDE.

## Coding guidelines

- Swift 6, SwiftUI, `@Observable @MainActor` for view models.
- Keep views thin; put SMC, sensor and power logic in `Services/`.
- Add tests for new model or service behaviour. UI changes can rely on manual verification.
- No force-unwraps in non-test code unless the invariant truly cannot break.
- Prefer existing files; don't add abstractions for one-off needs.
- Anything that runs as root (helper mode, IPC, install) gets extra scrutiny: validate inputs, don't follow symlinks, and never pass unescaped input to a shell.

## Filing a PR

1. Fork and branch from `main`.
2. Run the test suite locally.
3. Fill out the PR template (summary, testing notes, screenshots if the UI changed).
4. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything users will notice.
5. Keep each commit to a single clear purpose. Sign-off is not required.

## Reporting bugs

Use the [issue templates](https://github.com/fexxdev/Mystral/issues/new/choose). For chip or sensor problems, attach the SMC export from **Settings → Diagnostics → Export SMC Data for Developer**.

## Releases (maintainers)

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` (+1) in `Mystral/Info.plist`, and move the **Unreleased** changelog entries under the new version.
2. Build with the script. Never build the DMG by hand with `hdiutil`.

   ```bash
   bash scripts/build-dmg.sh /tmp
   ```

   It builds Release, signs the app with the hardened runtime, adds the Applications link and README to the DMG, and writes `Mystral-x.x.x.dmg.sig` with the Ed25519 key from the login Keychain (service `com.fexxdev.Mystral.update-signing`). It fails if the key is missing or doesn't match `UpdateSignature.publicKeyBase64`.
3. Publish both files. Without the `.sig`, the in-app updater only links to the release page.

   ```bash
   gh release create vX.Y.Z /tmp/Mystral-X.Y.Z.dmg /tmp/Mystral-X.Y.Z.dmg.sig --title "vX.Y.Z" --notes "..."
   ```

Never print, commit or log the private key. `scripts/update-key.sh private` exists only for an offline backup.
