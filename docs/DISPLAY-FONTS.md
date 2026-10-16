# Display fonts and LED shapes

| Name | Stable ID | Availability |
|---|---|---|
| Cuekeeper Matrix | `cuekeeper_matrix` | Original built-in font, unchanged |
| Cuekeeper Sq-Matrix | `cuekeeper_sq_matrix` | New built-in companion for square cells |
| Times New Roman | `times_new_roman` | Import a properly licensed Regular TTF in Display |

Choose a font in any text composer. **Display → Simulator LED shape** switches between square and circular cells for Live and dialog previews. This device preference survives restart. Shape changes do not alter glyphs, formatting, timing or the 512-bit output frame. The default is square. Physical LED geometry remains unverified until the sign arrives.

## Cuekeeper fonts

Cuekeeper Matrix remains in `assets/pixel_fonts/cuekeeper_matrix.json` and `lib/matrix_font.dart`. Its 80 glyphs, bold/italic behavior and seven-/fourteen-row rendering are preserved. Countdown digits continue to use this font.

Cuekeeper Sq-Matrix is saved separately in `assets/pixel_fonts/cuekeeper_sq_matrix.json` and `lib/square_matrix_font.dart`. Its condensed letters, straight terminals, rectangular digits and simpler punctuation suit square cells. Compact mode uses seven rows; tall mode doubles both axes with integer pixels for balanced strokes. Tall Sq-Matrix is consequently wider than tall original Matrix; use scrolling for longer text. Both sizes support bold, italic, alignment, speed, scroll and flash, using the same 80-character repertoire.

The Dart Sq-Matrix table mirrors the JSON source; a test verifies they match. Edit both together. The original Matrix files must remain unchanged.

## Times New Roman

In **Display → Import Times New Roman font**, select a Regular `.ttf` licensed for use on this Android device. The picker copies it into private app storage after bounded metadata checks and successful rasterization. It rejects other families, renamed unrelated files, bold/italic source faces, font collections, variable fonts and files over 4 MiB. A rejected replacement preserves the previous working import. Import/replacement is disabled during an active service.

Whole strings render using Android Paint/Canvas at integer sizes, antialiasing off and actual ink bounds. Text fits seven or fourteen rows without resampling. Bold and italic use native synthetic styling; italic overhang is included. Fourteen rows is recommended for the serif face. Raster results are cached locally; text and formatting remain portable, font bytes do not.

Missing Times New Roman is reported explicitly; no substitute is used. If restored data requires a missing font, output is held and saved data is preserved: import the font again to recover it. Service Serif and Clear Sans are removed. Existing selections of those retired fonts migrate to Cuekeeper Matrix while retaining other formatting.

## LedArt-Lite evidence

The supplied base APK SHA-256 was `4f36553aac8a221726e4d9e20a232133f4547d9fb53c87658677e6c3ac95f6ae`. Its complete font inventory did not include Times New Roman. Static inspection found a private downloaded font library, native Typeface loading, antialiasing disabled, synthetic bold/italic when needed, and fitting based on actual raster ink bounds. Cuekeeper independently implements that general native approach. The exact Times font on the user's phone and pixel-identical output were not established. No vendor code or font was copied.

Microsoft's [font redistribution FAQ](https://learn.microsoft.com/en-us/typography/fonts/font-faq) does not grant app redistribution rights for Windows fonts, including converted bitmap fonts. The [Times New Roman family page](https://learn.microsoft.com/en-us/typography/font-list/times-new-roman) links to licensing information. This APK/repository contains no Times font bytes or proprietary bitmap atlas; a bundled edition would require redistribution rights.

Actual Android rendering and distant physical readability still need device/sign checks. Tests with fake rasters verify application behavior, not the appearance of a genuine imported face.
