# Mystral - Claude Code Notes

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

## Version Bumping

Version is in `Mystral/Info.plist`:
- `CFBundleShortVersionString` — display version (e.g. 1.0.12)
- `CFBundleVersion` — build number (increment by 1 each release)

## Update Signing Key

`build-dmg.sh` signs the DMG with the Ed25519 key stored in the login Keychain (service `com.fexxdev.Mystral.update-signing`) and fails if it is missing or does not match `UpdateSignature.publicKeyBase64`. Always upload the `.sig` next to the DMG: without it the in-app updater only links to the release page. Never print, commit or log the private key; `scripts/update-key.sh private` exists only for an offline backup.
