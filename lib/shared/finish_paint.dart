import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/finish.dart';

/// Small tileable textures, drawn once (not bundled): flecks, brushed
/// streaks, weave, knit, pebbles. Each is white or black with its own
/// transparency, so a finish tints and scales it from its budget (see
/// [FinishLook]) and the same tile serves every theme.
class _Tiles {
  static final _cache = <String, ui.Image>{};

  static ui.Image _make(
    String key,
    int w,
    int h,
    void Function(Canvas canvas) draw,
  ) => _cache.putIfAbsent(key, () {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));
    return recorder.endRecording().toImageSync(w, h);
  });

  static Color _c(bool white, double a) =>
      (white ? Colors.white : Colors.black).withValues(alpha: a);

  /// Single-pixel flecks of random strength.
  static ui.Image fine(bool white) => _make('fine$white', 96, 96, (c) {
    final r = math.Random(white ? 11 : 12);
    for (var level = 1; level <= 4; level++) {
      final pts = <Offset>[];
      for (var i = 0; i < 96 * 96 * .1; i++) {
        pts.add(Offset(r.nextInt(96) + .5, r.nextInt(96) + .5));
      }
      c.drawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = _c(white, level / 4)
          ..strokeWidth = 1,
      );
    }
  });

  /// Soft round flecks, for wool.
  static ui.Image fuzz(bool white) => _make('fuzz$white', 96, 96, (c) {
    final r = math.Random(white ? 21 : 22);
    for (var level = 1; level <= 4; level++) {
      final pts = <Offset>[];
      for (var i = 0; i < 70; i++) {
        pts.add(Offset(r.nextDouble() * 96, r.nextDouble() * 96));
      }
      c.drawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = _c(white, level / 4 * .8)
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      );
    }
  });

  /// Long horizontal streaks, for brushed metal.
  static ui.Image brushed(bool white) => _make('brushed$white', 256, 64, (c) {
    final r = math.Random(white ? 31 : 32);
    for (var i = 0; i < 300; i++) {
      final y = r.nextInt(64) + .5, x = r.nextDouble() * 256;
      final len = 14 + r.nextDouble() * 130;
      final p = Paint()
        ..color = _c(white, .25 + r.nextDouble() * .75)
        ..strokeWidth = 1;
      c.drawLine(Offset(x, y), Offset(x + len, y), p);
      c.drawLine(Offset(x - 256, y), Offset(x - 256 + len, y), p);
    }
  });

  /// A 2 over 2 twill weave: each cell is a thread passing over, lit on one
  /// side and shaded on the other.
  static ui.Image weave(bool white) => _make('weave$white', 24, 24, (c) {
    const cell = 6.0;
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        final warp = (i - j) % 4 < 2;
        final rect = Rect.fromLTWH(i * cell, j * cell, cell, cell);
        final lit = _c(white, white ? .95 : 0),
            dim = _c(white, white ? 0 : .95);
        c.drawRect(
          rect.deflate(.4),
          Paint()
            ..shader = ui.Gradient.linear(
              warp ? rect.topCenter : rect.centerLeft,
              warp ? rect.bottomCenter : rect.centerRight,
              [
                white ? lit : Colors.transparent,
                white ? Colors.transparent : dim,
              ],
            ),
        );
      }
    }
  });

  /// Fine diagonal ribs, for twill (denim) and knit (cashmere).
  static ui.Image twill(bool white, {bool cross = false}) =>
      _make('twill$white$cross', 4, 4, (c) {
        final p = Paint()..color = _c(white, .95);
        for (var x = 0; x < 4; x++) {
          c.drawRect(Rect.fromLTWH(x.toDouble(), 3.0 - x, 1, 1), p);
          if (cross)
            c.drawRect(Rect.fromLTWH(x.toDouble(), x.toDouble(), 1, 1), p);
        }
      });

  /// Short vertical flecks, for slubs in cloth.
  static ui.Image slub(bool white) => _make('slub$white', 64, 96, (c) {
    final r = math.Random(white ? 41 : 42);
    for (var i = 0; i < 150; i++) {
      final x = r.nextInt(64) + .5, y = r.nextDouble() * 96;
      final len = 4 + r.nextDouble() * 12;
      final p = Paint()..color = _c(white, .2 + r.nextDouble() * .8);
      c.drawLine(Offset(x, y), Offset(x, y + len), p);
      c.drawLine(Offset(x, y - 96), Offset(x, y - 96 + len), p);
    }
  });

  /// Rounded bumps with a lit upper edge and a shaded lower one, for hide.
  static ui.Image pebble(bool white) => _make('pebble$white', 128, 128, (c) {
    final r = math.Random(51);
    for (var i = 0; i < 110; i++) {
      final cx = r.nextDouble() * 128,
          cy = r.nextDouble() * 128,
          rad = 4.5 + r.nextDouble() * 4.5;
      for (var dx = -128; dx <= 128; dx += 128) {
        for (var dy = -128; dy <= 128; dy += 128) {
          final o = Offset(cx + dx, cy + dy);
          if (o.dx < -12 || o.dy < -12 || o.dx > 140 || o.dy > 140) continue;
          final box = Rect.fromCircle(center: o, radius: rad);
          if (white) {
            c.drawArc(
              box,
              math.pi * .85,
              math.pi * .8,
              false,
              Paint()
                ..color = _c(true, .9)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4,
            );
          } else {
            c.drawCircle(
              o,
              rad,
              Paint()
                ..color = _c(false, .55)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.1,
            );
            c.drawArc(
              box.deflate(1.2),
              -math.pi * .15,
              math.pi * .8,
              false,
              Paint()
                ..color = _c(false, .6)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.6,
            );
          }
        }
      }
    }
  });
}

