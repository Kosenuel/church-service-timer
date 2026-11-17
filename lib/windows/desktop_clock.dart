import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';

/// Tells one run of Windows from the next.
///
/// A running service is timed with a counter that restarts from zero when
/// the PC restarts, so a saved time is only comparable with "now" inside
/// the same run. Android hands the app a boot count; Windows has no such
/// number, so this works it out: the moment Windows started is "now minus
/// the counter", and that moment stays put for as long as Windows keeps
/// running, through sleep and hibernation too. A marker file remembers it
/// with an id. If the next reading agrees (within [toleranceMs]) and the
/// counter has not gone backwards, it is the same run and the id is kept;
/// otherwise a new id is made, and [Stamp.since] falls back to the wall
/// clock exactly as it does after a phone restarts.
///
/// Getting it wrong in the cautious direction (a new id when Windows did
/// not restart, for example after the PC's date was changed while the app
/// was closed) only costs that fallback. Keeping an id across a real
/// restart would need two restarts within [toleranceMs] of each other.
class BootTracker {
  final File marker;
  final int toleranceMs;
  final String Function() _newId;
  BootTracker(this.marker, {this.toleranceMs = 10000, String Function()? newId})
    : _newId = newId ?? _randomId;

  static final _random = math.Random.secure();
  static String _randomId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  String? _id;
  int _lastMono = 0, _savedMono = -1;

  /// The id of this run of Windows, for a reading of [mono] (the counter)
  /// and [wall] (the date and time), both in milliseconds.
  String id(int mono, int wall) {
    var id = _id;
    if (id == null) {
      id = _fromMarker(mono, wall) ?? _newId();
      _save(id, mono, wall);
    } else if (mono < _lastMono) {
      // The counter never goes backwards inside one run.
      id = _newId();
      _save(id, mono, wall);
    } else if (mono - _savedMono >= 60000) {
      // Re-anchor now and then, so slow drift between the counter and the
      // date never adds up to the tolerance, and a corrected date is
      // picked up while the app is open to see it.
      _save(id, mono, wall);
    }
    _lastMono = mono;
    return _id = id;
  }

  String? _fromMarker(int mono, int wall) {
    try {
      if (!marker.existsSync()) return null;
      final saved = jsonDecode(marker.readAsStringSync()) as Map;
      final id = saved['id'],
          savedMono = saved['mono'],
          savedWall = saved['wall'];
      if (id is! String || id.isEmpty || savedMono is! int || savedWall is! int)
        return null;
      final started = wall - mono, savedStarted = savedWall - savedMono;
      return mono >= savedMono && (started - savedStarted).abs() <= toleranceMs
          ? id
          : null;
    } catch (_) {
      return null;
    }
  }

  void _save(String id, int mono, int wall) {
    _savedMono = mono;
    try {
      marker.parent.createSync(recursive: true);
      final next = File('${marker.path}.tmp');
      next.writeAsStringSync(
        jsonEncode({'id': id, 'mono': mono, 'wall': wall}),
        flush: true,
      );
      next.renameSync(marker.path);
    } catch (_) {
      // Without a marker the next launch starts a new id: the safe side.
    }
  }
}

/// The app's clock on a desktop: a counter that keeps running through
/// sleep, the date and time, and which run of the system this is.
class DesktopClock {
  final int Function() monotonicMs;
  final int Function() wallMs;
  final BootTracker boot;
  DesktopClock({
    required this.monotonicMs,
    required this.boot,
    int Function()? wallMs,
  }) : wallMs = wallMs ?? _now;
  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Stamp read() {
    final mono = monotonicMs(), wall = wallMs();
    return Stamp(mono, wall, boot.id(mono, wall));
  }
}
