# Releasing AnnoTex

AnnoTex v0.1.0 is distributed as a **non-notarized tester DMG**. This does not
require an Apple Developer Program account, Developer ID certificate, or Apple
notarization credentials.

This artifact is only appropriate for trusted testers. macOS Gatekeeper will
warn that the developer cannot be verified.

## Build A Tester DMG

Run the release script from the repo root:

```sh
scripts/release_dmg.sh
```

The script writes:

- `dist/AnnoTex-v0.1.0-not-notarized.dmg`
- `dist/AnnoTex-v0.1.0-not-notarized.dmg.sha256`

The script builds the Release app with Xcode signing disabled, applies an
ad-hoc local signature, creates a DMG, and writes a checksum. To leave the app
fully unsigned, run:

```sh
scripts/release_dmg.sh --no-ad-hoc-sign
```

## Manual Smoke Test

Before publishing to testers, install from the generated DMG and verify:

- Open a PDF.
- Add plain text, `$$H_{n-1}$$`, `Text $x$ text`, and
  `Map $A \xrightarrow{f} B$ now`.
- Change rendered color and font size.
- Resize, copy, cut, paste, delete, undo, and redo annotations.
- Save, close, reopen in AnnoTex, and edit the same annotations.
- Open the saved PDF in Preview and confirm visible appearances.

## Tester Install Instructions

Tell testers this is not notarized. If macOS blocks first launch:

1. Open the DMG and drag `AnnoTex.app` to Applications.
2. Right-click `AnnoTex.app` and choose Open.
3. If macOS still blocks it, open System Settings -> Privacy & Security and
   approve AnnoTex from the security prompt.

## Publish On GitHub

Tag and push the release commit:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Create a draft GitHub release and upload the DMG plus checksum:

```sh
gh release create v0.1.0 \
  dist/AnnoTex-v0.1.0-not-notarized.dmg \
  dist/AnnoTex-v0.1.0-not-notarized.dmg.sha256 \
  --draft \
  --title "AnnoTex v0.1.0" \
  --notes-file docs/releases/v0.1.0.md
```
