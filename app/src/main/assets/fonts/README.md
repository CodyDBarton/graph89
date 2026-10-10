# Approved Graph89 HD font

`Graph89HD.ttf` contains the approved v8 ASCII comparison face and the 45 approved special-character designs, based on TI92Pluspc (`Ti-92p.ttf`, from WordRider 0.8 resources). It preserves the accepted dotted zero and edits to 1, 3, A, i, j, l, and t. Original descender outlines and the original seven are retained.

The embedded original Monotype copyright, trademark, and license records are retained. This font is a separate licensed asset, not covered by the emulator source code’s GPL. This project and its APK are for the owner's personal use.

The reproducible adjustment script is `android/sharp-text/build-font.py`; it requires Python fontTools and the original `Ti-92p.ttf`. It does not modify the input font.

The approved specials are recorded in `android/sharp-text/approved-specials.json`. Each calculator code maps to a private-use character U+E100 plus that code, avoiding the legacy font's Windows character encoding. Infinity is symmetric; imaginary i has the approved upright stem, wider dot, and curved foot. Gamma, gamma, delta, alpha, and lambda use Times New Roman outlines from the Mac's installed fonts, with the approved lambda slope and flourishes. The Times source copyright is retained alongside the original font copyright. These are separate licensed font assets for the owner's personal project.

To reproduce the integrated face, first run `build-font.py` against `Ti-92p.ttf` to produce the approved v8 base, then run `android/sharp-text/build-special-font.py BASE_TTF OUTPUT_TTF`. The latter uses the approved manifest and the installed `/System/Library/Fonts/Supplemental/Times New Roman*.ttf` sources; it requires fontTools. Existing ASCII outlines/advances and all approved special outlines/advances are checked against their approved versions during integration.

Build 1150 adds the approved derivative d mapping (ROM code 188 → U+E1BC → existing `uniE008` outline). Earlier outlines and metrics are unchanged. The approved dropdown arrow is drawn as a triangle by the renderer within its original three-by-two pixel footprint; it is not a font glyph.

The approved Catalog right-pointing triangle (ROM character 18) is also drawn directly as a vector path using its native ink bounds. It is separate from the shafted arrow (code 22) and does not add or alter any TTF glyph.

Inverse trig raised −1 (Android build 1152): ROM character 180 now uses the approved size-specific composition of the existing minus and numeral 1. The three new font outlines use 200 units per LCD pixel and a baseline at y=10; both renderers use the same fixed transform, preserving the approved preview in normal and inverted text. Reproduce these additions with `android/sharp-text/build-inverse-trig-font.py INPUT_TTF OUTPUT_TTF` after the other approved font integration steps. Earlier outlines and advances remain unchanged.
