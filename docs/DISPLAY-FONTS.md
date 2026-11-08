# Display fonts

| Name | Stable ID | Availability |
|---|---|---|
| I-Proton Matrix | `i-proton_matrix` | Original bitmap font, unchanged |
| I-Proton Sq-Matrix | `i-proton_sq_matrix` | Original square-pixel bitmap font, unchanged |
| Tinos | `tinos` | Four bundled Android faces; no import required |

Both Matrix glyph tables, JSON font assets, scaling, weight and italic behavior are unchanged. Countdown digits continue to use I-Proton Matrix at 14 pixels. Square/circular LED appearance changes only cell painting, not the 512-bit display frame.

## Bundled Tinos

Regular, Bold, Italic and Bold Italic version 1.340 ship unchanged in `android/app/src/main/assets/display_fonts/tinos`. The `sources.json` manifest records official Google Fonts URLs and SHA-256 hashes. `OFL.txt` contains the Tinos project copyright and SIL Open Font License 1.1; the same license is registered in About → Open-source licenses.

Android `BundledFonts.kt` loads the appropriate face from APK assets. It draws the whole string using Android Canvas with antialiasing and subpixel rendering off, fitting actual ink to 7 or 14 rows. It preserves advances and italic overhang rather than resizing a rendered image. The Dart side caches style-specific rasters, clips/aligns them into 32 × 16 and scrolls long text. Bold and italic use their real bundled faces, without synthetic bold/skew. Static and flashing text must fit within 32 pixels.

14 pixels is recommended for serif detail. The earlier approved desktop preview used these same Tinos faces with a desktop rasterizer; Android hinting may differ slightly. Android device inspection remains necessary after building the APK.

Legacy `times_new_roman` selections migrate to `tinos`, keeping text, height, formatting, alignment, speed and effect. No Times New Roman bytes are bundled or read from another app. The old font-import UI, picker bridge and private-file loader are removed. Existing imported files are ignored. Retired `service_serif` and `clear_sans` selections still migrate to the unchanged I-Proton Matrix face.

## LedArt-Lite evidence

The inspected base APK SHA-256 was `4f36553aac8a221726e4d9e20a232133f4547d9fb53c87658677e6c3ac95f6ae`. Static inspection found a private downloaded font library, native Typeface loading, antialiasing disabled and fitting to actual raster ink. Church Service Timer independently implements the general phone-rendered bitmap approach. No vendor source or fonts were copied; pixel-identical vendor rendering has not been established.
