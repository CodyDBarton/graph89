# Android personal build

The active personal build is ARM64 only; `android/build.sh` builds only that APK. The ARM32 flavor remains as a historical comparison and is no longer part of the normal build.

The personal builds retain Graph89 1.1.3c's Android UI and CPU speed setting. The original architecture comparison used the same busy-calculation loop and compiler flags; the active ARM64 build now uses the unthrottled busy loop described below.

| Build | Native ABI | App ID |
| --- | --- | --- |
| Graph89 32-bit | armeabi-v7a | com.codybarton.graph89.arm32 |
| Graph89 64-bit | arm64-v8a | com.codybarton.graph89.arm64 |

Both can be installed alongside the paid app without replacing it. Preferences, calculator states, backup folders, and received files are separate. Import the same original ROM/OS into each through ROM Manager. Do not restore a 32-bit state/backup into the 64-bit build: legacy saved states contain architecture-dependent native structures. The firmware is not included in either APK.

## Build on this Mac

Java 11 is installed through Homebrew. Android command-line tools are under `~/Library/Android/sdk`. The project pins API 29, build-tools 30.0.3, and NDK 23.2.8568313. Rosetta is needed for the older Intel-only Mac packaging tools. `local.properties` specifies the SDK location and is ignored by Git.

Run from the repository root:

```sh
bash android/build.sh
```

The signed optimized APK appears in `app/build/outputs/apk/arm64/release/app-arm64-release.apk`.

They use the local Android development signing key, not the paid app's key. Keep that key (`~/.android/debug.keystore`) to install subsequent updates without uninstalling these personal apps. APKs and keys are ignored by Git.

## Install and compare

Copy the 64-bit APK to the phone and open it to install, or enable USB debugging, connect the phone, accept its debugging prompt, and use:

```sh
~/Library/Android/sdk/platform-tools/adb install -r app/build/outputs/apk/arm64/release/app-arm64-release.apk
```

Use the same firmware, CPU speed (100%), Overclock when Busy setting, calculator mode, and expression in both. Time each calculation after a warm-up, alternate between apps, and repeat several times. Compare the paid app separately: its compiler and other build details are unknown, so that comparison does not isolate architecture alone. No S22 Ultra speed increase has yet been measured.

## Validation (2026-10-07)

Both release builds complete successfully, including fatal release lint checks. APK signatures verify, and each APK contains only its declared ARM ABI. The 64-bit APK was installed on an isolated ARM64 Android 11 emulator: firmware import through ROM Manager, TI-89 Titanium startup, touch-key arithmetic (`2+3 = 5`), global and ROM settings, the default CPU speed of 100%, and saved-state restoration after a cold process launch were checked. That emulator supports ARM64 only; the 32-bit APK still needs a device runtime check. The shared iOS native core also passed startup, arithmetic, and a saved-state round trip on macOS; the ZIP compatibility fix passed an encrypted-archive checksum test.

These checks establish basic operation, not a measured S22 Ultra performance improvement.

## Back navigation and Titanium skin update

Build code 1134 fixes system Back so it toggles between the calculator and its options menu. On the main calculator screen it no longer exits the app. Back within ROM Configuration or Settings returns to the calculator normally. A fresh TI-89 Titanium instance now selects Classic 89 Titanium. Existing Titanium instances using the old generic default are migrated once; other skins and later deliberate choices are preserved. Updating the APK in place retains imported firmware and calculator states.

Verified on the ARM64 Android emulator: new Titanium default, migration of existing generic Titanium settings, preservation of Classic 89 and ordinary TI-89 preferences, repeated system Back presses, tapping the actual navigation-bar Back button, opening ROM Configuration from that menu, and preservation of a later skin choice across cold process launch. Both architecture APKs rebuild and signatures verify. The user reports the previous 32-bit build performs the integral similarly to the paid app, while the 64-bit build is noticeably faster on the S22 Ultra; that improvement has not been numerically timed.

## Titanium launcher icon and settings label

Build code 1136 uses a Titanium calculator with LCD as the launcher icon, derived from the user’s Android screenshot. Adaptive icon padding keeps the calculator within round masks. The calculator menu and configuration activity now say “Configuration Settings.” Key-repeat behavior is unchanged. [Artwork and generation notes](artwork/README.md).

Build 1136 validation: ARM64 release build and fatal release lint passed; APK signature verified and native libraries are ARM64 only. Installed on an isolated Android 11 emulator and visually checked the circular launcher icon: LCD and all keypad rows remain visible.

## Portrait Titanium power key

Build code 1137 ports the iOS screenshot-based ON/OFF drawing to Android's portrait Classic 89 Titanium skin. It follows the existing key contour, replaces EMU with white ON, and adds blue OFF above it. The drawing is applied in the same coordinate system as the skin; the original touch mask and key code are unchanged. The landscape Titanium skin already has ON/OFF. No image generation was used for this change; the established iOS drawing was translated to Android Canvas.

For TI-89 Titanium, ON is now sent to the emulated calculator instead of opening the emulator menu. 2ND + ON performs OFF; system Back still opens the emulator options. Other calculator models retain their existing menu-key behavior.

Build 1137 validation: ARM64 release build and release lint passed; APK signature verified. Visually checked the ON/OFF artwork on an isolated Android emulator, confirmed 2ND + ON blanks the calculator LCD, ON wakes it, and system Back still opens the Configuration Settings menu.

