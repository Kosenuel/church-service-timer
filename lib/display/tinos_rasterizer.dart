import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:church_service_timer/domain/domain.dart';

/// Rasterizes the bundled Tinos faces into LED rows with Flutter's own
/// text engine, for platforms without Android's canvas (Windows).
///
/// It follows `BundledFonts.kt` step for step: the same input rules, the
/// largest whole-pixel size whose ink fits the 7 or 14 rows, the real bold
/// and italic faces, and a width that keeps the text's advance and any
/// italic overhang. The one difference is how a pixel is decided: Android
/// draws without antialiasing, and here each pixel is lit when the engine
/// covers at least [coverage] of it. The shapes are close but not
/// identical to Android's, particularly at 7 rows.
class TinosRasterizer {
  /// Returns the font file for 'Regular', 'Bold', 'Italic' or 'BoldItalic'.
  final Future<Uint8List> Function(String style) loadFace;
  final double coverage;
  TinosRasterizer(this.loadFace, {this.coverage = .45});

  static const _maxWidth = 8192;
  final _faces = <String, Future<String>>{};

  static String _style(bool bold, bool italic) => bold && italic
      ? 'BoldItalic'
      : bold
      ? 'Bold'
      : italic
      ? 'Italic'
      : 'Regular';

  Future<String> _family(String style) => _faces[style] ??= () async {
    final family = 'CstDisplayTinos$style';
    await ui.loadFontFromList(await loadFace(style), fontFamily: family);
    return family;
  }();

  /// Whether all four faces load.
  Future<bool> available() async {
    try {
      for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
        await _family(style);
      }
      return true;
    } catch (_) {
      _faces.clear();
      return false;
    }
  }

  static void _validate(String text, int height) {
    require(
      height == 7 || height == 14,
      'Display font height must be 7 or 14 rows.',
    );
    require(
      text.trim().isNotEmpty && text.runes.length <= 160,
      'Display text must contain 1–160 characters and cannot be blank.',
    );
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      require(
        c >= 0x20 && !(c >= 0x7f && c <= 0x9f) && c != 0x2028 && c != 0x2029,
        'Display text must be a single line without control characters.',
      );
      final high = c >= 0xd800 && c <= 0xdbff, low = c >= 0xdc00 && c <= 0xdfff;
      if (high) {
        require(
          i + 1 < units.length &&
              units[i + 1] >= 0xdc00 &&
              units[i + 1] <= 0xdfff,
          'Display text contains an invalid Unicode character.',
        );
        i++;
      } else {
        require(!low, 'Display text contains an invalid Unicode character.');
      }
    }
  }

  /// `{width, height, rows}` with each row a string of 0s and 1s, the
  /// shape `rasterizeTinos` returns on Android.
  Future<Json> rasterize(
    String text,
    int height, {
    required bool bold,
    required bool italic,
  }) async {
    _validate(text, height);
    final family = await _family(_style(bold, italic));
    final threshold = (coverage * 255).round();
    // Fit actual whole-string ink, without resizing a rendered image.
    for (var size = 40; size >= 1; size--) {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: family,
                fontSize: size.toDouble(),
                maxLines: 1,
                textDirection: ui.TextDirection.ltr,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: const ui.Color(0xffffffff),
                fontFamily: family,
                fontSize: size.toDouble(),
              ),
            )
            ..addText(text);
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      final advance = paragraph.maxIntrinsicWidth;
      if (!advance.isFinite || advance < 0 || advance > _maxWidth) {
        paragraph.dispose();
        continue;
      }
      final padding = math.max(8, size);
      final width = advance.ceil() + padding * 2;
      final tall = paragraph.height.ceil() + padding * 2;
      if (tall < 1 || tall > 512) {
        paragraph.dispose();
        continue;
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawParagraph(
        paragraph,
        ui.Offset(padding.toDouble(), padding.toDouble()),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, tall);
      picture.dispose();
      paragraph.dispose();
      final ByteData? data;
      try {
        data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        image.dispose();
      }
      if (data == null) continue;
      bool lit(int x, int y) =>
          data!.getUint8((y * width + x) * 4 + 3) >= threshold;
      var top = tall, bottom = -1;
      for (var y = 0; y < tall; y++) {
        for (var x = 0; x < width; x++) {
          if (lit(x, y)) {
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
      }
      final inkHeight = bottom - top + 1;
      if (bottom < 0 || inkHeight < 1 || inkHeight > height) continue;
      // Horizontal bounds keep leading/trailing advances and italic
      // overhang.
      var firstX = padding, endX = padding + advance.ceil();
      for (var y = top; y <= bottom; y++) {
        for (var x = 0; x < width; x++) {
          if (lit(x, y)) {
            firstX = math.min(firstX, x);
            endX = math.max(endX, x + 1);
          }
        }
      }
      final rasterWidth = endX - firstX;
      if (rasterWidth < 1 || rasterWidth > _maxWidth) continue;
      return {
        'width': rasterWidth,
        'height': inkHeight,
        'rows': [
          for (var y = top; y <= bottom; y++)
            String.fromCharCodes([
              for (var x = firstX; x < endX; x++) lit(x, y) ? 0x31 : 0x30,
            ]),
        ],
      };
    }
    throw RuleError(
      'The text could not be rendered within the display bounds.',
    );
  }
}
