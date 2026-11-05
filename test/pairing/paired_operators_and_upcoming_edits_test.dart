import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import '../domain/service_timing_test.dart'
    show FakePort, start, after, running;
import '../hardware/hardware_integration_test.dart' show W2Port, setup, flush;

Future<void> until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsedMilliseconds > 8000)
      fail('Timed out waiting for paired state');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('Paired operator commands use the host clock and save path', () async {
    final c = AppController(FakePort()), client = PairHub();
    await c.initialize(startTicker: false);
    addTearDown(() async {
      await client.stop();
      await c.pairing.stop();
      client.dispose();
      c.dispose();
    });
    await c.act(
      'load',
      value: Timeline('Service', const [Segment('Talk', 1)], DisplaySettings()),
    );
    await c.act('start');
    await c.pairing.host('127.0.0.1');
    await client.join(c.pairing.code!.encode(), 'Operator', 'operator');
    await until(() => c.pairing.peers.isNotEmpty);
    final peer = c.pairing.peers.single;
    await c.pairing.approve(peer);
    c.pairing.grant(peer);
    await until(() => client.canControl);
    expect(await c.act('pause'), false);
    await client.sendCommand('pause', null);
    await until(() => c.state.session.paused);
    expect(c.state.session.events.any((e) => e.kind == 'operator'), true);
    c.pairing.reclaim();
    await until(() => !client.canControl);
    expect(await c.act('pause'), true);
    // A receiver's operator clock can show overtime while its stage output remains zero.
    c.now = after(70);
    final snapshot = c.pairedSnapshot(false);
    expect(snapshot['remaining'], '+00:10');
    expect(snapshot['displayText'], '00:00');
  });
  test(
    'Upcoming edits preserve current timing, completed metrics, and private notes',
    () {
      final s = transition(running(), 'advance', after(601));
      final before = s.remaining(after(630)),
          anchor = s.anchor,
          actual = s.run!.actualMs.first;
      replaceUpcoming(s, const [
        Segment('New', 3, notes: 'Private'),
        Segment('Last', 2),
      ], after(630));
      expect(s.remaining(after(630)), before);
      expect(s.anchor, anchor);
      expect(s.timeline!.segments.map((v) => v.name), [
        'First',
        'Second',
        'New',
        'Last',
      ]);
      expect(s.run!.actualMs, [actual, null, null, null]);
      expect(s.undo, isNull);
      final restored = Session.fromJson(s.toJson());
      expect(restored.timeline!.segments[2].notes, 'Private');
      final report = transition(restored, 'end', after(650));
      expect(report.run!.actualMs.length, 4);
      expect(report.events.last.kind, 'end');
    },
  );
  test('All upcoming segments can be removed without changing current', () {
    final s = running();
    replaceUpcoming(s, [], after(30));
    expect(s.timeline!.segments.length, 1);
    expect(s.remaining(after(30)), 570000);
    expect(s.run!.actualMs.length, 1);
    expect(s.run!.pausedMs.length, 1);
    expect(
      () => replaceUpcoming(Session(id: 'idle', anchor: start), [], start),
      throwsA(isA<RuleError>()),
    );
  });
  test(
    'Catch-up proposal shortens only future durations and preserves notes',
    () {
      final s = running();
      final current = s.timeline!.segments.first.toJson();
      final proposed = catchUpPlan(s, after(60), after(13 * 60).wall);
      expect(proposed.map((v) => v.minutes), [2, 1]);
      expect(s.timeline!.segments.first.toJson(), current);
      expect(s.timeline!.segments[1].minutes, 5);
      expect(
        () => catchUpPlan(s, after(60), after(10 * 60).wall),
        throwsA(isA<RuleError>()),
      );
    },
  );
  test('Target finish persists and rejects malformed timestamps', () {
    final s = running()..targetFinishWall = after(1000).wall;
    expect(Session.fromJson(s.toJson()).targetFinishWall, s.targetFinishWall);
    expect(
      () => Session.fromJson({...s.toJson(), 'targetFinishWall': 'tomorrow'}),
      throwsA(isA<RuleError>()),
    );
  });
  test('Print output excludes private notes by default and escapes HTML', () {
    final t = Timeline('A < B', const [
      Segment('Talk', 5, speaker: '<speaker>', notes: '<secret>'),
    ], DisplaySettings());
    final public = serviceSheetHtml(t, 'Church & Co');
    expect(public, contains('Church &amp; Co'));
    expect(public, contains('&lt;speaker&gt;'));
    expect(public, isNot(contains('secret')));
    expect(
      serviceSheetHtml(t, '', privateNotes: true),
      contains('&lt;secret&gt;'),
    );
  });
  test(
    'Deleting an in-flight warning keeps its full duration then returns to timer',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(
          570,
          TextLayout('WARN'),
          destination: 'stage',
          durationSeconds: 8,
        ),
      ]);
      p.at = after(30);
      await c.tick();
      await flush();
      await c.tick();
      final accepted = c.state.session.automaticCueAt!;
      expect(await c.setSharedWarnings([]), true);
      await flush();
      expect(c.state.session.automaticCue!.text, 'WARN');
      expect(
        c.state.session.hasAutomaticCue(
          Stamp(accepted.mono + 7000, accepted.wall + 7000, accepted.boot),
        ),
        true,
      );
      p.at = after(39);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.layout?.text, isNot('WARN'));
      expect(c.state.session.timeline!.display.warnings, isEmpty);
    },
  );
  test(
    'Offline LED sign does not block service and paired-screen cues',
    () async {
      final p = W2Port();
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.hardware.disconnect();
      expect(await c.act('cue', value: const TextLayout('AMEN')), true);
      expect(c.state.session.alert!.text, 'AMEN');
      expect(c.pairedSnapshot(false)['displayText'], 'AMEN');
      expect(p.sent.length, 1);
    },
  );
  test('Font labels change while persisted font IDs remain compatible', () {
    expect(displayFontNames['cuekeeper_matrix'], 'I-Proton Matrix');
    expect(displayFontNames['cuekeeper_sq_matrix'], 'I-Proton Sq-Matrix');
    expect(
      TextLayout.fromJson(const TextLayout('A').toJson()).font,
      'cuekeeper_matrix',
    );
  });
  test('Pairing code rejects expired invitations and public addresses', () {
    final expiry = DateTime.now().millisecondsSinceEpoch + 60000;
    final k = pairRandom(32);
    expect(
      PairCode.parse(PairCode('192.168.10.2', 1234, k, expiry).encode()).port,
      1234,
    );
    expect(
      () => PairCode.parse(PairCode('8.8.8.8', 1234, k, expiry).encode()),
      throwsA(isA<RuleError>()),
    );
    expect(
      () => PairCode.parse(PairCode('192.168.10.2', 1234, k, 1).encode()),
      throwsA(isA<RuleError>()),
    );
  });
  test(
    'Authenticated frames reject replay, corruption, and another connection binding',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final accepted = server.first;
      final client = await Socket.connect('127.0.0.1', server.port);
      final socket = await accepted;
      final input = StreamIterator(pairLines(socket));
      final key = await AesGcm.with256bits().newSecretKey();
      final out = PairWire(client, key, 'one'),
          inbound = PairWire(socket, key, 'one');
      await out.send({'type': 'secret', 'value': 'private note'});
      expect(await input.moveNext(), true);
      final line = input.current;
      expect(line, isNot(contains('private note')));
      expect((await inbound.decode(line))['value'], 'private note');
      await expectLater(inbound.decode(line), throwsA(isA<RuleError>()));
      await expectLater(
        PairWire(socket, key, 'two').decode(line),
        throwsA(isA<RuleError>()),
      );
      final corrupt = base64Decode(line)..[20] ^= 1;
      await expectLater(
        PairWire(socket, key, 'one').decode(base64Encode(corrupt)),
        throwsA(anything),
      );
      await client.close();
      out.close();
      inbound.close();
      await input.cancel();
      await server.close();
    },
  );
  test(
    'Host approval, one operator, notes isolation, reclaim and disconnect',
    () async {
      final host = PairHub(), viewer = PairHub(), operator = PairHub();
      addTearDown(() async {
        await viewer.stop();
        await operator.stop();
        await host.stop();
        viewer.dispose();
        operator.dispose();
        host.dispose();
      });
      var revision = 3, commands = 0;
      host.snapshotFor = (private) => {
        'revision': revision,
        'service': 'Sunday',
        if (private) 'notes': 'PRIVATE',
      };
      host.command = (action, value, expected) async {
        if (expected != revision) return false;
        commands++;
        revision++;
        return true;
      };
      await host.host('127.0.0.1');
      await viewer.join(host.code!.encode(), 'Observer', 'viewer');
      await until(() => host.peers.length == 1);
      expect(viewer.snapshot, isNull);
      await host.approve(host.peers.first);
      await until(() => viewer.snapshot != null);
      expect(viewer.snapshot!.containsKey('notes'), false);
      expect(() => host.grant(host.peers.first), throwsA(isA<RuleError>()));
      await operator.join(host.code!.encode(), 'Operator', 'operator');
      await until(() => host.peers.length == 2);
      final peer = host.peers.last;
      await host.approve(peer);
      await until(() => operator.snapshot != null);
      expect(operator.canControl, false);
      expect(operator.snapshot!.containsKey('notes'), false);
      host.grant(peer);
      await until(() => operator.canControl);
      expect(host.localControl, false);
      expect(operator.snapshot!['notes'], 'PRIVATE');
      await operator.sendCommand('pause', null, expectedRevision: 2);
      await until(
        () => operator.requestResult.startsWith('Action unavailable'),
      );
      expect(commands, 0);
      await operator.sendCommand('pause', null);
      await until(() => commands == 1);
      host.reclaim();
      await until(() => !operator.canControl);
      expect(host.localControl, true);
      expect(operator.snapshot!.containsKey('notes'), false);
      host.grant(peer);
      await until(() => operator.canControl);
      await operator.stop();
      await until(() => host.localControl);
      expect(viewer.snapshot!.containsKey('notes'), false);
    },
  );
  test(
    'Pending approval stays connected beyond the first receive timeout',
    () async {
      final host = PairHub(), client = PairHub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      await host.host('127.0.0.1');
      await client.join(host.code!.encode(), 'Stage', 'stage');
      await until(() => host.peers.isNotEmpty);
      await Future<void>.delayed(const Duration(seconds: 13));
      expect(client.status, 'Waiting for host approval');
      expect(host.peers.length, 1);
      await host.approve(host.peers.single);
      await until(() => client.snapshot != null);
    },
  );
  test(
    'Paired snapshots do not expose notes or prepared cue text to viewers',
    () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act(
        'load',
        value: Timeline('Sunday', const [
          Segment('Talk', 5, notes: 'SECRET'),
        ], DisplaySettings()),
      );
      final public = c.pairedSnapshot(false), priv = c.pairedSnapshot(true);
      expect(jsonEncode(public), isNot(contains('SECRET')));
      expect(public.containsKey('cues'), false);
      expect(jsonEncode(priv), contains('SECRET'));
      expect(priv.containsKey('cues'), true);
    },
  );
}