## Unthrottled busy overclocking

Build code 1138 removes the old limit of 30 extra engine batches and the 1 ms busy-loop sleep. With Overclock when Busy enabled and no touch key held, the engine runs continuously while the calculator's BUSY pixel is set. It checks BUSY directly in native LCD memory instead of waiting for a screen redraw. Turbo chunks run 10,000 CPU-loop iterations independently of the CPU Speed slider, matching the iOS turbo chunk size. Every chunk checks keys, stop requests, state operations, and the overclock setting; after approximately 10 ms the outer loop services remaining work without a deliberate pause.

Holding a calculator key temporarily restores normal pacing, as on iOS, to keep key repeats usable. Idle operation and disabling overclocking retain the normal CPU-speed pacing. ON interrupts a calculation, displaying the calculator's Break message. The emulated CPU remains single-threaded: unthrottled execution can occupy one host CPU core, rather than spreading one instruction stream across all cores.

Validation (2026-10-08): ARM64 release build and release lint passed. On an isolated ARM64 Android 11 emulator, `nInt(sin(x^2),x,0,100)` showed BUSY with the engine thread at 100% CPU in a sampled interval. Tapping ON produced Error: Break. Disabling overclocking through Configuration Settings returned the busy engine to normal pacing (8% CPU in the sampled interval); ON still interrupted, and subsequent `2+3` returned `5`. These CPU samples confirm pacing behavior; they do not establish a measured S22 Ultra speed increase.

Before/after emulator calculation timing: [2026-10-08 benchmark report](benchmarks/2026-10-08-overclock/README.md). Ten trials per build averaged 337.708 ms before versus 318.199 ms after for `nInt(sin(x^2),x,0,8)`: 6.13% higher throughput, or 5.78% less time. Results matched. This is an M4-hosted emulator measurement, not a Galaxy S22 Ultra measurement.

## Optional sharp text prototype

Build 1139 adds **Configuration Settings → Display Settings → Sharp Text (Prototype)** for TI-89/Titanium. It is off by default; unchecking it restores the original LCD. With Solid LCD and grayscale off, recognizable Home/menu text is redrawn with smooth outline fonts at its original position. Unsupported symbols and graphics remain pixels. See the [screenshots, implementation limits, and verification](sharp-text/README.md).

Build 1140 preserves outline-font proportions for narrow letters and validates previously recognized glyphs across cursor/word-context changes to prevent sharp/bitmap alternation. Changed glyphs are removed immediately; cursor padding is left visible.

Build 1141 replaces the substitute typeface with vector contours derived from each loaded ROM glyph. The original lowercase `i` serif and dot, letter shapes, spacing, and stroke widths are retained, with mild corner/diagonal smoothing. The original-display toggle and cursor-stability validation remain in place.

Build 1142 integrates the approved TI92Pluspc-based HD font and replaces bitmap contour tracing. It uniformly fits the entire face, including full descenders and round-capital overshoot, to the ROM cells. The original LCD toggle remains available. A new cursor regression covers recognizing letters even when the cursor is already on. The bundled font retains its original attribution and license metadata.

Build 1143 recognizes the small-font I within toolbar/status words, including MAIN and PrgmIO. Isolated vertical bars and menu-box borders remain original; no font outlines changed.

Build 1144 extends Sharp Text recognition for isolated superscripts and paired, variable-height pretty-print parentheses. Verified `1/sin(x^2)`, nested exponents, and nested parentheses on the Android ARM64 emulator. The approved font asset is unchanged. Fraction/radical bars and unsupported symbols remain original pixels.

Build 1145 fixes false small inverted-text recognition inside `e^(`. The special exponential token remains original pixels; actual inverse text remains sharp. Verified cursor blinking and inverse menu selection on the isolated Android emulator.

Build 1146 fixes inverted Home-input glitches and sharpens input `^`, `(` and `)` by matching the editor's medium-font grid. Unsupported italic e remains original pixels. Verified normal/inverse `e^(2)`, cursor blinking, and regression tests.

Build 1147 integrates the 44 approved special-character outlines, including italic e and the revised Greek letters, imaginary i, and symmetric infinity. Existing ASCII outlines/metrics are unchanged. Verified all 44 mappings against actual medium-font ROM templates, normal/inverse editor input, Greek/math menus, and cursor stability. Unsupported specials and dynamically assembled shapes remain original.

Build 1148 fixes the pixelated `e^(` Catalog entry by accepting the complete adjacent exponential token even though it contains only one text anchor. Glyph designs are unchanged. Actual Catalog display verification, normal/inverse and exclusion regressions, and ARM64 release build/lint passed.

Build 1149 recognizes variable-height Home pretty-print integrals (normal/inverse) with the existing approved shape and prevents fresh/cached fragments from overwriting disabled F-menu tiles. Derivative d and dropdown arrow candidates remain preview-only pending approval. All existing glyph designs are unchanged.

Build 1150 integrates the approved derivative d at all ROM font sizes and a sharp triangular dropdown beside enabled F-key labels. Normal/inverse dropdown context, disabled/cache rejection, and all 45 approved font-symbol tests pass. Earlier glyph designs and metrics remain unchanged.
