import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// What a finish is made of, before the theme's colours are mixed in.
///
/// Every finish builds its background (the wall) and its panels from the
/// theme's own colours plus a material colour, and may lay light and dark
/// texture over them. How much of each is allowed is a budget: a texture
/// never moves a pixel further than its budget from the base colour, so the
/// worst-case colour under any word is known, and [FinishLook] shrinks the
/// whole finish until the theme's text, muted text and accent still read on
/// that worst case. That holds for every built-in theme and for custom ones.
class _Spec {
  /// The wall: the theme's background mixed with [wallMat] by [wallMix], then
  /// up to [wallLight] toward white and [wallDark] toward black.
  final Color Function(AppPalette) wallMat;
  final double wallMix, wallLight, wallDark;

  /// The same for a panel, from the theme's surface.
  final Color Function(AppPalette) panelMat;
  final double panelMix, panelLight, panelDark;

  /// How much of a panel is its own colour; below 1 the wall shows through
  /// (Glass).
  final double panelAlpha;
  const _Spec({
    required this.wallMat,
    required this.wallMix,
    required this.wallLight,
    required this.wallDark,
    required this.panelMat,
    required this.panelMix,
    required this.panelLight,
    required this.panelDark,
    this.panelAlpha = 1,
  });
}

Color _surface(AppPalette p) => p.surface;
Color _text(AppPalette p) => p.text;
Color _accent(AppPalette p) => p.accent;
Color Function(AppPalette) _by(Color dark, Color light) =>
    (p) => p.light ? light : dark;

final _specs = <String, _Spec>{
  // Glass is a translucent panel over a soft glow, with no backdrop blur: the
  // wall behind it is a smooth gradient, where a blur would change nothing
  // you could see, and a blur costs a full-screen pass for every panel on a
  // phone. So it is cheap on every device, with nothing to fall back from.
  'glass': _Spec(
    wallMat: _accent,
    wallMix: .85,
    wallLight: 0,
    wallDark: 0,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.21,
    panelDark: 0.06,
    panelAlpha: .72,
  ),
  'console': _Spec(
    wallMat: _by(const Color(0xff7d868e), const Color(0xffaab2b9)),
    wallMix: .42,
    wallLight: 0.18,
    wallDark: 0.21,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.24,
    panelDark: 0.24,
  ),
  'brick': _Spec(
    wallMat: _by(const Color(0xff8f3f2a), const Color(0xffb9583c)),
    wallMix: .7,
    wallLight: 0.27,
    wallDark: 0.3,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.075,
    panelDark: 0.105,
  ),
  'cashmere': _Spec(
    wallMat: _surface,
    wallMix: .55,
    wallLight: 0.135,
    wallDark: 0.135,
    panelMat: _text,
    panelMix: .04,
    panelLight: 0.135,
    panelDark: 0.12,
  ),
  'denim': _Spec(
    wallMat: _by(const Color(0xff2f5186), const Color(0xff7f9fcf)),
    wallMix: .68,
    wallLight: 0.18,
    wallDark: 0.15,
    panelMat: _by(const Color(0xff2f5186), const Color(0xff7f9fcf)),
    panelMix: .30,
    panelLight: 0.15,
    panelDark: 0.12,
  ),
  'plastic': _Spec(
    wallMat: _text,
    wallMix: .07,
    wallLight: 0,
    wallDark: 0.06,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.24,
    panelDark: 0.3,
  ),
  'walnut': _Spec(
    wallMat: _by(const Color(0xff5f3c22), const Color(0xffc39763)),
    wallMix: .8,
    wallLight: 0.15,
    wallDark: 0.3,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.12,
    panelDark: 0.075,
  ),
  'oak': _Spec(
    wallMat: _by(const Color(0xff9c7a48), const Color(0xffe0c08a)),
    wallMix: .72,
    wallLight: 0.18,
    wallDark: 0.21,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.12,
    panelDark: 0.075,
  ),
  'leather': _Spec(
    wallMat: _by(const Color(0xff7a4a2c), const Color(0xffc08a5a)),
    wallMix: .62,
    wallLight: 0.15,
    wallDark: 0.24,
    panelMat: _by(const Color(0xff7a4a2c), const Color(0xffc08a5a)),
    panelMix: .16,
    panelLight: 0.105,
    panelDark: 0.27,
  ),
  'marble': _Spec(
    wallMat: _by(const Color(0xffc8cdd2), const Color(0xfffdfdfb)),
    wallMix: .28,
    wallLight: 0.18,
    wallDark: 0.18,
    panelMat: _by(const Color(0xffc8cdd2), const Color(0xfffdfdfb)),
    panelMix: .08,
    panelLight: 0.15,
    panelDark: 0.09,
  ),
  'carbon': _Spec(
    wallMat: _by(const Color(0xff3a3d42), const Color(0xff8b9097)),
    wallMix: .6,
    wallLight: 0.18,
    wallDark: 0.21,
    panelMat: _by(const Color(0xff3a3d42), const Color(0xff8b9097)),
    panelMix: .28,
    panelLight: 0.15,
    panelDark: 0.15,
  ),
};

