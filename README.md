# Miso

Miso is a macOS menu-bar pet. A borderless cat sits on the desktop, a care panel tracks feeding, tasks, and reminders, and the cat reacts to idle time, coding apps, and music. It is a SwiftPM executable for macOS 14, built with Swift 6. There are no third-party dependencies.

## Build and test

```sh
swift test
swift build -c release --product Miso
```

`swift build` produces a bare executable at `.build/release/Miso`. That binary is not an app bundle, so login items and `LSUIElement` do not apply until it is packaged.

## Install

`scripts/run.sh` builds the release binary, copies it with `scripts/Info.plist` into `~/Applications/Miso.app`, ad-hoc signs the bundle as `com.vrishab.miso`, and opens it. The script quits any running Miso first. Re-signing changes the bundle's code hash, which can make macOS drop or re-prompt the login item.

Info.plist lives in `scripts/` because SwiftPM does not embed it. The packaging script is what puts it in the bundle. The app is an agent (`LSUIElement`): no Dock icon.

## Layout

```
Sources/Miso/App/       entry point, app model, login item, day rollover
Sources/Miso/Model/     saved pet, care, tasks, reminders
Sources/Miso/Desk/      desk cues and the idle, app, and music watcher
Sources/Miso/Cat/       sprite, motion, click view, panels
Sources/Miso/Care/      menu-bar and floating care panel
Tests/MisoTests/        Swift Testing for the pure rules
scripts/                Info.plist and the install script
```

`Pet*` types are the saved record. `Cat*` types are the on-screen character. The product name is Miso.

State is stored at `~/Library/Application Support/Miso/pet.json`. Leave that filename in place so existing saves keep loading.

## Packaging choices

SwiftPM is the build system. `swift test` and `swift build` are the reproducible commands, and `scripts/run.sh` is the step that produces the signed app bundle `SMAppService` needs.

Sprites are drawn with Core Graphics, so there is no asset catalog. The app is ad-hoc signed and not sandboxed: idle time, Core Audio process output, and the Application Support file are used directly.
