import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class NetworkPort extends FakePort {
  int wifiOpened = 0;
  @override
  Future<void> openWifiSettings() async {
    wifiOpened++;
  }

  @override
  Future<Json> displayNetworkInfo({bool requestName = false}) async => {
    'wifiConnected': true,
    'ssid': 'Other network',
  };
}

void main() {
  testWidgets('Fullscreen stage text fills the display without distortion', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Future<void> show(String text, String effect) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: StageMessage(
              data: {'displayText': text, 'effect': effect, 'bold': true},
              stale: false,
              fullscreen: true,
            ),
          ),
        ),
      ),
    );
    for (final text in ['04:32', '+01:25:45', 'PLEASE FINISH YOUR MESSAGE']) {
      await show(text, 'static');
      await t.pumpAndSettle();
      final bounds = t.getRect(find.text(text));
      expect(bounds.width, greaterThan(1150));
      expect(bounds.left, greaterThanOrEqualTo(23.9));
      expect(bounds.right, lessThanOrEqualTo(1256.1));
      expect(bounds.top, greaterThanOrEqualTo(23.9));
      expect(bounds.bottom, lessThanOrEqualTo(576.1));
      expect(bounds.center.dx, closeTo(640, .1));
      expect(bounds.center.dy, closeTo(300, .1));
      expect(t.takeException(), isNull);
    }
    await show('WRAP UP', 'scroll');
    await t.pump(const Duration(seconds: 3));
    final scrollingBounds = t.getRect(find.text('WRAP UP'));
    expect(scrollingBounds.height, greaterThan(480));
    expect(scrollingBounds.top, greaterThanOrEqualTo(24));
    expect(scrollingBounds.bottom, lessThanOrEqualTo(576));
    expect(scrollingBounds.center.dy, closeTo(300, .1));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Administration shortcuts work while controller changes stay gated',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = NetworkPort();
      // Use the same port for the visible panel and the controller.
      final panelController = AppController(p);
      await panelController.initialize(startTicker: false);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: DeviceManagementPanel(controller: panelController),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Other network'), findsOneWidget);
      await t.ensureVisible(find.text('Open Wi-Fi'));
      await t.tap(find.text('Open Wi-Fi'));
      await t.pumpAndSettle();
      expect(p.wifiOpened, 1);
      final left = t.getRect(find.widgetWithText(OutlinedButton, 'Open Wi-Fi'));
      final right = t.getRect(
        find.widgetWithText(FilledButton, 'Connect LED display'),
      );
      expect(left.width, right.width);
      expect(left.top, right.top);
      expect(
        t.widget<ListTile>(find.widgetWithText(ListTile, 'Wi-Fi name')).enabled,
        false,
      );
      await t.tap(find.text('Connect LED display'));
      await t.pumpAndSettle();
      expect(find.byType(HardwareConnectionPage), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      panelController.dispose();
    },
  );

  testWidgets(
    'Static stage output stops animation, scrolling and flashing resume it',
    (t) async {
      Future<void> show(String effect, {bool stale = false}) => t.pumpWidget(
        MaterialApp(
          home: StageMessage(
            data: {'displayText': 'AMEN', 'effect': effect},
            stale: stale,
          ),
        ),
      );
      await show('static');
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, false);
      await show('scroll');
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.hasScheduledFrame, true);
      await show('scroll', stale: true);
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, false);
      await show('flash');
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.hasScheduledFrame, true);
      await show('static');
      await t.pumpAndSettle();
      expect(t.binding.hasScheduledFrame, false);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the stage countdown holds still as its digits change', (
    t,
  ) async {
    await loadAppFonts();
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<Rect> show(String time) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: StageMessage(
              data: {
                'displayText': time,
                'effect': 'static',
                'displayIsTimer': true,
                'paused': true,
              },
              stale: false,
              fullscreen: true,
            ),
          ),
        ),
      );
      await t.pump();
      return t.getRect(find.byKey(const ValueKey('stage-time-width')));
    }

    // Wide digits, narrow digits and a mix all take the same room, so the
    // time is never refitted to the screen from one second to the next.
    final wide = await show('24:32');
    final narrow = await show('11:11');
    final mixed = await show('20:01');
    expect(narrow, wide);
    expect(mixed, wide);
    // The digits themselves are equal width, so they do not shift either.
    Rect drawn() => t.getRect(
      find
          .descendant(
            of: find.byType(ClockText),
            matching: find.byType(RichText),
          )
          .first,
    );
    await show('24:32');
    final a = drawn();
    await show('11:11');
    expect(drawn(), a);
    await t.pumpWidget(const SizedBox());
  });
}