/// The contrast ratios a finish must keep wherever words sit: body text on a
/// panel, muted text and the accent on a panel (as good as the plain theme
/// gives, up to 4.5), and on the bare wall (a title or a button outside any
/// panel, which the layouts keep rare) body text the same and muted text and
/// the accent at 3:1, the bar for large text.
({
  double text,
  double muted,
  double accent,
  double wallMuted,
  double wallAccent,
})
finishBars(AppPalette p) => (
  text: math.min(4.5, contrast(p.text, p.surface)),
  muted: math.min(4.5, contrast(p.muted, p.surface)),
  accent: math.min(4.5, contrast(p.accent, p.surface)),
  wallMuted: math.min(3, contrast(p.muted, p.background)),
  wallAccent: math.min(3, contrast(p.accent, p.background)),
);

/// A finish resolved for one theme: the colours and texture budgets that the
/// painters in finish_paint.dart and the widgets in finish_widgets.dart use.
/// Flat is the app as it was, and draws nothing of its own.
@immutable
class FinishLook extends ThemeExtension<FinishLook> {
  final String id;

  /// The strength asked for (.5 Subtle, 1 Full) and the scale drawn for the
  /// wall and for panels, each lower when this theme could not keep its text
  /// legible at that strength (a pale theme has less room to darken).
  final double strength, wallScale, panelScale;
  final AppPalette palette;

  /// The base colour of the background and of a panel (opaque, as a solid
  /// stand-in for bars and fallbacks).
  final Color wall, panel;

  /// The material colour, for painters that draw it (bricks, thread).
  final Color wallMaterial, panelMaterial, thread;

  /// How far the texture may go toward white and black, at this scale.
  final double wallLight, wallDark, panelLight, panelDark, panelAlpha;

  /// Every colour a pixel of the wall or a panel can have: the base and the
  /// base pushed to each end of its budget. Text must read on all of them.
  final List<Color> wallSamples, panelSamples;
  const FinishLook._({
    required this.id,
    required this.strength,
    required this.wallScale,
    required this.panelScale,
    required this.palette,
    required this.wall,
    required this.panel,
    required this.wallMaterial,
    required this.panelMaterial,
    required this.thread,
    required this.wallLight,
    required this.wallDark,
    required this.panelLight,
    required this.panelDark,
    required this.panelAlpha,
    required this.wallSamples,
    required this.panelSamples,
  });

  bool get active => id != 'flat';
  bool get light => palette.light;

  /// Toward the colour of the text: where a highlight or a knit line may go
  /// without being a stronger mark than the words themselves.
  Color get ink => light ? Colors.black : Colors.white;
  Color get border => Color.lerp(panel, palette.text, light ? .20 : .14)!;

  static const flatId = 'flat';

  factory FinishLook.flat(AppPalette p) => FinishLook._(
    id: flatId,
    strength: 0,
    wallScale: 0,
    panelScale: 0,
    palette: p,
    wall: p.background,
    panel: p.surface,
    wallMaterial: p.background,
    panelMaterial: p.surface,
    thread: p.accent,
    wallLight: 0,
    wallDark: 0,
    panelLight: 0,
    panelDark: 0,
    panelAlpha: 1,
    wallSamples: [p.background],
    panelSamples: [p.surface],
  );

  static final _cache = <String, FinishLook>{};

