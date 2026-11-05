import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/time_picker.dart';
import 'package:church_service_timer/app_theme.dart';
import 'package:church_service_timer/pairing.dart';
import 'domain_test.dart' show FakePort, timeline;
import 'revision_16_test.dart' show eventually;
import 'live_helpers.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  void size(WidgetTester t, [Size s = const Size(430, 1000)]) {
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await t.pumpAndSettle();
    await t.tap(find.text(text).last);
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets(
    'Wheel picker scrolls, accepts typed seconds and presets without truncation',
    (t) async {
      size(t);
      int? result;
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('midnight_lime'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showWheelTimePicker(
                    ctx,
                    title: 'Set segment duration',
                    initial: 90,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Open');
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      await shot(t, 'time-picker-duration-019');
      await t.drag(find.byType(CupertinoPicker).last, const Offset(0, -88));
      await t.pumpAndSettle();
      expect(find.text('Use 01:30'), findsNothing);
      await t.tapAt(t.getCenter(find.byType(CupertinoPicker).last));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '45');
      await tap(t, 'Use value');
      expect(find.text('Use 01:45'), findsOneWidget);
      await tap(t, 'Use 01:45');
      expect(result, 105);
      await t.pump(const Duration(seconds: 1));
      await tap(t, 'Open');
      await tap(t, '5 min');
      await tap(t, 'Use 05:00');
      expect(result, 300);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Clock wheel accepts midnight; warning duration is capped at two minutes',
    (t) async {
      size(t);
      int? clock;
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('royal_navy'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      clock = await showWheelTimePicker(
                        ctx,
                        title: 'Finish time',
                        initial: 0,
                        clock: true,
                      );
                    },
                    child: const Text('Clock'),
                  ),
                  TextButton(
                    onPressed: () => showWheelTimePicker(
                      ctx,
                      title: 'Warning duration',
                      initial: 120,
                      maximum: 120,
                    ),
                    child: const Text('Warning'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Clock');
      await shot(t, 'time-picker-clock-019');
      await tap(t, 'Use 00:00');
      expect(clock, 0);
      await tap(t, 'Warning');
      expect(find.text('5 min'), findsNothing);
      expect(find.text('Use 02:00'), findsOneWidget);
      await tap(t, 'Cancel');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Focused view keeps compact timing overview, expand reveals details',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await openLiveMenu(t, 'Focused operator view');
      final overview = find.byKey(const ValueKey('focused-timing-overview'));
      expect(overview, findsOneWidget);
      await t.ensureVisible(overview);
      await t.pumpAndSettle();
      await shot(t, 'focused-overview-019');
      await t.tap(find.text('Service timing overview'));
      await t.pumpAndSettle();
      expect(find.textContaining('This segment'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Jump confirmation names bypassed segments and preserves paused state',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act('pause');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tapJump(t);
      await tap(t, 'Last');
      expect(find.textContaining('Mark as skipped: Second.'), findsOneWidget);
      await shot(t, 'jump-segment-confirm-019');
      await tap(t, 'Jump to segment');
      expect(c.state.session.index, 2);
      expect(c.state.session.paused, true);
      expect(c.state.session.run!.skipped, {1});
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Program long-press menu puts export first and confirms before deleting',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      final name = c.state.templates.first.name,
          count = c.state.templates.length;
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Programs');
      await t.longPress(find.byKey(ValueKey('template-row:$name')));
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.text('Export program')).dy,
        lessThan(t.getTopLeft(find.text('Delete program')).dy),
      );
      await shot(t, 'program-actions-019');
      await tap(t, 'Delete program');
      expect(find.text('Delete program?'), findsOneWidget);
      expect(c.state.templates.length, count);
      await tap(t, 'Cancel');
      expect(c.state.templates.length, count);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'QR dialog closes for new pending join and waits for host approval',
    (t) async {
      size(t);
      late PairHub host, guest;
      await t.runAsync(() async {
        host = PairHub();
        guest = PairHub();
      });
      addTearDown(() async {
        await t.runAsync(() async {
          await guest.stop();
          await host.stop();
        });
        guest.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 1, 'displayText': '00:42'};
      await t.runAsync(() => host.host('127.0.0.1'));
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('midnight_lime'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => PairQrDialog(hub: host),
                ),
                child: const Text('QR'),
              ),
            ),
          ),
        ),
      );
      await tap(t, 'QR');
      expect(find.text('Pair with QR code'), findsOneWidget);
      await t.runAsync(() async {
        await guest.join(host.code!.encode(), 'Stage tablet', 'stage');
        await eventually(() => host.peers.isNotEmpty);
      });
      await t.pump();
      await t.pumpAndSettle();
      expect(find.text('Pair with QR code'), findsNothing);
      expect(find.text('Approve paired device?'), findsOneWidget);
      expect(host.peers.single.approved, false);
      await shot(t, 'pair-approval-019');
      await tap(t, 'Approve');
      // Dialog work uses Flutter's fake clock; sockets use real I/O. Flush both.
      for (var i = 0; i < 30 && !host.peers.single.approved; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
      }
      expect(host.peers.single.approved, true);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Clock format setting persists and refreshes the active clock', (
    t,
  ) async {
    size(t);
    final port = FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline());
    await c.act('start');
    await c.act('clock');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await tap(t, 'Settings');
    await tap(t, 'Display settings');
    await tap(t, 'Clock format');
    await tap(t, '12-hour');
    expect(c.state.clockFormat, '12h');
    expect(c.state.session.intended(c.now)!.text, contains(RegExp('AM|PM')));
    await shot(t, 'clock-format-019');
    await t.pumpWidget(const SizedBox());
    final restored = AppController(port);
    await restored.initialize(startTicker: false);
    expect(restored.state.clockFormat, '12h');
    restored.dispose();
  });

  testWidgets(
    'Post-service clock and cue confirmation preserve report and welcome card',
    (t) async {
      size(t, const Size(430, 1200));
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act('end');
      final report = c.state.reports.single.toJson().toString();
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(find.text('View last service report'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Show clock').hitTestable(), 300);
      await tap(t, 'Show clock');
      expect(c.state.session.outputMode(c.now), 'Clock');
      await t.ensureVisible(find.text(c.state.stageCues.first.text).first);
      await tap(t, c.state.stageCues.first.text);
      expect(find.text('Send after service ended?'), findsOneWidget);
      expect(c.state.session.outputMode(c.now), 'Clock');
      await shot(t, 'post-service-cue-019');
      await tap(t, 'Cancel');
      expect(c.state.session.outputMode(c.now), 'Clock');
      await tap(t, c.state.stageCues.first.text);
      await tap(t, 'Send cue');
      expect(c.state.session.outputMode(c.now), 'Cue');
      // The sent cue's button swaps to the way back to what was underneath.
      expect(find.text(c.state.stageCues.first.text), findsNothing);
      await passShowTimerGuard(t);
      await tap(t, 'Back to clock');
      expect(c.state.session.outputMode(c.now), 'Clock');
      expect(find.text(c.state.stageCues.first.text), findsOneWidget);
      expect(c.state.reports.single.toJson().toString(), report);
      await t.pumpWidget(const SizedBox());
    },
  );
}
