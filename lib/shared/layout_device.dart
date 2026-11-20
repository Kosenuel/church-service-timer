import 'package:flutter/widgets.dart';

import 'package:church_service_timer/domain/domain.dart';

/// Where the wide Live layouts (see [builtDesktopLayouts]) can appear, for
/// the setting that chooses one.
enum WideLayoutDevice {
  /// A computer: its window can always be made large enough.
  computer,

  /// A tablet whose screen is at least [desktopLayoutMinWidth] by
  /// [desktopLayoutMinHeight] when held in landscape.
  tablet,

  /// A phone, or a tablet too small for the layouts even in landscape:
  /// Live always uses the phone layout, so the setting is hidden.
  none,
}

/// Which [WideLayoutDevice] the app is on.
///
/// A phone or tablet is judged by its whole screen, not the app's window,
/// so turning it round or using split screen does not change the answer.
/// A screen whose shorter side is under 600 is a phone, as Android itself
/// counts it; a tablet can show the layouts only if its longer side is at
/// least [desktopLayoutMinWidth], which in practice means a 10-inch tablet
/// or larger (1280 × 800 and up), not a 7 or 8-inch one (about 960 × 600).
WideLayoutDevice wideLayoutDevice(
  BuildContext context, {
  required bool desktop,
}) {
  if (desktop) return WideLayoutDevice.computer;
  final view = View.of(context);
  var screen = Size.zero;
  try {
    final display = view.display;
    screen = display.size / display.devicePixelRatio;
  } catch (_) {
    // No display to ask: fall back to the app's own window below.
  }
  if (screen.isEmpty) screen = view.physicalSize / view.devicePixelRatio;
  final window = MediaQuery.sizeOf(context);
  final reaches =
      (screen.shortestSide >= 600 &&
          screen.longestSide >= desktopLayoutMinWidth &&
          screen.shortestSide >= desktopLayoutMinHeight) ||
      // Already showing one, whatever the screen says.
      (window.width >= desktopLayoutMinWidth &&
          window.height >= desktopLayoutMinHeight);
  return reaches ? WideLayoutDevice.tablet : WideLayoutDevice.none;
}

/// The setting's name: "Desktop layout" on a computer, "Tablet layout" on
/// a tablet.
String wideLayoutSettingName(WideLayoutDevice device) =>
    device == WideLayoutDevice.tablet ? 'Tablet layout' : 'Desktop layout';