/// A paint that fills with [tile], repeated, at [alpha] of its strength
/// (0..1, where 1 is the tile's own transparency).
Paint _tilePaint(ui.Image tile, double alpha, {double scale = 1}) {
  final a = alpha.clamp(0.0, 1.0);
  return Paint()
    ..shader = ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.diagonal3Values(scale, scale, 1).storage,
      filterQuality: FilterQuality.low,
    )
    ..colorFilter = ColorFilter.matrix([
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, a, 0,
    ]);
}

Color _toward(Color c, Color to, double t) => Color.lerp(c, to, t.clamp(0, 1))!;

/// Fills [area] with white and black [tile]s at the given opacities.
void _speckle(
  Canvas c,
  Rect area,
  ui.Image Function(bool white) tile,
  double light,
  double dark, {
  double scale = 1,
}) {
  if (light > 0) c.drawRect(area, _tilePaint(tile(true), light, scale: scale));
  if (dark > 0) c.drawRect(area, _tilePaint(tile(false), dark, scale: scale));
}

/// A wash of [color] from [from] fading to nothing at [to].
Paint _wash(
  Rect area,
  Alignment from,
  Alignment to,
  Color color,
  double a, {
  double stop = 1,
}) => Paint()
  ..shader = LinearGradient(
    begin: from,
    end: to,
    colors: [
      color.withValues(alpha: a),
      color.withValues(alpha: 0),
    ],
    stops: [0, stop],
  ).createShader(area);

