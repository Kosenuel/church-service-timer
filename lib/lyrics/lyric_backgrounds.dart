import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';
import 'package:flutter/material.dart';

/// The slow movement a background has with Gentle motion, as in the
/// approved mockup: a slow zoom, a sideways drift, a colour shimmer, and
/// for two designs twinkling stars or rising embers over a slow zoom.
String lyricMotionOf(String background) {
  if (background.startsWith('photo:')) {
    return lyricPhotoById(background.substring(6))?.motion ?? 'zoom';
  }
  if (background.startsWith('custom:')) return 'zoom';
  return switch (background) {
    'midnight' || 'sunrise' || 'mountain_dusk' || 'royal_velvet' => 'zoom',
    'aurora' || 'stained_glass' => 'shimmer',
    'ocean' || 'forest_mist' => 'drift',
    'starry_night' => 'twinkle',
    'candlelight' => 'embers',
    _ => '',
  };
}

/// Where a picture for a background comes from: the second screen reads
/// Your picture from its file, the screens in this app from memory.
class LyricPictureSource {
  LyricPictureSource._();

  /// Your picture as read in this app, set by the lyrics controller.
  static Uint8List? bytes;
}

/// A slide's background, moving gently unless [moving] is false (Still,
/// or reduced motion). [picture] is Your picture's path on this computer,
/// for the second screen.
class LyricBackground extends StatefulWidget {
  final String id;
  final bool moving;
  final String? picture;
  const LyricBackground({
    super.key,
    required this.id,
    this.moving = true,
    this.picture,
  });

  @override
  State<LyricBackground> createState() => _LyricBackgroundState();
}

