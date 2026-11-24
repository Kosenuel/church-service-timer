import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/finish.dart';

/// What each finish is made of: the photographed texture of its wall and of
/// its panels (grey detail tiles in assets/finish, see
/// docs/FINISH-TEXTURES.md), and how many logical pixels one repeat of each
/// covers. Glass and Plastic have no photograph for their wall: Glass is
/// lit by soft fields of colour and Plastic is moulded.
class FinishMaterial {
  final String? wall, panel;
  final double wallTile, panelTile;
  const FinishMaterial({
    this.wall,
    this.wallTile = 512,
    this.panel,
    this.panelTile = 512,
  });
}

const finishMaterials = <String, FinishMaterial>{
  'glass': FinishMaterial(panel: 'plastic', panelTile: 240),
  'papery': FinishMaterial(
    wall: 'paper',
    wallTile: 720,
    panel: 'paper',
    panelTile: 560,
  ),
  'console': FinishMaterial(
    wall: 'hull',
    wallTile: 760,
    panel: 'steel',
    panelTile: 560,
  ),
  'brick': FinishMaterial(
    wall: 'brick',
    wallTile: 520,
    panel: 'plaster',
    panelTile: 420,
  ),
  'cashmere': FinishMaterial(
    wall: 'knit',
    wallTile: 820,
    panel: 'knit',
    panelTile: 470,
  ),
  'denim': FinishMaterial(
    wall: 'denim',
    wallTile: 640,
    panel: 'denim',
    panelTile: 560,
  ),
  'plastic': FinishMaterial(
    wall: 'plastic',
    wallTile: 620,
    panel: 'plastic',
    panelTile: 520,
  ),
  'walnut': FinishMaterial(
    wall: 'walnut',
    wallTile: 900,
    panel: 'walnut',
    panelTile: 760,
  ),
  'oak': FinishMaterial(
    wall: 'oak',
    wallTile: 1000,
    panel: 'oak',
    panelTile: 820,
  ),
  'leather': FinishMaterial(
    wall: 'leather',
    wallTile: 620,
    panel: 'leather',
    panelTile: 520,
  ),
  'marble': FinishMaterial(
    wall: 'marble',
    wallTile: 980,
    panel: 'marble',
    panelTile: 720,
  ),
  'carbon': FinishMaterial(
    wall: 'carbon',
    wallTile: 340,
    panel: 'carbon',
    panelTile: 290,
  ),
};

/// Every texture the app bundles, by name (`assets/finish/<name>.jpg`).
final finishTextureNames = {
  for (final m in finishMaterials.values) ...[?m.wall, ?m.panel],
};

/// The finishes whose panels are stitched: a running stitch inside the edge.
const stitchedFinishes = {'denim', 'leather'};

/// How far inside a stitched panel's edge its content starts: clear of the
/// thread (at [_seamAt]) and of its shadow, so nothing is ever drawn across
/// the stitches.
const finishSeamInset = 9.0;
const _seamAt = 5.5;

/// Where a stitched panel's content box starts: its own margin, which is
/// empty, may reach under the seam, but nothing it draws is shown there.
const finishContentInset = 4.0;

/// How far inside a panel's edge its content is cut off: clear of the
/// finish's edge detail (a wood lip, a marble chamfer, a plastic rim, a
/// steel bevel, a seam), which is drawn over the content, so a row or a
/// picture never runs across it. Content that scrolls toward it fades out
/// under the edge over [finishFade] instead of being sliced. Each is far
/// enough in that the corner of the cut (a plain rectangle, the cheapest
/// clip there is) is still on the panel: the rounded part of the corner is
/// covered by the panel's own material, drawn over the content.
double finishEdgeInset(String id) => switch (id) {
  'denim' || 'leather' => finishSeamInset,
  'plastic' => 8,
  'cashmere' => 7,
  'glass' || 'walnut' || 'oak' => 6,
  'marble' || 'console' || 'brick' => 4,
  'papery' || 'carbon' => 3,
  _ => 0,
};

/// Where a panel's content box starts, inside its edge: only a stitched
/// panel's content is moved in (see [finishContentInset]); every other
/// panel keeps the room it always had and is only cut off at its edge.
double finishContentPadding(String id) =>
    stitchedFinishes.contains(id) ? finishContentInset : 0;

/// How far content fades out under a panel's edge.
const finishFade = 6.0;

/// How many times the material has been drawn, for tests: once per surface
/// when it first shows, and never again for a tick of the clock or a scroll.
class FinishPaintCount {
  static int walls = 0, panels = 0, seams = 0;
  static int get total => walls + panels + seams;

  /// How many images the finish has made (tinted tiles, edges, shadows),
  /// and their size in bytes: each is recorded and rasterised when it is
  /// first needed, which is work a frame pays for.
  static int images = 0, imageBytes = 0;
}

ui.Image _made(ui.Image image) {
  FinishPaintCount.images++;
  FinishPaintCount.imageBytes += image.width * image.height * 4;
  return image;
}

/// The photographs, decoded once and kept. A finish draws its plain colours
/// until its photographs arrive (a few milliseconds after it is first
/// chosen), then draws them once.
class FinishTextures extends ChangeNotifier {
  FinishTextures._();
  static final instance = FinishTextures._();

  final _images = <String, ui.Image>{};
  final _pending = <String, Future<void>>{};
  final _failed = <String>{};

  /// [name] decoded, or null while it loads (asking for it starts it).
  ui.Image? image(String name) {
    final image = _images[name];
    if (image == null) load(name);
    return image;
  }

  Future<void> load(String name) {
    if (_images.containsKey(name) || _failed.contains(name)) {
      return Future.value();
    }
    return _pending[name] ??= _decode(name);
  }

  Future<void> _decode(String name) async {
    try {
      final data = await rootBundle.load('assets/finish/$name.jpg');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      _images[name] = frame.image;
    } catch (error) {
      // Drawn in its plain colours instead.
      _failed.add(name);
      debugPrint('Finish texture $name did not load: $error');
    } finally {
      _pending.remove(name);
    }
    notifyListeners();
  }

