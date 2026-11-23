import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The colours a stage screen draws its clock (and, with the countdown
/// layouts, its time) in: the host's theme, as the stage snapshot carries
/// it in `stageTheme`. A host from before this sends none, and the screen
/// then keeps to the look it always had: white on black.
class StageColors {
  final Color background, surface, accent, muted, text;
  const StageColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.muted,
    required this.text,
  });

  /// White on black, as stage screens were before they followed the theme.
  static const classic = StageColors(
    background: Color(0xff000000),
    surface: Color(0xff141414),
    accent: Color(0xffffffff),
    muted: Color(0xffb3b3b3),
    text: Color(0xffffffff),
  );

  /// The theme in [data], or [classic] when it has none or it is not
  /// colours: every colour is a checked "#rrggbb".
  factory StageColors.of(Json data) {
    final theme = stageThemeOf(data);
    if (theme == null) return classic;
    Color read(String key) =>
        Color(0xff000000 | int.parse(theme[key]!.substring(1), radix: 16));
    return StageColors(
      background: read('background'),
      surface: read('surface'),
      accent: read('accent'),
      muted: read('muted'),
      text: read('text'),
    );
  }

  /// The theme as a stage snapshot carries it.
  static Json fieldsOf(AppPalette p) => {
    'background': stageColorHex(p.background.toARGB32()),
    'surface': stageColorHex(p.surface.toARGB32()),
    'accent': stageColorHex(p.accent.toARGB32()),
    'muted': stageColorHex(p.muted.toARGB32()),
    'text': stageColorHex(p.text.toARGB32()),
  };

  bool get light => background.computeLuminance() > .179;

  // A flip card shades from a little lighter at the top to a little darker
  // at the bottom. They are worked out from the theme, so a light theme
  // gets light cards and a dark one dark cards.
  Color get cardTop => Color.lerp(surface, text, .06)!;
  Color get cardBottom => Color.lerp(surface, background, .35)!;

  /// The line between a card's halves: darker than the screen on a dark
  /// theme, and a shade of the digits on a light one, where black would
  /// be harsh.
  Color get hinge => light
      ? Color.lerp(background, text, .30)!
      : Color.lerp(background, Colors.black, .30)!;

  /// The AM and PM tile that is not lit, and its edge.
  Color get tileOff => Color.lerp(background, text, .06)!;
  Color get tileLine => Color.lerp(background, text, .14)!;

  /// Words on the lit tile (the accent): whichever of near-black and white
  /// reads better on it.
  Color get onAccent =>
      contrast(const Color(0xff10150a), accent) >=
          contrast(Colors.white, accent)
      ? const Color(0xff10150a)
      : Colors.white;
}

/// The colour a stage screen's own area is painted: the theme's background
/// where the snapshot shows the clock, black as ever otherwise (cues and
/// messages have their own backgrounds).
Color stageBackdropOf(Json? data) {
  if (data == null ||
      data['stageSharing'] == false ||
      data['blank'] == true ||
      data['quickMessage'] is Map) {
    return Colors.black;
  }
  final under = stageBannerPosition(data) == null
      ? data
      : stageUnderBanner(data);
  if (stageShowsClock(under) && stageClockFace(under) != null) {
    return StageColors.of(data).background;
  }
  return Colors.black;
}
