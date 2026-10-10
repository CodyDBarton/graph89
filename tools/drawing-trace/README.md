# Drawing-call tracing prototype

This is a standalone diagnostic for the shared TI-68k core, not a replacement renderer or an app setting. It observes entry to drawing routines before their 68000 instructions execute. Neither the ROM nor calculator registers/RAM are modified by the observer. Normal Android/iOS builds compile out this verbose diagnostic logger. The separate, lightweight retained-text capture described below is included in both apps and enabled only with Sharp Text.

## Run on this Apple Silicon Mac

With Xcode and Python 3 installed, from the repository root:

```sh
python3 tools/drawing-trace/run.py TI89Titanium_OS.89u
```

The ROM is your local ignored file. The runner builds separate normal and `GRAPH89_DRAW_TRACE` macOS libraries, then runs identical fresh calculator sessions with capture off, verbose tracing, and retained capture on (including diagnostic frame sampling inside shape drawing). It never loads state from your apps, simulators, or physical devices. Output defaults to ignored `build/drawing-trace/`:

- `observe-run/events.jsonl`: call sequence, phase, ROM call ID/address, return address, live font/port, raw stack arguments and registers, plus decoded text/character/geometry where supported.
- `observe-run/calls.json`: resolved drawing entry points and verified state-variable addresses.
- `observe-run/*.pgm`, `control-run/*.pgm`: original LCD snapshots.
- `summary.json`: call counts, representative samples, scenario assertions, and framebuffer comparisons.
- `retained-run/*.cells.json`: validated native character packets.
- `retained-summary.json`: per-screen retained counts and original-LCD comparisons.

Text strings are TI character bytes, stored in hexadecimal rather than guessed Unicode. Arguments use the SDK's 16-bit shorts, 32-bit guest pointers, and two-byte character slots. Coordinates on window calls are relative to the window; `DrawChar`/`DrawClipChar` coordinates are port-relative. `Print2DExpr` records its opaque expression pointer, window and coordinates; the expression structure is not decoded yet.

For live state, the observer recognizes the tiny `FontGetSys` and `PortRestore` accessor instruction patterns and reads their RAM variables directly. If those patterns differ on another ROM, the live font stays unknown. `font_hint`/`port_hint` record the last public setter calls for comparison, but are not authoritative: saved state and internal writes can change them. Event state is recorded **before** the called routine executes, so a setter event contains the previous live state.

## Verified on TI-89 Titanium AMS 3.10

The final run captured **16,043 drawing/state events** over Home, editor, pretty-print, selected history, Tools, Catalog/scroll, two integral heights, italic e, derivative, and Apps. **All 18 LCD snapshots in the original tracing run matched the untraced build byte for byte.** Automated coverage assertions also passed.

Concrete observations:

| Area | Observed calls / information |
|---|---|
| Home toolbar and menus | `DrawStr`, `DrawFkey`, `DrawChar`; actual labels, glyph codes, position and attributes |
| Home input and status | `DrawClipChar`; clipping, normal body font and small status font |
| Superscript in `1/sin(x^2)` | `DrawChar`: code 50 (`2`) at (40,70), font 1; base `x` at (33,74) |
| Italic e | Code 150 in editor, pretty-print and Catalog, without bitmap matching |
| Derivative | Code 188 in pretty-print, including numerator and denominator d |
| Disabled toolbar | Attribute 3 (`A_SHADED`) explicitly identifies disabled text |
| Expression rendering | 26 `Print2DExpr` entries; `Parse2DExpr` was not observed |
| Menu close/restoration | `BitmapGet`/`BitmapPut`, saving/restoring drawing state |

The last selected font differed from live font on **254 events**, demonstrating why setter tracking alone is insufficient. Nested calls are logged separately: `WinStrXY` → `WinStr` → character drawing is not three independent visible strings.

## Integrated retained text prototype (Android and iOS)

The shared native `hdtext.c` now maintains a bounded display list from `DrawChar`, `DrawClipChar` (including partial characters), and `DrawStr`. It records the ROM character byte, coordinates, live font, port, attribute, and clipping rectangle. Java and Swift merge those identities over the existing pixel recognizer before drawing the approved font. Turning Sharp Text off clears the captured list and restores the original LCD. Reset and state loading invalidate it; loading a state cannot resurrect a previous display list.