  /// The photographs of [finish], so it shows complete from its first frame.
  Future<void> loadFor(String finish) {
    final m = finishMaterials[finish];
    if (m == null) return Future.value();
    return Future.wait([?m.wall, ?m.panel].map(load));
  }

  Future<void> loadAll() => Future.wait(finishTextureNames.map(load));
}

/// A grey detail tile laid over [base] (or over nothing when null): above
/// mid grey goes toward white by up to [light], below it toward black by up
/// to [dark], the budgets [FinishLook] checks text against. Drawn once into
/// a new image, so a frame only samples it.
ui.Image _tint(
  ui.Image grey,
  Color? base,
  double light,
  double dark,
  int width,
) {
  final height = math.max(1, (width * grey.height / grey.width).round());
  final w = width.toDouble(), h = height.toDouble();
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  if (base != null) c.drawColor(base, BlendMode.src);
  final src = Rect.fromLTWH(
    0,
    0,
    grey.width.toDouble(),
    grey.height.toDouble(),
  );
  final dst = Rect.fromLTWH(0, 0, w, h);
  // A colour matrix works on 0..255; alpha is k × (grey − 128), clamped at
  // nothing, so only one of the two layers marks any pixel.
  // A little inside the budget, for the rounding of 8-bit colour.
  final kl = light * .97 * 255 / 127, kd = dark * .97 * 255 / 127;
  if (light > 0) {
    c.drawImageRect(
      grey,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.matrix([
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 255,
          0, 0, 0, 0, 255,
          kl, 0, 0, 0, -128 * kl,
        ]),
    );
  }
  if (dark > 0) {
    c.drawImageRect(
      grey,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.matrix([
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0,
          0, 0, 0, 0, 0,
          -kd, 0, 0, 0, 128 * kd,
        ]),
    );
  }
  return _made(recorder.endRecording().toImageSync(width, height));
}

ui.Image _record(int w, int h, void Function(Canvas c) draw) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));
  return _made(
    recorder.endRecording().toImageSync(math.max(1, w), math.max(1, h)),
  );
}

Color _toward(Color c, Color to, double t) => Color.lerp(c, to, t.clamp(0, 1))!;

/// How round a finish's panels are.
double finishRadius(String id) => switch (id) {
  'glass' => 18,
  'papery' => 4,
  'console' => 5,
  'brick' => 4,
  'cashmere' => 22,
  'denim' => 12,
  'plastic' => 24,
  'walnut' || 'oak' => 10,
  'leather' => 14,
  'marble' => 10,
  'carbon' => 8,
  _ => 14,
};

/// Everything a finish draws, made once for one look at one pixel ratio:
/// tinted tiles, the pre-blurred shadow and the edge of each corner size,
/// screw heads and the stitch. A surface then draws only images.
class _Art {
  final FinishLook look;
  final double dpr;
  _Art(this.look, this.dpr);

  static final _cache = Expando<Map<double, _Art>>();
  static _Art of(FinishLook look, double dpr) =>
      (_cache[look] ??= {})[dpr] ??= _Art(look, dpr);

  FinishMaterial get material =>
      finishMaterials[look.id] ?? const FinishMaterial();

  Paint? _wall, _panel, _frame;
  bool _wallTried = false, _panelTried = false;