/// The background of a route.
class FinishWallPainter extends CustomPainter {
  final FinishLook look;
  const FinishWallPainter(this.look);

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final l = look, wl = l.wallLight, wd = l.wallDark;
    canvas.drawRect(area, Paint()..color = l.wall);
    switch (l.id) {
      case 'glass':
        // Three soft glows of the accent; together no stronger than the
        // budget, so the wall never leaves the range text was checked on.
        final a = l.wallScale * .55;
        void glow(Offset at, double radius, double share) => canvas.drawRect(
          area,
          Paint()
            ..shader = ui.Gradient.radial(at, radius, [
              l.palette.accent.withValues(alpha: a * share),
              l.palette.accent.withValues(alpha: 0),
            ]),
        );
        canvas.drawRect(area, Paint()..color = l.palette.background);
        final big = math.max(size.width, size.height);
        glow(Offset(size.width * .12, size.height * .08), big * .55, .5);
        glow(Offset(size.width * .92, size.height * .9), big * .5, .3);
        glow(Offset(size.width * .7, size.height * .15), big * .4, .2);
      case 'console':
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topCenter,
            Alignment.bottomCenter,
            Colors.white,
            wl * .4,
          ),
        );
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.bottomCenter,
            Alignment.topCenter,
            Colors.black,
            wd * .4,
          ),
        );
        _speckle(canvas, area, _Tiles.brushed, wl * .6, wd * .6);
      case 'brick':
        _bricks(canvas, size, l);
      case 'cashmere':
        final knit = l.light
            ? _Tiles.twill(false, cross: true)
            : _Tiles.twill(true, cross: true);
        canvas.drawRect(
          area,
          _tilePaint(knit, (l.light ? wd : wl) * .5, scale: 1.25),
        );
        _speckle(canvas, area, _Tiles.fuzz, wl * .5, wd * .5);
      case 'denim':
        canvas.drawRect(
          area,
          _tilePaint(_Tiles.twill(true), wl * .5, scale: 1.4),
        );
        canvas.drawRect(area, _tilePaint(_Tiles.slub(true), wl * .4));
        canvas.drawRect(area, _tilePaint(_Tiles.slub(false), wd * .5));
      case 'plastic':
        // A faint lift at the top, as light on a table top.
        canvas.drawRect(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [l.wall, l.palette.background],
            ).createShader(area),
        );
      case 'walnut' || 'oak':
        _planks(canvas, size, l);
      case 'leather':
        _speckle(canvas, area, _Tiles.pebble, wl * .5, wd * .5);
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topCenter,
            Alignment.bottomCenter,
            Colors.white,
            wl * .3,
          ),
        );
      case 'marble':
        _veins(canvas, size, l, wl, wd, 1);
      case 'papery':
        _paperWall(canvas, size, l);
      case 'carbon':
        _speckle(canvas, area, _Tiles.weave, wl * .5, wd * .5);
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topLeft,
            Alignment.bottomRight,
            Colors.white,
            wl * .4,
            stop: .6,
          ),
        );
    }
  }

  @override
  bool shouldRepaint(FinishWallPainter old) => !identical(old.look, look);
}

