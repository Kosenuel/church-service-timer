import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/diagnostics/performance_report.dart';
import 'package:church_service_timer/diagnostics/service_metrics.dart';
import 'package:church_service_timer/settings/diagnostics_views.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show after, start;
import 'service_metrics_test.dart' show BatteryPort, frame;

/// A two-hour recording: memory steady, one warning on time, one display
/// drop that takes 22 s to come back, battery 100% → 80%.
Future<String> recording() async {
  final store = MemoryMetricsStore();
  final r = ServiceMetricsRecorder(store: store, memoryBytes: () => 140 << 20);
  await r.start(
    start,
    label: 'Test service',
    app: 'Church Service Timer 0.26.0',
  );
  for (var m = 1; m <= 120; m++) {
    r.addFrames([for (var i = 0; i < 20; i++) frame(i == 0 ? 20 : 8)]);
    if (m == 30) {
      await r.event(after(m * 60 - 30), 'display', 'display=Disconnected');
      await r.event(
        after(m * 60 - 8),
        'reconnected',
        'display=Display connected',
      );
    }
    if (m == 50) await r.warning(after(m * 60 - 10), 900);
    await r.sample(after(m * 60), battery: {'level': 100 - m ~/ 6});
  }
  await r.stop(after(7200));
  return (await store.read())!;
}

void main() {
  test('The report marks each measure and names what to check', () async {
    final report = buildPerformanceReport(
      await recording(),
      device: 'Google Pixel 6a · Android 14',
      when: '6 Nov 2026, 10:00',
    );
    final md = report.markdown;
    expect(md, startsWith('# Service metrics · Test service'));
    expect(md, contains('Church Service Timer 0.26.0 · Google Pixel 6a'));
    expect(md, contains('| Smooth frames | 95.0% | ≥ 90% | ✅ |'));
    expect(md, contains('| Timer drift | 0.0 s | ≤ 1 s | ✅ |'));
    expect(md, contains('| Latest warning | 0.9 s after due (1 warning)'));
    expect(md, contains('| Slowest reconnect | 22 s (1 drop) | ≤ 15 s | ❌ |'));
    expect(md, contains('first run sets this phone’s baseline | — |'));
    expect(md, contains('1 to check: Slowest reconnect.'));
    expect(md.trim(), endsWith('*Created by I-Proton · Church Service Timer*'));
    expect(report.batteryPerHour, closeTo(10, .01));
    // The Diagnostics page reads the same rows back.
    final rows = reportRows(md);
    expect(rows.map((r) => r[0]), contains('Slowest reconnect'));
    expect(rows.firstWhere((r) => r[0] == 'Slowest reconnect')[3], '❌');
  });

  test('Battery is marked against this phone’s last run', () async {
    final csv = await recording();
    expect(
      buildPerformanceReport(
        csv,
        batteryBaseline: 9.5,
      ).results.firstWhere((r) => r.measure == 'Battery use').ok,
      isTrue,
      reason: '10%/h is within 10% of 9.5%/h',
    );
    expect(
      buildPerformanceReport(
        csv,
        batteryBaseline: 8,
      ).results.firstWhere((r) => r.measure == 'Battery use').ok,
      isFalse,
    );
  });

  test(
    'Ending a recording saves the report and the battery baseline',
    () async {
      final port = BatteryPort();
      final store = MemoryMetricsStore();
      final c = AppController(port, metricsStore: store);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      port.level = 100;
      expect(await c.startTestService(), isTrue);
      await c.tick();
      for (var m = 1; m <= 40; m++) {
        port.at = after(m * 60);
        port.level = 100 - m ~/ 4;
        await c.tick();
      }
      await c.act('end');
      await c.tick();
      expect(c.error, isNull);
      final md = (await store.readReport())!;
      expect(md, contains('# Service metrics · Test service'));
      expect(md, contains('Created by I-Proton'));
      expect(c.lastReport, isNotNull);
      expect(c.state.metricsBatteryBaseline, closeTo(15, 1));
    },
  );

  test('The computer report uses the same targets as the app', () {
    final script = File('scripts/perf_report.py').readAsStringSync();
    double budget(String key) => double.parse(
      RegExp('"$key":\\s*([0-9.]+)').firstMatch(script)!.group(1)!,
    );
    expect(budget('smooth_pct'), PerformanceTargets.smoothPct);
    expect(
      budget('memory_growth_mb_per_hour'),
      PerformanceTargets.memoryGrowthMbPerHour,
    );
    expect(budget('drift_s'), PerformanceTargets.driftSeconds);
    expect(budget('warning_late_s'), PerformanceTargets.warningLateSeconds);
    expect(budget('reconnect_s'), PerformanceTargets.reconnectSeconds);
    expect(script, contains(PerformanceReport.watermark));
  });
}
