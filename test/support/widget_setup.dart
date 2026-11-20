import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's fonts so screenshots show real text and icons, not
/// test boxes. Use as `setUpAll(loadAppFonts);`.
Future<void> loadAppFonts() async {
  await (FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
      .load();
  await (FontLoader('Tinos')..addFont(
        rootBundle.load(
          'android/app/src/main/assets/display_fonts/tinos/Tinos-Bold.ttf',
        ),
      ))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

/// Sets the test screen to [size] logical pixels at 1×, restored after
/// the test. The device's whole display is the same size, so a phone-sized
/// screen is a phone and a 1366 × 768 one a tablet; pass [display] for an
/// app window smaller than its screen.
void setScreen(
  WidgetTester t, [
  Size size = const Size(430, 1000),
  Size? display,
]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.display.size = display ?? size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.display.resetSize);
}
