# Graph 89 for iPhone and iPad (prototype)

A universal, personal-use TI-89 Titanium app built from the bundled TiEmu C engine.
The first version uses the original Titanium keyboard artwork, a monochrome LCD,
and automatically saves/restores calculator state. It targets iOS/iPadOS 16 or later.
The app icon uses the same Titanium artwork as Android, from
`android/artwork/titanium-launcher.png`, resized into the iOS AppIcon asset.
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

The shared scheme uses **Release** for the normal Run action. Swift text recognition and compact layout need compiler optimization to stay responsive on physical devices. For deliberate source debugging, select **Product → Scheme → Edit Scheme → Run → Info → Build Configuration → Debug**; restore Release for normal use. Tests retain their separate configuration.
Keep the bundled firmware and generated builds local.

## Configuration Settings

The LCD and button face have the same width and form one panel. There is no title,
footer, or system status bar. A translucent gear is nestled against the
display's upper-right corner in every mode and never changes the panel's size. Its
44-point circular badge is also its exact touch target; there is no invisible hit area. On iPad, the badge
sits just below the top system-input strip: real simulator mouse clicks there
were intercepted before reaching the app, despite synthetic touch tests passing.

Stretch mode is saved and applies immediately:

1. **Aspect ratio; no loss** (default): uniformly fits the panel inside iOS's safe
   display area, protecting content from corners, cutouts, and gesture margins.
   These system-provided bounds are conservative; no private corner-radius APIs are used.
2. **Horizontal**: starts from no loss and stretches only the width to the full display.
3. **Vertical**: starts from no loss and stretches only the height to the full display.
4. **Horizontal and vertical**: stretches to fill the full display in both dimensions.
5. **Aspect ratio, full**: uniformly fits the full display, ignoring rounded corners.
6. **Aspect ratio, crop**: uniformly fills the full display, clipping any overflow.

CPU Speed ranges from 30% to 250%; Overclock when Busy runs extra work while the
calculator shows BUSY. Changes apply immediately and are saved independently of
calculator state. Restore Defaults sets 100% CPU Speed, enables busy overclocking,
selects Aspect ratio; no loss, and restores 8 ms haptic feedback.

Haptic Feedback matches Android's 0–30 ms duration setting (8 ms by default,
0 disables it). A vibration plays once on each calculator key press, never on
release. Core Haptics provides timed vibration on supported hardware; the physical
feel differs by device. Simulators and devices without haptic hardware remain silent.

The iOS port now uses Android's model-specific engine batch size (90,000 CPU-loop
iterations for this Titanium at 100%) and pause calculation: truncate(30 / speed)
milliseconds after each normal batch, with the batch itself multiplied by speed.
Here speed is the selected percentage divided by 100. This preserves the original
slider's nonlinear behavior; 200% is not a promise of exactly twice the throughput.
100% follows Android's pacing, not a new calibration against physical hardware.

Screen refresh remains at a target 30 Hz, independently of engine scheduling.
Busy overclocking uses the same bottom-right LCD indicator as Android. While it
is active, a dedicated serial background queue runs the native engine continuously,
without pacing sleeps or a limit on additional batches. This uses the throughput
of one CPU core; the sequential emulated processor cannot distribute a calculation
across cores. OS scheduling and thermal limits still apply. The normal CPU Speed
slider governs paced operation; busy overclocking runs at maximum throughput
regardless of its value.

