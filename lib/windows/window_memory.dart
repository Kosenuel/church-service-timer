import 'dart:async';

import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/mini_window.dart';

/// Where the window is: its frame when not maximised, and whether it is.
typedef WindowPlace = ({List<int> frame, bool maximised});

/// Reads and moves the app's window. The real one calls Windows.
abstract class WindowHandle {
  WindowPlace? read();

  /// False when [place] is no longer on any screen; nothing moves then.
  bool restore(WindowPlace place);
}

/// A window that can also be kept above other programs.
abstract class PinnableWindow implements WindowHandle {
  /// Keeps the window above all others ([onTop]) with no maximise button,
  /// or puts both back. False when Windows refused.
  bool pin(bool onTop);
}

/// A window that can also cover its whole monitor, with no frame.
abstract class FillableWindow implements WindowHandle {
  /// Covers the monitor the window is on. False when Windows refused;
  /// nothing has changed then.
  bool fill();

  /// Gives the window its frame back and puts it at [place].
  void unfill(WindowPlace place);
}

/// Reopens the window where it was last closed, and at the same size.
///
/// The place is saved a moment after it stops changing rather than only on
/// exit, so it survives a power cut. A place that is no longer on any
/// screen (a second monitor that has been unplugged) is ignored and the
/// window opens in its default spot.
///
/// It is also the mini timer's window ([MiniWindow]). While the window is
/// small, the saved place stays that of the normal window, so closing the
/// app then opens it normally next time; only the small window's corner is
/// remembered, under its own name.
///
/// And it is the window made full screen ([FullScreenWindow]), with the
/// same care: the saved place stays that of the normal window.
class WindowMemory implements MiniWindow, FullScreenWindow {
  final JsonPrefs prefs;
  final WindowHandle window;

  /// The size of the inside of the window, to work out how much the title
  /// bar and borders add. Without it a usual Windows frame is assumed.
  final ViewMetrics Function()? metrics;
  WindowMemory(this.prefs, this.window, {this.metrics});
  Timer? _timer;
  String? _saved;

  static WindowPlace? _decode(Object? value) {
    if (value is! Map) return null;
    final frame = value['frame'];
    if (frame is! List || frame.length != 4 || frame.any((v) => v is! int))
      return null;
    final f = frame.cast<int>();
    // A window needs some size to be usable at all.
    if (f[2] - f[0] < 200 || f[3] - f[1] < 200) return null;
    return (frame: f, maximised: value['maximised'] == true);
  }

  static String _key(WindowPlace p) => '${p.frame.join(',')},${p.maximised}';

  Future<void> restore() async {
    final place = _decode(await prefs.get('window'));
    if (place == null) return;
    if (window.restore(place)) _saved = _key(place);
  }

  Future<void> save() async {
    final place = window.read();
    if (place == null) return;
    // Full screen, the window reports the screen as its place.
    if (full) return;
    if (mini) return _saveMiniCorner(place.frame);
    if (_decode({'frame': place.frame}) == null) return;
    final key = _key(place);
    if (key == _saved) return;
    _saved = key;
    await prefs.set('window', {
      'frame': place.frame,
      'maximised': place.maximised,
    });
  }

  // ---- The mini timer's window --------------------------------------------

  /// Where the normal window was when it was made small.
  WindowPlace? _normal;
  String? _savedCorner;
  bool _changing = false;

  /// Whether the window is the small one now.
  bool get mini => _normal != null;

  static List<int>? _decodeCorner(Object? value) {
    final at = value is Map ? value['at'] : null;
    if (at is! List || at.length != 2 || at.any((v) => v is! int)) return null;
    return at.cast<int>();
  }

  Future<void> _saveMiniCorner(List<int> frame) async {
    final key = '${frame[0]},${frame[1]}';
    if (key == _savedCorner) return;
    _savedCorner = key;
    await prefs.set('mini', {
      'at': [frame[0], frame[1]],
    });
  }

