import 'dart:convert';
import 'domain.dart';
import 'platform.dart';

class TextRaster {
  final int width, height;
  final List<String> rows;
  TextRaster(this.width, this.height, this.rows);
  factory TextRaster.fromJson(Json value) {
    final width = value['width'] as int, height = value['height'] as int;
    final rows = List<String>.from(value['rows']);
    require(
      width > 0 &&
          width <= 8192 &&
          height > 0 &&
          height <= 14 &&
          rows.length == height &&
          rows.every(
            (r) => r.length == width && RegExp(r'^[01]+$').hasMatch(r),
          ),
      'Invalid font bitmap.',
    );
    return TextRaster(width, height, rows);
  }
}

/// Only user-imported font data is rasterized; no replacement face is substituted.
class NativeDisplayFonts {
  static bool available = false;
  static DevicePort? _port;
  static int _generation = 0;
  static final _cache = <String, TextRaster>{};
  static final _pending = <String, Future<void>>{};
  static String key(TextLayout l) =>
      jsonEncode([l.font, l.text, l.bold, l.italic, l.height]);
  static Future<void> initialize(DevicePort port) async {
    _generation++;
    _port = port;
    _cache.clear();
    _pending.clear();
    available = await port.hasTimesFont();
  }

  static TextRaster? cached(TextLayout l) => _cache[key(l)];
  static Future<void> prepare(TextLayout l) async {
    if (l.font != 'times_new_roman') return;
    l.validate();
    require(
      available && _port != null,
      'Import a licensed Times New Roman Regular .ttf in Settings → Display settings first.',
    );
    final k = key(l);
    if (_cache.containsKey(k)) return;
    final generation = _generation;
    await (_pending[k] ??= () async {
      try {
        final data = await _port!.rasterizeTimes(l);
        final raster = TextRaster.fromJson(data);
        require(
          raster.height <= l.height * 7,
          'Font bitmap exceeds the selected height.',
        );
        if (generation == _generation) _cache[k] = raster;
      } finally {
        if (generation == _generation) _pending.remove(k);
      }
    }());
  }

  static Future<void> prepareState(AppState state) async {
    Iterable<TextLayout> display(DisplaySettings d) sync* {
      yield* d.cues;
      yield* d.warnings.map((w) => w.cue);
      yield d.end;
      if (d.zero != null) yield d.zero!;
    }

    Iterable<TextLayout> session(Session s) sync* {
      if (s.timeline != null) yield* display(s.timeline!.display);
      if (s.alert != null) yield s.alert!;
      if (s.automaticCue != null) yield s.automaticCue!;
      if (s.prior != null) yield* session(s.prior!);
    }

    for (final l in [
      ...state.stageCues,
      ...display(state.defaults),
      ...state.templates.expand((t) => display(t.display)),
      ...session(state.session),
    ]) {
      await prepare(l);
    }
  }
}
