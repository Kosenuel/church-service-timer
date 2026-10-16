import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'domain.dart';

Future<void> validateBannerPixels(String value) async {
  churchBannerValue(value);
  if (value.isEmpty) return;
  final codec = await ui.instantiateImageCodec(base64Decode(value));
  try {
    final frame = await codec.getNextFrame();
    try {
      require(
        frame.image.width == 600 &&
            frame.image.height == 200 &&
            codec.frameCount == 1,
        'Choose a valid 3:1 church banner.',
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class ChurchProfileBanner extends StatefulWidget {
  final String image;
  const ChurchProfileBanner({super.key, required this.image});
  @override
  State<ChurchProfileBanner> createState() => _ChurchProfileBannerState();
}

class _ChurchProfileBannerState extends State<ChurchProfileBanner> {
  ImageProvider? picture;
  void loadPicture() {
    picture = widget.image.isEmpty
        ? null
        : MemoryImage(base64Decode(widget.image));
  }

  @override
  void initState() {
    super.initState();
    loadPicture();
  }

  @override
  void didUpdateWidget(ChurchProfileBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Retain the provider and decoded frame when other profile fields rebuild.
    if (oldWidget.image != widget.image) loadPicture();
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    Widget fallback() => DecoratedBox(
      key: const ValueKey('built-in-church-banner'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.track, colors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _ChurchLandscape(colors.accent, colors.muted),
      ),
    );
    return Semantics(
      label: picture == null ? 'Built-in church banner' : 'Your church banner',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 3,
          child: picture == null
              ? fallback()
              : Image(
                  image: picture!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => fallback(),
                ),
        ),
      ),
    );
  }
}

/// Built-in panoramic church artwork; scales with the banner and active theme.
class _ChurchLandscape extends CustomPainter {
  final Color accent, muted;
  const _ChurchLandscape(this.accent, this.muted);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 600, size.height / 200);
    final paint = Paint()..color = accent.withValues(alpha: 0.09);
    canvas.drawCircle(const Offset(300, 106), 106, paint);
    canvas.drawCircle(const Offset(300, 106), 77, paint);
    paint.color = muted.withValues(alpha: 0.13);
    final hills = Path()
      ..moveTo(0, 153)
      ..quadraticBezierTo(100, 96, 220, 156)
      ..quadraticBezierTo(380, 194, 470, 135)
      ..quadraticBezierTo(545, 99, 600, 151)
      ..lineTo(600, 200)
      ..lineTo(0, 200)
      ..close();
    canvas.drawPath(hills, paint);
    paint
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final church = Path()
      ..moveTo(250, 158)
      ..lineTo(250, 113)
      ..lineTo(278, 91)
      ..lineTo(278, 72)
      ..lineTo(300, 52)
      ..lineTo(322, 72)
      ..lineTo(322, 91)
      ..lineTo(350, 113)
      ..lineTo(350, 158)
      ..close();
    canvas.drawPath(church, paint);
    canvas.drawLine(const Offset(300, 33), const Offset(300, 51), paint);
    canvas.drawLine(const Offset(293, 39), const Offset(307, 39), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(289, 126, 22, 32),
        const Radius.circular(10),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(300, 91), 10, paint);
    canvas.drawLine(const Offset(230, 163), const Offset(370, 163), paint);
    paint
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.4);
    for (final x in [65.0, 140.0, 460.0, 535.0]) {
      canvas.drawLine(Offset(x, 146), Offset(x, 176), paint);
      canvas.drawPath(
        Path()
          ..moveTo(x - 14, 154)
          ..lineTo(x, 128)
          ..lineTo(x + 14, 154)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChurchLandscape old) =>
      old.accent != accent || old.muted != muted;
}
