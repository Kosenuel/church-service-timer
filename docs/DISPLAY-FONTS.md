# Display font assets

| Name | Stable ID | Source |
|---|---|---|
| Cuekeeper Matrix | `cuekeeper_matrix` | Original Cuekeeper pixel glyphs, preserved unchanged |
| Service Serif | `service_serif` | Pixel derivatives of Liberation Serif 2.1.5 |
| Clear Sans | `clear_sans` | Pixel derivatives of Liberation Sans 2.1.5 |

Cuekeeper Matrix is saved in `assets/pixel_fonts/cuekeeper_matrix.json` and `lib/matrix_font.dart`. The JSON includes its name, version and seven-row glyph maps. Its bold and italic transformations and 14-pixel vertical scaling preserve the prototype's original rendering. Countdown digits always use this font.

The alternatives are saved in `assets/pixel_fonts/alternate_fonts.json` and generated `lib/font_atlas.dart`. Each has separate regular, bold, italic and bold italic maps at seven and fourteen rows. Validation and rendering use the same maps, so preview width and clipping rules match. All fonts cover the same explicit 80-glyph set; unsupported characters are rejected rather than substituted.

Service Serif is a Times-style alternative, not Microsoft's Times New Roman. No Windows font files are redistributed. The alternatives derive from the official [Liberation Fonts project](https://github.com/liberationfonts/liberation-fonts), release [2.1.5](https://github.com/liberationfonts/liberation-fonts/releases/tag/2.1.5), under the SIL Open Font License. The full copyright and license notice is in `assets/pixel_fonts/OFL-Liberation.txt` and is available through the app's font and software licenses screen. Derivative display fonts have new names.

## Regenerate the alternatives

Download and extract the official [2.1.5 TTF archive](https://github.com/liberationfonts/liberation-fonts/files/7261482/liberation-fonts-ttf-2.1.5.tar.gz). Its SHA-256 is `7191c669bf38899f73a2094ed00f7b800553364f90e2637010a69c0e268f25d0`.

With Python and Pillow 12.3.0, run from the repository:

```sh
python scripts/build-font-atlas.py --source /path/to/liberation-fonts-ttf-2.1.5
dart format lib/font_atlas.dart
flutter test
```

The generator preserves a common baseline, trims horizontal blank columns and converts scaled grayscale glyphs into one-bit maps with a fixed threshold. It does not alter Cuekeeper Matrix. Seven-pixel serifs inevitably lose detail; fourteen pixels is recommended for the serif face. Physical display tests are still required before claiming readability at a given distance.
