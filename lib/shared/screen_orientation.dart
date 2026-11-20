import 'package:flutter/services.dart';

/// Which ways round the app lets a phone or tablet turn. A paired stage
/// screen keeps itself landscape; full screen on the device running the
/// service turns landscape too, and on leaving goes back to whatever the
/// app had asked for before. Empty means any way round.
class ScreenOrientation {
  ScreenOrientation._();

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
  static Future<void> setFullScreen(bool on) async {
    if (on == _fullScreen) return;
    _fullScreen = on;
    await SystemChrome.setPreferredOrientations(on ? landscape : _app);
  }

  /// For tests: forgets what was asked for.
  static void reset() {
    _app = const [];
    _fullScreen = false;
  }
}
