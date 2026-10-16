import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/pixels.dart';
import 'feature_cases.dart';
import 'domain_test.dart' show FakePort;

void main() {
  for (final entry in featureCases.entries) {
    test(entry.key, entry.value);
  }

  test(
    'Warning persistence failure never publishes uncommitted output',
    () async {
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act(
        'load',
        value: Timeline(
          'Warnings',
          const [Segment('Talk', 3)],
          DisplaySettings(
            warnings: [
              const WarningRule(120, TextLayout('TWO'), destination: 'stage'),
              const WarningRule(0, TextLayout('ZERO'), destination: 'stage'),
            ],
          ),
        ),
      );
      await c.act('start');
      port.at = at(60);
      port.fail = true;
      await c.tick();
      expect(c.state.session.warningSeen, isEmpty);
      expect(c.simulator.delivered!.text, '02:00');
      expect(c.error, isNotNull);
      port.fail = false;
      port.at = at(181);
      expect(await c.retry!(), true);
      expect(c.simulator.delivered!.text, 'ZERO');
      expect(c.state.session.warningSeen, [0, 1]);
      c.dispose();
    },
  );

  test(
    'Report and ended state commit atomically and restore exactly once',
    () async {
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      port.at = at(50);
      port.fail = true;
      expect(await c.act('end'), false);
      expect(c.state.reports, isEmpty);
      expect(c.state.session.active, true);
      port.at = at(60);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.reports.single.totalMs, 60000);
      final restarted = AppController(port);
      await restarted.initialize(startTicker: false);
      expect(restarted.state.reports.length, 1);
      expect(restarted.state.reports.single.totalMs, 60000);
      expect(await restarted.act('end'), false);
      expect(restarted.state.reports.length, 1);
      restarted.dispose();
      c.dispose();
    },
  );

  test('Service Matrix preserves every original style and size', () {
    for (final height in [1, 2]) {
      for (final bold in [false, true]) {
        for (final italic in [false, true]) {
          final layout = TextLayout(
            'Ag',
            height: height,
            bold: bold,
            italic: italic,
          );
          validateLayout(layout);
          expect(renderPixels(layout, 0).length, 512);
          expect(
            renderPixels(layout, 0),
            renderPixels(
              TextLayout.fromJson(jsonDecode(jsonEncode(layout.toJson()))),
              0,
            ),
          );
        }
      }
    }
  });
}
