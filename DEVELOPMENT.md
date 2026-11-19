# Working on Scratchbar

How to build, test and release Scratchbar. For using it, see the [README](README.md).

## Building from source

You'll need Xcode 26 or later.

```bash
git clone https://github.com/geraint360/scratchbar.git
cd scratchbar
SIGN_ID=- scripts/make-app.sh --install   # build, sign for this Mac, install in Applications
```

Without `--install`, the app is left in `build/Scratchbar.app`. `SIGN_ID=-` signs it for
your own Mac only. Leave it out to sign with the Developer ID in `scripts/make-app.sh`.

## Tests

```bash
swift test
```

## How it's organised

- `Sources/ScratchbarCore/`: storage, sync, backups, search and the other logic. The
  tests cover this part.
- `Sources/Scratchbar/`: the AppKit app (menu bar item, window, editor, Settings).
- `Resources/`: `Info.plist` and the app icon.
- `scripts/`: building, releasing and the icon.

## Trying it without touching your pages

```bash
open build/Scratchbar.app --args -dataFolder ~/some/folder
```

runs Scratchbar on a separate folder, leaving your own pages alone. The screenshots in
the README were made this way.

## The app icon

The icon is an Icon Composer project, `Resources/AppIcon.icon`, whose note layer is drawn
by `scripts/make-icon.swift`. After changing either, run `scripts/make-icon.sh`. It
rebuilds `Resources/Assets.car` and the `AppIcon.icns` fallback for macOS 14 and 15.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Commit and push.
3. Run `scripts/release.sh --publish`. It builds, notarises and staples the app, then
   uploads `Scratchbar-<version>.zip` to a new GitHub release.

Notarising needs credentials saved once in the keychain. The script's header explains
how.
