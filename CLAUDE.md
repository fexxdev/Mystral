# Mystral - Claude Code Notes

## Release Process

To build a release DMG with proper drag-and-drop layout (app + Applications symlink + README):

```bash
bash scripts/build-dmg.sh /tmp
```

Then upload to GitHub:

```bash
gh release create v<VERSION> /tmp/Mystral-<VERSION>.dmg --title "v<VERSION>" --notes "..."
```

Do NOT create DMGs manually with `hdiutil` — always use `scripts/build-dmg.sh` which handles ad-hoc signing, Applications symlink, and the README.

## Version Bumping

Version is in `Mystral/Info.plist`:
- `CFBundleShortVersionString` — display version (e.g. 1.0.12)
- `CFBundleVersion` — build number (increment by 1 each release)
