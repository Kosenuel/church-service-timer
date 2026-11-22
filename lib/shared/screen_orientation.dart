import 'dart:async';

import 'package:flutter/services.dart';

/// Which ways round the app lets a phone or tablet turn. A paired stage
/// screen keeps itself landscape; full screen on the device running the
/// service turns landscape too, and on leaving goes back to whatever the
/// app had asked for before. Empty means any way round.
class ScreenOrientation {
  ScreenOrientation._();

  /// Android's own end of the device channel, which holds the screen to
  /// whichever landscape the sensor reports.
  static const _device = MethodChannel('church.timer/device');

  static const landscape = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static List<DeviceOrientation> _app = const [];
  static bool _fullScreen = false;

  /// What the app asks for outside full screen, as last set.
  static List<DeviceOrientation> get app => _app;

  /// Whether full screen holds the screen landscape just now.
  static bool get fullScreen => _fullScreen;

  /// Sets what the app asks for outside full screen. While full screen
  /// shows it stays landscape, and this is used when it leaves.
  static Future<void> setApp(List<DeviceOrientation> value) async {
    _app = List.unmodifiable(value);
    if (_fullScreen) return;
    await SystemChrome.setPreferredOrientations(_app);
  }

  /// Full screen turns the screen landscape, and leaving it brings back
  /// what the app asked for before.
  ///
  /// Asking Flutter for both landscapes becomes Android's "user
  /// landscape", which follows the sensor only while the system's
  /// auto-rotate is on. So full screen also asks Android, on the device
  /// channel, for "sensor landscape", which turns between the two
  /// landscapes whatever auto-rotate says. Leaving drops that first, then
  /// asks for what the app had asked for before.
  static Future<void> setFullScreen(bool on) async {
    if (on == _fullScreen) return;
    _fullScreen = on;
    if (on) {
      final landscapes = SystemChrome.setPreferredOrientations(landscape);
      // Sent after the first, so it is the one that stands. Not waited
      // for: the screen does not wait for it either.
      unawaited(_sensorLandscape(true));
      await landscapes;
    } else {
      unawaited(_sensorLandscape(false));
      await SystemChrome.setPreferredOrientations(_app);
    }
  }

  static Future<void> _sensorLandscape(bool on) async {
    try {
      await _device.invokeMethod<void>('sensorLandscape', on);
    } catch (_) {
      // No Android side to ask (a test, or an older build): the two
      // landscapes asked for above still apply.
    }
  }

  /// For tests: forgets what was asked for.
  static void reset() {
    _app = const [];
    _fullScreen = false;
  }
}