  /// A fill of [name] tinted over [base] at the given budget, repeating
  /// every [tile] logical pixels; null while the photograph loads.
  Paint? _fill(String? name, Color? base, double l, double d, double tile) {
    if (name == null) return null;
    final grey = FinishTextures.instance.image(name);
    if (grey == null) return null;
    // At the size it is shown, so a frame samples it one to one, but never
    // larger than the photograph: on a high-density screen (a phone, a 4K
    // monitor at 200%) a bigger tile would only be the same detail spread
    // out, at four times the memory; the GPU stretches it as it draws,
    // which costs it nothing.
    final px = (tile * dpr).round().clamp(16, math.max(16, grey.width)).toInt();
    final image = _tint(grey, base, l, d, px);
    final scale = tile / px;
    return Paint()
      ..shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.diagonal3Values(scale, scale, 1).storage,
        filterQuality: FilterQuality.low,
      );
  }

  /// How much of the panel's budget its texture takes: the rest is left for
  /// the sheen of brushed steel and the brightness of a pane.
  (double, double) get _panelShare => switch (look.id) {
    'glass' => (.3, .4),
    'console' => (.5, .6),
    'carbon' => (.7, .7),
    'plastic' => (.4, .35),
    'brick' => (.6, .7),
    _ => (1, 1),
  };

  /// Whether every photograph this look draws has arrived.
  bool get complete {
    final m = material;
    for (final n in [?m.wall, ?m.panel]) {
      if (FinishTextures.instance.image(n) == null &&
          !FinishTextures.instance._failed.contains(n)) {
        return false;
      }
    }
    return true;
  }

  Paint? get wallFill {
    if (_wall == null && !_wallTried) {
      _wall = _fill(
        material.wall,
        // Plastic's moulded grain lies over its drawn table-top light.
        look.id == 'plastic' ? null : look.wall,
        look.wallLight,
        look.wallDark,
        material.wallTile,
      );
      _wallTried = _wall != null || material.wall == null;
    }
    return _wall;
  }

  Paint? get panelFill {
    if (_panel == null && !_panelTried) {
      final glass = look.id == 'glass';
      _panel = _fill(
        material.panel,
        // Glass's frost is laid over the pane, so it has no colour of its
        // own; the others are the panel colour with the texture in it.
        glass ? null : look.panel,
        look.panelLight * _panelShare.$1,
        look.panelDark * _panelShare.$2,
        material.panelTile,
      );
      _panelTried = _panel != null || material.panel == null;
    }
    return _panel;
  }

  /// The frame round a wooden panel: the desk's own wood, a little darker.
  Paint? get frameFill => _frame ??= _fill(
    material.wall,
    _toward(look.wall, Colors.black, .12),
    look.wallLight * .8,
    look.wallDark * .6,
    material.wallTile,
  );

  // Glass: the wall's fields of light, and a blurred, brightened copy of it
  // that panes show, each drawn once for a wall size.
  static const _glassScale = 8.0;
  final _glass = <String, (ui.Image wall, ui.Image pane)>{};

  (ui.Image, ui.Image) glass(Size wall) {
    final key = '${wall.width.round()}x${wall.height.round()}';
    final hit = _glass[key];
    if (hit != null) return hit;
    if (_glass.length > 3) _glass.clear();
    final w = (wall.width / _glassScale).ceil(),
        h = (wall.height / _glassScale).ceil();
    final big = math.max(w, h).toDouble();
    final fields = look.wallFields.isEmpty ? [look.wall] : look.wallFields;
    final bg = look.palette.background;
    final field = _record(w, h, (c) {
      c.drawColor(bg, BlendMode.src);
      // Large, soft fields of light: where they are brightest the wall is
      // the field's colour, within the budget text was checked on.
      final spots = [
        (Offset(w * .14, h * .12), big * .5, 0),
        (Offset(w * .9, h * .82), big * .46, 1),
        (Offset(w * .62, h * .2), big * .34, 2),
        (Offset(w * .3, h * .95), big * .36, 1),
      ];
      for (final (at, radius, i) in spots) {
        c.drawCircle(
          at,
          radius * .55,
          Paint()
            ..color = fields[i % fields.length]
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .45),
        );
      }
    });
    final pl = look.panelLight;
    final pane = _record(w, h, (c) {
      final area = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      c.saveLayer(
        area,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 2.6,
            sigmaY: 2.6,
            tileMode: TileMode.clamp,
          ),
      );
      c.drawImage(field, Offset.zero, Paint());
      c.restore();
      c.drawRect(
        area,
        Paint()..color = Colors.white.withValues(alpha: pl * .4),
      );
      c.drawRect(
        area,
        Paint()
          ..color = look.palette.surface.withValues(alpha: look.panelAlpha),
      );
    });
    return _glass[key] = (field, pane);
  }

  final _nines = <String, ui.Image>{};

  ui.Image _nine(String key, int size, void Function(Canvas c) draw) =>
      _nines[key] ??= _record(size, size, draw);

  /// A shadow under a panel with [corners], pre-blurred into a nine-patch:
  /// its middle stretches, so one small image serves every panel size.
  ({ui.Image image, Rect centre, double reach, double scale}) shadow(
    BorderRadius corners,
  ) {
    final l = look, s = l.panelScale;
    var blur = 4 + 10 * s, dy = 2 + 5 * s;
    var alpha = (l.light ? .14 : .32) * (.6 + .6 * s);
    switch (l.id) {
      case 'brick':
        alpha *= 1.6;
        blur *= .8;
        dy *= 1.3;
      case 'papery':
        blur = 3 + 3 * s;
        dy = 1 + 1.5 * s;
        alpha = (l.light ? .10 : .25) * (.6 + .6 * s);
      case 'cashmere':
        blur *= 1.6;
        alpha *= .8;
      case 'glass':
        blur *= 1.8;
        alpha *= .8;
      case 'console':
        blur *= .7;
    }
    final r = _maxRadius(corners);
    final reach = (blur + dy + 6).ceilToDouble();
    final core = r + 2;
    final size = ((reach + core) * 2).ceil();
    final image = _nine('shadow|$corners', size, (c) {
      final body = corners.toRRect(
        Rect.fromLTWH(reach, reach, core * 2, core * 2),
      );
      if (l.id == 'papery') {
        // The edge of a second sheet beneath.
        final under = body.shift(Offset(1.5 + 1.5 * s, 2.5 + 2 * s));
        c.drawRRect(
          under,
          Paint()..color = _toward(l.panel, l.palette.text, .05),
        );
        c.drawRRect(
          under.deflate(.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _toward(l.panel, l.palette.text, .2),
        );
      }
      if (l.id == 'plastic') {
        // A hard ledge under the shell, as a moulded edge.
        c.drawRRect(
          body.shift(Offset(0, 2 + 4 * s)),
          Paint()
            ..color = _toward(
              l.palette.background,
              Colors.black,
              l.light ? .2 : .45,
            ),
        );
      }
      c.drawRRect(
        body.shift(Offset(0, dy)),
        Paint()
          ..color = Colors.black.withValues(alpha: alpha.clamp(0, .6))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
      );
    });
    return (
      image: image,
      centre: Rect.fromLTWH(reach + core - 1, reach + core - 1, 2, 2),
      reach: reach,
      scale: 1,
    );
  }

  /// The edge of a panel: its rim, bevel and inner light, in a nine-patch
  /// drawn at the screen's pixel ratio.
  ({ui.Image image, Rect centre, double border}) rim(
    BorderRadius corners, {
    required bool strip,
  }) {
    final r = _maxRadius(corners);
    final border = math.max(r, 10.0) + 2;
    final logical = border * 2 + 4;
    final px = (logical * dpr).ceil();
    final image = _nine('rim|$corners|$strip', px, (c) {
      c.scale(dpr);
      final rr = corners.toRRect(Rect.fromLTWH(0, 0, logical, logical));
      _drawRim(c, rr, strip: strip);
    });
    return (
      image: image,
      centre: Rect.fromLTWH(border * dpr, border * dpr, 4 * dpr, 4 * dpr),
      border: border,
    );
  }

  void _drawRim(Canvas c, RRect rr, {required bool strip}) {
    final l = look, pl = l.panelLight, pd = l.panelDark;
    final area = rr.outerRect;
    Paint line(Color color, [double width = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    // Light from above: a lit top edge and a shaded foot.
    Paint bevel(double top, double foot, [double width = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = ui.Gradient.linear(
        area.topCenter,
        area.bottomCenter,
        [
          Colors.white.withValues(alpha: top),
          Colors.white.withValues(alpha: 0),
          Colors.black.withValues(alpha: 0),
          Colors.black.withValues(alpha: foot),
        ],
        const [0, .45, .55, 1],
      );
    switch (l.id) {
      case 'glass':
        // A bright edge where the light comes in at the top left, a faint
        // shade inside the opposite edge, and the pane's own thin rim.
        c.drawRRect(
          rr.deflate(.5),
          line(_toward(l.panel, l.palette.text, .22)),
        );
        c.drawRRect(
          rr.deflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..shader = ui.Gradient.linear(area.topLeft, area.bottomRight, [
              Colors.white.withValues(alpha: .55 * (.4 + pl * 2.5)),
              Colors.white.withValues(alpha: 0),
            ]),
        );
        c.save();
        c.clipRRect(rr);
        c.drawRRect(
          rr.inflate(3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = Colors.black.withValues(alpha: l.light ? .05 : .12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        c.restore();
      case 'console':
        // A machined plate: dark outline, a bright chamfer along the top, a
        // dark one at the foot.
        c.drawRRect(rr.deflate(.5), line(Colors.black.withValues(alpha: .55)));
        c.drawRRect(rr.deflate(1.6), bevel(.30 + pl, .35, 1.6));
        c.drawRRect(rr.deflate(3), line(Colors.black.withValues(alpha: .12)));
      case 'brick':
        // A painted signboard: a crisp edge, light along the top and a
        // shaded lower lip.
        c.drawRRect(rr.deflate(.5), line(_toward(l.panel, Colors.black, .4)));
        c.drawRRect(rr.deflate(1.7), bevel(.22, .22, 1.6));
      case 'cashmere':
        // Felt: no hard line, a soft light inside the top and shade at the
        // foot, as a padded edge.
        c.save();
        c.clipRRect(rr);
        c.drawRRect(
          rr.inflate(4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..shader = ui.Gradient.linear(
              area.topCenter,
              area.bottomCenter,
              [
                Colors.white.withValues(alpha: .10 + pl * .4),
                Colors.white.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: .10 + pd * .5),
              ],
              const [0, .4, .6, 1],
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        c.restore();
      case 'denim' || 'leather':
        // The folded edge of a patch: dark outline and a rolled, padded rim.
        c.drawRRect(rr.deflate(.5), line(_toward(l.panel, Colors.black, .38)));
        c.save();
        c.clipRRect(rr);
        c.drawRRect(
          rr.inflate(3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = Colors.black.withValues(
              alpha: (l.id == 'leather' ? .22 : .16) + pd * .6,
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        c.restore();
        c.drawRRect(rr.deflate(1.5), bevel(.10 + pl * .6, 0, 1));
      case 'plastic':
        // A moulded shell: its rounded lip catches the light, and a parting
        // line runs just inside it where the two halves of the mould met.
        c.drawRRect(rr.deflate(.5), line(l.border));
        c.drawRRect(rr.deflate(1.5), bevel(.25 + pl, .05, 1.2));
        c.drawRRect(
          rr.deflate(4.5),
          line(Colors.black.withValues(alpha: l.light ? .10 : .22), .8),
        );
        c.drawRRect(
          rr.deflate(5.3),
          line(Colors.white.withValues(alpha: .06 + pl * .5), .8),
        );
      case 'papery':
        c.drawRRect(
          rr.deflate(.5),
          line(_toward(l.panel, l.palette.text, .22)),
        );
        // A cut sheet: a crisp, bright cut edge along the top and left, and
        // the faint shade of its thickness along the foot.
        c.drawRRect(rr.deflate(1.3), bevel(.75, .10, 1.2));
      case 'walnut' || 'oak':
        // A panel set into the desk: the frame's outer edge, the groove
        // where the panel meets it, and light on the frame's lip.
        c.drawRRect(rr.deflate(.5), line(_toward(l.wall, Colors.black, .5)));
        c.drawRRect(
          rr.deflate(1.5),
          line(Colors.white.withValues(alpha: .08 + pl * .5)),
        );
        if (!strip) {
          c.drawRRect(
            rr.deflate(_frameWidth + .5),
            line(_toward(l.wall, Colors.black, .55)),
          );
          c.drawRRect(
            rr.deflate(_frameWidth + 1.5),
            line(Colors.black.withValues(alpha: .12)),
          );
          // The inlay's lip: lit along the top where it rises from the
          // groove, shaded along the foot.
          c.drawRRect(
            rr.deflate(_frameWidth - .8),
            bevel(.14 + pl * .6, .28, 1.2),
          );
        }
      case 'marble':
        c.drawRRect(
          rr.deflate(.5),
          line(_toward(l.panel, l.palette.text, .18)),
        );
        // A polished chamfer round the slab, with a soft specular edge
        // where the light from the top left runs along it.
        c.drawRRect(rr.deflate(1.8), bevel(.22 + pl, .12, 2.2));
        c.drawRRect(
          rr.deflate(1.2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = ui.Gradient.linear(area.topLeft, area.center, [
              Colors.white.withValues(alpha: .45 + pl),
              Colors.white.withValues(alpha: 0),
            ]),
        );
      case 'carbon':
        c.drawRRect(rr.deflate(.5), line(Colors.black.withValues(alpha: .6)));
        c.drawRRect(rr.deflate(1.5), bevel(.14 + pl, .25, 1));
    }
  }

  ui.Image? _screw;

  /// A screw head, drawn once: a countersunk ring, a domed head lit from
  /// the top left, a cross slot with a lit lip, and a glint.
  ui.Image get screw => _screw ??= _record(
    (_screwSize * dpr).ceil(),
    (_screwSize * dpr).ceil(),
    (c) {
      c.scale(dpr);
      const o = Offset(_screwSize / 2, _screwSize / 2);
      const r = _screwSize / 2 - 1.2;
      final metal = _toward(const Color(0xffb8bec6), look.panel, .25);
      c.drawCircle(
        o.translate(0, .5),
        r + 1,
        Paint()
          ..color = Colors.black.withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .6),
      );
      c.drawCircle(
        o,
        r + .7,
        Paint()
          ..shader = ui.Gradient.linear(
            o.translate(-r, -r),
            o.translate(r, r),
            [
              Colors.black.withValues(alpha: .5),
              Colors.white.withValues(alpha: .35),
            ],
          ),
      );
      c.drawCircle(
        o,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            o.translate(-r * .35, -r * .4),
            r * 1.5,
            [
              _toward(metal, Colors.white, .55),
              metal,
              _toward(metal, Colors.black, .55),
            ],
            const [0, .45, 1],
          ),
      );
      final slot = Paint()
        ..color = _toward(metal, Colors.black, .75)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;
      final lip = Paint()
        ..color = Colors.white.withValues(alpha: .45)
        ..strokeWidth = .6
        ..strokeCap = StrokeCap.round;
      const a = .62;
      for (final (d1, d2) in [
        (const Offset(-a, -a), const Offset(a, a)),
        (const Offset(-a, a), const Offset(a, -a)),
      ]) {
        c.drawLine(o + d1 * r, o + d2 * r, slot);
        c.drawLine(
          o + d1 * r + const Offset(.35, .55),
          o + d2 * r + const Offset(.35, .55),
          lip,
        );
      }
      c.drawCircle(
        o.translate(-r * .45, -r * .5),
        r * .18,
        Paint()..color = Colors.white.withValues(alpha: .7),
      );
    },
  );

  ui.Image? _stitch;

  /// One stitch: a short raised length of thread, lit along its top, with
  /// a tiny shadow where it sinks into the cloth at each end.
  ui.Image get stitch => _stitch ??= _record(
    (_stitchLength + 3) * dpr ~/ 1 + 1,
    (_stitchWidth + 3) * dpr ~/ 1 + 1,
    (c) {
      c.scale(dpr);
      const a = Offset(1.4, 1.3), b = Offset(1.4 + _stitchLength, 1.3);
      final t = look.thread;
      c.drawLine(
        a.translate(.4, .9),
        b.translate(.4, .9),
        Paint()
          ..color = Colors.black.withValues(alpha: .55)
          ..strokeWidth = _stitchWidth
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5),
      );
      c.drawLine(
        a,
        b,
        Paint()
          ..shader = ui.Gradient.linear(
            a.translate(0, -_stitchWidth / 2),
            a.translate(0, _stitchWidth / 2),
            [_toward(t, Colors.white, .35), t, _toward(t, Colors.black, .35)],
            const [0, .45, 1],
          )
          ..strokeWidth = _stitchWidth
          ..strokeCap = StrokeCap.round,
      );
      // The twist of the thread.
      final twist = Paint()
        ..color = _toward(t, Colors.black, .3).withValues(alpha: .6)
        ..strokeWidth = .45;
      for (var x = a.dx + 1.2; x < b.dx - .6; x += 1.4) {
        c.drawLine(Offset(x, a.dy - .8), Offset(x + .8, a.dy + .8), twist);
      }
    },
  );

  /// A gradient as a strip of pixels, made once: laid along a line with
  /// [_along], it draws what a gradient shader would, but as an image, which
  /// the fade under a panel's edge can draw (see [_fade]).
  ui.Image strip(String key, List<Color> colors, [List<double>? stops]) =>
      _nines[key] ??= _record(
        _stripLength,
        1,
        (c) => c.drawRect(
          const Rect.fromLTWH(0, 0, _stripLength + 0.0, 1),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              const Offset(_stripLength + 0.0, 0),
              colors,
              stops,
            ),
        ),
      );
}

const _stripLength = 256;

/// [strip] laid from [from] to [to]: across that line it runs through its
/// colours, and beyond either end it keeps the colour at that end.
Paint _along(ui.Image strip, Offset from, Offset to) {
  final d = to - from;
  final n = Offset(-d.dy, d.dx) / math.max(d.distance, 1e-6);
  final m = Matrix4.zero()
    ..setEntry(0, 0, d.dx / strip.width)
    ..setEntry(1, 0, d.dy / strip.width)
    ..setEntry(0, 1, n.dx)
    ..setEntry(1, 1, n.dy)
    ..setEntry(2, 2, 1)
    ..setEntry(0, 3, from.dx)
    ..setEntry(1, 3, from.dy)
    ..setEntry(3, 3, 1);
  return Paint()
    ..shader = ImageShader(
      strip,
      TileMode.clamp,
      TileMode.clamp,
      m.storage,
      filterQuality: FilterQuality.low,
    );
}

const _screwSize = 9.0;
const _stitchLength = 4.6, _stitchWidth = 2.0, _stitchGap = 3.2;
const _frameWidth = 4.0;

double _maxRadius(BorderRadius b) => [
  b.topLeft.x,
  b.topRight.x,
  b.bottomLeft.x,
  b.bottomRight.x,
].reduce(math.max);

/// Draws the border of a nine-patch made at [scale] pixels per logical
/// pixel: its corners at their own size and its edges stretched along
/// [dst], as one batch of triangles. Its middle is not drawn at all: a
/// shadow's middle is under the panel, and an edge's is clear, and drawing
/// either would cost a pass over the whole panel on every frame.
void _drawNine(Canvas c, ui.Image image, Rect centre, Rect dst, double scale) {
  final w = image.width.toDouble(), h = image.height.toDouble();
  var l = centre.left / scale, r = (w - centre.right) / scale;
  var t = centre.top / scale, b = (h - centre.bottom) / scale;
  // Smaller than its corners: the corners shrink to fit, as drawImageNine
  // does.
  if (l + r > dst.width) {
    final k = dst.width / (l + r);
    l *= k;
    r *= k;
  }
  if (t + b > dst.height) {
    final k = dst.height / (t + b);
    t *= k;
    b *= k;
  }
  final xs = [dst.left, dst.left + l, dst.right - r, dst.right];
  final ys = [dst.top, dst.top + t, dst.bottom - b, dst.bottom];
  final us = [0.0, centre.left, centre.right, w];
  final vs = [0.0, centre.top, centre.bottom, h];
  final positions = <Offset>[], texture = <Offset>[];
  for (var j = 0; j < 4; j++) {
    for (var i = 0; i < 4; i++) {
      positions.add(Offset(xs[i], ys[j]));
      texture.add(Offset(us[i], vs[j]));
    }
  }
  final indices = <int>[];
  for (var j = 0; j < 3; j++) {
    for (var i = 0; i < 3; i++) {
      if (i == 1 && j == 1) continue;
      final o = j * 4 + i;
      indices.addAll([o, o + 1, o + 4, o + 1, o + 5, o + 4]);
    }
  }
  c.drawVertices(
    ui.Vertices(
      VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: indices,
    ),
    BlendMode.srcOver,
    Paint()
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.low,
      ),
  );
}

/// The points round [r], [_arc] + 1 on each corner, clockwise from the top
/// left; two rounded rectangles give points that pair up.
List<Offset> _contour(RRect r) {
  final points = <Offset>[];
  void arc(double cx, double cy, double rx, double ry, double from) {
    for (var i = 0; i <= _arc; i++) {
      final a = from + math.pi / 2 * i / _arc;
      points.add(Offset(cx + rx * math.cos(a), cy + ry * math.sin(a)));
    }
  }

  arc(
    r.left + r.tlRadiusX,
    r.top + r.tlRadiusY,
    r.tlRadiusX,
    r.tlRadiusY,
    math.pi,
  );
  arc(
    r.right - r.trRadiusX,
    r.top + r.trRadiusY,
    r.trRadiusX,
    r.trRadiusY,
    -math.pi / 2,
  );
  arc(
    r.right - r.brRadiusX,
    r.bottom - r.brRadiusY,
    r.brRadiusX,
    r.brRadiusY,
    0,
  );
  arc(
    r.left + r.blRadiusX,
    r.bottom - r.blRadiusY,
    r.blRadiusX,
    r.blRadiusY,
    math.pi / 2,
  );
  return points;
}

const _arc = 6;

/// The triangles laid over the edge of a panel's content, which is cut off
/// along the plain rectangle [cut]: the corners of [cut] outside [inner]
/// (the panel's own rounded corner, there) solid, and a band inside
/// [inner] fading from solid to clear over [finishFade]. Drawn in the
/// panel's own material, it hides what the rectangle let through at the
/// corners and lets content scrolled toward the edge fade under it.
@visibleForTesting
ui.Vertices finishFadeVertices(Rect cut, RRect inner) {
  final rings = [
    (_contour(inner), 1.0),
    (_contour(inner.deflate(finishFade * .35)), .5),
    (_contour(inner.deflate(finishFade)), 0.0),
  ];
  final positions = <Offset>[], colors = <Color>[], indices = <int>[];
  for (final (points, alpha) in rings) {
    positions.addAll(points);
    colors.addAll(List.filled(points.length, Color.fromRGBO(0, 0, 0, alpha)));
  }
  final n = rings.first.$1.length;
  for (var ring = 0; ring < rings.length - 1; ring++) {
    final o = ring * n;
    for (var i = 0; i < n; i++) {
      final a = o + i, b = o + (i + 1) % n;
      indices.addAll([a, b, a + n, b, b + n, a + n]);
    }
  }
  // The corners of the cut that the rounded edge leaves out.
  final corners = [cut.topLeft, cut.topRight, cut.bottomRight, cut.bottomLeft];
  for (var k = 0; k < 4; k++) {
    final at = positions.length;
    positions.add(corners[k]);
    colors.add(const Color(0xff000000));
    for (var i = 0; i < _arc; i++) {
      indices.addAll([at, k * (_arc + 1) + i, k * (_arc + 1) + i + 1]);
    }
  }
  return ui.Vertices(
    VertexMode.triangles,
    positions,
    colors: colors,
    indices: indices,
  );
}

/// Which part of a finish a [FinishPaint] draws.
enum FinishPart {
  /// The background of a route.
  wall,

  /// Under a panel's content: its shadow and material. A strip (a bar) has
  /// no content over it that scrolls, so it draws its edge here too.
  panel,

  /// Over a panel's content: the content's edge fading under the panel's
  /// material, then the panel's edge (its rim, screws or stitches), so
  /// nothing the content draws is ever across the edge.
  seam,

  /// Over a popup's content: the edge alone, as a popup's own content comes
  /// nearer its edge than a panel's and is kept in by the popup itself.
  edge,
}

/// Which edges of a strip (a bar across the window) carry a seam.
typedef FinishEdges = ({bool top, bool bottom, bool left, bool right});
const allEdges = (top: true, bottom: true, left: true, right: true);

/// One part of the finish, drawn into its own layer once and kept: it is a
/// repaint boundary of its own, so the clock ticking above it, a scroll or a
/// button press never draws it again. It draws only pre-made images (see
/// [_Art]): no layers, blurs or shaders are made while it paints.
///
/// What it draws is drawn again by the GPU on every frame (a scroll, a page
/// sliding in), so it covers as little as it can: one pass over a panel's
/// area for its material, and only thin bands for its shadow and edge.
class FinishPaint extends LeafRenderObjectWidget {
  final FinishLook look;
  final FinishPart part;
  final BorderRadius corners;

  /// A bar or column edge to edge: no shadow, and a seam only on [edges].
  final bool strip;
  final FinishEdges edges;
  const FinishPaint({
    super.key,
    required this.look,
    required this.part,
    this.corners = BorderRadius.zero,
    this.strip = false,
    this.edges = allEdges,
  });

  @override
  RenderFinishPaint createRenderObject(BuildContext context) =>
      RenderFinishPaint(
        look: look,
        part: part,
        corners: corners,
        strip: strip,
        edges: edges,
        dpr: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        wall: part == FinishPart.wall ? null : FinishWallScope.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFinishPaint renderObject,
  ) => renderObject
    ..look = look
    ..part = part
    ..corners = corners
    ..strip = strip
    ..edges = edges
    ..dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1
    ..wall = part == FinishPart.wall ? null : FinishWallScope.of(context);
}

/// Where the wall of the route is, so a glass pane can show the part of the
/// wall behind it.
class FinishWallScope extends InheritedWidget {
  final GlobalKey wallKey;
  const FinishWallScope({
    super.key,
    required this.wallKey,
    required super.child,
  });
  static GlobalKey? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FinishWallScope>()?.wallKey;
  @override
  bool updateShouldNotify(FinishWallScope old) => old.wallKey != wallKey;
}

class RenderFinishPaint extends RenderBox {
  RenderFinishPaint({
    required FinishLook look,
    required FinishPart part,
    required BorderRadius corners,
    required bool strip,
    required FinishEdges edges,
    required double dpr,
    GlobalKey? wall,
  }) : _look = look,
       _part = part,
       _corners = corners,
       _strip = strip,
       _edges = edges,
       _dpr = dpr,
       _wall = wall;

  FinishLook _look;
  FinishPart _part;
  BorderRadius _corners;
  bool _strip;
  FinishEdges _edges;
  double _dpr;
  GlobalKey? _wall;

  FinishLook get look => _look;
  set look(FinishLook v) {
    if (identical(v, _look)) return;
    _look = v;
    _watch();
    markNeedsPaint();
  }

  FinishPart get part => _part;
  set part(FinishPart v) {
    if (v == _part) return;
    _part = v;
    markNeedsPaint();
  }

  BorderRadius get corners => _corners;
  set corners(BorderRadius v) {
    if (v == _corners) return;
    _corners = v;
    markNeedsPaint();
  }

  set strip(bool v) {
    if (v == _strip) return;
    _strip = v;
    markNeedsPaint();
  }

  set edges(FinishEdges v) {
    if (v == _edges) return;
    _edges = v;
    markNeedsPaint();
  }

  set dpr(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  set wall(GlobalKey? v) => _wall = v;

  @override
  bool get isRepaintBoundary => true;
  @override
  bool get sizedByParent => true;
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;
  @override
  bool hitTestSelf(Offset position) => false;

  _Art get _art => _Art.of(_look, _dpr);

  bool _listening = false;

  /// Until its photographs arrive, draw again when they do; after that,
  /// nothing outside it can make it draw.
  void _watch() {
    final want = attached && !_art.complete;
    if (want == _listening) return;
    _listening = want;
    if (want) {
      FinishTextures.instance.addListener(markNeedsPaint);
    } else {
      FinishTextures.instance.removeListener(markNeedsPaint);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _watch();
  }

  @override
  void detach() {
    if (_listening) FinishTextures.instance.removeListener(markNeedsPaint);
    _listening = false;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _watch();
    final c = context.canvas;
    c.save();
    c.translate(offset.dx, offset.dy);
    switch (_part) {
      case FinishPart.wall:
        FinishPaintCount.walls++;
        _paintWall(c);
      case FinishPart.panel:
        FinishPaintCount.panels++;
        _paintPanel(c);
      case FinishPart.seam:
        FinishPaintCount.seams++;
        _paintSeam(c);
      case FinishPart.edge:
        FinishPaintCount.seams++;
        _paintEdge(c, _corners.toRRect(Offset.zero & size));
    }
    c.restore();
  }

  /// Where this box is on the wall behind it (for Glass), and the wall's size.
  (Offset, Size) _onWall() {
    final wall = _wall?.currentContext?.findRenderObject();
    if (wall is RenderBox && wall.attached && wall.hasSize) {
      return (
        MatrixUtils.transformPoint(getTransformTo(wall), Offset.zero),
        wall.size,
      );
    }
    return (Offset.zero, size);
  }

  void _paintWall(Canvas c) {
    final l = _look, area = Offset.zero & size;
    if (l.id == 'glass') {
      final (field, _) = _art.glass(size);
      c.drawImageRect(
        field,
        Rect.fromLTWH(0, 0, field.width.toDouble(), field.height.toDouble()),
        Rect.fromLTWH(
          0,
          0,
          field.width * _Art._glassScale,
          field.height * _Art._glassScale,
        ),
        Paint()..filterQuality = FilterQuality.low,
      );
      return;
    }
    if (l.id == 'plastic') {
      // A faint lift at the top, as light on a table top.
      c.drawRect(
        area,
        Paint()
          ..shader = ui.Gradient.linear(area.topCenter, area.bottomCenter, [
            l.wall,
            l.palette.background,
          ]),
      );
      final grain = _art.wallFill;
      if (grain != null) c.drawRect(area, grain);
      return;
    }
    c.drawRect(area, _art.wallFill ?? (Paint()..color = l.wall));
  }

  /// The layers of a panel's material, bottom first, each with the part of
  /// the panel it covers: the panel's own texture over all of it, and the
  /// light laid over that (Plastic's gloss along its top and shade along its
  /// foot, the sheen of brushed steel, a pane's frost). Each is an image,
  /// so the fade over the content's edge can draw them again (see
  /// [finishFadeVertices]).
  List<(Paint, RRect)> _fills(RRect rr) {
    final l = _look, art = _art, area = rr.outerRect;
    final plain = Paint()..color = l.panel;
    switch (l.id) {
      case 'glass':
        final (at, wall) = _onWall();
        final (_, pane) = art.glass(wall);
        final s = _Art._glassScale;
        return [
          (
            Paint()
              ..shader = ImageShader(
                pane,
                TileMode.clamp,
                TileMode.clamp,
                (Matrix4.translationValues(
                  -at.dx,
                  -at.dy,
                  0,
                )..scaleByDouble(s, s, 1, 1)).storage,
                filterQuality: FilterQuality.low,
              ),
            rr,
          ),
          if (art.panelFill case final frost?) (frost, rr),
        ];
      case 'plastic':
        // The moulded surface, then the gloss of the shell over it: a wash of
        // light over its top, and its shade along the foot.
        final pl = l.panelLight, pd = l.panelDark;
        final top = math.min(area.height * .5, 90.0);
        final foot = math.min(area.height * .2, 30.0);
        return [
          (art.panelFill ?? plain, rr),
          (
            _along(
              art.strip('gloss', [
                Colors.white.withValues(alpha: pl * .6),
                Colors.white.withValues(alpha: 0),
              ]),
              area.topCenter,
              area.topCenter.translate(0, top),
            ),
            _band(
              rr,
              Rect.fromLTRB(area.left, area.top, area.right, area.top + top),
            ),
          ),
          (
            _along(
              art.strip('shade', [
                Colors.black.withValues(alpha: pd * .6),
                Colors.black.withValues(alpha: 0),
              ]),
              area.bottomCenter,
              area.bottomCenter.translate(0, -foot),
            ),
            _band(
              rr,
              Rect.fromLTRB(
                area.left,
                area.bottom - foot,
                area.right,
                area.bottom,
              ),
            ),
          ),
        ];
      case 'console':
        // Brushed steel catches the light in a broad soft band across it.
        return [
          (art.panelFill ?? plain, rr),
          (
            _along(
              art.strip(
                'sheen',
                [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: l.panelLight * .45),
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: l.panelLight * .25),
                  Colors.white.withValues(alpha: 0),
                ],
                const [.05, .3, .55, .78, 1],
              ),
              area.topLeft,
              Offset(area.left + math.min(area.width, 700), area.bottom),
            ),
            rr,
          ),
        ];
      default:
        return [(art.panelFill ?? plain, rr)];
    }
  }

  void _paintPanel(Canvas c) {
    final l = _look, art = _art, area = Offset.zero & size;
    final rr = _corners.toRRect(area);
    if (!_strip) {
      final sh = art.shadow(_corners);
      _drawNine(c, sh.image, sh.centre, area.inflate(sh.reach), 1);
    }
    for (final (paint, shape) in _fills(rr)) {
      c.drawRRect(shape, paint);
    }
    if ((l.id == 'walnut' || l.id == 'oak') && !_strip) {
      c.drawDRRect(
        rr,
        rr.deflate(_frameWidth),
        art.frameFill ?? (Paint()..color = l.wall),
      );
    }
    // A bar has no content inside its edge that scrolls: its edge is drawn
    // here, under what is on it.
    if (_strip) _paintEdge(c, rr);
  }

  /// The edge of a panel: its rim, and a console's screws or a stitched
  /// finish's stitches.
  void _paintEdge(Canvas c, RRect rr) {
    final rim = _art.rim(_corners, strip: _strip);
    _drawNine(c, rim.image, rim.centre, rr.outerRect, _dpr);
    if (_look.id == 'console') _screws(c, rr);
    if (stitchedFinishes.contains(_look.id)) _stitches(c, rr);
  }

  void _screws(Canvas c, RRect rr) {
    final image = _art.screw;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // Clear of the corner's curve, so the head sits on flat plate.
    double inset(double radius) => 4 + radius * .32 + _screwSize / 2;
    final a = rr.outerRect;
    if (a.width < 40 || a.height < 26) return;
    c.drawAtlas(
      image,
      [
        for (final o in [
          Offset(a.left + inset(rr.tlRadiusX), a.top + inset(rr.tlRadiusY)),
          Offset(a.right - inset(rr.trRadiusX), a.top + inset(rr.trRadiusY)),
          Offset(a.left + inset(rr.blRadiusX), a.bottom - inset(rr.blRadiusY)),
          Offset(a.right - inset(rr.brRadiusX), a.bottom - inset(rr.brRadiusY)),
        ])
          RSTransform.fromComponents(
            rotation: 0,
            scale: _screwSize / image.width,
            anchorX: image.width / 2,
            anchorY: image.height / 2,
            translateX: o.dx,
            translateY: o.dy,
          ),
      ],
      List.filled(4, src),
      null,
      null,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// Over a panel's content: the content's edge fading under the panel's
  /// material, then the panel's edge.
  void _paintSeam(Canvas c) {
    final area = Offset.zero & size;
    final rr = _corners.toRRect(area);
    final inset = finishEdgeInset(_look.id);
    final cut = area.deflate(inset);
    if (cut.width > finishFade * 2 && cut.height > finishFade * 2) {
      final fade = finishFadeVertices(
        cut,
        _inner(_corners, inset).toRRect(cut),
      );
      for (final (paint, _) in _fills(rr)) {
        c.drawVertices(fade, BlendMode.srcIn, paint);
      }
    }
    _paintEdge(c, rr);
  }

  /// A running stitch [_seamAt] inside [rr], laid as one batch of images.
  void _stitches(Canvas c, RRect rr) {
    final art = _art, image = art.stitch;
    final seam = rr.deflate(_seamAt);
    if (seam.width <= 0 || seam.height <= 0) return;
    final metric = (Path()..addRRect(seam)).computeMetrics().firstOrNull;
    if (metric == null) return;
    const period = _stitchLength + _stitchGap;
    final count = (metric.length / period).floor();
    if (count < 4) return;
    final step = metric.length / count;
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final a = rr.outerRect;
    for (var i = 0; i < count; i++) {
      final t = metric.getTangentForOffset(i * step + step / 2);
      if (t == null) continue;
      final p = t.position;
      if (_strip) {
        // On a bar only along the edges that face the page.
        final near = math.min(
          math.min(
            _edges.top ? (p.dy - a.top).abs() : 1e9,
            _edges.bottom ? (a.bottom - p.dy).abs() : 1e9,
          ),
          math.min(
            _edges.left ? (p.dx - a.left).abs() : 1e9,
            _edges.right ? (a.right - p.dx).abs() : 1e9,
          ),
        );
        if (near > _seamAt + 1) continue;
      }
      final angle = -t.angle;
      transforms.add(
        RSTransform.fromComponents(
          rotation: angle,
          scale: 1 / _dpr,
          anchorX: (1.4 + _stitchLength / 2) * _dpr,
          anchorY: 1.3 * _dpr,
          translateX: p.dx,
          translateY: p.dy,
        ),
      );
      rects.add(src);
    }
    if (transforms.isEmpty) return;
    c.drawAtlas(
      image,
      transforms,
      rects,
      null,
      null,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

/// The part of [rr] inside [band], with [rr]'s corners where [band]
/// reaches them.
RRect _band(RRect rr, Rect band) {
  final a = rr.outerRect;
  bool at(double x, double y) =>
      (x == a.left ? band.left == a.left : band.right == a.right) &&
      (y == a.top ? band.top == a.top : band.bottom == a.bottom);
  return RRect.fromRectAndCorners(
    band,
    topLeft: at(a.left, a.top) ? rr.tlRadius : Radius.zero,
    topRight: at(a.right, a.top) ? rr.trRadius : Radius.zero,
    bottomLeft: at(a.left, a.bottom) ? rr.blRadius : Radius.zero,
    bottomRight: at(a.right, a.bottom) ? rr.brRadius : Radius.zero,
  );
}

BorderRadius _inner(BorderRadius b, double by) => BorderRadius.only(
  topLeft: Radius.circular(math.max(0, b.topLeft.x - by)),
  topRight: Radius.circular(math.max(0, b.topRight.x - by)),
  bottomLeft: Radius.circular(math.max(0, b.bottomLeft.x - by)),
  bottomRight: Radius.circular(math.max(0, b.bottomRight.x - by)),
);

/// The corners of a panel's content where it is cut off, [by] inside the
/// panel's edge.
BorderRadius finishInnerCorners(BorderRadius b, double by) => _inner(b, by);
