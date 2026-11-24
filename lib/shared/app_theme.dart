import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:church_service_timer/domain/domain.dart'
    show
        AppearancePreferences,
        effectiveFinish,
        finishStrengthFor,
        stageCardBackground,
        desktopLayoutMinHeight,
        desktopLayoutMinWidth,
        effectiveDesktopLayout;

String densityName(String value) => switch (value) {
  'comfortable' => 'Comfortable',
  'spacious' => 'Spacious',
  'automatic' => 'Automatic',
  _ => 'Compact',
};

class AppLayout extends ThemeExtension<AppLayout> {
  final AppearancePreferences preferences;
  final String density;
  const AppLayout(this.preferences, this.density);
  factory AppLayout.resolve(AppearancePreferences preferences, Size size) {
    // Phones get Comfortable: larger touch targets for one-handed use
    // under time pressure, while a full rundown still fits.
    // A desktop layout packs three panes into the window, so it keeps to
    // Comfortable where a single column would stretch to Spacious.
    final desktop =
        effectiveDesktopLayout(preferences.desktopLayout) != 'classic' &&
        size.width >= desktopLayoutMinWidth &&
        size.height >= desktopLayoutMinHeight;
    // The Keys layout is the dense one.
    final automatic = desktop && preferences.desktopLayout == 'keys'
        ? 'compact'
        : size.shortestSide < 600 || desktop
        ? 'comfortable'
        : size.width >= 1000 && size.height >= 700
        ? 'spacious'
        : 'comfortable';
    return AppLayout(
      preferences,
      preferences.density == 'automatic' ? automatic : preferences.density,
    );
  }
  double get rowPadding => switch (density) {
    'spacious' => 20,
    'comfortable' => 14,
    _ => 10,
  };
  double get tilePadding => switch (density) {
    'spacious' => 10,
    'comfortable' => 5,
    _ => 0,
  };
  double get panelPadding => switch (density) {
    'spacious' => 28,
    'comfortable' => 24,
    _ => 20,
  };
  double get controlHeight => switch (density) {
    'spacious' => 60,
    'comfortable' => 54,
    _ => 50,
  };
  double get gap => switch (density) {
    'spacious' => 16,
    'comfortable' => 12,
    _ => 8,
  };
  EdgeInsets get rowInsets =>
      EdgeInsets.symmetric(horizontal: 16, vertical: rowPadding);
  EdgeInsets get tileInsets =>
      EdgeInsets.symmetric(horizontal: 16, vertical: tilePadding);
  @override
  AppLayout copyWith() => this;
  @override
  AppLayout lerp(covariant AppLayout? other, double t) =>
      t < .5 ? this : other ?? this;
}

AppLayout appLayout(BuildContext context) =>
    Theme.of(context).extension<AppLayout>() ??
    const AppLayout(AppearancePreferences(), 'compact');
bool reduceAppMotion(BuildContext context) =>
    appLayout(context).preferences.reducedMotion ||
    MediaQuery.disableAnimationsOf(context);

/// Hidden removes decorative rules, but never a destructive-action separator.
class AppDivider extends StatelessWidget {
  final double indent, endIndent;
  final bool essential;
  const AppDivider({
    super.key,
    this.indent = 16,
    this.endIndent = 16,
    this.essential = false,
  });
  @override
  Widget build(BuildContext context) {
    final settings = appLayout(context).preferences;
    if (settings.dividers == 'hidden' && !essential)
      return const SizedBox(height: 8);
    final look = finishLook(context);
    if (look.active && settings.dividers != 'strong') {
      return FinishGroove(indent: indent, endIndent: endIndent);
    }
    return Divider(
      height: 1,
      thickness: settings.dividers == 'strong' || settings.highContrast
          ? 1.5
          : 1,
      indent: indent,
      endIndent: endIndent,
      color: settings.dividers == 'strong' || settings.highContrast
          ? appColors(context).muted
          : appColors(context).border,
    );
  }
}

