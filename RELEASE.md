# Releasing AnnoTex

AnnoTex releases are distributed as Developer ID signed and notarized DMGs on
GitHub. The first target release is `v0.1.0`.

## One-Time Setup

1. Install the full Xcode app and open it once.
2. Join or use an Apple Developer Program team.
3. Install a `Developer ID Application` certificate in Keychain.
4. Store notarization credentials:

   ```sh
   xcrun notarytool store-credentials "annotex-notarytool" \
     --apple-id "<apple-id>" \
     --team-id "<team-id>" \
     --password "<app-specific-password>"
   ```

5. Confirm the signing identity is visible:

   ```sh
   security find-identity -v -p codesigning
   ```

## Build A DMG

Run the release script from the repo root:

```sh
APPLE_TEAM_ID="<team-id>" scripts/release_dmg.sh
```

Useful local checks:

```sh
APPLE_TEAM_ID="<team-id>" scripts/release_dmg.sh --skip-notarization
```

Do not publish a `--skip-notarization` DMG. That flag is only for checking
local archive, export, and DMG creation before using Apple notarization.

The script writes:

- `dist/AnnoTex-v0.1.0.dmg`
- `dist/AnnoTex-v0.1.0.dmg.sha256`

## Manual Smoke Test

Before publishing, install from the generated DMG and verify:

- Open a PDF.
- Add plain text, `$$H_{n-1}$$`, `Text $x$ text`, and
  `Map $A \xrightarrow{f} B$ now`.
- Change rendered color and font size.
- Resize, copy, cut, paste, delete, undo, and redo annotations.
- Save, close, reopen in AnnoTex, and edit the same annotations.
- Open the saved PDF in Preview and confirm visible appearances.

## Publish On GitHub

Tag and push the release commit:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Create a draft GitHub release and upload the DMG plus checksum:

```sh
gh release create v0.1.0 \
  dist/AnnoTex-v0.1.0.dmg \
  dist/AnnoTex-v0.1.0.dmg.sha256 \
  --draft \
  --title "AnnoTex v0.1.0" \
  --notes-file docs/releases/v0.1.0.md
```
