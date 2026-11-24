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

  /// More colours the wall is lit with besides [wallMat], each mixed in up
  /// to [wallMix] at the middle of a soft field of light (Glass).
  final List<Color Function(AppPalette)> wallFields;
  const _Spec({
    this.wallFields = const [],
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
Color Function(AppPalette) _by(Color dark, Color light) =>
    (p) => p.light ? light : dark;

/// A light the colour of the accent turned round the colour wheel by
/// [degrees], about as bright as the background: colour changes the look of
/// the wall far more than brightness does, and leaves the words on it as
/// readable as on the background itself.
Color Function(AppPalette) _glow(double degrees) => (p) {
  final h = HSLColor.fromColor(p.accent);
  final hue = (h.hue + degrees) % 360;
  final bg = p.background.computeLuminance();
  final want = p.light ? bg * .9 : math.max(bg * 6, bg + .06);
  var lo = 0.0, hi = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    final l = HSLColor.fromAHSL(1, hue, .75, mid).toColor().computeLuminance();
    if (l < want) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return HSLColor.fromAHSL(1, hue, .75, lo).toColor();
};

final _specs = <String, _Spec>{
  // Glass: frosted panes over soft fields of coloured light. The wall is
  // drawn once, and so is a blurred copy of it that each pane shows through
  // itself, so a pane looks as if it blurs what is behind it with no
  // backdrop blur at all (which would cost a full-screen pass for every
  // pane, every frame).
  'glass': _Spec(
    wallMat: _glow(0),
    wallFields: [_glow(70), _glow(-80)],
    wallMix: .85,
    wallLight: 0,
    wallDark: 0,
    panelMat: _surface,
    panelMix: 0,
    panelLight: 0.21,
    panelDark: 0.06,
    panelAlpha: .55,
  ),
  // Papery: a warm sheet with a fine tooth, and brighter sheets stacked on
  // it. Only for the Paper & Ink themes (see paperyThemeIds); the panel stays
  // the theme's own white, so its ink keeps its full contrast.
  'papery': _Spec(
    wallMat: _by(const Color(0xffe3d9c2), const Color(0xffe3d9c2)),
    wallMix: .7,
    wallLight: .08,
    wallDark: .13,
    panelMat: _surface,
    panelMix: 0,
    panelLight: .02,
    panelDark: .035,
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
    wallLight: 0.06,
    wallDark: 0.08,
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

  /// Glass: the colours at the middle of each field of light on the wall
  /// (the first is [wall]); empty for the other finishes.
  final List<Color> wallFields;

  /// How far the texture may go toward white and black, at this scale.
  final double wallLight, wallDark, panelLight, panelDark, panelAlpha;

  /// Every colour a pixel of the wall or a panel can have: the base and the
  /// base pushed to each end of its budget. Text must read on all of them.
  final List<Color> wallSamples, panelSamples;

  /// Whether this is the look of a small card set into a panel ([card]).
  final bool isCard;
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
    this.wallFields = const [],
    required this.wallLight,
    required this.wallDark,
    required this.panelLight,
    required this.panelDark,
    required this.panelAlpha,
    required this.wallSamples,
    required this.panelSamples,
    this.isCard = false,
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
    final fields = [
      if (spec.wallFields.isNotEmpty) wall,
      for (final f in spec.wallFields)
        toward(p.background, f(p), spec.wallMix * ws),
    ];
    final wl = spec.wallLight * ws, wd = spec.wallDark * ws;
    final pl = spec.panelLight * ps, pd = spec.panelDark * ps;
    final panel = toward(p.surface, panelMat, spec.panelMix * ps);
    // Glass shows the wall through its panels, so a panel is its colour laid
    // over each colour the wall can have; as the scale falls the panel turns
    // solid, so at none it is the plain surface.
    final alpha = 1 - (1 - spec.panelAlpha) * ps;
    final under = alpha < 1
        ? [p.background, wall, ...fields.skip(1)]
        : [Colors.transparent];
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
      // Thread that suits the cloth: the gold of jeans, the cream of a
      // saddler's waxed linen.
      thread: switch ((id, p.light)) {
        ('leather', false) => const Color(0xffe8d6b0),
        ('leather', true) => const Color(0xff7a5434),
        (_, false) => const Color(0xffe0a64e),
        _ => const Color(0xffa8701f),
      },
      wallFields: fields,
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
        ...fields.skip(1),
      ],
      panelSamples: panelSamples,
    );
  }

  static final _cards = Expando<FinishLook>();

  /// A small card set into a panel (a hint, a group of settings): the same
  /// material as the panel, a step darker and calmer, so it reads as a
  /// separate piece set into the panel and not as a second sheet on it. As
  /// dark and as textured as it can be, up to that step, while the theme's
  /// text, muted text and accent still read on every colour it can have,
  /// as on a panel. Glass's card is a solid frosted plate: a pane in a pane
  /// would show the wall twice. Flat and a card are their own card.
  FinishLook get card {
    if (!active || isCard) return this;
    return _cards[this] ??= () {
      Color toward(Color c, Color to, double t) => Color.lerp(c, to, t)!;
      // Darker on a dark theme; on a pale one darker is toward the ink, so
      // only a little.
      final steps = light
          ? const [.06, .04, .02, 0.0]
          : const [.16, .12, .08, .04, 0.0];
      // Glass's panel colour is its pane over the wall, as a solid.
      final base = panel;
      FinishLook? last;
      for (final k in steps) {
        for (final share in const [.6, .45, .3, 0.0]) {
          final c = toward(base, Colors.black, k);
          final pl = panelLight * share, pd = panelDark * share;
          final look = FinishLook._(
            id: id,
            strength: strength,
            wallScale: wallScale,
            panelScale: panelScale * share,
            palette: palette,
            wall: wall,
            panel: c,
            wallMaterial: wallMaterial,
            panelMaterial: panelMaterial,
            thread: thread,
            wallFields: wallFields,
            wallLight: wallLight,
            wallDark: wallDark,
            panelLight: pl,
            panelDark: pd,
            panelAlpha: 1,
            wallSamples: wallSamples,
            panelSamples: [
              c,
              toward(c, Colors.white, pl),
              toward(c, Colors.black, pd),
            ],
            isCard: true,
          );
          last = look;
          if (look._panelLegible()) return look;
        }
      }
      return last!;
    }();
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
