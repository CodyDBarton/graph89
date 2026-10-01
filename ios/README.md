# Graph 89 for iPhone and iPad (prototype)

A universal, personal-use TI-89 Titanium app built from the bundled TiEmu C engine.
The first version uses the original Titanium keyboard artwork, a monochrome LCD,
and automatically saves/restores calculator state. It targets iOS/iPadOS 16 or later.
It does not yet reproduce Graph89's complete Android feature set or other calculator models.

## Open and run

1. Keep your own `TI89Titanium_OS.89u` file at the repository root. It is ignored by Git.
2. Open `ios/Graph89.xcodeproj` in Xcode.
3. Select the **Graph89** scheme and an iPhone or iPad simulator, then click Run (▶).
   The native engine builds automatically; no Homebrew libraries or extra packages are required.
4. For a physical device, select the Graph89 target, open **Signing & Capabilities**,
   and select your Personal Team. Connect your device, enable Developer Mode if requested,
   choose it as the run destination, and click Run. Xcode may ask you to sign in first.

The OS file is bundled into the application and converted to an emulator image on startup.
State is saved in the app's Application Support directory when the app enters the background.
Returning to the app resumes the saved calculator session and wakes the display.
The power key is labeled ON with blue OFF above it; 2ND + ON turns the calculator off.
Tapping a key wakes a sleeping calculator. Uninstalling the app removes its state.
A free Personal Team's device provisioning expires after seven days; reinstall from Xcode to renew it.
Keep the bundled firmware and generated builds local.

## Native checks on a Mac

From the repository root:

```sh
/usr/bin/python3 ios/tools/build_native.py
ios/build/macosx/boot-test TI89Titanium_OS.89u ios/build/macosx/titanium.img ios/build/macosx/calculation.pgm
ios/build/macosx/boot-test TI89Titanium_OS.89u ios/build/macosx/titanium.img ios/build/macosx/restored.pgm ios/build/macosx/titanium.img.state
cmp ios/build/macosx/calculation.pgm ios/build/macosx/restored.pgm
```

The test boots the real OS, enters `1+1`, saves the session, changes the display, restores it,
and verifies the display matches exactly. The second invocation verifies the same saved state
in a fresh process. The `.pgm` file is a 160×100 grayscale screenshot.

To build for a simulator or device without opening Xcode:

```sh
xcodebuild -project ios/Graph89.xcodeproj -scheme Graph89 -sdk iphonesimulator -derivedDataPath ios/build/Xcode CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Graph89.xcodeproj -scheme Graph89 -configuration Release -sdk iphoneos -derivedDataPath ios/build/Xcode-device CODE_SIGNING_ALLOWED=NO build
```

An unsigned device build verifies compilation, but cannot be installed until Xcode signs it.
Use the `--smoke-test` launch argument only for development; it enters `1+1` and saves state.

## Touchscreen check

The Graph89 scheme includes a UI test. In Xcode, choose Product → Test to run it
on the selected simulator. It starts with a sleeping calculator, taps the actual
keyboard coordinates to wake it and enter `2+3`, and compares the displayed result
with a reference generated independently by the native emulator. The test uses
a separate saved session so it does not overwrite your calculator session.

## Implementation notes

- `tools/build_native.py` reads the existing Android library source lists and builds static Apple
  libraries. It generates Apple/LP64 GLib configuration headers in the ignored build folder,
  avoiding changes to Android's existing configuration. All current Apple builds use arm64.
- JNI callbacks are excluded on Apple, and Android logging has an Apple compatibility path.
- `native/Graph89Core.c` exposes startup, input, framebuffer, and saved-state operations to Swift.
- `App/Graph89App.swift` owns the emulator on the main thread, runs at 30 frames per second,
  supports simultaneous touch input, and maps keys with the existing skin's bitmap mask.
- `tools/create_project.py` regenerates the checked-in project. If you edit project settings in
  Xcode, do not regenerate it unless you also update the generator.

The emulator libraries retain their original licenses; the Graph89 application is GPLv3.
