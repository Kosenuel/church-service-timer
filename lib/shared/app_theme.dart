import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/domain/domain.dart'
    show AppearancePreferences;

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
    final automatic = size.shortestSide < 600
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
      'Your colors · readable accents',
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

AppPalette appColors(BuildContext context) =>
    Theme.of(context).extension<AppPalette>() ?? appPalettes.first;

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
  final brightness = p.light ? Brightness.light : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [p, layout],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    splashFactory: appearance.reducedMotion
        ? NoSplash.splashFactory
        : InkRipple.splashFactory,
    pageTransitionsTheme: appearance.reducedMotion
        ? PageTransitionsTheme(
            builders: {
              for (final platform in TargetPlatform.values)
                platform: const _StillPageTransitions(),
            },
          )
        : const PageTransitionsTheme(),
    listTileTheme: ListTileThemeData(
      contentPadding: layout.tileInsets,
      minTileHeight: layout.controlHeight,
      minVerticalPadding: layout.tilePadding + 4,
      selectedColor: p.text,
      selectedTileColor: p.accent.withValues(alpha: .16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.border),
      ),
    ),
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
    scaffoldBackgroundColor: p.background,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      centerTitle: false,
      systemOverlayStyle: p.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
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
      ),
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
      ),
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

/// One legible chapel symbol, with theme-colored raised surfaces.
class ChurchTimerMark extends StatelessWidget {
  final double size;
  const ChurchTimerMark({super.key, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final p = appColors(context);
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
        child: Icon(Icons.church_outlined, color: p.accent, size: size * .8),
      ),
    );
  }
}
