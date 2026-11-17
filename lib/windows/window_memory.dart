import 'dart:async';

import 'package:church_service_timer/windows/atomic_store.dart';

/// Where the window is: its frame when not maximised, and whether it is.
typedef WindowPlace = ({List<int> frame, bool maximised});

/// Reads and moves the app's window. The real one calls Windows.
abstract class WindowHandle {
  WindowPlace? read();

  /// False when [place] is no longer on any screen; nothing moves then.
  bool restore(WindowPlace place);
}

/// Reopens the window where it was last closed, and at the same size.
///
/// The place is saved a moment after it stops changing rather than only on
/// exit, so it survives a power cut. A place that is no longer on any
/// screen (a second monitor that has been unplugged) is ignored and the
/// window opens in its default spot.
class WindowMemory {
  final JsonPrefs prefs;
  final WindowHandle window;
  WindowMemory(this.prefs, this.window);
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
    if (place == null || _decode({'frame': place.frame}) == null) return;
    final key = _key(place);
    if (key == _saved) return;
    _saved = key;
    await prefs.set('window', {
      'frame': place.frame,
      'maximised': place.maximised,
    });
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