/// A sheet of paper: a fine tooth, and short fibres lying every which way.
/// The fibres are drawn into one layer and laid on at their budget, so ones
/// that cross never add up past it.
void _paperWall(Canvas c, Size size, FinishLook l) {
  final area = Offset.zero & size;
  final wl = l.wallLight, wd = l.wallDark;
  _speckle(c, area, _Tiles.fine, wl * .45, wd * .4);
  final r = math.Random(17);
  final count = (size.width * size.height / 1800).round().clamp(0, 1400);
  for (final white in [false, true]) {
    c.saveLayer(
      area,
      Paint()
        ..color = (white ? Colors.white : Colors.black).withValues(
          alpha: (white ? wl : wd) * .55,
        ),
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = .8
      ..color = white ? Colors.white : Colors.black;
    for (var i = 0; i < count; i++) {
      final at = Offset(
        r.nextDouble() * size.width,
        r.nextDouble() * size.height,
      );
      final a = r.nextDouble() * math.pi, len = 5 + r.nextDouble() * 14;
      final bend = (r.nextDouble() - .5) * 6;
      final end = at + Offset(math.cos(a), math.sin(a)) * len;
      final mid =
          Offset.lerp(at, end, .5)! + Offset(-math.sin(a), math.cos(a)) * bend;
      p.color = (white ? Colors.white : Colors.black).withValues(
        alpha: .35 + r.nextDouble() * .65,
      );
      c.drawPath(
        Path()
          ..moveTo(at.dx, at.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy),
        p,
      );
    }
    c.restore();
  }
}

/// Running-bond brickwork, each brick a little lighter or darker.
void _bricks(Canvas c, Size size, FinishLook l) {
  const bw = 62.0, bh = 28.0, gap = 4.0;
  final wl = l.wallLight, wd = l.wallDark;
  // Mortar goes toward the lighter or darker end, whichever suits the theme.
  c.drawRect(
    Offset.zero & size,
    Paint()
      ..color = l.light
          ? _toward(l.wall, Colors.white, wl * .7)
          : _toward(l.wall, Colors.black, wd * .7),
  );
  final r = math.Random(7);
  final p = Paint();
  for (var row = 0; row * (bh + gap) < size.height + bh; row++) {
    final shift = row.isOdd ? -(bw + gap) / 2 : 0.0;
    for (var x = shift + gap / 2; x < size.width; x += bw + gap) {
      final t = r.nextDouble() * 2 - 1;
      p.color = t >= 0
          ? _toward(l.wall, Colors.white, t * wl * .7)
          : _toward(l.wall, Colors.black, -t * wd * .7);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, row * (bh + gap) + gap / 2, bw, bh),
          const Radius.circular(1.5),
        ),
        p,
      );
    }
  }
  _speckle(c, Offset.zero & size, _Tiles.fine, wl * .3, wd * .3);
}

/// Horizontal planks with long wavy grain lines.
void _planks(Canvas c, Size size, FinishLook l) {
  final wl = l.wallLight,
      wd = l.wallDark,
      r = math.Random(l.id == 'oak' ? 5 : 3);
  const plank = 78.0;
  final p = Paint();
  for (var y = 0.0; y < size.height; y += plank) {
    final t = r.nextDouble() * 2 - 1;
    p.color = t >= 0
        ? _toward(l.wall, Colors.white, t * wl * .35).withValues(alpha: 1)
        : _toward(l.wall, Colors.black, -t * wd * .35);
    c.drawRect(Rect.fromLTWH(0, y, size.width, plank), p);
  }
  // Grain: long, thin, slightly wavering lines.
  final grain = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final lines = (size.width * size.height / 700).round().clamp(0, 2600);
  for (var i = 0; i < lines; i++) {
    final dark = r.nextBool();
    grain.color = (dark ? Colors.black : Colors.white).withValues(
      alpha: (dark ? wd : wl) * (.1 + r.nextDouble() * .3),
    );
    var x = r.nextDouble() * size.width - 40, y = r.nextDouble() * size.height;
    final path = Path()..moveTo(x, y);
    final len = 90 + r.nextDouble() * 320;
    for (var s = 0.0; s < len; s += 18) {
      x += 18;
      y += (r.nextDouble() - .5) * 1.8;
      path.lineTo(x, y);
    }
    c.drawPath(path, grain);
  }
  // Seams between planks.
  final seam = Paint()
    ..color = Colors.black.withValues(alpha: wd * .5)
    ..strokeWidth = 1.5;
  for (var y = plank; y < size.height; y += plank) {
    c.drawLine(Offset(0, y), Offset(size.width, y), seam);
  }
}