class _StillPageTransitions extends PageTransitionsBuilder {
  const _StillPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class AppPalette extends ThemeExtension<AppPalette> {
  final String id, name, description;
  final bool light;
  final bool highContrast;
  final Color background, surface, accent, muted, text;
  const AppPalette(
    this.id,
    this.name,
    this.description,
    this.background,
    this.surface,
    this.accent,
    this.muted,
    this.text, {
    this.light = false,
    this.highContrast = false,
  });
  Color get border => Color.lerp(
    surface,
    text,
    highContrast
        ? .65
        : light
        ? .20
        : .14,
  )!;
  Color get input => Color.lerp(surface, background, .65)!;
  Color get track => Color.lerp(surface, text, .15)!;
  Color get warning =>
      light ? const Color(0xff875100) : const Color(0xfff3ba61);
  Color get error => light ? const Color(0xffad2835) : const Color(0xffffb4ab);
  Color get info => light ? const Color(0xff176b83) : const Color(0xff7bcfe8);

  /// On-time and connected status; distinct from the accent used for actions.
  Color get success =>
      light ? const Color(0xff1f7a45) : const Color(0xff9fe6b0);
  @override
  AppPalette copyWith() => this;
  @override
  AppPalette lerp(covariant AppPalette? other, double t) =>
      t < .5 ? this : (other ?? this);
}

const appPalettes = [
  AppPalette(
    'midnight_lime',
    'Midnight Lime',
    'Forest darkness · lively lime',
    Color(0xff0a1210),
    Color(0xff131d1a),
    Color(0xffc9f96c),
    Color(0xff9caaa5),
    Color(0xffe4e7de),
  ),
  AppPalette(
    'royal_navy',
    'Royal Navy',
    'Deep navy · warm gold',
    Color(0xff0b1426),
    Color(0xff15233b),
    Color(0xfff0ca7b),
    Color(0xffa4b4ca),
    Color(0xffeef2fa),
  ),
  AppPalette(
    'warm_ivory',
    'Warm Ivory',
    'Soft cream · forest green',
    Color(0xfff7f4eb),
    Color(0xfffffcf5),
    Color(0xff266347),
    Color(0xff626b61),
    Color(0xff202f28),
    light: true,
  ),
  AppPalette(
    'deep_plum',
    'Deep Plum',
    'Rich plum · lavender',
    Color(0xff1a1125),
    Color(0xff291d36),
    Color(0xffd8b5ff),
    Color(0xffbcaac8),
    Color(0xfff1e7f6),
  ),
  AppPalette(
    'slate_teal',
    'Slate Teal',
    'Slate charcoal · fresh teal',
    Color(0xff10191d),
    Color(0xff1b282e),
    Color(0xff7ee0cb),
    Color(0xffa2b5bb),
    Color(0xffe6f0f2),
  ),
  AppPalette(
    'morning_sky',
    'Morning Sky',
    'Cool white · clear blue',
    Color(0xffedf5fc),
    Color(0xfff9fcff),
    Color(0xff165aab),
    Color(0xff52657a),
    Color(0xff152b45),
    light: true,
  ),
  AppPalette(
    'sage_linen',
    'Sage Linen',
    'Soft linen · calm sage',
    Color(0xfff3f2e9),
    Color(0xfffbfcf5),
    Color(0xff345d48),
    Color(0xff5e685d),
    Color(0xff20372b),
    light: true,
  ),
  AppPalette(
    'ocean_deep',
    'Ocean Deep',
    'Deep ocean · bright aqua',
    Color(0xff071722),
    Color(0xff0f2331),
    Color(0xff5ed0f5),
    Color(0xff9fb4c2),
    Color(0xffe5f1f7),
  ),
  AppPalette(
    'cobalt_night',
    'Cobalt Night',
    'Midnight blue · soft cobalt',
    Color(0xff0c1020),
    Color(0xff161c33),
    Color(0xff8fb2ff),
    Color(0xffa7b0c8),
    Color(0xffeceffa),
  ),
  AppPalette(
    'graphite',
    'Graphite',
    'Neutral charcoal · clean white, for dark booths',
    Color(0xff121314),
    Color(0xff1c1e20),
    Color(0xfff2f2f2),
    Color(0xffa9adb1),
    Color(0xffe8eaec),
  ),
  AppPalette(
    'paper_ink',
    'Paper & Ink',
    'Bright paper · near-black ink, for well-lit rooms',
    Color(0xfff5f5f2),
    Color(0xffffffff),
    Color(0xff1f2937),
    Color(0xff5b6470),
    Color(0xff111827),
    light: true,
  ),
  AppPalette(
    'paper_ink_blue',
    'Paper & Ink (blue)',
    'Bright paper · ink-blue buttons, for well-lit rooms',
    Color(0xfff5f5f2),
    Color(0xffffffff),
    // Ink blue, so links and buttons stand apart from the near-black text.
    Color(0xff1d4ed8),
    Color(0xff5b6470),
    Color(0xff111827),
    light: true,
  ),
  AppPalette(
    'meadow',
    'Meadow',
    'Fresh mint · deep teal',
    Color(0xffeaf5ef),
    Color(0xfffbfefc),
    Color(0xff0f6b5c),
    Color(0xff55675f),
    Color(0xff12332b),
    light: true,
  ),
];
double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
}

