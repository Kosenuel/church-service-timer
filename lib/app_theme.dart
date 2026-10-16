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
];
AppPalette paletteFor(String id) =>
    appPalettes.firstWhere((p) => p.id == id, orElse: () => appPalettes.first);
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
      onPrimary: p.light ? Colors.white : p.background,
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

/// The same church, cross and clock motif as the Android launcher asset.
class ChurchTimerMark extends StatelessWidget {
  final double size;
  const ChurchTimerMark({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ChurchTimerPainter(appColors(context).accent),
      ),
    ),
  );
}

class _ChurchTimerPainter extends CustomPainter {
  final Color color;
  _ChurchTimerPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(50, 8), const Offset(50, 26), p);
    canvas.drawLine(const Offset(42, 15), const Offset(58, 15), p);
    canvas.drawPath(
      Path()
        ..moveTo(18, 51)
        ..lineTo(50, 27)
        ..lineTo(82, 51)
        ..lineTo(82, 90)
        ..lineTo(18, 90)
        ..close(),
      p,
    );
    canvas.drawCircle(const Offset(50, 63), 18, p);
    canvas.drawPath(
      Path()
        ..moveTo(50, 51)
        ..lineTo(50, 63)
        ..lineTo(59, 68),
      p,
    );
  }

  @override
  bool shouldRepaint(_ChurchTimerPainter oldDelegate) =>
      color != oldDelegate.color;
}