The worker returns to its queue approximately every 10 ms to handle keys, settings,
lifecycle changes and framebuffer snapshots, then immediately continues computing.
Each native call runs 10,000 CPU-loop iterations, so a single call can overrun that
quantum on slower hardware. All native access stays on this queue because TiEmu
has global mutable state. UIKit runs on the main thread. Turbo is suppressed while
a key is held to avoid accelerated key repetition. Minimum key-hold time scales
with the normal speed setting so short taps can still be scanned at 30%.

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
xcodebuild -project ios/Graph89.xcodeproj -scheme Graph89 -configuration Release -sdk iphonesimulator -derivedDataPath ios/build/Xcode CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Graph89.xcodeproj -scheme Graph89 -configuration Release -sdk iphoneos -derivedDataPath ios/build/Xcode-device CODE_SIGNING_ALLOWED=NO build
```

An unsigned device build verifies compilation, but cannot be installed until Xcode signs it.
Use the `--smoke-test` launch argument only for development; it enters `1+1` and saves state.

## Touchscreen check

The Graph89 scheme includes a UI test. In Xcode, choose Product → Test to run it
on the selected simulator. It starts with a sleeping calculator, taps the actual
keyboard coordinates to wake it and enter `2+3`, and compares the displayed result
with a reference generated independently by the native emulator. Additional checks
verify saved settings, actual engine throughput at 30/100/250%, busy overclocking
using `nInt(sin(x^2),x,0,8)`, sustained maximum throughput and ON interruption
using the longer limit of 100, selection and persistence of all six stretch modes,
direct taps on the visible corner gear in portrait and landscape, and haptic
duration persistence, disabling, and one request per key press. The test uses
a separate saved session so it does not overwrite your calculator session.

## Implementation notes

- `tools/build_native.py` reads the existing Android library source lists and builds static Apple
  libraries. It generates Apple/LP64 GLib configuration headers in the ignored build folder,
  avoiding changes to Android's existing configuration. All current Apple builds use arm64.
- JNI callbacks are excluded on Apple, and Android logging has an Apple compatibility path.
- `native/Graph89Core.c` exposes startup, input, framebuffer, and saved-state operations to Swift.
- `App/Graph89App.swift` owns the emulator on a serial background queue, refreshes the screen at 30 frames per second,
  supports simultaneous touch input, and maps keys with the existing skin's bitmap mask.
- `tools/create_project.py` regenerates the checked-in project. If you edit project settings in
  Xcode, do not regenerate it unless you also update the generator.

The emulator libraries retain their original licenses; the Graph89 application is GPLv3.

## HD text prototype

The iPhone/iPad app now includes the Android HD text prototype. Open the gear → **Sharp Text (Prototype)** (scroll down in Configuration Settings). It is off by default; the saved toggle takes effect immediately and turning it off restores the original LCD.

`App/SharpTextRecognizer.swift` ports the Android recognizer, including mixed font sizes, all 45 approved math/Greek font symbols, derivative d, dropdown arrows, variable-height integrals/parentheses, normal/inverse input, cursor preservation, and disabled F-menu exclusions. The native engine extracts font templates from the loaded ROM on its serial queue. The app bundles the same `app/src/main/assets/fonts/Graph89HD.ttf`; no alternate glyph designs were introduced. Font attribution is retained in that asset and its README.

`App/SharpTextView.swift` clears matched glyph ink in a copy of the original 160 × 100 bitmap, draws it with nearest-neighbor scaling, then draws approved CoreText outlines at display resolution. This prevents faint bitmap remnants at fractional display scales. Unmatched graphics remain original; computation, input, aspect/stretch modes, and the calculator framebuffer are unchanged. The shared native retained-text layer now captures ROM character identities, positions, and live font state before rasterization. Validated captured characters take priority over the bitmap recognizer; unsupported shapes and drawing paths keep its existing fallback. Bitmap save/restore, inversion, cursor padding, clearing and state loading are handled without changing the ROM or approved font. See [retained-text details](../tools/drawing-trace/README.md).

### Verification

`python3 ios/tests/sharp-text-parity.py FONT_TEMPLATES FRAME_DIRECTORY` compares the Swift recognizer with the Android reference using private local original-screen fixtures. The 43 available actual-ROM screens have identical fresh and cached recognition results. Firmware/fonts extracted from the ROM and raw screen fixtures are kept in ignored local build output, not committed.

`ios/tests/FontCheck.swift` verifies CoreText can load all 45 approved symbol outlines and that its ASCII family bounds match Android. UI tests cover the saved toggle, restoring the original display, calculator operation, derivative rendering, fractional zoom, and disabled/selected history text. Use the shared Graph89 scheme to build/run from Xcode; existing signing settings are preserved.

Verified on 2026-10-09: release simulator and physical-device builds passed; saved-toggle/calculation UI tests passed on iPhone 17 and iPad 9 simulators. After the native-resolution clearing fix, fresh derivative and selected-history screenshots passed visual inspection on both devices. [iPhone screenshot](tests/screenshots/iphone-hd-derivative.png), [iPad screenshot](tests/screenshots/ipad-hd-history.png). Both app bundles contain the exact approved Android font bytes. Physical-device visual/performance confirmation remains to be done.

### Tall mathematical shapes and selection

Tall parentheses are checked in both normal and inverted text, with pairs required to have matching height and polarity. After native character identities are merged, a second exact-shape pass uses those character positions to validate integrals and parentheses. This avoids rejecting valid selected expressions because a background border is clipped, or because limits/fractions separate the integrand from the integral stem. Complete caps and stems remain mandatory; clipped or altered shapes stay original. Shape detection can replace conflicting pixel-recognized fragments but cannot overwrite verified native characters, editor text, disabled toolbar tiles or graph areas. Approved outlines are unchanged.

Actual-ROM checks cover a 25-row integral and paired parentheses in normal and inverted history selection. Java/Swift behavior matches on all 21 captured screens; existing graph, clearing, changed-cap and disabled-menu regressions pass.

Visual UI checks pass on iPhone 17 and iPad 9: [normal tall math](tests/screenshots/iphone-hd-tall-normal.png), [inverted tall math](tests/screenshots/iphone-hd-tall-inverted.png), [iPad selection](tests/screenshots/ipad-hd-tall-inverted.png).

### Approved Catalog triangle

ROM character 18 now uses the approved filled right-pointing triangle in both renderers, including normal/inverse conversion commands and the Catalog selection pointer. Its vertices use the original glyph ink bounds; the medium-font path is `(1,1) → (4,3.5) → (1,6)`. Character advance and padding stay unchanged. It is drawn as a vector path, separately from the shafted arrow (ROM code 22); the TTF and earlier glyph designs are unchanged.

Clipped text and tall math (2026-10-10): the retained layer now preserves partially visible ROM characters and captures integral/parenthesis geometry before clipping. The approved outlines are drawn at their full original height and clipped to the calculator's own viewport, including inverted selections. Font designs are unchanged. Unknown internal ROM instruction layouts retain pixel fallback.

Clipped-math verification passed on iPhone 17 and iPad 9 simulators, including normal/inverse 80-row shapes. The iPad test exposed mid-drawing validation removing unfinished symbols; retaining pending geometry until the ROM continuation fixes it. [iPhone normal](tests/screenshots/iphone-hd-clipped-normal.png), [iPad inverted](tests/screenshots/ipad-hd-clipped-inverted.png).

Inverse trig raised −1 (Android build 1152): ROM character 180 now uses the approved size-specific composition of the existing minus and numeral 1. The three new font outlines use 200 units per LCD pixel and a baseline at y=10; both renderers use the same fixed transform, preserving the approved preview in normal and inverted text. Reproduce these additions with `android/sharp-text/build-inverse-trig-font.py INPUT_TTF OUTPUT_TTF` after the other approved font integration steps. Earlier outlines and advances remain unchanged.

Home editor cursor (Android build 1153): capture the verified two-column, eight-row XOR rectangle call in the medium-font Home input line. A cursor packet (font 4) carries its position and the rows already toggled. Native validation and both recognizers remove those XOR pixels from a host copy before comparing glyphs, including snapshots partway through a blink. This avoids invalidating a neighboring glyph when the cursor overlaps its ink. Both HD renderers restore that original text and draw a centered 0.6-LCD-pixel cursor, preserving the calculator's position and blink timing. Original Display keeps the native cursor. No guest framebuffer or font outline is changed. Actual-ROM checks cover end/middle cursor positions and both blink phases across 40 frames, plus 64 validations during row-by-row cursor redraw; Android/iOS merge parity covers 67 frames.


### Compact layout prototype

Gear → **Compact Layout (Prototype)** enables Sharp Text and a denser Home view on iPhone/iPad. Android has the same toggle under Configuration Settings → Display Settings. It is off by default. Disabling it restores original equation spacing; disabling Sharp Text also disables compact layout. No approved glyph outline, guest framebuffer, editor contents or calculation changes.

The input uses the complete `TEXT_EDIT` buffer, resolving its movable heap handle on every snapshot. Characters advance 4.5 LCD units instead of 6, with the existing glyphs uniformly scaled to 80%. Up to 35 characters fit instead of 26 (34 plus a visible end caret). Its viewport stays fixed until the full cursor offset crosses its left or right edge, independently of the ROM scroll offset. Selections and blink timing are preserved. Unknown symbols use their ROM bitmap.

Home pretty print retains `Print2DExpr` character, delimiter, line and pixel calls **before LCD clipping**, including original coordinates beyond the visible display. Complete live expression groups are rendered uniformly at 72%, revealing about 39% more horizontal equation span. Coordinates are anchored at the body bottom and at the expression's left edge or a right-aligned result. Fractions/radicals keep their line geometry; approved tall parentheses/integrals keep their full height. Menus, plots and status/toolbar remain at their original layout.

This is a drawing-layout prototype, not a semantic expression reformatter: it shrinks glyphs and original equation geometry together. It does not remove internal pretty-print padding independently or repaginate all history. Capture is bounded to sixteen groups of 512 primitives and a 512-byte input. Incomplete/oversize/unknown capture falls back to the original layout. It may still require calculator scrolling for very wide expressions.

Run `python3 tools/drawing-trace/compact-parity.py RETAINED_RUN_DIRECTORY PRIVATE_FONT_TEMPLATES` against local capture output to compare Android/iOS placements and verify that scrolled-off input and previously clipped pretty-print characters become visible. `testCompactFullContentAndToggle` checks a 41-character input, wide/selected pretty print and the reversible toggle in an isolated simulator. Firmware and captured buffers remain ignored local files.

Verified locally: 84 control/retained ROM framebuffer captures remain identical; Android/iOS original merge and compact placement parity pass, including input edits after history capture and suppression of native delimiter stems. Compact input/full pretty-print/toggle UI checks pass on iPhone 17 and iPad 9; final compact full-height/inverse math checks pass on iPad. ARM64 APK build/signature and iOS simulator/unsigned physical-device builds pass. Actual Galaxy/iPhone/iPad hardware visual testing remains manual.

Oversize input or live expression capture keeps the original Home body. Tall-shape validation is bounded to 512 rows. Clearing any calculator window that overlaps the history invalidates full-content groups, preventing a retained equation layer from erasing a calculator dialog. The 84-frame capture suite includes a long injected expression; its key queue is fully drained before submission.

Compact layout identifies Home with Tools/PrgmIO and Y= with Tools/Zoom plus the input borders. Each editor uses its own TEXT_EDIT identity and bounds. Y= preserves and compacts the fixed y1(x)= prefix, fitting 29 editor characters (28 plus an end caret). The equation list uses a top-aligned 72% layout, keeping equation labels, selection marks and unknown graphics through a compact raster fallback while full Print2DExpr groups reveal previously clipped content. Input viewports persist while the cursor moves within them; they scroll only when the cursor crosses an edge. Eighty-four ROM captures verify Android/iOS placement parity and both editor scrolling regressions.

Y= compact layout and scrolling: `testCompactYEditorAndEdgeScrolling` verifies a long equation, stationary viewport during left movement and scrolling across the left edge. `testCompactYEquationListAndToggle` verifies list rendering and that toggling presentation preserves the native equation list. Both passed on the isolated iPad simulator. Graph/Window isolation, Home/Y= placement parity, clipped labels and existing sharp-text regressions passed across 82 native captures.

Y= available-height fix: a uniquely verified AMS drawing-loop signature identifies its local WinHeight result. The HD capture extends that scratch drawing limit from 67 to 93 logical units while retaining the original window/LCD clip, causing AMS to lay out additional real rows and their equations. Extra labels use explicit font-11 packets; completed full equation groups can be retained below the original LCD edge. Compact rendering excludes the native input/status rows from the list. This does not patch the ROM file or change equation contents. The original LCD stays identical in 84 control/retained captures. Fixtures cover a populated hidden y9 and extra rows after scrolling. Compact row count varies with equation heights; empty rows show ten full entries and part of the eleventh.

Final expanded-height checks: `testCompactYFillsAvailableHeight` passed on the isolated iPad before/after ten Down presses and with original spacing restored. Partly clipped rows retain the transformed PLOTS-header boundary. Final visual checks, 84 native framebuffer comparisons and Android/iOS compact/merge parity passed; simulator and unsigned physical iOS builds and the Android ARM64 APK passed.

### Compact spacing refinement (Android build 1158)

Home and Y= input now use narrower advances for spaces, punctuation, I/i/l and parentheses, with the same 80% glyph size. Caret position, selection backgrounds and edge-triggered scrolling use accumulated character widths. Wide characters retain the previous 4.5-unit advance. The viewport can show more narrow characters without reducing their font size; moving left inside it does not scroll.

Pretty print now removes half of excess empty horizontal gutters, retaining at least one native unit of separation. Each complete glyph cell, vertical stroke and diagonal is protected. Numerators, denominators, exponents, delimiters and fraction-bar endpoints share an expression-wide horizontal coordinate map; glyph shapes, glyph size and vertical coordinates are unchanged. Right-aligned Home answers keep their right edge. Normal and inverted expressions use identical positions. Oversize coordinate spans fall back to the previous uniform layout. This applies to both Home history and Y= equations.

This is geometric spacing refinement, rather than an expression-tree typesetter: it does not independently recenter fraction components, change vertical fraction spacing or move separate components across overlapping occupied columns. Existing long-expression captures become about 5–8% narrower than the previous compact view, with gains depending on the expression. Compact Layout remains the existing reversible option and defaults off.

### Vertical mathematical spacing (Android build 1159)

Compact pretty print now halves unoccupied vertical gaps, preserving at least half a native unit between occupied rows. Ordinary glyph cells retain their complete height, including descenders and superscripts. Horizontal bars and text share the same vertical map. Tall integral/parenthesis outlines shorten with the enclosed expression; their duplicate raster stems do not block spacing refinement. Oblique and other non-delimiter vertical graphics protect their full height. This geometric refinement does not redesign font outlines.

Home expressions keep their bottom anchor; history selection backgrounds follow the new bounds and history markers move with their expressions. Y= expressions keep their equation-label baseline (including multi-digit labels), so shortening does not detach the equation from its label. Native equation-row placement is retained. The captured 80-unit nested-fraction integral becomes 75 units tall before the existing 72% compact scaling, a further 6.25% height reduction. Gains depend on available gaps.

Y= also retains complete extra-row labels when their glyphs cross the original LCD boundary, rather than only when their origin is wholly below it. This prevents a boundary row from losing the y or equals sign in compact view.

Calculated Home answers retain right justification in compact mode, including answers that start left of the screen midpoint and answers that first fit after compaction. Native packet type 5 now uses its attribute for expression identity: 1 calculated output, 2 entered expression, 0 unknown. This is read from the leftover Parse2DMultiExpr argument only after verifying the complete Home caller instruction sequence and its ROM-call targets; Y= is excluded. The packet remains twelve integers. Fitting outputs share a right-edge translation across glyphs, fraction rules and selection backgrounds; oversized outputs preserve their native left/scroll origin. Sharp-only and original display coordinates remain unchanged. Regression coverage includes medium, newly fitting, oversized and inverted outputs, plus an input ending at the screen edge.

Compact Home history now captures an additional 134 native layout units above the original viewport using a uniquely verified AMS Home paint-loop sequence. Only its local record-range boundary changes; window clipping, stored history, selection, and scrolling coordinates remain native. Capture is bounded to 64 expression groups and 32 markers. Completed passes use packet 13, packet 5's height field identifies the current input/answer pair, and packet 12 retains offscreen history markers. Unsupported sequences and incomplete/oversize captures retain the original display.

The compact renderer merges vertically overlapping bands to preserve side-by-side inputs and answers, then packs distinct bands upward from the bottom with a one-unit gap within a pair and two units between pairs. Markers, inversion backgrounds, and mathematical glyphs share the same translation. Filled, selected, and scrolled real-ROM captures expose nine pairs (eight complete) versus six original pairs (five complete) in the filled-view example. Turning compact mode off preserves the original history framebuffer. The extra draw work can change the cursor's blink phase in fixed-cycle captures; verification accepts only the complete known two-column XOR cursor and requires all history/body pixels to match.

Structure-specific gap caps refine the generic empty-space rule: raised powers use up to 0.75 native units horizontally and 0.5 vertically, fraction bars keep up to 0.75 units of separation from numerator/denominator, and integral limits keep up to one unit around the integrand. These rules apply only to recognizable drawing geometry and empty gutters. Ordinary glyph cells, descenders, unknown symbols, diagonals, and approved outlines keep their dimensions. Fractions, powers, integral limits, side-by-side history, selection, and viewport capacity are covered by 87 ROM captures plus 19 parity fixtures on Swift and Java.

Repacking preserves the native lower scrolling boundary: newer entries lying fully below the original viewport stay below it. A dedicated fixture verifies that such rows cannot displace selected older history.

Compact Y= layout also remains active when Plot1/2/3 is selected. The verified list paint pass is independent of whether the bottom equation editor is focused. Plot dialogs and other calculator screens retain their existing layout.

HD Plotting is now a separate prototype setting for ordinary Titanium AMS 3.10 function graphs. It adds real ROM evaluations at eight samples per native LCD column and draws their unrounded coordinates. Axes, ticks and grid dots also render as thin device-resolution vectors; stored equations and the original LCD remain intact. Enable it and use Graph F4 ReGraph; turn it off for the original graph. Other modes/styles and trace views retain the original display. Completed HD graphs and in-flight evaluator continuations survive calculator save/restore. See [the plotting prototype](../tools/plot-trace/README.md) for scope and isolated numerical checks.
