import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app_theme.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pixels.dart';
import 'package:church_service_timer/hardware_output.dart';
import 'domain_test.dart' show after, start, FakePort;
import 'hardware_integration_test.dart' show W2Port, setup, flush;
import 'live_helpers.dart';

class ActivePort extends W2Port {
  bool active = false;
  Future<void> Function()? pulse;
  @override
  void setBackgroundHandler(Future<void> Function()? handler) =>
      pulse = handler;
  @override
  Future<bool> setActiveService(bool enabled) async => active = enabled;
  @override
  Future<bool> activeServiceRunning() async => active;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'Warning display duration begins at acknowledgement after a slow upload',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(570, TextLayout('WARN'), destination: 'stage'),
      ]);
      final gate = Completer<Json>();
      p.sendGate = gate;
      p.at = after(30);
      await c.tick();
      p.at = after(40);
      await c.tick();
      p.sendGate = null;
      gate.complete({'accepted': true, 'generation': p.nativeGeneration});
      await flush();
      await c.tick();
      expect(c.state.session.automaticCueAt!.mono, after(40).mono);
      p.at = after(47);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.automaticCue);
      p.at = after(48);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.running);
      expect(p.sent.last.deadline, start.wall + 600000);
    },
  );
  test(
    'Late warning acknowledgement cannot replace a newer manual cue',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(570, TextLayout('WARN'), destination: 'stage'),
      ]);
      final gate = Completer<Json>();
      p.sendGate = gate;
      p.at = after(30);
      await c.tick();
      p.at = after(32);
      await c.act('cue', value: const TextLayout('AMEN', effect: 'static'));
      p.sendGate = null;
      gate.complete({'accepted': true, 'generation': p.nativeGeneration});
      await flush();
      await c.tick();
      expect(c.hardware.accepted!.layout!.text, 'AMEN');
      p.at = after(45);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.layout!.text, 'AMEN');
    },
  );
  test(
    'Next segment after overtime clears cues and restores both adapters',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings([]);
      p.at = after(620);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
      await c.act('cue', value: const TextLayout('STOP', effect: 'static'));
      await flush();
      c.hardware.hold('App interrupted');
      expect(await c.act('advance'), true);
      await flush();
      expect(c.state.session.alert, isNull);
      expect(c.state.session.index, 1);
      expect(
        c.simulator.delivered,
        isNull,
      ); // Only the selected output is driven.
      expect(c.hardware.held, false);
      expect(c.hardware.accepted!.segmentIndex, 1);
      expect(p.sent.last.deadline, after(920).wall);
    },
  );
  test(
    'Advancing offers deliberate keep blank, while default shows the timer',
    () async {
      final c = await setup(W2Port());
      addTearDown(c.dispose);
      await c.act('blank');
      await flush();
      await c.act('advance', value: true);
      await flush();
      expect(c.state.session.outputBlank, true);
      expect(c.hardware.accepted!.kind, HardwareOutputKind.blank);
      await c.act('advance');
      await flush();
      expect(c.state.session.outputBlank, false);
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
    },
  );
  test(
    'Scroll-once duration persists and returns to the original deadline',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      const rule = WarningRule(
        570,
        TextLayout('PLEASE WRAP UP', speed: 12),
        destination: 'stage',
        scrollOnce: true,
      );
      await c.setSharedWarnings([rule]);
      p.at = after(30);
      await c.tick();
      await flush();
      expect(p.sent.last.bytes.length, greaterThan(233));
      final duration = warningDurationMs(rule);
      expect(c.state.session.automaticCueDurationMs, duration);
      expect(
        AppState.fromJson(
          jsonDecode(p.data!),
        ).defaults.warnings.single.scrollOnce,
        true,
      );
      p.at = after(30 + (duration / 1000).ceil());
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
      expect(p.sent.last.deadline, start.wall + 600000);
    },
  );
  test(
    'Pause and adjustment during a warning restore adjusted paused time',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(
          570,
          TextLayout('WAIT', effect: 'static'),
          destination: 'stage',
          durationSeconds: 12,
        ),
      ]);
      p.at = after(30);
      await c.tick();
      await flush();
      p.at = after(32);
      await c.act('pause');
      await c.act('adjust', value: 60);
      await flush();
      p.at = after(43);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.paused);
      expect(c.hardware.accepted!.layout!.text, '10:28');
    },
  );
  test(
    'Blank and Next segment preempt a pending warning without replay',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(570, TextLayout('WARN'), destination: 'stage'),
      ]);
      p.at = after(30);
      await c.tick();
      await flush();
      await c.act('blank');
      await flush();
      p.at = after(31);
      await c.act('advance');
      await flush();
      p.at = after(40);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.running);
      expect(p.sent.last.deadline, after(331).wall);
    },
  );
  test(
    'Background service keeps warning and expiry operating while suspended',
    () async {
      final p = ActivePort();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(570, TextLayout('WARN'), destination: 'stage'),
      ]);
      expect(c.backgroundActive, true);
      await c.suspend();
      expect(c.hardware.held, false);
      p.at = after(30);
      await p.pulse!();
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.automaticCue);
      p.at = after(39);
      await p.pulse!();
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
      await c.resume();
      expect(c.hardware.held, false);
      await c.act('end');
      await flush(); // Let the acknowledged end-screen upload finish.
      expect(p.active, false);
    },
  );
  test(
    'Native service stopping holds output rather than silently claiming continuity',
    () async {
      final p = ActivePort();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.suspend();
      p.active = false;
      await p.pulse!();
      expect(c.backgroundActive, false);
      expect(c.hardware.held, true);
      await c.resume();
      expect(c.hardware.held, true);
    },
  );
  test(
    'Activity records attempts, acknowledgement, failure and survives restart',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.tick();
      await c.act('pause');
      await flush();
      await c.tick();
      p.acknowledged = false;
      await c.act('pause');
      await flush();
      await c.tick();
      await c.act('end');
      await flush();
      await c.tick();
      final report = AppState.fromJson(jsonDecode(p.data!)).reports.single;
      expect(report.events.any((e) => e.kind == 'sending'), true);
      expect(report.events.any((e) => e.kind == 'accepted'), true);
      expect(report.events.any((e) => e.kind == 'failed'), true);
      expect(report.events.any((e) => e.kind == 'pause'), true);
      expect(exportReportJson(report), contains('events'));
    },
  );
  test('Delayed display events stay chronological across save and reload', () {
    final events = <ServiceEvent>[];
    addServiceEvent(events, const ServiceEvent(3000, 'pause', 'Paused'));
    addServiceEvent(events, const ServiceEvent(1000, 'sending', 'Sending'));
    addServiceEvent(events, const ServiceEvent(2000, 'accepted', 'Accepted'));
    addServiceEvent(
      events,
      const ServiceEvent(3000, 'sending', 'Pause output'),
    );
    expect(events.map((e) => e.message), [
      'Sending',
      'Accepted',
      'Paused',
      'Pause output',
    ]);
    final restored = readServiceEvents([
      events[2].toJson(),
      events[0].toJson(),
      events[1].toJson(),
      events[3].toJson(),
    ]);
    expect(restored.map((e) => e.message), events.map((e) => e.message));
    for (var i = 0; i < 1000; i++) {
      addServiceEvent(restored, ServiceEvent(4000 + i, 'sending', 'Update'));
    }
    expect(restored.length, 1000);
    expect(restored.first.wall, 4000);
    expect(restored.last.wall, 4999);
  });
  test('Warning durations validate imports and migrate older rules', () {
    final old = const WarningRule(30, TextLayout('WARN')).toJson()
      ..remove('durationSeconds')
      ..remove('scrollOnce');
    expect(WarningRule.fromJson(old).durationSeconds, 8);
    for (final bad in [0, 121, 'ten']) {
      expect(
        () => WarningRule.fromJson({...old, 'durationSeconds': bad}),
        throwsA(isA<RuleError>()),
      );
    }
  });
  test(
    'Custom theme survives backup and supplies readable accent and primary text',
    () {
      final a = AppState.fresh(start)..themeId = 'custom:eeeeee:edf5fc:f9fcff';
      final restored = importBackup(exportBackup(a, start), start);
      expect(restored.themeId, a.themeId);
      final p = paletteFor(a.themeId);
      expect(contrast(p.accent, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.text, p.background), greaterThanOrEqualTo(4.5));
      expect(
        contrast(appTheme(a.themeId).colorScheme.onPrimary, p.accent),
        greaterThanOrEqualTo(4.5),
      );
    },
  );
  testWidgets('Focus keeps the blank preview and lock blocks timer controls', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await openLiveMenu(t, 'Focused operator view');
    await c.act('blank');
    await t.pumpAndSettle();
    expect(find.text('DISPLAY PREVIEW'), findsOneWidget);
    expect(find.text('Screen intentionally blanked'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('pause-resume')))
          .onPressed,
      isNull,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/focus-blank-locked-phone.png'),
    );
    await t.longPress(find.byKey(const ValueKey('unlock-controls')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('pause-resume')))
          .onPressed,
      isNotNull,
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Report timeline shows actions and delivery outcomes', (t) async {
    t.view.physicalSize = const Size(430, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final p = FakePort();
    final c = AppController(p);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    p.at = after(30);
    await c.act('pause');
    await c.act('end');
    final report = c.state.reports.single;
    report.events.addAll([
      ServiceEvent(after(30).wall, 'sending', 'Sending end screen'),
      ServiceEvent(
        after(31).wall,
        'accepted',
        'Controller accepted end screen',
      ),
    ]);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme('midnight_lime'),
        home: ReportDetailPage(
          report: report,
          onExport: (_) async {},
          onDelete: () async => false,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Activity timeline'));
    await t.tap(find.text('Activity timeline'));
    await t.pumpAndSettle();
    expect(find.text('Sending end screen'), findsOneWidget);
    expect(find.text('Controller accepted end screen'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/report-activity-phone.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Rundown details include private notes without advancing', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act(
      'load',
      value: Timeline('Service', const [
        Segment(
          'Welcome',
          2,
          speaker: 'Pastor',
          notes: 'Private microphone reminder',
        ),
      ], DisplaySettings()),
    );
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final row = find.byKey(const ValueKey('rundown-0'));
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.text('Private microphone reminder').last, findsOneWidget);
    expect(find.text('Speaker: Pastor').last, findsOneWidget);
    expect(c.state.session.index, 0);
    expect(c.state.session.phase, 'active');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rundown-details-phone.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Custom theme editor previews, validates and returns chosen colors',
    (t) async {
      t.view.physicalSize = const Size(430, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      String? selected;
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('morning_sky'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async => selected = await showDialog<String>(
                  context: ctx,
                  builder: (_) =>
                      const CustomThemeEditor(initial: 'morning_sky'),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open editor'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '9e4059');
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/custom-theme-phone.png'),
      );
      await t.tap(find.text('Use theme'));
      await t.pumpAndSettle();
      expect(selected, 'custom:9e4059:edf5fc:f9fcff');
      await t.tap(find.text('Open editor'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'xx');
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use theme'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(selected, isNull);
    },
  );
}
