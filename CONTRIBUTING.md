# Contributing to Mystral

Thanks for your interest in helping out!

## Development setup

Requirements:
- macOS 14+ with Xcode 16+
- Apple Silicon Mac for hardware testing (Intel won't exercise the SMC paths)

```sh
git clone https://github.com/fexxdev/Mystral.git
cd Mystral
open Mystral.xcodeproj
```

If you change `project.yml`, regenerate with `xcodegen generate`.

## Running tests

```sh
xcodebuild test \
  -project Mystral.xcodeproj \
  -scheme Mystral \
  -destination 'platform=macOS'
```

## Building a release DMG

```sh
./scripts/build-dmg.sh
```

The output lands in `dist/`.

## Coding guidelines

- Swift, SwiftUI, `@Observable @MainActor` for view models.
- Keep controllers thin; put SMC and sensor logic in `Services/`.
- Add tests for new model/service behavior. UI changes can rely on manual verification.
- No force-unwraps in non-test code unless the invariant is genuinely unbreakable.
- Prefer existing files; avoid introducing new abstractions for one-off needs.

## Filing a PR

1. Fork & branch from `main`.
2. Run the test suite locally.
3. Fill out the PR template (summary, testing notes, screenshots if UI changed).
4. Sign-off not required; commits should have a clear single purpose.

## Reporting bugs

Use the issue templates. SMC exports (Settings → Diagnostics) are extremely helpful for unsupported-chip reports.
