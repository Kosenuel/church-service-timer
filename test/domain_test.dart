import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/platform.dart';
import 'package:church_service_timer/pixels.dart';

const start = Stamp(100000, 10000000, 'boot-1');
Stamp after(int seconds, {int wallShift = 0, String boot = 'boot-1'}) => Stamp(
  start.mono + seconds * 1000,
  start.wall + seconds * 1000 + wallShift,
  boot,
);
Timeline timeline() => Timeline('Sunday', const [
  Segment('First', 10),
  Segment('Second', 5),
  Segment('Last', 1),
], DisplaySettings());
Session loaded() => transition(
  Session(id: 'idle', anchor: start),
  'load',
  start,
  value: timeline(),
);
Session running() => transition(loaded(), 'start', start);

class FakePort implements DevicePort {
  Stamp at = start;
  String? data;
  bool fail = false;
  Completer<void>? saveGate;
  @override
  Future<Stamp> clock() async => at;
  @override
  Future<String?> load() async => data;
  @override
  Future<void> save(String state) async {
    await saveGate?.future;
    if (fail) throw Exception('Disk full');
    data = state;
  }

  @override
  Future<Map<String, dynamic>?> pickFile() async => null;
  @override
  Future<void> exportFile(String filename, String content) async {}
}

void main() {
  group('Authoritative service clock', () {
    test('Ready never starts or emits output', () {
      final s = loaded();
      expect(s.remaining(after(100)), 600000);
      expect(s.intended(after(100)), isNull);
      expect(
        () => transition(s, 'cue', start, value: const TextLayout('STOP')),
        throwsA(isA<RuleError>()),
      );
      expect(recover(s, after(3600)).phase, 'ready');
    });
    test('Delayed callbacks do not cause drift; wall clock is irrelevant', () {
      final s = running();
      expect(s.formatted(after(90)), '08:30');
      expect(s.formatted(after(90, wallShift: -8000000)), '08:30');
      expect(s.formatted(after(90, wallShift: 8000000)), '08:30');
    });
    test('Pause freezes and resume retains elapsed accounting', () {
      var s = transition(running(), 'pause', after(90));
      expect(s.formatted(after(500)), '08:30');
      s = transition(s, 'pause', after(500));
      expect(s.formatted(after(530)), '08:00');
    });
    test('Alert replacement and dismissal preserve timer', () {
      var s = transition(
        running(),
        'cue',
        after(20),
        value: const TextLayout('WRAP UP'),
      );
      expect(s.intended(after(90))!.text, 'WRAP UP');
      expect(s.formatted(after(90)), '08:30');
      s = transition(s, 'cue', after(100), value: const TextLayout('MIC LOW'));
      s = transition(s, 'timer', after(120));
      expect(s.intended(after(120))!.text, '08:00');
    });
    test('Alerts cover expiry and zero has no implicit advance', () {
      var s = transition(
        running(),
        'cue',
        start,
        value: const TextLayout('WAIT'),
      );
      expect(s.intended(after(900))!.text, 'WAIT');
      s = transition(s, 'timer', after(900));
      expect(s.intended(after(900))!.text, '00:00');
      expect(s.index, 0);
      expect(s.phase, 'active');
    });
    test(
      'Separate adjustments clamp, enforce upper bound, preserve alert and pause',
      () {
        var s = transition(
          running(),
          'cue',
          start,
          value: const TextLayout('WAIT'),
        );
        s = transition(s, 'pause', start);
        s = transition(s, 'adjust', start, value: 120);
        expect(s.formatted(after(500)), '12:00');
        expect(s.alert!.text, 'WAIT');
        s = transition(s, 'adjust', after(500), value: -900);
        expect(s.formatted(after(500)), '00:00');
        s = transition(s, 'adjust', after(500), value: 5999);
        expect(s.formatted(after(600)), '99:59');
        expect(
          () => transition(s, 'adjust', after(600), value: 1),
          throwsA(isA<RuleError>()),
        );
      },
    );
    test('Adding after expiry resumes unless explicitly paused', () {
      var s = transition(running(), 'adjust', after(900), value: 30);
      expect(s.formatted(after(910)), '00:20');
      s = transition(s, 'pause', after(910));
      s = transition(s, 'adjust', after(920), value: 30);
      expect(s.formatted(after(950)), '00:50');
    });
    test(
      'Advance from pause runs next; undo restores paused checkpoint and cue',
      () {
        var s = transition(running(), 'pause', after(420));
        s = transition(s, 'cue', after(421), value: const TextLayout('WAIT'));
        s = transition(s, 'advance', after(422));
        expect(s.paused, false);
        expect(s.formatted(after(427)), '04:55');
        s = transition(s, 'undo', after(427));
        expect(s.formatted(after(1000)), '03:00');
        expect(s.paused, true);
        expect(s.alert!.text, 'WAIT');
        expect(s.undo, isNull);
      },
    );
    test('Undo running time accounts for elapsed time', () {
      var s = transition(running(), 'advance', after(420));
      expect(s.fastUndo(after(430)), true);
      expect(s.fastUndo(after(431)), false);
      s = transition(s, 'undo', after(425));
      expect(s.formatted(after(425)), '02:55');
    });
    test('Adjusting next segment requires undo confirmation', () {
      var s = transition(running(), 'advance', after(420));
      s = transition(s, 'adjust', after(421), value: 120);
      expect(s.fastUndo(after(422)), false);
      s = transition(s, 'undo', after(425));
      expect(s.formatted(after(425)), '02:55');
    });
    test('Revision rejects duplicate advance and stale confirmations', () {
      final s = running();
      final next = transition(
        s,
        'advance',
        start,
        expectedRevision: s.revision,
      );
      expect(
        () => transition(next, 'advance', start, expectedRevision: s.revision),
        throwsA(isA<RuleError>()),
      );
    });
    test('End clears alerts/undo and never restarts on recovery', () {
      var s = transition(running(), 'advance', after(30));
      s = transition(s, 'cue', after(31), value: const TextLayout('WAIT'));
      s = transition(s, 'end', after(32));
      s = recover(s, after(60));
      expect(s.phase, 'ended');
      expect(s.alert, isNull);
      expect(s.undo, isNull);
      expect(s.intended(after(100))!.text, 'Hallelujah');
    });
    test('Final segment cannot advance and never ends automatically', () {
      var s = transition(running(), 'advance', start);
      s = transition(s, 'advance', start);
      expect(() => transition(s, 'advance', start), throwsA(isA<RuleError>()));
      expect(s.remaining(after(9999)), 0);
      expect(s.active, true);
    });
  });
  group('Recovery and output ownership', () {
    test('30-minute boundary and repeated recovery preserve hold', () {
      expect(recover(running(), after(1799)).held, false);
      final s = recover(running(), after(1800));
      expect(s.held, true);
      expect(recover(s, after(1801)).held, true);
    });
    test('Reboot fallback is flagged uncertain and held', () {
      final s = recover(running(), after(90, boot: 'boot-2'));
      expect(s.uncertain, true);
      expect(s.held, true);
      expect(s.formatted(after(90, boot: 'boot-2')), '08:30');
    });
    test(
      'Manual disconnect survives reopening and long outage requires release',
      () {
        var s = transition(running(), 'disconnect', after(10));
        expect(recover(s, after(20)).disconnected, true);
        s = transition(s, 'connect', after(1810));
        expect(s.held, true);
        s = transition(s, 'release', after(1811));
        expect(s.held, false);
        expect(s.disconnected, false);
      },
    );
    test('Reconnect delivers current time with no missed update replay', () {
      final adapter = Simulator();
      var s = running();
      adapter.update(s, after(90));
      expect(adapter.delivered!.text, '08:30');
      s = transition(s, 'disconnect', after(90));
      adapter.update(s, after(120));
      expect(adapter.delivered!.text, '08:30');
      s = transition(s, 'connect', after(120));
      adapter.update(s, after(120));
      expect(adapter.delivered!.text, '08:00');
    });
    test('Dismissed cue while disconnected never replays', () {
      var s = transition(
        running(),
        'cue',
        start,
        value: const TextLayout('WAIT'),
      );
      final adapter = Simulator();
      adapter.update(s, start);
      s = transition(s, 'disconnect', after(1));
      s = transition(s, 'timer', after(2));
      s = transition(s, 'connect', after(5));
      adapter.update(s, after(5));
      expect(adapter.delivered!.text, '09:55');
    });
    test('Loading Ready and cancelling never revive pending ended output', () {
      var s = transition(running(), 'disconnect', start);
      s = transition(s, 'end', start);
      s = transition(s, 'load', after(1), value: timeline());
      s = transition(s, 'connect', after(2));
      final adapter = Simulator();
      adapter.update(s, after(2));
      expect(adapter.delivered, isNull);
      s = transition(s, 'cancelReady', after(3));
      adapter.update(s, after(3));
      expect(adapter.delivered, isNull);
      expect(s.held, true);
    });
    test('Template edits do not mutate active snapshot', () {
      final state = AppState.fresh(start);
      state.session = transition(
        state.session,
        'load',
        start,
        value: state.templates.first,
      );
      state.templates[0] = Timeline('Changed', const [
        Segment('Other', 1),
      ], DisplaySettings());
      expect(state.session.timeline!.name, 'Sunday Service');
      expect(state.session.timeline!.segments.first.minutes, 15);
    });
  });
  group('Imports and validation', () {
    test('JSON round trip preserves all text formatting', () {
      final t = Timeline(
        'Styled',
        const [Segment('Music', 10)],
        DisplaySettings(
          end: const TextLayout(
            'Peace',
            bold: true,
            italic: true,
            height: 2,
            speed: 18,
          ),
        ),
      );
      expect(
        importTemplate(exportJson(t), 'test.json', DisplaySettings()).toJson(),
        t.toJson(),
      );
    });
    test('CSV quoting preserves commas, quotes and row order', () {
      final t = Timeline('CSV', const [
        Segment('Music, prayer', 2),
        Segment('"Good morning"', 3),
      ], DisplaySettings());
      expect(
        importTemplate(exportCsv(t), 'CSV.csv', DisplaySettings()).toJson(),
        t.toJson(),
      );
    });
    test('One invalid CSV row blocks all rows and identifies row', () {
      expect(
        () => importTemplate(
          'Segment Name,Duration (Minutes)\nValid,1\nBad,1.5\n',
          'x.csv',
          DisplaySettings(),
        ),
        throwsA(predicate((e) => e.toString().contains('Row 3'))),
      );
    });
    test(
      'Empty, malformed, oversized, excessive segments and forbidden fields rejected',
      () {
        for (final content in [
          '',
          'Segment Name,Duration (Minutes)\nBad,0',
          'Segment Name,Duration (Minutes)\nBad,05:30',
          'Segment Name,Duration (Minutes)\n"Unclosed,5',
        ]) {
          expect(
            () => importTemplate(content, 'x.csv', DisplaySettings()),
            throwsA(isA<RuleError>()),
          );
        }
        expect(
          () => importTemplate('x' * 1048577, 'x.csv', DisplaySettings()),
          throwsA(isA<RuleError>()),
        );
        final j = timeline().toJson()..['controllerAddress'] = 'example';
        expect(
          () => importTemplate(jsonEncode(j), 'x.json', DisplaySettings()),
          throwsA(isA<RuleError>()),
        );
        j.remove('controllerAddress');
        j['schemaVersion'] = 3;
        expect(() => Timeline.fromJson(j), throwsA(isA<RuleError>()));
        expect(
          () => Timeline.fromJson(
            Timeline(
              'Too many',
              List.filled(201, const Segment('x', 1)),
              DisplaySettings(),
            ).toJson(),
          ),
          throwsA(isA<RuleError>()),
        );
      },
    );
    test('Names are trimmed, length bounded, case-insensitively unique', () {
      final a = AppState.fresh(start);
      final t = timeline().renamed(' Sunday Service ');
      expect(t.name, 'Sunday Service');
      expect(() => a.saveTemplate(t), throwsA(isA<RuleError>()));
      expect(() => nameValue('a' * 81, 'Name'), throwsA(isA<RuleError>()));
    });
    test('CSV captures defaults without sharing mutable lists', () {
      final d = DisplaySettings(end: const TextLayout('Amen'));
      final t = importTemplate(
        'Segment Name,Duration (Minutes)\nPrayer,2',
        'x.csv',
        d,
      );
      expect(t.display.end.text, 'Amen');
      expect(
        () => t.display.cues.add(const TextLayout('NEW')),
        throwsUnsupportedError,
      );
    });
  });
  group('Pixel output', () {
    test('Countdown fits and produces exactly 512 bits', () {
      for (final value in ['00:00', '11:11', '88:88', '99:59']) {
        final l = TextLayout(value, effect: 'static', height: 2);
        validateLayout(l);
        expect(textWidth(l), lessThanOrEqualTo(32));
        expect(renderPixels(l, 0).length, 512);
        expect(renderPixels(l, 0).where((x) => x).length, greaterThan(0));
      }
    });
    test('Bold and italic materially change rendered pixels', () {
      final regular = renderPixels(const TextLayout('Hi', effect: 'static'), 0);
      expect(
        renderPixels(const TextLayout('Hi', effect: 'static', bold: true), 0),
        isNot(regular),
      );
      expect(
        renderPixels(const TextLayout('Hi', effect: 'static', italic: true), 0),
        isNot(regular),
      );
    });
    test(
      'Unsupported characters and oversized static text fail explicitly',
      () {
        expect(
          () => validateLayout(const TextLayout('Hello 🙂')),
          throwsA(isA<RuleError>()),
        );
        expect(
          () =>
              validateLayout(const TextLayout('Hallelujah', effect: 'static')),
          throwsA(isA<RuleError>()),
        );
        expect(
          () => validateLayout(const TextLayout('Hallelujah')),
          returnsNormally,
        );
      },
    );
    test('Scrolling advances and flash has a dark phase', () {
      const l = TextLayout('NURSERY CALL');
      expect(renderPixels(l, 0), isNot(renderPixels(l, 1000)));
      expect(
        renderPixels(
          const TextLayout('STOP', effect: 'flash'),
          600,
        ).any((p) => p),
        false,
      );
    });
  });
  group('Atomic publication', () {
    test('Background callbacks cannot hide a 30-minute absence', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      port.at = after(10);
      await c.suspend();
      final saved = port.data, frame = c.simulator.delivered!.text;
      for (final seconds in [70, 600, 1200, 1810]) {
        port.at = after(seconds);
        await c.tick();
      }
      expect(port.data, saved);
      expect(c.simulator.delivered!.text, frame);
      await c.resume();
      expect(c.state.session.held, true);
      expect(c.simulator.delivered!.text, frame);
      expect(c.state.session.formatted(port.at), '00:00');
      await c.act('releaseTimer');
      expect(c.simulator.delivered!.text, '00:00');
      c.dispose();
    });
    test('Resume waits for an in-flight save before recovery', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      final gate = Completer<void>();
      port.saveGate = gate;
      final advancing = c.act('advance');
      await Future<void>.delayed(Duration.zero);
      await c.suspend();
      port.at = after(1800);
      final resuming = c.resume();
      expect(c.busy, true);
      expect(c.simulator.delivered!.text, '10:00');
      gate.complete();
      await advancing;
      await resuming;
      expect(c.state.session.index, 1);
      expect(c.state.session.held, true);
      expect(c.simulator.delivered!.text, '10:00');
      c.dispose();
    });
    test('Failed recovery prevents output until a durable retry', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.suspend();
      port.at = after(30);
      port.fail = true;
      await c.resume();
      await c.tick();
      expect(c.simulator.delivered!.text, '10:00');
      expect(await c.act('advance'), false);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.session.held, true);
      await c.act('releaseTimer');
      expect(c.simulator.delivered!.text, '09:30');
      c.dispose();
    });
    test('Successful checkpoint retry clears its error', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      port.fail = true;
      await c.checkpoint();
      expect(c.storageUncertain, true);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.error, isNull);
      expect(c.retry, isNull);
      c.dispose();
    });
    test(
      'Failed advance preserves state and emits no new display; retry accounts for time',
      () async {
        final port = FakePort();
        final c = AppController(port);
        await c.initialize(startTicker: false);
        await c.act('load', value: timeline());
        await c.act('start');
        final rev = c.state.session.revision,
            shown = c.simulator.delivered!.text;
        port.fail = true;
        expect(await c.act('advance'), false);
        expect(c.state.session.revision, rev);
        expect(c.state.session.index, 0);
        expect(c.simulator.delivered!.text, shown);
        port.at = after(90);
        await c.tick();
        expect(c.state.session.formatted(port.at), '08:30');
        port.fail = false;
        expect(await c.retry!(), true);
        expect(c.state.session.index, 1);
        c.dispose();
      },
    );
    test('Failed cue, end, and import retain committed state', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      port.fail = true;
      await c.act('cue', value: const TextLayout('WAIT'));
      expect(c.state.session.alert, isNull);
      await c.act('end');
      expect(c.state.session.active, true);
      final count = c.state.templates.length;
      await c.commit((a, _) => a.saveTemplate(timeline()));
      expect(c.state.templates.length, count);
      c.dispose();
    });
    test(
      'A stale retry cannot repeat an action after another revision',
      () async {
        final port = FakePort();
        final c = AppController(port);
        await c.initialize(startTicker: false);
        await c.act('load', value: timeline());
        await c.act('start');
        port.fail = true;
        await c.act('advance');
        final retry = c.retry!;
        port.fail = false;
        await c.act('pause');
        expect(await retry(), false);
        expect(c.state.session.index, 0);
        c.dispose();
      },
    );
    test('Corrupt save blocks output instead of silently resetting', () async {
      final port = FakePort()..data = '{broken';
      final c = AppController(port);
      await c.initialize(startTicker: false);
      expect(c.corrupt, true);
      expect(c.simulator.delivered, isNull);
      expect(port.data, '{broken');
      c.dispose();
    });
    test('Persisted active alert and timer survive reopening', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act('cue', value: const TextLayout('WAIT'));
      c.dispose();
      port.at = after(90);
      final reopened = AppController(port);
      await reopened.initialize(startTicker: false);
      expect(reopened.state.session.formatted(port.at), '08:30');
      expect(reopened.simulator.delivered!.text, 'WAIT');
      reopened.dispose();
    });
  });
}
