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
  'glass': FinishMaterial(panel: 'frost', panelTile: 128),
  'papery': FinishMaterial(
    wall: 'paper',
    wallTile: 512,
    panel: 'paper',
    panelTile: 420,
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
  'plastic': FinishMaterial(),
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
    wallTile: 144,
    panel: 'carbon',
    panelTile: 120,
  ),
};

/// Every texture the app bundles, by name (`assets/finish/<name>.jpg`).
final finishTextureNames = {
  for (final m in finishMaterials.values) ...[?m.wall, ?m.panel],
};

/// The finishes whose panels are stitched: their content is kept inside the
/// seam (see [finishSeamInset]).
const stitchedFinishes = {'denim', 'leather'};

/// How far inside a stitched panel's edge its content starts: clear of the
/// thread (at [_seamAt]) and of its shadow, so nothing is ever drawn across
/// the stitches.
const finishSeamInset = 9.0;
const _seamAt = 5.5;

/// Where a stitched panel's content box starts: its own margin, which is
/// empty, may reach under the seam, but nothing it draws is shown there.
const finishContentInset = 4.0;

/// How many times the material has been drawn, for tests: once per surface
/// when it first shows, and never again for a tick of the clock or a scroll.
class FinishPaintCount {
  static int walls = 0, panels = 0, seams = 0;
  static int get total => walls + panels + seams;
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
  // nothing, so only one of the two layers marks any pixel. The tile is made
  // at the size it is shown on this screen, so a frame samples it one to
  // one, with no scaling.
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
  return recorder.endRecording().toImageSync(width, height);
}

ui.Image _record(int w, int h, void Function(Canvas c) draw) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));
  return recorder.endRecording().toImageSync(math.max(1, w), math.max(1, h));
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
    final px = (tile * dpr).round().clamp(16, 2048);
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
        look.wall,
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
        c.drawRRect(rr.deflate(.5), line(l.border));
        c.drawRRect(rr.deflate(1.5), bevel(.25 + pl, .05, 1.2));
      case 'papery':
        c.drawRRect(
          rr.deflate(.5),
          line(_toward(l.panel, l.palette.text, .22)),
        );
        c.drawRRect(rr.deflate(1.5), line(Colors.white.withValues(alpha: .6)));
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
        }
      case 'marble':
        c.drawRRect(
          rr.deflate(.5),
          line(_toward(l.panel, l.palette.text, .18)),
        );
        c.drawRRect(rr.deflate(1.5), bevel(.18 + pl, .08, 1));
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

  final _hems = <String, ui.Image>{};

  /// Inside a stitched panel's seam: the panel's colour fading in over the
  /// first few pixels, so content scrolled toward the seam passes softly
  /// under the hem instead of being cut.
  ({ui.Image image, Rect centre, double border}) hem(BorderRadius corners) {
    final r = _maxRadius(corners);
    final border = math.max(r, _hemFade) + 2;
    final logical = border * 2 + 4;
    final px = (logical * dpr).ceil();
    final image = _hems['$corners'] ??= _record(px, px, (c) {
      c.scale(dpr);
      final rr = corners.toRRect(Rect.fromLTWH(0, 0, logical, logical));
      c.clipRRect(rr);
      for (var i = 0; i < _hemFade; i++) {
        c.drawRRect(
          rr.deflate(i + .5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = look.panel.withValues(
              alpha: math.pow(1 - i / _hemFade, 1.6).toDouble(),
            ),
        );
      }
    });
    return (
      image: image,
      centre: Rect.fromLTWH(border * dpr, border * dpr, 4 * dpr, 4 * dpr),
      border: border,
    );
  }
}

const _screwSize = 9.0;
const _stitchLength = 4.6, _stitchWidth = 2.0, _stitchGap = 3.2;
const _hemFade = 6.0;
const _frameWidth = 4.0;

double _maxRadius(BorderRadius b) => [
  b.topLeft.x,
  b.topRight.x,
  b.bottomLeft.x,
  b.bottomRight.x,
].reduce(math.max);

/// Draws a nine-patch made at [dpr] so its corners stay the right size.
void _drawNine(
  Canvas c,
  ui.Image image,
  Rect centre,
  Rect dst,
  double dpr, [
  Paint? paint,
]) {
  c.save();
  c.scale(1 / dpr);
  c.drawImageNine(
    image,
    centre,
    Rect.fromLTRB(
      dst.left * dpr,
      dst.top * dpr,
      dst.right * dpr,
      dst.bottom * dpr,
    ),
    paint ?? Paint()
      ..filterQuality = FilterQuality.low,
  );
  c.restore();
}

/// Which part of a finish a [FinishPaint] draws.
enum FinishPart {
  /// The background of a route.
  wall,

  /// A panel's shadow, material and edge.
  panel,

  /// Over a stitched panel's content: the hem and the stitches.
  seam,
}

/// Which edges of a strip (a bar across the window) carry a seam.
typedef FinishEdges = ({bool top, bool bottom, bool left, bool right});
const allEdges = (top: true, bottom: true, left: true, right: true);

