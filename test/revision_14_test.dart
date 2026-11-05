import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/hardware/hardware_output.dart';
import 'domain_test.dart' show FakePort, start, after, timeline;
import 'hardware_integration_test.dart' show W2Port, setup, flush;
import 'revision_13_test.dart' show until;

class RecoveryPort extends W2Port {
  int connects = 0;
  bool auto = true, found = true;
  String? saved;
  Completer<List<Json>>? discoveryGate;
  Completer<void>? preferenceGate;
  @override
  Future<void> setDisplayAutoReconnect(bool value) async {
    auto = value;
    if (value) await preferenceGate?.future;
  }

  @override
  Future<Json> displayPreferences() async => {
    ...await super.displayPreferences(),
    'autoReconnect': auto,
  };
  @override
  Future<String?> savedDisplayPassword(String id) async => saved;
  @override
  Future<List<Json>> discoverDisplays() async =>
      discoveryGate?.future ?? (found ? [profile] : []);
  @override
  Future<Json> connectDisplay(String id, String password) async {
    connects++;
    nativeGeneration++;
    return super.connectDisplay(id, password);
  }
}

Future<void> outage(AppController c, RecoveryPort p) async {
  p.reachable = false;
  for (final second in [10, 12, 14]) {
    p.at = after(second);
    await c.hardware.check(p.at);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'One or two lost health replies do not disconnect or resend output',
    () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      p.reachable = false;
      await c.hardware.check(after(10));
      await c.hardware.check(after(12));
      expect(c.hardware.connected, true);
      expect(c.hardware.interrupted, true);
      p.reachable = true;
      await c.hardware.check(after(14));
      expect(c.hardware.interrupted, false);
      expect(p.connects, 1);
      expect(p.sent.length, 1);
    },
  );
  test(
    'Confirmed outage reauthenticates and restores current original deadline',
    () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      await outage(c, p);
      expect(c.hardware.connected, false);
      p.reachable = true;
      p.at = after(17);
      await c.hardware.check(p.at);
      await flush();
      expect(c.hardware.connected, true);
      expect(c.hardware.held, false);
      expect(p.connects, 2);
      expect(p.sent.length, 2);
      expect(p.sent.last.deadline, start.wall + 600000);
    },
  );
  test(
    'Recovery sends the latest paused adjustment instead of queued old jobs',
    () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      await outage(c, p);
      p.at = after(15);
      await c.act('pause');
      await c.act('adjust', value: 120);
      p.reachable = true;
      p.at = after(17);
      await c.hardware.check(p.at);
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.paused);
      expect(c.hardware.accepted!.layout!.text, '11:45');
      expect(p.sent.length, 2);
    },
  );
  test(
    'Explicit disconnect persists and prevents background retries',
    () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      await c.hardware.disconnect();
      for (final second in [5, 20, 60]) {
        await c.hardware.check(after(second));
      }
      expect(p.connects, 1);
      expect(p.auto, false);
      expect(c.hardware.retryEnabled, false);
      await c.hardware.initialize();
      expect(c.hardware.autoReconnect, false);
    },
  );
  test('Explicit disconnect wins over an in-flight discovery retry', () async {
    final p = RecoveryPort(), c = await setup(p);
    addTearDown(c.dispose);
    await outage(c, p);
    p.discoveryGate = Completer<List<Json>>();
    final retry = c.hardware.reconnectSaved();
    await flush();
    await c.hardware.disconnect();
    p.discoveryGate!.complete([p.profile]);
    expect(await retry, false);
    expect(c.hardware.connected, false);
    expect(p.auto, false);
    expect(p.connects, 1);
  });
  test(
    'Manual reconnect owns the retry while its preference is saving',
    () async {
      final p = RecoveryPort()..saved = 'synthetic';
      final c = await setup(p);
      addTearDown(c.dispose);
      await c.hardware.disconnect();
      p.preferenceGate = Completer<void>();
      final retry = c.hardware.reconnectSaved();
      await flush();
      await c.hardware.check(after(20));
      expect(p.connects, 1);
      p.preferenceGate!.complete();
      expect(await retry, true);
      expect(p.connects, 2);
      expect(c.hardware.connected, true);
    },
  );
  test('App restart uses saved login but holds output for review', () async {
    final p = RecoveryPort()
      ..hardwarePreference = true
      ..saved = 'synthetic';
    final c = AppController(p);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.hardware.check(start);
    await flush();
    expect(c.hardware.connected, true);
    expect(c.hardware.held, true);
    expect(p.sent, isEmpty);
  });
  test('Missing saved credential stops retries and requests entry', () async {
    final p = RecoveryPort()..hardwarePreference = true;
    final c = AppController(p);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.hardware.check(start);
    expect(c.hardware.credentialsNeeded, true);
    expect(c.hardware.retryEnabled, false);
    expect(p.connects, 0);
  });
  test('An explicitly held session stays held after reconnect', () async {
    final p = RecoveryPort(), c = await setup(p);
    addTearDown(c.dispose);
    c.hardware.hold('Review required');
    await outage(c, p);
    p.reachable = true;
    p.at = after(17);
    await c.hardware.check(p.at);
    await flush();
    expect(c.hardware.held, true);
    expect(p.sent.length, 1);
  });
  test(
    'Blank toggles after service end without creating another report',
    () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act('end');
      final end = c.state.session.intended(c.now)!.text;
      expect(await c.act('blank'), true);
      expect(c.state.session.outputBlank, true);
      expect(c.simulator.pixels.any((p) => p), false);
      expect(await c.act('blank'), true);
      expect(c.state.session.outputBlank, false);
      expect(c.simulator.delivered!.text, end);
      expect(c.state.reports.length, 1);
      expect(c.state.session.phase, 'ended');
    },
  );
  test(
    'Tick refreshes Live and matrix without rebuilding the whole app',
    () async {
      final p = FakePort(), c = AppController(p);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      var app = 0, live = 0, preview = 0;
      c.addListener(() => app++);
      c.liveClock.addListener(() => live++);
      c.previewClock.addListener(() => preview++);
      for (var i = 0; i < 10; i++) {
        p.at = Stamp(start.mono + i * 100, start.wall + i * 100, start.boot);
        await c.tick();
      }
      expect(app, 0);
      expect(live, 1);
      expect(preview, 10);
    },
  );
  test('Print banner defaults on, optional off, text remains escaped', () {
    final t = Timeline('<Sunday>', const [
      Segment('A&B', 1, notes: 'PRIVATE'),
    ], DisplaySettings());
    final html = serviceSheetHtml(t, '<Church>');
    expect(html, contains('<header class="banner">'));
    expect(html, contains('&lt;Church&gt;'));
    expect(html, isNot(contains('PRIVATE')));
    expect(
      serviceSheetHtml(t, '', includeBanner: false),
      isNot(contains('<header class="banner">')),
    );
    expect(
      () => serviceSheetHtml(t, '', banner: '" onerror="alert(1)'),
      throwsA(isA<RuleError>()),
    );
  });
  test(
    'Paired cue tolerates warning revision but rejects a changed segment or cue',
    () async {
      final c = await setup(W2Port());
      addTearDown(c.dispose);
      await c.hardware.disconnect();
      await c.pairing.host('127.0.0.1');
      c.pairing.owner = 'synthetic-approved-operator';
      final snap = c.pairedSnapshot(true);
      final value = {
        'session': snap['session'],
        'segment': snap['index'],
        'index': 0,
        'version': (snap['cueVersions'] as List).first,
      };
      c.state.session.revision++;
      expect(await c.pairing.command!('cue', value, snap['revision']), true);
      expect(
        c.pairedSnapshot(false)['displayText'],
        (snap['cues'] as List).first,
      );
      await c.pairing.command!('advance', false, c.state.session.revision);
      expect(await c.pairing.command!('cue', value, snap['revision']), false);
      value['segment'] = c.state.session.index;
      value['version'] = 'old format';
      expect(await c.pairing.command!('cue', value, snap['revision']), false);
    },
  );
  test(
    'Approved peer reconnects after loss and code expiry without restoring control',
    () async {
      final host = PairHub(), client = PairHub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (private) => {
        'revision': 1,
        'rundown': [
          {'name': 'Talk', if (private) 'notes': 'SECRET'},
        ],
      };
      await host.host('127.0.0.1');
      await client.join(host.code!.encode(), 'Operator', 'operator');
      await until(() => host.peers.isNotEmpty);
      final id = host.peers.single.id;
      await host.approve(host.peers.single);
      host.grant(host.peers.single);
      await until(() => client.canControl);
      expect(jsonEncode(client.snapshot), contains('SECRET'));
      final code = host.code!;
      host.code = PairCode(code.address, code.port, code.secret, 1);
      host.peers.single.wire.close();
      await until(() => host.localControl && client.stale);
      expect(jsonEncode(client.snapshot), isNot(contains('SECRET')));
      await until(
        () => !client.stale && host.peers.any((p) => p.id == id && p.approved),
      );
      expect(client.canControl, false);
      expect(host.localControl, true);
      expect(jsonEncode(client.snapshot), isNot(contains('SECRET')));
      host.remove(host.peers.single);
      await until(() => client.stale);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(host.peers, isEmpty);
      expect(client.reconnecting, false);
    },
  );
  test('Leaving during reconnect cancels retries', () async {
    final host = PairHub(), client = PairHub();
    addTearDown(() async {
      await client.stop();
      await host.stop();
      client.dispose();
      host.dispose();
    });
    host.snapshotFor = (_) => {'revision': 1};
    await host.host('127.0.0.1');
    await client.join(host.code!.encode(), 'Viewer', 'viewer');
    await until(() => host.peers.isNotEmpty);
    await host.approve(host.peers.single);
    await until(() => !client.stale);
    host.peers.single.wire.close();
    await until(() => client.stale);
    await client.stop();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(client.mode, 'off');
    expect(host.peers, isEmpty);
  });
}