/// Veins running across, with soft clouds between them; [weight] thins them
/// for a panel. Each kind is drawn into its own layer at full strength and
/// laid on at its budget, so veins that cross never add up past it.
void _veins(
  Canvas c,
  Size size,
  FinishLook l,
  double wl,
  double wd,
  double weight, {
  bool panel = false,
}) {
  final r = math.Random(panel ? 9 : 4);
  final area = Offset.zero & size;
  final big = math.max(size.width, size.height);
  // Soft clouds, light and dark.
  for (final white in [true, false]) {
    c.saveLayer(
      area,
      Paint()
        ..color = (white ? Colors.white : Colors.black).withValues(
          alpha: (white ? wl : wd) * .3 * weight,
        ),
    );
    final cloud = Paint()
      ..color = white ? Colors.white : Colors.black
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    for (var i = 0; i < (panel ? 2 : 4); i++) {
      c.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        big * (.12 + r.nextDouble() * .15),
        cloud,
      );
    }
    c.restore();
  }
  // Veins go toward the lighter end on a dark stone and the darker end on a
  // pale one.
  final vein = l.light ? Colors.black : Colors.white;
  final room = l.light ? wd : wl;
  c.saveLayer(
    area,
    Paint()..color = vein.withValues(alpha: room * .6 * weight),
  );
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = vein
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .7);
  void walk(
    Offset from,
    double angle,
    double width,
    double alpha,
    double length,
    int depth,
  ) {
    var at = from, a = angle;
    final path = Path()..moveTo(at.dx, at.dy);
    for (var s = 0.0; s < length; s += 12) {
      a += (r.nextDouble() - .5) * .55;
      at += Offset(math.cos(a), math.sin(a)) * 12;
      path.lineTo(at.dx, at.dy);
      if (depth < 2 && r.nextDouble() < .07) {
        walk(
          at,
          a + (r.nextBool() ? .9 : -.9),
          width * .55,
          alpha * .8,
          length * .4,
          depth + 1,
        );
      }
    }
    c.drawPath(
      path,
      p
        ..strokeWidth = width
        ..color = vein.withValues(alpha: alpha),
    );
  }

  for (var i = 0; i < (panel ? 2 : 9); i++) {
    final start = Offset(
      r.nextDouble() * size.width,
      r.nextDouble() * size.height,
    );
    walk(
      start,
      r.nextDouble() * math.pi * 2,
      (panel ? .8 : 1.1) + r.nextDouble() * 1.6,
      .5 + r.nextDouble() * .5,
      big * (panel ? .5 : .55),
      0,
    );
  }
  c.restore();
}

/// How round a finish's panels are.
double finishRadius(String id) => switch (id) {
  'glass' => 18,
  'papery' => 4,
  'console' => 5,
  'brick' => 6,
  'cashmere' => 22,
  'denim' => 10,
  'plastic' => 24,
  'walnut' || 'oak' => 10,
  'leather' => 12,
  'marble' => 10,
  'carbon' => 8,
  _ => 14,
};

/// A panel: its shadow, its material and its trim. A [pane] (a column that
/// fills its area edge to edge) has the material but no shadow or trim.
class FinishPanelPainter extends CustomPainter {
  final FinishLook look;
  final double radius;
  final bool pane;
  const FinishPanelPainter(this.look, this.radius, {this.pane = false});