Color readable(Color background) =>
    contrast(Colors.black, background) >= contrast(Colors.white, background)
    ? Colors.black
    : Colors.white;
AppPalette paletteFor(String id) {
  if (RegExp(r'^custom:[0-9a-f]{6}:[0-9a-f]{6}:[0-9a-f]{6}$').hasMatch(id)) {
    final values = id
        .split(':')
        .skip(1)
        .map((hex) => Color(0xff000000 | int.parse(hex, radix: 16)))
        .toList();
    final bg = values[1], surface = values[2], text = readable(bg);
    var accent = values[0];
    for (var i = 0; i < 24 && contrast(accent, surface) < 4.5; i++) {
      accent = Color.lerp(accent, readable(surface), .12)!;
    }
    var muted = Color.lerp(surface, text, .72)!;
    if (contrast(muted, surface) < 4.5) muted = text;
    return AppPalette(
      id,
      'Custom theme',
      'Your colours · readable accents',
      bg,
      surface,
      accent,
      muted,
      text,
      light: bg.computeLuminance() > .179,
    );
  }
  return appPalettes.firstWhere(
    (p) => p.id == id,
    orElse: () => appPalettes.first,
  );
}

/// A theme's accent as a cue colour on screens, as RGB: the accent itself,
/// lightened where needed until it reads clearly on the stage background.
int stageAccentRgb(String themeId) =>
    stageAccentRgbOf(paletteFor(themeId).accent);

/// [accent] lightened, a little at a time and only as far as needed, until
/// it reads at 7:1 or better on a coloured cue's charcoal (and so on a
/// stage screen's black too): a full-screen cue in the theme's colour has
/// its words in that colour (see [stageCardInkFor]).
int stageAccentRgbOf(Color accent) {
  const card = Color(0xff000000 | stageCardBackground);
  // Each step is rounded to the colour as it is sent, "#rrggbb".
  accent = Color(accent.toARGB32());
  for (var i = 0; i < 80 && contrast(accent, card) < 7; i++) {
    accent = Color(Color.lerp(accent, Colors.white, .03)!.toARGB32());
  }
  return accent.toARGB32() & 0xffffff;
}

AppPalette appColors(BuildContext context) =>
    Theme.of(context).extension<AppPalette>() ?? appPalettes.first;

/// The app's own text face, on every platform. The app ships Roboto, but a
/// theme with no font of its own lets Windows draw ordinary text (buttons,
/// headings, lists) in Segoe UI, whose letters are a different width, so the
/// layouts that are tested here could wrap or cut words on a PC.
const appFontFamily = 'Roboto';

