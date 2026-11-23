# Finish textures

The textures the finishes are made of (Settings › Appearance › Theme › Finish). Every one is CC0: none needs a credit on screen, and they are listed here, and in the app under **Texture credits** in the Finish section, with thanks. The list the app reads is `assets/finish/credits.json`; a test checks that every bundled texture has an entry, that each is CC0, and that the set stays under 4 MB.

The photographs are from [Poly Haven](https://polyhaven.com) (CC0). Poly Haven has no plain veined marble slab, paper or carbon fibre, and ambientCG (also CC0), which has them, could not be downloaded from where this was built (its download host was blocked), so those four, and the fine grain of frosted glass, were drawn for the app with the script below and are CC0 too.

| File | Texture | Author | Licence | Source | Used for |
|---|---|---|---|---|---|
| `brick.jpg` | Red Brick 03 | Rob Tuytel | CC0 | https://polyhaven.com/a/red_brick_03 | Bricks: a calm, evenly lit wall of red brick in running bond. Grey detail tile, 1024 px. |
| `plaster.jpg` | White Plaster 02 | Rob Tuytel | CC0 | https://polyhaven.com/a/white_plaster_02 | Brick panels: painted plaster for the signboards. Grey detail tile, 512 px. |
| `hull.jpg` | Blue Metal Plate | Rob Tuytel | CC0 | https://polyhaven.com/a/blue_metal_plate | Bridge console wall: steel hull plates. Grey detail tile, 1024 px. |
| `steel.jpg` | Grey Plaster | Rob Tuytel | CC0 | https://polyhaven.com/a/grey_plaster | Bridge console plates: the fine grain of this photograph drawn out sideways into brushed steel. Grey detail tile, 1024 px. |
| `knit.jpg` | Knitted Fleece | colormass, Rico Cilliers | CC0 | https://polyhaven.com/a/knitted_fleece | Cashmere: a fine knit. Grey detail tile from the 2K photograph, 1024 px. |
| `denim.jpg` | Denim Fabric 03 | colormass, Rico Cilliers | CC0 | https://polyhaven.com/a/denim_fabric_03 | Denim: twill weave. Grey detail tile from the 2K photograph, 1024 px. |
| `leather.jpg` | Brown Leather | Rob Tuytel | CC0 | https://polyhaven.com/a/brown_leather | Leather: pebbled hide. Grey detail tile from the 2K photograph, 1024 px. |
| `walnut.jpg` | Wood Table 001 | Dimitrios Savva, Rico Cilliers | CC0 | https://polyhaven.com/a/wood_table_001 | Walnut: close, straight grain, turned to run across. Grey detail tile, 1024 px. |
| `oak.jpg` | Oak Wood Planks | Dimitrios Savva | CC0 | https://polyhaven.com/a/oak_wood_planks | Oak: open grain running across. Grey detail tile, 1024 px. |
| `marble.jpg` | Veined marble | Church Service Timer | CC0 | Made for this app (docs/FINISH-TEXTURES.md) | Marble: veining drawn from filtered noise for this app (Poly Haven has no plain veined slab). Grey detail tile, 1024 px. |
| `carbon.jpg` | Carbon weave | Church Service Timer | CC0 | Made for this app (docs/FINISH-TEXTURES.md) | Carbon fibre: a 2 x 2 twill of flat tows drawn for this app (neither library has one). Grey detail tile, 512 px. |
| `paper.jpg` | Paper tooth | Church Service Timer | CC0 | Made for this app (docs/FINISH-TEXTURES.md) | Papery: fine tooth and fibres drawn for this app (neither library has a plain paper). Grey detail tile, 512 px. |
| `frost.jpg` | Frost grain | Church Service Timer | CC0 | Made for this app (docs/FINISH-TEXTURES.md) | Glass: the fine grain of frosted glass, drawn for this app. Grey detail tile, 256 px. |

## How the files are made

Each file is a **grey detail tile**: the photograph's brightness only, with lighting that varies across the photograph (a hotspot, a vignette) taken out by a wrap-around high pass, so the tile repeats with no seam or bright patch, then centred on mid grey (128). At paint time the app lays it over the theme's own colour once, as a new image, and keeps it: brighter than mid grey lifts the colour toward white by up to the finish's budget, darker sinks it toward black by up to its budget (the budgets `FinishLook` checks text against, see `lib/shared/finish.dart`). So one grey tile serves every theme, built-in or custom, and the photograph never decides the colours.

`tool/finish_textures/prep.py` makes a tile from a Poly Haven colour map (1K, or 2K for the cloth and leather, whose weave is fine), and `tool/finish_textures/gen.py` makes the four drawn ones:

```
python3 tool/finish_textures/prep.py red_brick_03_diff_1k.jpg assets/finish/brick.jpg 1024 --hp .25 --quality 80
python3 tool/finish_textures/prep.py white_plaster_02_diff_1k.jpg assets/finish/plaster.jpg 512 --hp .06 --quality 82
python3 tool/finish_textures/prep.py blue_metal_plate_diff_1k.jpg assets/finish/hull.jpg 1024 --hp .05 --quality 78
python3 tool/finish_textures/prep.py grey_plaster_diff_1k.jpg fine.jpg 1024 --hp .01 --soft 0
python3 tool/finish_textures/prep.py fine.jpg assets/finish/steel.jpg 1024 --hblur 45 --hp .08 --quality 80
python3 tool/finish_textures/prep.py knitted_fleece_diff_2k.jpg assets/finish/knit.jpg 1024 --hp .1 --quality 78
python3 tool/finish_textures/prep.py denim_fabric_03_diff_2k.jpg assets/finish/denim.jpg 1024 --hp .1 --quality 78
python3 tool/finish_textures/prep.py brown_leather_diff_2k.jpg assets/finish/leather.jpg 1024 --hp .1 --quality 78
python3 tool/finish_textures/prep.py wood_table_001_diff_1k.jpg assets/finish/walnut.jpg 1024 --hp .2 --rot --quality 80
python3 tool/finish_textures/prep.py oak_wood_planks_diff_1k.jpg assets/finish/oak.jpg 1024 --hp .2 --quality 80
python3 tool/finish_textures/gen.py marble assets/finish/marble.jpg
python3 tool/finish_textures/gen.py carbon assets/finish/carbon.jpg
python3 tool/finish_textures/gen.py paper assets/finish/paper.jpg
python3 tool/finish_textures/gen.py frost assets/finish/frost.jpg
```

Brushed steel is the fine grain of the Grey Plaster photograph drawn out sideways (a long horizontal blur), which is how brushed metal looks: fine streaks all one way. Walnut's grain is turned a quarter so it runs across, like the oak.

To add a texture: a grey tile made as above, at most 1024 px and 700 KB, at `assets/finish/<name>.jpg`, an entry in `credits.json` and in the table above, and its name in `finishMaterials` in `lib/shared/finish_paint.dart`. Only CC0.
