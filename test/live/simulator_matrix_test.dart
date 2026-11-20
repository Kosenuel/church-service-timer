import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/simulator_matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';

const wrapUp = TextLayout('PLEASE WRAP UP', speed: 12);

void main() {
  group('The simulator', () {
    test('says when a scroll or a flash next changes', () {
      final sim = Simulator();
      var s = running();
      sim.update(s, start);
      // The countdown holds still between ticks.
      expect(sim.moving, isFalse);
      expect(sim.nextChangeAfter(start.mono), isNull);
      s = transition(s, 'cue', start, value: wrapUp);
      sim.update(s, start);
      expect(sim.moving, isTrue);
      final from = sim.deliveredAt;
      // 12 columns a second: one every 83 or 84 ms.
      expect(sim.nextChangeAfter(from), from + 84);
      expect(sim.nextChangeAfter(from + 84), from + 167);
      expect(sim.nextChangeAfter(from + 999), from + 1000);
      expect(sim.pixelsAt(from + 500), renderPixels(wrapUp, 500));
      s = transition(
        s,
        'cue',
        after(1),
        value: const TextLayout('AMEN', effect: 'flash'),
      );
      sim.update(s, after(1));
      expect(sim.moving, isTrue);
      expect(sim.nextChangeAfter(sim.deliveredAt + 10), sim.deliveredAt + 500);
      // Short text that fits the sign does not scroll.
      s = transition(s, 'cue', after(2), value: const TextLayout('HI'));
      sim.update(s, after(2));
      expect(sim.moving, isFalse);
    });
  });

  group('The simulator on Live', () {
    late AppController c;
    late FakePort port;

    Future<void> running(WidgetTester t) async {
      port = FakePort();
      c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act('cue', value: wrapUp);
      await c.tick();
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(width: 320, child: SimulatorMatrix(controller: c)),
          ),
        ),
      );
    }

    List<bool> shown(WidgetTester t) =>
        t.widget<LedMatrix>(find.byType(LedMatrix)).pixels;

    testWidgets('scrolls a column at a time, on time, between ticks', (
      t,
    ) async {
      await running(t);
      final from = c.simulator.deliveredAt;
      expect(shown(t), c.simulator.pixels);
      // A second of frames with no tick from the app's clock, which stops
      // ticking while it saves.
      final changes = <int>[];
      var last = shown(t);
      for (var ms = 0; ms <= 1000; ms += 4) {
        await t.pump(const Duration(milliseconds: 4));
        final now = shown(t);
        if (!listEquals(now, last)) changes.add(ms + 4);
        last = now;
      }
      // Each of the 12 columns came when due, one at a time, never two.
      expect(changes.length, 12);
      for (var i = 0; i < changes.length; i++) {
        final due = ((i + 1) * 1000 + 11) ~/ 12;
        expect(changes[i], inInclusiveRange(due, due + 4));
      }
      expect(last, renderPixels(wrapUp, c.now.mono - from + 1000));
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('a tick that arrives late does not step it back', (t) async {
      await running(t);
      await t.pump(const Duration(milliseconds: 600));
      final ahead = shown(t);
      // The clock reading of a tick taken a little earlier.
      port.at = Stamp(c.now.mono + 450, c.now.wall + 450, c.now.boot);
      await c.tick();
      await t.pump();
      expect(shown(t), ahead);
      // Then it carries on from there.
      await t.pump(const Duration(milliseconds: 300));
      expect(listEquals(shown(t), ahead), isFalse);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('holds its picture while the service is held', (t) async {
      await running(t);
      await t.pump(const Duration(milliseconds: 300));
      await c.act('disconnect');
      await c.tick();
      await t.pump();
      final held = shown(t);
      await t.pump(const Duration(seconds: 1));
      expect(shown(t), held);
      expect(t.widget<LedMatrix>(find.byType(LedMatrix)).stale, isTrue);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