ThemeData appTheme(
  String id, {
  AppearancePreferences appearance = const AppearancePreferences(),
  Size size = const Size(430, 900),
}) {
  final base = paletteFor(id);
  Color stronger(Color color, double ratio) {
    for (var i = 0; i < 40 && contrast(color, base.surface) < ratio; i++) {
      color = Color.lerp(color, readable(base.surface), .15)!;
    }
    return color;
  }

  final p = appearance.highContrast
      ? AppPalette(
          base.id,
          base.name,
          base.description,
          base.background,
          base.surface,
          stronger(base.accent, 7),
          stronger(base.muted, 7),
          stronger(base.text, 7),
          light: base.light,
          highContrast: true,
        )
      : base;
  final layout = AppLayout.resolve(appearance, size);
  // High contrast always draws Flat (FinishLook.resolve), so the outlines and
  // text it asks for are never under a texture.
  // A Paper & Ink theme always has Papery; the saved choice is kept.
  final finishId = effectiveFinish(id, appearance.finish);
  final finish = FinishLook.resolve(
    p,
    finishId,
    // The strength chosen, or the finish's own.
    finishStrengthFor(finishId, appearance.finishStrength) == 'full' ? 1 : .5,
  );
  // Its photographs start loading now, so the first frame that shows the
  // finish can draw them.
  if (finish.active) FinishTextures.instance.loadFor(finish.id);
  final finishShape = finish.active
      ? RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            math.max(finishRadius(finish.id), 8),
          ),
          side: BorderSide(color: finish.border),
        )
      : null;
  final brightness = p.light ? Brightness.light : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    fontFamily: appFontFamily,
    brightness: brightness,
    extensions: [p, layout, finish],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    splashFactory: appearance.reducedMotion
        ? NoSplash.splashFactory
        : InkRipple.splashFactory,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final entry
            in appearance.reducedMotion
                ? {
                    for (final platform in TargetPlatform.values)
                      platform:
                          const _StillPageTransitions()
                              as PageTransitionsBuilder,
                  }.entries
                : const PageTransitionsTheme().builders.entries)
          entry.key: finish.active
              ? FinishPageTransitions(entry.value)
              : entry.value,
      },
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: layout.tileInsets,
      minTileHeight: layout.controlHeight,
      minVerticalPadding: layout.tilePadding + 4,
      selectedColor: p.text,
      // In a finish a chosen row is pressed into the material, a little
      // darker with a hint of the accent, not painted over.
      selectedTileColor: finish.active
          ? Color.alphaBlend(
              p.accent.withValues(alpha: .08),
              Colors.black.withValues(alpha: p.light ? .06 : .2),
            )
          : p.accent.withValues(alpha: .16),
    ),
    // And a row under the pointer or the keyboard sinks a little, instead
    // of taking a grey wash.
    hoverColor: finish.active
        ? Colors.black.withValues(alpha: p.light ? .04 : .12)
        : null,
    focusColor: finish.active
        ? Colors.black.withValues(alpha: p.light ? .06 : .16)
        : null,
    // Menus, dialogs and sheets in the panel colour and shape of the finish;
    // opened on a page, they are laid on its material as well
    // (FinishPopupFrame).
    popupMenuTheme: PopupMenuThemeData(
      color: finish.active ? finish.panel : p.surface,
      surfaceTintColor: Colors.transparent,
      shape:
          finishShape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.border),
          ),
    ),
    // Snack bars and tooltips are too brief, and too small, for material:
    // a finish gives them its panel colour, edge and corners, so they are
    // not the plain theme's dark slips over it.
    snackBarTheme: finish.active
        ? SnackBarThemeData(
            backgroundColor: finish.panel,
            contentTextStyle: TextStyle(color: p.text, fontSize: 15),
            actionTextColor: p.accent,
            closeIconColor: p.muted,
            elevation: 4,
            shape: finishShape,
          )
        : null,
    tooltipTheme: finish.active
        ? TooltipThemeData(
            decoration: BoxDecoration(
              color: finish.panel,
              borderRadius: BorderRadius.circular(
                math.min(finishRadius(finish.id), 8),
              ),
              border: Border.all(color: finish.border),
            ),
            textStyle: TextStyle(color: p.text, fontSize: 13),
          )
        : null,
    dialogTheme: DialogThemeData(
      backgroundColor: finish.active ? finish.panel : p.surface,
      shape:
          finishShape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: p.border),
          ),
    ),
    bottomSheetTheme: finish.active
        ? BottomSheetThemeData(
            backgroundColor: finish.panel,
            surfaceTintColor: Colors.transparent,
          )
        : null,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      primary: p.accent,
      onPrimary: readable(p.accent),
      surface: p.surface,
      onSurface: p.text,
      error: p.error,
      outline: p.muted,
      outlineVariant: p.border,
    ),
    // A finish draws the background itself, behind each page (FinishWall),
    // so the page and its bar must not cover it.
    scaffoldBackgroundColor: finish.active ? Colors.transparent : p.background,
    appBarTheme: AppBarTheme(
      // The bar is a plate of the finish's panel colour, so its words sit on
      // a panel too.
      backgroundColor: finish.active ? finish.panel : p.background,
      surfaceTintColor: finish.active ? Colors.transparent : null,
      elevation: finish.active ? 3 : null,
      scrolledUnderElevation: finish.active ? 3 : null,
      shadowColor: finish.active ? Colors.black : null,
      foregroundColor: p.text,
      centerTitle: false,
      systemOverlayStyle: p.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    ),
    navigationBarTheme: NavigationBarThemeData(
      // A finish lays the bar on a plate of its material.
      backgroundColor: finish.active ? Colors.transparent : finish.panel,
      elevation: finish.active ? 0 : null,
      indicatorColor: p.accent.withValues(alpha: .22),
    ),
    dividerColor: p.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: EdgeInsets.all(layout.rowPadding + 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(48, layout.controlHeight),
        animationDuration: appearance.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 150),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).merge(finishButtonStyle(finish, filled: true)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(48, layout.controlHeight),
        animationDuration: appearance.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 150),
        side: BorderSide(
          color: p.muted,
          width: appearance.highContrast ? 1.5 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ).merge(finishButtonStyle(finish, filled: false)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: Size(48, layout.controlHeight)),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: p.text),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
    ),
  );
}

