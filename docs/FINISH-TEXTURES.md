# Finish textures

The textures the finishes are made of (Settings › Appearance › Theme › Finish). Every one is a CC0 photograph: none needs a credit on screen, and they are listed here, and in the app under **Texture credits** in the Finish section, with thanks. The list the app reads is `assets/finish/credits.json`; a test checks that every bundled texture has an entry, that each is CC0 from Poly Haven or ambientCG, and that the set stays under 5 MB.

The photographs are from [Poly Haven](https://polyhaven.com) and [ambientCG](https://ambientcg.com) (both CC0; ambientCG's materials are made by Lennart Demes). Glass has no photograph of its own: its wall is drawn from the theme's colours, and its frost is the Plastic grain at a finer scale.

| File | Texture | Author | Licence | Source | Used for |
|---|---|---|---|---|---|
| `brick.jpg` | Red Brick 03 | Rob Tuytel | CC0 | https://polyhaven.com/a/red_brick_03 | Bricks: a calm, evenly lit wall of red brick in running bond. Grey detail tile, 1024 px. |
| `plaster.jpg` | White Plaster 02 | Rob Tuytel | CC0 | https://polyhaven.com/a/white_plaster_02 | Brick panels: painted plaster for the signboards. Grey detail tile, 512 px. |
| `hull.jpg` | Blue Metal Plate | Rob Tuytel | CC0 | https://polyhaven.com/a/blue_metal_plate | Bridge console wall: steel hull plates. Grey detail tile, 1024 px. |
| `steel.jpg` | Metal 009 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Metal009 | Bridge console plates: brushed steel. Grey detail tile, 1024 px. |
| `knit.jpg` | Knitted Fleece | colormass, Rico Cilliers | CC0 | https://polyhaven.com/a/knitted_fleece | Cashmere: a fine knit. Grey detail tile from the 2K photograph, 1024 px. |
| `denim.jpg` | Denim Fabric 03 | colormass, Rico Cilliers | CC0 | https://polyhaven.com/a/denim_fabric_03 | Denim: twill weave. Grey detail tile from the 2K photograph, 1024 px. |
| `leather.jpg` | Leather 037 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Leather037 | Leather: the embossed grain, lit from the top left from the material’s normal map. Grey detail tile, 1024 px. |
| `walnut.jpg` | Wood 051 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Wood051 | Walnut: espresso hardwood, straight cathedral grain running across, no knots. Grey detail tile, 1024 px. |
| `oak.jpg` | Wood 049 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Wood049 | Oak: plain, straight open grain running across, no knots or plank gaps. Grey detail tile, 1024 px. |
| `marble.jpg` | Marble 014 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Marble014 | Marble: a polished slab with gentle veining, its fine mottling quietened so the veins lead. Grey detail tile, 1024 px. |
| `carbon.jpg` | Fabric 004 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Fabric004 | Carbon fibre: a 2 x 2 twill weave. Grey detail tile, 1024 px. |
| `paper.jpg` | Paper 001 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Paper001 | Papery: the fine tooth of white paper. Grey detail tile, 1024 x 600 px. |
| `plastic.jpg` | Plastic 004 | Lennart Demes (ambientCG) | CC0 | https://ambientcg.com/a/Plastic004 | Plastic: a moulded, pebbled surface, lit from the top left from the material’s normal map; at a finer scale the frost on Glass. Grey detail tile, 1024 px. |

## How the files are made

Each file is a **grey detail tile**: the photograph's brightness only, with lighting that varies across the photograph (a hotspot, a vignette) taken out by a wrap-around high pass, so the tile repeats with no seam or bright patch, then centred on mid grey (128). At paint time the app lays it over the theme's own colour once, as a new image, and keeps it: brighter than mid grey lifts the colour toward white by up to the finish's budget, darker sinks it toward black by up to its budget (the budgets `FinishLook` checks text against, see `lib/shared/finish.dart`). So one grey tile serves every theme, built-in or custom, and the photograph never decides the colours.

For Leather and Plastic the tile is made from the material's normal map (`_NormalGL.jpg`) instead of its colour: their colour maps are almost flat, and their grain is in the relief, which the script lights from the top left. Marble's fine mottling is quietened (`--quiet`), so the veins lead and the slab is calm under text.

`tool/finish_textures/prep.py` makes a tile from a downloaded map (Poly Haven 1K or 2K diffuse; ambientCG 1K-JPG `_Color.jpg` or `_NormalGL.jpg`):

```
python3 tool/finish_textures/prep.py red_brick_03_diff_1k.jpg assets/finish/brick.jpg 1024 --hp .25 --quality 80
python3 tool/finish_textures/prep.py white_plaster_02_diff_1k.jpg assets/finish/plaster.jpg 512 --hp .06 --quality 82
python3 tool/finish_textures/prep.py blue_metal_plate_diff_1k.jpg assets/finish/hull.jpg 1024 --hp .05 --quality 78
python3 tool/finish_textures/prep.py Metal009_1K-JPG_Color.jpg assets/finish/steel.jpg 1024 --hp .1 --quality 80
python3 tool/finish_textures/prep.py knitted_fleece_diff_2k.jpg assets/finish/knit.jpg 1024 --hp .1 --quality 78
python3 tool/finish_textures/prep.py denim_fabric_03_diff_2k.jpg assets/finish/denim.jpg 1024 --hp .1 --quality 78
python3 tool/finish_textures/prep.py Leather037_1K-JPG_NormalGL.jpg assets/finish/leather.jpg 1024 --normal --hp .1 --quality 80
python3 tool/finish_textures/prep.py Wood051_1K-JPG_Color.jpg assets/finish/walnut.jpg 1024 --hp .2 --quality 80
python3 tool/finish_textures/prep.py Wood049_1K-JPG_Color.jpg assets/finish/oak.jpg 1024 --hp .2 --quality 80
python3 tool/finish_textures/prep.py Marble014_1K-JPG_Color.jpg assets/finish/marble.jpg 1024 --hp .2 --quiet 2.2 --clip .2 --quality 82
python3 tool/finish_textures/prep.py Fabric004_1K-JPG_Color.jpg assets/finish/carbon.jpg 1024 --hp .2 --quality 80
python3 tool/finish_textures/prep.py Paper001_1K-JPG_Color.jpg assets/finish/paper.jpg 1024 --hp .15 --quality 80
python3 tool/finish_textures/prep.py Plastic004_1K-JPG_NormalGL.jpg assets/finish/plastic.jpg 1024 --normal --hp .1 --quality 80
```

To add a texture: a grey tile made as above, at most 1024 px and 700 KB, at `assets/finish/<name>.jpg`, an entry in `credits.json` and in the table above, and its name in `finishMaterials` in `lib/shared/finish_paint.dart`. Only CC0.

## How a surface is drawn

Everything a finish draws is made once as an image (a tinted tile, the shadow and edge of each corner size, a screw head, a stitch, a gradient as a strip of pixels) and kept; each surface records a few draws of those images into its own layer, once. The GPU still draws every layer on every frame (a scroll, a page sliding in; Impeller keeps no raster cache), so a surface covers as little as it can:

- **Under the content** a panel draws its shadow and its material. The shadow is a nine-patch drawn as its border only (its middle is under the panel), and the material covers the panel once; only brushed steel's sheen and a glass pane's frost lie over the whole of it again. Plastic's gloss covers only the band along its top and its shade the band along its foot.
- **Over the content** it draws the content's edge fading into the panel's own material over 6 px, the corners of the content's cut covered by that material, and then the edge itself (the wood lip, the marble chamfer, the plastic rim, the steel bevel and screws, the seam and its stitches), as a nine-patch border with no middle. The content is cut off along a plain rectangle a little inside the edge (`finishEdgeInset`), the cheapest clip there is, so nothing it draws is ever across the edge or past it.
- Tiles are made at the size they are shown, but never larger than the photograph they come from, so a phone or a 4K monitor does not hold four times the memory for the same detail.

`test/shared/finish_performance_test.dart` holds that nothing is drawn again on a tick or a scroll; `test/shared/finish_cost_test.dart` holds what each frame covers and how much memory the images take, and prints what each page costs with `FINISH_COST=1`.