class _LyricBackgroundState extends State<LyricBackground>
    with SingleTickerProviderStateMixin {
  // Seconds, running for an hour and round again; every movement's period
  // divides an hour, so the turn is never seen.
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(hours: 1),
  );

  String get _motion => lyricMotionOf(widget.id);

  void _follow() {
    final move = widget.moving && _motion.isNotEmpty;
    if (move && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!move && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(LyricBackground old) {
    super.didUpdateWidget(old);
    _follow();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Widget _base() {
    final id = widget.id;
    ImageProvider? image;
    if (id.startsWith('photo:')) {
      final photo = lyricPhotoById(id.substring(6));
      if (photo != null) image = AssetImage(photo.asset);
    } else if (id.startsWith('custom:')) {
      final path = widget.picture;
      if (path != null && File(path).existsSync()) {
        image = FileImage(File(path));
      } else if (LyricPictureSource.bytes != null) {
        image = MemoryImage(LyricPictureSource.bytes!);
      }
    }
    if (image != null) {
      return Image(
        image: image,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _drawn(lyricPictureStandIn),
      );
    }
    final drawn = lyricDrawnBackgrounds.containsKey(id)
        ? id
        : lyricPictureStandIn;
    return _drawn(drawn);
  }

  Widget _drawn(String id) => CustomPaint(
    painter: LyricBackgroundPainter(id),
    child: const SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) {
    final base = RepaintBoundary(child: _base());
    final motion = _motion;
    if (motion.isEmpty) return ClipRect(child: base);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, space) => AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final t = widget.moving ? _clock.value * 3600 : 0.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                _moved(motion, t, space.biggest, base),
                if (motion == 'twinkle' || motion == 'embers')
                  CustomPaint(
                    painter: LyricParticlesPainter(motion, t, widget.moving),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// A back-and-forth over [period] seconds, eased at both ends, from 0
  /// to 1 and back, as CSS's `ease-in-out infinite alternate`.
  static double swing(double t, double period) {
    final p = (t / period) % 2;
    final x = p <= 1 ? p : 2 - p;
    return Curves.easeInOut.transform(x);
  }

  Widget _moved(String motion, double t, Size size, Widget base) {
    switch (motion) {
      case 'drift':
        final p = swing(t, 22);
        // The layer is 16% wider than the screen and moves across it.
        final scale = 1.02 + .04 * p;
        final dx = (-.06 + .12 * p) * size.width * 1.16;
        return OverflowBox(
          maxWidth: size.width * 1.16,
          minWidth: size.width * 1.16,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(dx, 0, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
            child: base,
          ),
        );
      case 'shimmer':
        final p = swing(t, 16);
        final scale = 1.05 + .15 * p;
        final turn = (-1.5 + 3 * p) * math.pi / 180;
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(
            _hueBrightness(-18 + 40 * p, .95 + .15 * p),
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..rotateZ(turn)
              ..scaleByDouble(scale, scale, 1, 1),
            child: base,
          ),
        );
      default:
        // A slow zoom, also under stars and embers.
        final p = swing(t, 28);
        final scale = 1 + .12 * p;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(
              -.015 * p * size.width,
              -.01 * p * size.height,
              0,
              1,
            )
            ..scaleByDouble(scale, scale, 1, 1),
          child: base,
        );
    }
  }

  /// CSS's `hue-rotate(deg) brightness(b)` as a colour matrix.
  static List<double> _hueBrightness(double degrees, double b) {
    final a = degrees * math.pi / 180, c = math.cos(a), s = math.sin(a);
    final m = [
      .213 + c * .787 - s * .213,
      .715 - c * .715 - s * .715,
      .072 - c * .072 + s * .928,
      .213 - c * .213 + s * .143,
      .715 + c * .285 + s * .140,
      .072 - c * .072 - s * .283,
      .213 - c * .213 - s * .787,
      .715 - c * .715 + s * .715,
      .072 + c * .928 + s * .072,
    ];
    return [
      m[0] * b, m[1] * b, m[2] * b, 0, 0, //
      m[3] * b, m[4] * b, m[5] * b, 0, 0,
      m[6] * b, m[7] * b, m[8] * b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// Twinkling stars or rising embers, laid over their background. The
/// same pseudo-random places as the mockup and the web page.
class LyricParticlesPainter extends CustomPainter {
  final String kind;
  final double t;
  final bool moving;
  LyricParticlesPainter(this.kind, this.t, this.moving);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final twinkle = kind == 'twinkle';
    var x = 11;
    for (var k = 0; k < (twinkle ? 26 : 12); k++) {
      x = (x * 61 + 17) % 991;
      final delay = -(x % 90) / 10;
      final left = (x % 100) / 100 * w;
      if (twinkle) {
        final top = ((x * 7) % 70) / 100 * h;
        final r = (.5 + (k % 3) * .25) / 100 * w / 2;
        // 3.2 s: dim, bright, dim. Held half lit when still.
        final phase = moving ? ((t - delay) % 3.2) / 3.2 : .25;
        final o = .1 + .85 * (1 - (2 * phase - 1).abs());
        canvas.drawCircle(
          Offset(left, top),
          r,
          Paint()..color = Colors.white.withValues(alpha: o.clamp(0, 1)),
        );
      } else {
        if (!moving) continue;
        final top = (60 + (x % 35)) / 100 * h;
        final d = (2 + (k % 4)) / 100 * w;
        final p = ((t - delay) % 9) / 9;
        final o = p < .15 ? p / .15 * .8 : .8 * (1 - (p - .15) / .85);
        final scale = .7 + .55 * p;
        final c = Offset(left + d / 2, top + d / 2 - .45 * w * p);
        final r = d / 2 * scale;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
              c,
              r,
              [
                Color.fromRGBO(255, 214, 150, .9 * o),
                Color.fromRGBO(255, 170, 80, 0),
              ],
              [0, .7],
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(LyricParticlesPainter old) =>
      old.t != t || old.kind != kind || old.moving != moving;
}

/// The twelve drawn designs. Shapes are drawn on a 160 × 90 grid
/// stretched to the screen, as the mockup's pictures are.
class LyricBackgroundPainter extends CustomPainter {
  final String id;
  const LyricBackgroundPainter(this.id);

  static Color _c(int rgb, [double a = 1]) =>
      Color(0xff000000 | rgb).withValues(alpha: a);

  /// A vertical gradient over the whole grid: [a] to [b] (to [c], with
  /// [b] at 60%).
  static void _vertical(Canvas canvas, int a, int b, [int? c]) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 160, 90),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 90), [
          _c(a),
          _c(b),
          if (c != null) _c(c),
        ], c == null ? [0, 1] : [0, .6, 1]),
    );
  }

  /// A path from the mockup's SVG commands (M, L, Q, T, V, H, Z).
  static Path _path(String d) {
    final path = Path();
    final tokens = RegExp(
      r'[MLQTVHZ]|-?\d*\.?\d+',
    ).allMatches(d).map((m) => m[0]!).toList();
    var i = 0;
    var cmd = 'M';
    var cur = Offset.zero, control = Offset.zero;
    double n() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      if (RegExp(r'[A-Z]').hasMatch(tokens[i])) cmd = tokens[i++];
      switch (cmd) {
        case 'M':
          cur = Offset(n(), n());
          path.moveTo(cur.dx, cur.dy);
          cmd = 'L';
        case 'L':
          cur = Offset(n(), n());
          path.lineTo(cur.dx, cur.dy);
        case 'Q':
          control = Offset(n(), n());
          cur = Offset(n(), n());
          path.quadraticBezierTo(control.dx, control.dy, cur.dx, cur.dy);
        case 'T':
          control = cur * 2 - control;
          cur = Offset(n(), n());
          path.quadraticBezierTo(control.dx, control.dy, cur.dx, cur.dy);
        case 'V':
          cur = Offset(cur.dx, n());
          path.lineTo(cur.dx, cur.dy);
        case 'H':
          cur = Offset(n(), cur.dy);
          path.lineTo(cur.dx, cur.dy);
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  static void _fill(Canvas canvas, String d, int rgb, [double a = 1]) =>
      canvas.drawPath(_path(d), Paint()..color = _c(rgb, a));

  /// CSS's `radial-gradient(rx ry at cx cy, …)`, in fractions of the
  /// screen, over the whole screen.
  static void _glow(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double rx,
    double ry,
    List<Color> colors,
    List<double> stops,
  ) {
    canvas.save();
    canvas.translate(cx * size.width, cy * size.height);
    canvas.scale(rx * size.width, ry * size.height);
    canvas.drawRect(
      Rect.fromLTRB(-cx / rx, -cy / ry, (1 - cx) / rx, (1 - cy) / ry),
      Paint()..shader = ui.Gradient.radial(Offset.zero, 1, colors, stops),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    void grid(void Function() draw) {
      canvas.save();
      canvas.scale(w / 160, h / 90);
      draw();
      canvas.restore();
    }

    const clear = Color(0x00000000);
    switch (id) {
      case 'midnight':
        _glow(
          canvas,
          size,
          .5,
          1.1,
          1.2,
          .9,
          [_c(0x24407a), _c(0x0a1330), _c(0x05081a)],
          [0, .6, 1],
        );
      case 'aurora':
        canvas.drawRect(all, Paint()..color = _c(0x06121c));
        _glow(
          canvas,
          size,
          .2,
          .3,
          .6,
          .5,
          [_c(0x48dda0, .75), clear],
          [0, .7],
        );
        _glow(
          canvas,
          size,
          .78,
          .22,
          .55,
          .55,
          [_c(0x786eff, .7), clear],
          [0, .7],
        );
        _glow(
          canvas,
          size,
          .55,
          .9,
          .7,
          .5,
          [_c(0x1ea0be, .6), clear],
          [0, .7],
        );
      case 'sunrise':
        grid(() {
          _vertical(canvas, 0x2a2f6b, 0xe9746a, 0xffc27a);
          canvas.drawCircle(
            const Offset(80, 74),
            16,
            Paint()..color = _c(0xffe3a6, .9),
          );
          _fill(canvas, 'M0 78 Q40 70 80 76 T160 72 V90 H0Z', 0x3a2350);
        });
      case 'mountain_dusk':
        grid(() {
          _vertical(canvas, 0x1b2550, 0x7a5a8c, 0xf0a077);
          _fill(
            canvas,
            'M0 62 L28 40 L46 54 L70 30 L98 58 L120 42 L160 64 V90 H0Z',
            0x4a3f6b,
          );
          _fill(
            canvas,
            'M0 72 L22 58 L50 70 L84 52 L112 70 L138 60 L160 72 V90 H0Z',
            0x2c2748,
          );
          _fill(
            canvas,
            'M0 82 L40 72 L80 82 L120 74 L160 82 V90 H0Z',
            0x17152b,
          );
        });
      case 'starry_night':
        grid(() {
          _vertical(canvas, 0x040716, 0x0f1f4a);
          var x = 7;
          for (var i = 0; i < 70; i++) {
            x = (x * 73 + 41) % 997;
            final y = (x * 31 + i * 17) % 90;
            final r = i % 5 == 0 ? .5 : .25;
            // A star is round whatever the screen's shape.
            canvas.save();
            canvas.translate((x % 160).toDouble(), y.toDouble());
            canvas.scale(1, (w / 160) / (h / 90));
            canvas.drawCircle(
              Offset.zero,
              r,
              Paint()
                ..color = Colors.white.withValues(alpha: .4 + (i % 4) * .15),
            );
            canvas.restore();
          }
        });
      case 'candlelight':
        canvas.drawRect(all, Paint()..color = _c(0x1a0e06));
        for (final (cx, cy, rx, ry, rgb, a) in const [
          (.18, .7, .18, .3, 0xffbe5a, .75),
          (.4, .3, .14, .24, 0xffa046, .55),
          (.72, .62, .2, .34, 0xffcd78, .65),
          (.88, .22, .12, .2, 0xffaa50, .5),
          (.58, .84, .1, .18, 0xffdc96, .5),
        ]) {
          _glow(canvas, size, cx, cy, rx, ry, [_c(rgb, a), clear], [0, .7]);
        }
      case 'ocean':
        grid(() {
          _vertical(canvas, 0x0b2a4a, 0x2f7fa8);
          _fill(
            canvas,
            'M0 58 Q20 52 40 58 T80 58 T120 58 T160 58 V90 H0Z',
            0x1f6690,
            .8,
          );
          _fill(
            canvas,
            'M0 68 Q20 62 40 68 T80 68 T120 68 T160 68 V90 H0Z',
            0x144d74,
          );
          _fill(
            canvas,
            'M0 79 Q20 74 40 79 T80 79 T120 79 T160 79 V90 H0Z',
            0x0b3355,
          );
        });
      case 'forest_mist':
        grid(() {
          _vertical(canvas, 0xb9cfc6, 0x4f7268);
          _fill(
            canvas,
            'M0 60 Q30 44 60 58 T120 52 T160 58 V90 H0Z',
            0x3e6259,
            .7,
          );
          _fill(canvas, 'M0 72 Q40 58 80 70 T160 66 V90 H0Z', 0x27463f);
          _fill(canvas, 'M0 84 Q50 74 100 82 T160 80 V90 H0Z', 0x132a25);
        });
      case 'stained_glass':
        // CSS's conic gradient starts at the top; Flutter's at the right.
        final centre = Offset(.3 * w, .4 * h);
        canvas.drawRect(
          all,
          Paint()
            ..shader = ui.Gradient.sweep(
              centre,
              [
                _c(0x7a1f3d),
                _c(0xb9462f),
                _c(0xd9a23a),
                _c(0x2f7d5b),
                _c(0x24508f),
                _c(0x5a2f86),
                _c(0x7a1f3d),
              ],
              [0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1],
              TileMode.clamp,
              0,
              2 * math.pi,
              _rotationAbout(centre, (20 - 90) * math.pi / 180),
            ),
        );
      case 'royal_velvet':
        _glow(
          canvas,
          size,
          .5,
          0,
          .9,
          1.2,
          [_c(0x6b2fa0), _c(0x2a0f4a), _c(0x12051f)],
          [0, .6, 1],
        );
      case 'linen':
        canvas.drawRect(all, Paint()..color = _c(0xefe9dc));
        // A fine weave: a faint line every 3 px each way, as in CSS.
        final step = math.max(3.0, w / 640);
        final line = Paint()..color = const Color(0x09000000);
        for (var y = 0.0; y < h; y += step) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, step / 3), line);
        }
        for (var x = 0.0; x < w; x += step) {
          canvas.drawRect(Rect.fromLTWH(x, 0, step / 3, h), line);
        }
      default:
        canvas.drawRect(all, Paint()..color = Colors.black);
    }
  }

  static Float64List _rotationAbout(Offset c, double angle) =>
      (Matrix4.identity()
            ..translateByDouble(c.dx, c.dy, 0, 1)
            ..rotateZ(angle)
            ..translateByDouble(-c.dx, -c.dy, 0, 1))
          .storage;

  @override
  bool shouldRepaint(LyricBackgroundPainter old) => old.id != id;
}
