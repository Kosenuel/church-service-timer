// Scrolling benchmarks for the performance review (docs/performance-review.md).
//
// Run on a phone, in a profile build:
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/scroll_benchmark_test.dart
//
// The app runs on in-memory data here: nothing on the phone is changed.
import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class BenchmarkPort extends DevicePort {
  final watch = Stopwatch()..start();
  final int wall0 = DateTime.now().millisecondsSinceEpoch;
  String? data;
  BenchmarkPort(this.data);
  @override
  Future<Stamp> clock() async => Stamp(
    watch.elapsedMilliseconds,
    wall0 + watch.elapsedMilliseconds,
    'bench',
  );
  @override
  Future<String?> load() async => data;
  @override
  Future<void> save(String state) async => data = state;
  @override
  Future<Map<String, dynamic>?> pickFile() async => null;
  @override
  Future<void> exportFile(String filename, String content) async {}
}

/// 200 programs (some with 60 segments) and 500 past services.
String heavyState() {
  var at = Stamp(0, DateTime(2026).millisecondsSinceEpoch, 'bench');
  final state = AppState.fresh(at);
  for (var p = 0; p < 200; p++) {
    final count = p % 10 == 0 ? 60 : 8;
    state.saveTemplate(
      Timeline('Program ${p + 1}', [
        for (var s = 0; s < count; s++)
          Segment('Segment ${s + 1}', 1 + s % 9, speaker: 'Speaker ${s % 5}'),
      ], DisplaySettings()),
    );
  }
  for (var r = 0; r < 500; r++) {
    final program = state.templates[r % state.templates.length];
    var s = transition(
      Session(id: 'bench-$r', anchor: at),
      'load',
      at,
      value: program,
    );
    s = transition(s, 'start', at);
    at = Stamp(at.mono + 60000, at.wall + 7 * 86400000, 'bench');
    s = transition(s, 'end', at);
    state.reports.add(ServiceReport.fromSession(s, at));
  }
  state.session = Session(id: 'idle', anchor: at);
  return jsonEncode(state.toJson());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Scroll Programs, Reports and a long program', (t) async {
    final c = AppController(BenchmarkPort(heavyState()));
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();

    Future<void> fling(String key) => binding.watchPerformance(() async {
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 6; i++) {
        await t.fling(list, const Offset(0, -1200), 3000);
        await t.pumpAndSettle();
      }
      for (var i = 0; i < 6; i++) {
        await t.fling(list, const Offset(0, 1200), 3000);
        await t.pumpAndSettle();
      }
    }, reportKey: key);

    await t.tap(find.byType(NavigationDestination).at(1));
    await t.pumpAndSettle();
    await fling('programs_scroll');

    await t.tap(find.byType(NavigationDestination).at(2));
    await t.pumpAndSettle();
    await fling('reports_scroll');

    await t.tap(find.byType(NavigationDestination).at(1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('template-row:Program 1')));
    await t.pumpAndSettle();
    await fling('program_details_scroll');
  });
}