/// One legible chapel symbol, with theme-colored raised surfaces, or the
/// church's own square [logo] (base64 PNG) when one is set.
class ChurchTimerMark extends StatelessWidget {
  final double size;
  final String logo;
  const ChurchTimerMark({super.key, this.size = 42, this.logo = ''});

  // Decoded once per logo, so rebuilding the header doesn't decode again.
  static final _decoded = <String, Uint8List>{};
  static Uint8List _bytes(String logo) {
    if (_decoded.length > 4) _decoded.clear();
    return _decoded.putIfAbsent(logo, () => base64Decode(logo));
  }

  @override
  Widget build(BuildContext context) {
    final p = appColors(context);
    if (logo.isNotEmpty) {
      return ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .24),
            border: Border.all(color: p.accent.withValues(alpha: .25)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .24),
            child: Image.memory(
              _bytes(logo),
              key: const ValueKey('church-logo-image'),
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .24),
          border: Border.all(color: p.accent.withValues(alpha: .25)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(p.surface, Colors.white, p.light ? .9 : .12)!,
              p.surface,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.light ? .12 : .3),
              blurRadius: size * .16,
              offset: Offset(0, size * .08),
            ),
          ],
        ),
        child: CustomPaint(painter: AppMarkPainter(p.accent)),
      ),
    );
  }
}

/// The app's mark: a countdown arc that ends in a cross, as on the launcher
/// icon (android/.../drawable/ic_church_timer_foreground.xml). Drawn in the
/// icon's 108-unit grid, framed on the mark itself so it fills the box.
class AppMarkPainter extends CustomPainter {
  final Color color;
  const AppMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // The mark spans about 61 × 62 units around (55, 54.5); frame 66.
    final scale = math.min(size.width, size.height) / 66;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-55, -54.5);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // The ring: three quarters of a circle, from the top round to the right.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(54, 56), radius: 26),
      -math.pi / 2,
      -math.pi * 1.5,
      false,
      stroke..strokeWidth = 7,
    );
    stroke.strokeWidth = 5;
    canvas
      ..drawLine(const Offset(76, 26), const Offset(76, 48), stroke)
      ..drawLine(const Offset(69, 33), const Offset(83, 33), stroke)
      ..drawCircle(const Offset(54, 56), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(AppMarkPainter old) => old.color != color;
}