Native characters are validated against the current original LCD, using the ROM's font pixels rather than guessing which character those pixels represent. Inverted selection is detected from final pixels. A single solid cursor column or bottom underline may occupy blank padding, but changed glyph ink and cleared/solid regions invalidate the entry. Disabled (`A_SHADED`) glyphs remain original. Partially clipped characters keep their full glyph geometry. Validation compares only pixels inside the guest clip, and both renderers erase/draw only within that rectangle. Small/medium font templates have a one-column bearing relative to the public drawing coordinate; exported coordinates include that bearing so both renderers align identically.

`BitmapGet` retains text inside the saved rectangle. `BitmapPut` restores it after matching actual saved bitmap content, including when the OS relocates the heap buffer. Pixel comparison discards stale or modified entries. `ClrScr` clears the active port. Public rectangle scroll/shift tracking is conservative; private OS scrolling, arbitrary bitmap writes, and unrecognized ROM accessor layouts still rely on validation and the existing recognizer. It is not complete drawing coverage.

Caches are bounded to 1,024 cells per port, eight ports and eight bitmap saves. A ROM-page filter limits interception work to relevant instruction pages; capture is disabled with Sharp Text off. Android snapshots the LCD and retained packets together under the CPU lock; iOS reads both on its engine queue. No ROM patches or calculator register/RAM modifications are made. The fonts and original calculator framebuffer are unchanged.

The retained run covers **24 screens** (including inverted tall math and the Catalog conversion triangle): all match capture-off LCD bytes. Cursor, inversion, clearing and state restoration checks pass. The italic e is retained in editor, pretty-print and Catalog; derivative d is retained in pretty-print. The Android/Swift merge results match on all 24 captured frames. Compact evidence is in `retained-results.json`; full private fixtures remain in ignored build output.

```sh
python3 tools/drawing-trace/merge-parity.py build/drawing-trace/retained-run build/sharp-text-test/fonts.bin
```

Fraction rules and other mathematical shapes still mix text with line/pixel operations. The existing HD shape recognizer remains their fallback. It now uses retained character positions as additional context and validates tall parentheses in either polarity. A real 25-row integral and paired parentheses are checked in normal/inverted selections. Integral and left/right parenthesis geometry is now captured before clipping from three verified internal pretty-print instruction sequences. These are located by instruction fingerprints rather than fixed addresses, and enabled only when all three matches are unique and agree on the window global. The layout record supplies full symbol height; window state supplies origin and clip bounds. Unknown ROM layouts keep the existing pixel fallback. Physical-device performance has not been benchmarked for this layer.

SDK definitions used to verify signatures, attributes and call IDs:
[graph.h documentation](https://debrouxl.github.io/gcc4ti/graph.html),
[graph.h source](https://github.com/debrouxl/gcc4ti/blob/master/trunk/tigcc/include/C/graph.h),
[wingraph.h source](https://github.com/debrouxl/gcc4ti/blob/master/trunk/tigcc/include/C/wingraph.h),
[estack.h source](https://github.com/debrouxl/gcc4ti/blob/master/trunk/tigcc/include/C/estack.h).

### Clipped expression regression

The new nested-fraction integral exceeds the Home viewport. Both normal and selected/inverted snapshots must retain the integral and parentheses with original full height and clipped bounds. A raised `1` crossing the top edge is also checked. The host harness verifies that changing hidden pixels does not invalidate the integral, inverting its visible pixels changes polarity, and clearing those visible pixels invalidates it. Original LCD snapshots remain identical with capture on/off. Native packets now contain 12 integers: x, y, font (3 for a shape), ROM code, polarity, width, height, attribute, and left/top/right/bottom clip bounds (exclusive). Bitmap save/restore carries clipped identities and their bounds.

The retained host run also installs a diagnostic-only observer that validates frames at 20 intermediate cap-drawing calls. Pending geometry is kept until the three shape routines reach their verified common continuation; unfinished, non-matching shapes are never exported. This prevents a host frame between stem and cap operations from permanently deleting the symbol. No timing delay or calculator execution change is introduced.

Home editor cursor (Android build 1153): capture the verified two-column, eight-row XOR rectangle call in the medium-font Home input line. A cursor packet (font 4) carries its position and the rows already toggled. Native validation and both recognizers remove those XOR pixels from a host copy before comparing glyphs, including snapshots partway through a blink. This avoids invalidating a neighboring glyph when the cursor overlaps its ink. Both HD renderers restore that original text and draw a centered 0.6-LCD-pixel cursor, preserving the calculator's position and blink timing. Original Display keeps the native cursor. No guest framebuffer or font outline is changed. Actual-ROM checks cover end/middle cursor positions and both blink phases across 40 frames, plus 64 validations during row-by-row cursor redraw; Android/iOS merge parity covers 67 frames.
