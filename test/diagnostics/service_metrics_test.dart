import 'dart:ui' show FrameTiming;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/diagnostics/service_metrics.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/diagnostics_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

class BatteryPort extends FakePort {
  int level = 80;
  @override
  Future<Json> batteryStatus() async => {
    'level': level,
    'temperature': 31.5,
    'charging': false,
  };
}

FrameTiming frame(int ms) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: ms * 500,
  rasterStart: ms * 500,
  rasterFinish: ms * 1000,
  rasterFinishWallTime: ms * 1000,
);

void main() {
  test('A recording samples, notes events and ends with a summary', () async {
    final store = MemoryMetricsStore();
    var memory = 120 * 1024 * 1024;
    final r = ServiceMetricsRecorder(store: store, memoryBytes: () => memory);
    await r.start(start, label: 'Service', app: 'Church Service Timer 0.26.0');
    r.addFrames([frame(8), frame(20), frame(40)]);
    expect(r.sampleDue(after(30)), isFalse);
    expect(r.sampleDue(after(60)), isTrue);
    await r.sample(after(60), battery: {'level': 90});
    memory = 150 * 1024 * 1024;
    await r.warning(after(70), 1200);
    await r.event(after(80), 'background');
    // The wall clock jumped 3 s against the monotonic clock.
    final summary = (await r.stop(
      after(120, wallShift: 3000),
      battery: {'level': 88},
    ))!;
    expect(r.recording, isFalse);
    expect(summary.frames, 3);
    expect(summary.slowFrames, 2);
    expect(summary.jankyFrames, 1);
    expect(summary.worstFrameMs, closeTo(40, .01));
    expect(summary.peakMemoryMb, closeTo(150, .01));
    expect(summary.maxDriftMs, 3000);
    expect(summary.maxWarningLateMs, 1200);
    expect(summary.backgrounded, 1);
    expect(summary.batteryStart, 90);
    expect(summary.batteryEnd, 88);
    final csv = (await store.read())!;
    expect(csv, contains(ServiceMetricsRecorder.columns));
    expect(csv, contains(',warning,'));
    expect(recordingSummaryLines(csv), summary.lines);
  });

  test('The test service is two hours long', () {
    final t = testServiceProgram();
    expect(t.segments.fold(0, (n, s) => n + s.durationMs), 2 * 3600000);
  });

  test('Recording covers one service, then switches itself off', () async {
    final port = BatteryPort();
    final store = MemoryMetricsStore();
    final c = AppController(port, metricsStore: store);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    expect(await c.setRecordMetrics(true), isTrue);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await c.tick();
    expect(c.metrics.recording, isTrue);
    port.at = after(61);
    await c.tick();
    port.at = after(70);
    await c.act('end');
    await c.tick();
    expect(c.metrics.recording, isFalse);
    expect(c.state.recordMetrics, isFalse);
    expect(c.lastMetrics!.label, 'Service');
    final csv = (await store.read())!;
    // Service content never reaches the recording.
    for (final s in c.state.templates.first.segments) {
      expect(csv, isNot(contains(s.name)));
    }
    expect(csv, isNot(contains(c.state.templates.first.name)));
    expect(c.state.reports, hasLength(1), reason: 'A real service saves one');
  });

  test('A test service records and saves no report', () async {
    final port = BatteryPort();
    final c = AppController(port, metricsStore: MemoryMetricsStore());
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    expect(await c.startTestService(), isTrue);
    expect(c.state.session.active, isTrue);
    expect(c.state.session.noReport, isTrue);
    expect(c.state.recordMetrics, isTrue);
    await c.tick();
    expect(c.metrics.recording, isTrue);
    port.at = after(30);
    await c.act('end');
    await c.tick();
    expect(c.state.reports, isEmpty);
    expect(c.lastMetrics!.label, 'Test service');
    expect(
      c.state.templates.any((t) => t.name.startsWith('Test service')),
      isFalse,
    );
  });

  testWidgets('Diagnostics sits in About; Live shows when recording is on', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(BatteryPort(), metricsStore: MemoryMetricsStore());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('metrics-chip')), findsNothing);
    await t.tap(find.byType(NavigationDestination).at(3));
    await t.pumpAndSettle();
    final about = find.text('About');
    await t.ensureVisible(about.first);
    await t.pumpAndSettle();
    await t.tap(about.first);
    await t.pumpAndSettle();
    final row = find.byKey(const ValueKey('about-diagnostics'));
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await t.pumpAndSettle();
    expect(
      find.textContaining('Nothing about the service content'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('record-metrics')));
    await t.pumpAndSettle();
    expect(c.state.recordMetrics, isTrue);
    Navigator.of(
      t.element(find.byType(Scaffold).last),
    ).popUntil((r) => r.isFirst);
    await t.pumpAndSettle();
    await t.tap(find.byType(NavigationDestination).at(0));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('metrics-chip')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