/// One part of the finish, drawn into its own layer once and kept: it is a
/// repaint boundary of its own, so the clock ticking above it, a scroll or a
/// button press never draws it again. It draws only pre-made images (see
/// [_Art]): no layers, blurs or shaders are made while it paints.
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

  set look(FinishLook v) {
    if (identical(v, _look)) return;
    _look = v;
    _watch();
    markNeedsPaint();
  }

  set part(FinishPart v) {
    if (v == _part) return;
    _part = v;
    markNeedsPaint();
  }

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
      return;
    }
    c.drawRect(area, _art.wallFill ?? (Paint()..color = l.wall));
  }

  void _paintPanel(Canvas c) {
    final l = _look, art = _art, area = Offset.zero & size;
    final rr = _corners.toRRect(area);
    if (!_strip) {
      final sh = art.shadow(_corners);
      _drawNine(c, sh.image, sh.centre, area.inflate(sh.reach), 1);
    }
    switch (l.id) {
      case 'glass':
        final (_, pane) = art.glass(_onWall().$2);
        final (at, _) = _onWall();
        final s = _Art._glassScale;
        c.drawRRect(
          rr,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..shader = ImageShader(
              pane,
              TileMode.clamp,
              TileMode.clamp,
              (Matrix4.translationValues(
                -at.dx,
                -at.dy,
                0,
              )..scaleByDouble(s, s, 1, 1)).storage,
              filterQuality: FilterQuality.medium,
            ),
        );
        final frost = art.panelFill;
        if (frost != null) c.drawRRect(rr, frost);
      case 'plastic':
        c.drawRRect(rr, Paint()..color = l.panel);
        // Gloss: a wash of light over the top of the shell, and its shade.
        final pl = l.panelLight, pd = l.panelDark;
        c.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.linear(
              area.topCenter,
              Offset(area.center.dx, area.top + math.min(area.height * .5, 90)),
              [
                Colors.white.withValues(alpha: pl * .85),
                Colors.white.withValues(alpha: 0),
              ],
            ),
        );
        c.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.linear(
              area.bottomCenter,
              Offset(
                area.center.dx,
                area.bottom - math.min(area.height * .2, 30),
              ),
              [
                Colors.black.withValues(alpha: pd * .8),
                Colors.black.withValues(alpha: 0),
              ],
            ),
        );
      case 'console':
        c.drawRRect(rr, art.panelFill ?? (Paint()..color = l.panel));
        // Brushed steel catches the light in a broad soft band across it.
        c.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.linear(
              area.topLeft,
              Offset(area.left + math.min(area.width, 700), area.bottom),
              [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: l.panelLight * .45),
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: l.panelLight * .25),
                Colors.white.withValues(alpha: 0),
              ],
              const [.05, .3, .55, .78, 1],
              TileMode.clamp,
            ),
        );
      case 'walnut' || 'oak':
        c.drawRRect(rr, art.panelFill ?? (Paint()..color = l.panel));
        if (!_strip) {
          c.drawDRRect(
            rr,
            rr.deflate(_frameWidth),
            art.frameFill ?? (Paint()..color = l.wall),
          );
        }
      default:
        c.drawRRect(rr, art.panelFill ?? (Paint()..color = l.panel));
    }
    final rim = art.rim(_corners, strip: _strip);
    _drawNine(c, rim.image, rim.centre, area, _dpr);
    if (l.id == 'console') _screws(c, rr);
    // A strip has no content inside a seam: its stitches are drawn here.
    if (_strip && stitchedFinishes.contains(l.id)) _stitches(c, rr);
  }

  void _screws(Canvas c, RRect rr) {
    final art = _art, image = art.screw;
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
    for (final o in [
      Offset(a.left + inset(rr.tlRadiusX), a.top + inset(rr.tlRadiusY)),
      Offset(a.right - inset(rr.trRadiusX), a.top + inset(rr.trRadiusY)),
      Offset(a.left + inset(rr.blRadiusX), a.bottom - inset(rr.blRadiusY)),
      Offset(a.right - inset(rr.brRadiusX), a.bottom - inset(rr.brRadiusY)),
    ]) {
      c.drawImageRect(
        image,
        src,
        Rect.fromCenter(center: o, width: _screwSize, height: _screwSize),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  void _paintSeam(Canvas c) {
    final area = Offset.zero & size;
    final rr = _corners.toRRect(area);
    // The hem: over the edge of the content, inside the stitches.
    final hemRect = area.deflate(finishSeamInset);
    if (!hemRect.isEmpty) {
      final hem = _art.hem(_inner(_corners, finishSeamInset));
      _drawNine(c, hem.image, hem.centre, hemRect, _dpr);
    }
    _stitches(c, rr);
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

BorderRadius _inner(BorderRadius b, double by) => BorderRadius.only(
  topLeft: Radius.circular(math.max(0, b.topLeft.x - by)),
  topRight: Radius.circular(math.max(0, b.topRight.x - by)),
  bottomLeft: Radius.circular(math.max(0, b.bottomLeft.x - by)),
  bottomRight: Radius.circular(math.max(0, b.bottomRight.x - by)),
);

/// The corners of a stitched panel's content, inside its seam.
BorderRadius finishInnerCorners(BorderRadius b) => _inner(b, finishSeamInset);
