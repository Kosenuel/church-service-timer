import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/practice_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort, after;

void main() {
  test(
    'A practice run ticks steps, saves no report and changes no data',
    () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      expect(c.destination, 'simulator');
      final programs = jsonEncode([
        for (final p in c.state.templates) p.toJson(),
      ]);
      final recent = Map.of(c.state.programLibrary.recent);
      expect(c.practice.blocker, isNull);
      expect(await c.practice.start(), isTrue);
      expect(c.practice.active, isTrue);
      expect(c.state.session.rate, practiceRate);
      expect(c.practice.current!.id, 'start');

      await c.act('start');
      await c.act('pause');
      await c.act('pause');
      await c.act('adjust', value: 120);
      await c.act('adjust', value: -120);
      await c.act('advance');
      await c.act('undo');
      await c.act('advance');
      await c.act('cue', value: c.state.stageCues.first);
      await c.act('timer');
      await c.act('blank');
      await c.act('blank');
      expect(c.practice.done, {
        'start',
        'pause',
        'adjust',
        'next',
        'cue',
        'blank',
      });
      expect(c.practice.current!.id, 'overtime');

      // At 5×, the 5-minute segment runs out after a minute.
      port.at = after(70);
      await c.tick();
      expect(c.practice.done, contains('overtime'));

      await c.act('end');
      expect(c.practice.active, isFalse);
      expect(c.practice.finished!.done, practiceSteps.length);
      expect(c.state.reports, isEmpty);
      expect(c.state.practisedWall, isNotNull);
      expect(
        jsonEncode([for (final p in c.state.templates) p.toJson()]),
        programs,
      );
      expect(c.state.programLibrary.recent, recent);
    },
  );

  test(
    'Practice waits for the simulator and never interrupts a service',
    () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.selectDestination('led');
      expect(await c.practice.start(), isFalse);
      await c.selectDestination('simulator');
      await c.act('load', value: c.state.templates.first);
      expect(c.practice.blocker, contains('current service'));
      expect(await c.practice.start(), isFalse);
      await c.act('cancelReady');
      expect(await c.practice.start(), isTrue);
      c.practice.skip();
      expect(c.practice.skipped, {'start'});
      await c.practice.leave();
      expect(c.practice.active, isFalse);
      expect(c.state.reports, isEmpty);
      expect(c.state.practisedWall, isNull);
    },
  );

  test(
    'Changing to a real program in Ready ends practice and keeps reports',
    () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      expect(await c.practice.start(), isTrue);
      await c.act('load', value: c.state.templates.first);
      expect(c.practice.active, isFalse);
      expect(c.state.session.noReport, isFalse);
      expect(c.state.session.rate, 1);
      await c.act('start');
      await c.act('end');
      expect(c.state.reports, hasLength(1));
    },
  );
}
