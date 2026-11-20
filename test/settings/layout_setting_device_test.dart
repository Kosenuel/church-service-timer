import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/layout_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The layout setting by device: hidden on a phone, "Tablet layout" on a
/// tablet large enough in landscape, "Desktop layout" on a computer.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  Future<AppController> settings(
    WidgetTester t,
    Size window, {
    Size? display,
    bool desktop = false,
  }) async {
    setScreen(t, window, display);
    desktopWording = desktop;
    final c = AppController(desktop ? DesktopFakePort() : FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    return c;
  }

  Future<void> layoutTab(WidgetTester t) async {
    final appearance = find.text('Appearance');
    await t.ensureVisible(appearance);
    await t.pumpAndSettle();
    await t.tap(appearance);
    await t.pumpAndSettle();
    await t.tap(find.text('Layout & accessibility'));
    await t.pumpAndSettle();
  }

  Future<void> search(WidgetTester t, String words) async {
    await t.enterText(find.byKey(const ValueKey('settings-search')), words);
    await t.pumpAndSettle();
  }

  WideLayoutDevice deviceFor(WidgetTester t) => wideLayoutDevice(
    t.element(find.byType(Scaffold).first),
    desktop: desktopWording,
  );

  group('a phone', () {
    for (final (name, window) in [
      ('upright', const Size(412, 915)),
      ('turned sideways', const Size(915, 412)),
    ]) {
      testWidgets('has no desktop or tablet layout setting, $name', (t) async {
        await settings(t, window);
        expect(deviceFor(t), WideLayoutDevice.none);
        expect(find.text('Desktop layout'), findsNothing);
        expect(find.text('Tablet layout'), findsNothing);
        await search(t, 'layout');
        expect(find.text('Desktop layout'), findsNothing);
        expect(find.text('Tablet layout'), findsNothing);
        await search(t, '');
        await layoutTab(t);
        expect(
          find.byKey(const ValueKey('desktop-layout-section')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('desktop-layout-when')), findsNothing);
        expect(
          find.byKey(const ValueKey('desktop-layout-mission_control')),
          findsNothing,
        );
        // Saved looks and the key labels stay.
        expect(find.byKey(const ValueKey('save-look')), findsOneWidget);
        expect(find.byKey(const ValueKey('key-hints')), findsOneWidget);
        expect(t.takeException(), isNull);
        if (window.width < window.height) {
          await t.ensureVisible(find.byKey(const ValueKey('save-look')));
          await t.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../goldens/layout-setting-phone.png'),
          );
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('a 7 or 8-inch tablet is too small even in landscape', (t) async {
    // A Lenovo Tab M8 or Galaxy Tab A 8: 1280 × 800 pixels at 213 dpi.
    await settings(t, const Size(601, 962));
    expect(deviceFor(t), WideLayoutDevice.none);
    expect(find.text('Tablet layout'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  group('a 10-inch tablet', () {
    // 2560 × 1600 pixels at density 2, as a Pixel Tablet or Galaxy Tab S9.
    for (final (name, window, display) in [
      ('in portrait', const Size(800, 1280), const Size(800, 1280)),
      ('in landscape', const Size(1280, 800), const Size(1280, 800)),
      ('in split screen', const Size(640, 800), const Size(1280, 800)),
    ]) {
      testWidgets('calls it Tablet layout, $name', (t) async {
        await settings(t, window, display: display);
        expect(deviceFor(t), WideLayoutDevice.tablet);
        expect(find.text('Desktop layout'), findsNothing);
        await search(t, 'landscape');
        expect(find.text('Tablet layout'), findsOneWidget);
        expect(find.text('How Live is arranged in landscape'), findsOneWidget);
        await search(t, '');
        final row = find.text('Tablet layout');
        await t.ensureVisible(row);
        await t.pumpAndSettle();
        expect(find.text('Mission control · in landscape'), findsOneWidget);
        await t.tap(row);
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('desktop-layout-when')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Used when the tablet is in landscape'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('desktop-layout-mission_control')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        if (name == 'in portrait') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../goldens/layout-setting-tablet.png'),
          );
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('a computer keeps Desktop layout, in any window', (t) async {
    await settings(t, const Size(900, 700), desktop: true);
    expect(deviceFor(t), WideLayoutDevice.computer);
    expect(find.text('Tablet layout'), findsNothing);
    final row = find.text('Desktop layout');
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    expect(find.text('Mission control · for a wide window'), findsOneWidget);
    await t.tap(row);
    await t.pumpAndSettle();
    expect(
      find.textContaining('at least 1200 wide and 600 tall'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