  /// The whole small window in screen pixels: the asked-for inside plus
  /// the title bar and borders, measured from the window as it is now.
  List<int> _miniSize(WindowPlace now, double width, double height) {
    ViewMetrics? view;
    try {
      view = metrics?.call();
    } catch (_) {}
    final scale = view != null && view.scale >= 0.5 && view.scale <= 8
        ? view.scale
        : 1.0;
    // What Windows 10 and 11 add around a window at 100%.
    var extraWidth = (16 * scale).round(), extraHeight = (39 * scale).round();
    if (view != null && !now.maximised) {
      // A window snapped to a screen edge reports the place it had before,
      // so a difference that cannot be a frame is not believed.
      final w = now.frame[2] - now.frame[0] - view.width.round();
      final h = now.frame[3] - now.frame[1] - view.height.round();
      if (w >= 0 && w <= 48 * scale && h >= 0 && h <= 96 * scale) {
        extraWidth = w;
        extraHeight = h;
      }
    }
    return [
      (width * scale).round() + extraWidth,
      (height * scale).round() + extraHeight,
    ];
  }

  @override
  Future<bool> enter({required double width, required double height}) async {
    final window = this.window;
    if (mini) return true;
    if (window is! PinnableWindow || _changing || full) return false;
    _changing = true;
    try {
      final corner = _decodeCorner(await prefs.get('mini'));
      final normal = window.read();
      if (normal == null) return false;
      final size = _miniSize(normal, width, height);
      // Above other programs first: the runner only lets the window become
      // this small while it is.
      if (!window.pin(true)) {
        window.pin(false);
        return false;
      }
      // Where it was last time; failing that (first use, or that screen is
      // gone) the top right corner of the normal window.
      final corners = [
        ?corner,
        [normal.frame[2] - size[0], normal.frame[1]],
      ];
      if (!corners.any(
        (at) => window.restore((
          frame: [at[0], at[1], at[0] + size[0], at[1] + size[1]],
          maximised: false,
        )),
      )) {
        window.pin(false);
        return false;
      }
      _normal = normal;
      _savedCorner = corner?.join(',');
      // What the next start opens, should the app be closed while small.
      if (_decode({'frame': normal.frame}) != null) {
        _saved = _key(normal);
        await prefs.set('window', {
          'frame': normal.frame,
          'maximised': normal.maximised,
        });
      }
      return true;
    } finally {
      _changing = false;
    }
  }

  @override
  Future<void> leave() async {
    final window = this.window, normal = _normal;
    if (normal == null || window is! PinnableWindow || _changing) return;
    _changing = true;
    try {
      final small = window.read();
      // If the normal place is no longer on any screen, the normal size
      // where the small window is now.
      if (!window.restore(normal) && small != null) {
        window.restore((
          frame: [
            small.frame[0],
            small.frame[1],
            small.frame[0] + normal.frame[2] - normal.frame[0],
            small.frame[1] + normal.frame[3] - normal.frame[1],
          ],
          maximised: false,
        ));
      }
      window.pin(false);
      _normal = null;
      if (small != null) await _saveMiniCorner(small.frame);
    } finally {
      _changing = false;
    }
  }

  // ---- Full screen ---------------------------------------------------------

  /// Where the normal window was when it was made full screen.
  WindowPlace? _beforeFull;

  /// Whether the window is full screen now.
  bool get full => _beforeFull != null;

  @override
  Future<bool> enterFullScreen() async {
    final window = this.window;
    if (full) return true;
    if (window is! FillableWindow || mini || _changing) return false;
    _changing = true;
    try {
      final normal = window.read();
      if (normal == null || !window.fill()) return false;
      _beforeFull = normal;
      // What the next start opens, should the app be closed full screen.
      if (_decode({'frame': normal.frame}) != null) {
        _saved = _key(normal);
        await prefs.set('window', {
          'frame': normal.frame,
          'maximised': normal.maximised,
        });
      }
      return true;
    } finally {
      _changing = false;
    }
  }

  @override
  Future<void> leaveFullScreen() async {
    final window = this.window, normal = _beforeFull;
    if (normal == null || window is! FillableWindow) return;
    _beforeFull = null;
    window.unfill(normal);
  }

  void start() => _timer ??= Timer.periodic(
    const Duration(seconds: 2),
    (_) => unawaited(save().catchError((_) {})),
  );

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