  /// [id] at [strength] for [p]; Flat when [id] is Flat or the theme is the
  /// High contrast one.
  factory FinishLook.resolve(AppPalette p, String id, double strength) {
    final spec = _specs[id];
    if (spec == null || p.highContrast) return FinishLook.flat(p);
    final key = '${p.id}|${p.light}|$id|$strength';
    final cached = _cache[key];
    if (cached != null) return cached;
    // The wall first (Glass shows it through its panels), then the panels,
    // each as strong as it can be while text still reads on it.
    // The limit is found from the top, so Subtle is never stronger than Full.
    var ws = 1.0;
    while (ws > 0 && !_build(p, id, spec, strength, ws, 0)._wallLegible()) {
      ws = ((ws * 20).round() - 1) / 20;
    }
    var ps = 1.0;
    while (ps > 0 && !_build(p, id, spec, strength, ws, ps)._panelLegible()) {
      ps = ((ps * 20).round() - 1) / 20;
    }
    ws = math.min(ws, strength);
    ps = math.min(ps, strength);
    if (_cache.length > 200) _cache.clear();
    return _cache[key] = _build(p, id, spec, strength, ws, ps);
  }

  static FinishLook _build(
    AppPalette p,
    String id,
    _Spec spec,
    double strength,
    double ws,
    double ps,
  ) {
    Color toward(Color c, Color to, double t) => Color.lerp(c, to, t)!;
    final wallMat = spec.wallMat(p), panelMat = spec.panelMat(p);
    final wall = toward(p.background, wallMat, spec.wallMix * ws);
    final wl = spec.wallLight * ws, wd = spec.wallDark * ws;
    final pl = spec.panelLight * ps, pd = spec.panelDark * ps;
    final panel = toward(p.surface, panelMat, spec.panelMix * ps);
    // Glass shows the wall through its panels, so a panel is its colour laid
    // over each colour the wall can have; as the scale falls the panel turns
    // solid, so at none it is the plain surface.
    final alpha = 1 - (1 - spec.panelAlpha) * ps;
    final under = alpha < 1 ? [p.background, wall] : [Colors.transparent];
    final panelSamples = <Color>[];
    for (final u in under) {
      final base = alpha < 1
          ? Color.alphaBlend(panel.withValues(alpha: alpha), u)
          : panel;
      panelSamples
        ..add(base)
        ..add(toward(base, Colors.white, pl))
        ..add(toward(base, Colors.black, pd));
    }
    return FinishLook._(
      id: id,
      strength: strength,
      wallScale: ws,
      panelScale: ps,
      palette: p,
      wall: wall,
      panel: alpha < 1 ? panelSamples.first : panel,
      wallMaterial: wallMat,
      panelMaterial: panelMat,
      thread: p.light ? const Color(0xff9a6a2c) : const Color(0xffe2b35e),
      wallLight: wl,
      wallDark: wd,
      panelLight: pl,
      panelDark: pd,
      panelAlpha: alpha,
      wallSamples: [
        wall,
        toward(wall, Colors.white, wl),
        toward(wall, Colors.black, wd),
        if (alpha < 1) p.background,
      ],
      panelSamples: panelSamples,
    );
  }

  bool _panelLegible() {
    final p = palette, bars = finishBars(p);
    for (final c in panelSamples) {
      if (contrast(p.text, c) < bars.text ||
          contrast(p.muted, c) < bars.muted ||
          contrast(p.accent, c) < bars.accent) {
        return false;
      }
    }
    return true;
  }

  bool _wallLegible() {
    final p = palette, bars = finishBars(p);
    for (final c in wallSamples) {
      if (contrast(p.text, c) < bars.text ||
          contrast(p.muted, c) < bars.wallMuted ||
          contrast(p.accent, c) < bars.wallAccent) {
        return false;
      }
    }
    return true;
  }

  @override
  FinishLook copyWith() => this;
  @override
  FinishLook lerp(covariant FinishLook? other, double t) =>
      t < .5 ? this : other ?? this;
}

/// The look drawn now: Flat when the theme has none.
FinishLook finishLook(BuildContext context) =>
    Theme.of(context).extension<FinishLook>() ??
    FinishLook.flat(appColors(context));
