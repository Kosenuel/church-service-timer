import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  final String id, name, description;
  final bool light;
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
  });
  Color get border => Color.lerp(surface, text, light ? .20 : .14)!;
  Color get input => Color.lerp(surface, background, .65)!;
  Color get track => Color.lerp(surface, text, .15)!;
  Color get warning =>
      light ? const Color(0xff875100) : const Color(0xfff3ba61);
  Color get error => light ? const Color(0xffad2835) : const Color(0xffffb4ab);
  Color get info => light ? const Color(0xff176b83) : const Color(0xff7bcfe8);
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

ThemeData appTheme(String id) {
  final p = paletteFor(id);
  final brightness = p.light ? Brightness.light : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [p],
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
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