  @override
  void paint(Canvas canvas, Size size) {
    final l = look, pl = l.panelLight, pd = l.panelDark, s = l.panelScale;
    final area = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(area, Radius.circular(radius));
    final white = Colors.white, black = Colors.black;
    if (!pane) _shadow(canvas, rr, l);
    // Glass is the surface colour over the wall behind it; the rest are
    // solid.
    canvas.drawRRect(
      rr,
      Paint()
        ..color = l.panelAlpha < 1
            ? l.palette.surface.withValues(alpha: l.panelAlpha)
            : l.panel,
    );
    canvas
      ..save()
      ..clipRRect(rr);
    switch (l.id) {
      case 'glass':
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topLeft,
            Alignment.bottomRight,
            white,
            pl * 1.0,
            stop: .75,
          ),
        );
      case 'console':
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topCenter,
            Alignment.bottomCenter,
            white,
            pl * .4,
            stop: .5,
          ),
        );
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.bottomCenter,
            Alignment.topCenter,
            black,
            pd * .4,
            stop: .4,
          ),
        );
        _speckle(canvas, area, _Tiles.brushed, pl * .28, pd * .28);
      case 'brick':
        _speckle(canvas, area, _Tiles.fine, pl * .6, pd * .7);
      case 'cashmere':
        final knit = l.light
            ? _Tiles.twill(false, cross: true)
            : _Tiles.twill(true, cross: true);
        canvas.drawRect(
          area,
          _tilePaint(knit, (l.light ? pd : pl) * .6, scale: 1.1),
        );
        _speckle(canvas, area, _Tiles.fuzz, pl * .35, pd * .3);
      case 'denim':
        canvas.drawRect(
          area,
          _tilePaint(_Tiles.twill(true), pl * .6, scale: 1.4),
        );
        canvas.drawRect(area, _tilePaint(_Tiles.slub(false), pd * .4));
      case 'plastic':
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topCenter,
            Alignment.bottomCenter,
            white,
            pl * .85,
            stop: .44,
          ),
        );
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.bottomCenter,
            Alignment.topCenter,
            black,
            pd * .8,
            stop: .18,
          ),
        );
      case 'papery':
        _speckle(canvas, area, _Tiles.fine, pl * .5, pd * .6);
      case 'walnut' || 'oak':
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topCenter,
            Alignment.bottomCenter,
            white,
            pl * .6,
            stop: .25,
          ),
        );
        _speckle(canvas, area, _Tiles.fine, pl * .35, pd * .5);
      case 'leather':
        _speckle(canvas, area, _Tiles.pebble, pl * .45, pd * .35);
        // The padded edge: a soft shade just inside the rim.
        canvas.drawRRect(
          rr.inflate(6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..color = black.withValues(alpha: pd * .8)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      case 'marble':
        _veins(canvas, size, l, pl * .5, pd * .5, .6, panel: true);
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topLeft,
            Alignment.bottomRight,
            white,
            pl * .5,
            stop: .5,
          ),
        );
      case 'carbon':
        canvas.drawRect(
          area,
          _tilePaint(_Tiles.weave(true), pl * .5, scale: .8),
        );
        canvas.drawRect(
          area,
          _tilePaint(_Tiles.weave(false), pd * .5, scale: .8),
        );
        canvas.drawRect(
          area,
          _wash(
            area,
            Alignment.topLeft,
            Alignment.bottomRight,
            white,
            pl * .4,
            stop: .55,
          ),
        );
    }
    canvas.restore();
    if (pane) return;
    _trim(canvas, rr, size, l, s);
  }

  void _shadow(Canvas canvas, RRect rr, FinishLook l) {
    final s = l.panelScale;
    var depth = 4 + 10 * s,
        dy = 2 + 5 * s,
        alpha = (l.light ? .14 : .32) * (.6 + .6 * s);
    var blur = depth;
    switch (l.id) {
      case 'brick':
        alpha *= 1.5;
      case 'papery':
        // A short, soft shadow, and the edge of a second sheet beneath.
        blur = 3 + 3 * s;
        dy = 1 + 1.5 * s;
        alpha = (l.light ? .10 : .25) * (.6 + .6 * s);
        canvas.drawRRect(
          rr.shift(Offset(1.5 + 1.5 * s, 2.5 + 2 * s)),
          Paint()..color = _toward(l.panel, l.palette.text, .05),
        );
        canvas.drawRRect(
          rr.shift(Offset(1.5 + 1.5 * s, 2.5 + 2 * s)).deflate(.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _toward(l.panel, l.palette.text, .2),
        );
      case 'cashmere':
        blur *= 1.6;
        alpha *= .8;
      case 'glass':
        blur *= 1.8;
        alpha *= .8;
      case 'console':
        blur *= .7;
      case 'plastic':
        // A hard ledge under the shell, as a moulded edge.
        canvas.drawRRect(
          rr.shift(Offset(0, 2 + 4 * s)),
          Paint()
            ..color = _toward(
              l.palette.background,
              Colors.black,
              l.light ? .2 : .45,
            ),
        );
    }
    canvas.drawRRect(
      rr.shift(Offset(0, dy)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha.clamp(0, .6))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
  }

  void _trim(Canvas canvas, RRect rr, Size size, FinishLook l, double s) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final pl = l.panelLight;
    switch (l.id) {
      case 'glass':
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.panel, l.palette.text, .24),
        );
        canvas.drawRRect(
          rr.deflate(1.5),
          line..color = Colors.white.withValues(alpha: pl * .5),
        );
      case 'console':
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.palette.surface, Colors.black, .45),
        );
        canvas.drawLine(
          Offset(rr.left + 3, rr.top + 1.5),
          Offset(rr.right - 3, rr.top + 1.5),
          line..color = Colors.white.withValues(alpha: pl * .6),
        );
        _screws(canvas, size);
      case 'brick':
        canvas.drawRRect(rr.deflate(.5), line..color = l.border);
      case 'denim':
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.panel, Colors.black, .3),
        );
        _stitch(
          canvas,
          rr.deflate(7),
          l.thread.withValues(alpha: .9),
          6,
          4,
          1.5,
        );
      case 'plastic':
        canvas.drawRRect(rr.deflate(.5), line..color = l.border);
        canvas.drawRRect(
          rr.deflate(1.5),
          line..color = Colors.white.withValues(alpha: pl * .8),
        );
      case 'papery':
        // A crisp hairline edge, and a pale line just inside it.
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.panel, l.palette.text, .22),
        );
        canvas.drawRRect(
          rr.deflate(1.5),
          line..color = Colors.white.withValues(alpha: .6),
        );
      case 'walnut' || 'oak':
        // The panel is set into a frame of the desk's own wood.
        canvas.drawRRect(
          rr.deflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = _toward(l.wall, l.palette.text, .0).withValues(alpha: 1),
        );
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.wall, Colors.black, .45),
        );
        canvas.drawRRect(
          rr.deflate(4.5),
          line..color = _toward(l.wall, Colors.black, .4),
        );
        canvas.drawRRect(
          rr.deflate(1.5),
          line..color = Colors.white.withValues(alpha: pl * .6),
        );
      case 'leather':
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.panel, Colors.black, .3),
        );
        _stitch(
          canvas,
          rr.deflate(8),
          l.thread.withValues(alpha: .85),
          5,
          3.5,
          1.6,
        );
      case 'marble':
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.panel, l.palette.text, .16),
        );
        canvas.drawRRect(
          rr.deflate(1.5),
          line..color = Colors.white.withValues(alpha: pl * .5),
        );
      case 'carbon':
        canvas.drawRRect(
          rr.deflate(.5),
          line..color = _toward(l.panel, Colors.black, .45),
        );
        canvas.drawRRect(
          rr.deflate(1.5),
          line..color = Colors.white.withValues(alpha: pl * .6),
        );
    }
  }

  /// A running stitch along [rr].
  void _stitch(
    Canvas c,
    RRect rr,
    Color color,
    double on,
    double off,
    double width,
  ) {
    final path = Path()..addRRect(rr);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += on + off) {
        c.drawPath(metric.extractPath(d, math.min(d + on, metric.length)), p);
      }
    }
  }

  void _screws(Canvas c, Size size) {
    const inset = 10.0, r = 3.2;
    for (final o in [
      const Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      c.drawCircle(
        o,
        r + 1.2,
        Paint()..color = Colors.white.withValues(alpha: .18),
      );
      c.drawCircle(o, r, Paint()..color = Colors.black.withValues(alpha: .55));
      c.drawCircle(
        o.translate(-.7, -.7),
        r * .55,
        Paint()..color = Colors.white.withValues(alpha: .35),
      );
      c.drawLine(
        o.translate(-r * .6, r * .6),
        o.translate(r * .6, -r * .6),
        Paint()
          ..color = Colors.black.withValues(alpha: .7)
          ..strokeWidth = .9,
      );
    }
  }

  @override
  bool shouldRepaint(FinishPanelPainter old) =>
      !identical(old.look, look) || old.radius != radius || old.pane != pane;
}
