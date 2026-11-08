import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import '../support/fake_port.dart';
import '../support/w2_port.dart';
import '../support/waiting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'End save retry preserves finish time and saves one historical program',
    () async {
      final p = FakePort();
      final host = AppController(p);
      await host.initialize(startTicker: false);
      addTearDown(host.dispose);
      await host.act('load', value: timeline());
      await host.act('start');
      p.at = after(45);
      p.fail = true;
      expect(await host.act('end'), false);
      expect(host.reportSavePending, true);
      expect(host.liveSession.phase, 'ended');
      expect(host.state.reports, isEmpty);
      expect(await host.act('advance'), false);
      p.at = after(90);
      await host.tick();
      p.fail = false;
      expect(await host.retry!(), true);
      expect(host.reportSavePending, false);
      expect(host.state.session.phase, 'ended');
      expect(host.state.reports.single.endedWall, after(45).wall);
      expect(host.state.reports.single.program!.name, 'Sunday');
      expect(host.state.reports.single.rows.first.actualMs, 45000);
      expect(host.simulator.delivered!.text, 'Hallelujah');
      expect(host.retry, isNull);
      expect(await host.act('end'), false);
      expect(host.state.reports, hasLength(1));
    },
  );

  test(
    'Mobile destination cancels in-flight LED reconnect and persists across restart',
    () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      await c.hardware.disconnect();
      p.saved = 'synthetic';
      p.discoveryGate = Completer<List<Json>>();
      final reconnect = c.hardware.reconnectSaved();
      await flush();
      final remaining = c.state.session.balance(c.now);
      expect(await c.selectDestination('mobile'), true);
      p.discoveryGate!.complete([p.profile]);
      await reconnect;
      expect(c.hardware.retryEnabled, false);
      expect(c.hardware.connected, false);
      expect(c.destination, 'mobile');
      expect(c.state.session.balance(c.now), remaining);
      expect(c.displayConnection, DisplayConnection.stageWaiting);
      final next = AppController(p);
      await next.initialize(startTicker: false);
      addTearDown(next.dispose);
      expect(next.destination, 'mobile');
      expect(next.hardware.retryEnabled, false);
    },
  );

  test(
    'Quick message presets validate limits, retain style and survive backup',
    () {
      final state = AppState.fresh(start);
      for (final p in defaultQuickMessages) p.validate();
      state.quickMessages = [
        const QuickMessage(
          headline: 'A TITLE',
          body: 'My custom message',
          bold: true,
          italic: true,
          palette: 'mint',
          align: 'left',
          seconds: 30,
          scale: 1.15,
        ),
      ];
      state.outputDestination = 'mobile';
      final restored = importBackup(exportBackup(state, start), start);
      expect(
        restored.quickMessages.single.toJson(),
        state.quickMessages.single.toJson(),
      );
      expect(restored.outputDestination, isNull);
      expect(
        () => QuickMessage(body: 'x' * 161).validate(),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => const QuickMessage(body: 'A', palette: 'invisible').validate(),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => const QuickMessage(body: '').validate(),
        throwsA(isA<RuleError>()),
      );
    },
  );

  test('Old saved states acquire presets without changing their programs', () {
    final old = AppState.fresh(start).toJson()
      ..['version'] = 9
      ..remove('outputDestination')
      ..remove('quickMessages');
    final restored = AppState.fromJson(old);
    expect(restored.templates.first.name, 'Sunday Service');
    expect(restored.quickMessages.length, 4);
    expect(restored.outputDestination, isNull);
  });

  test(
    'Report print uses recorded date and program, escapes content and excludes private notes by default',
    () async {
      final p = FakePort();
      final host = AppController(p);
      await host.initialize(startTicker: false);
      addTearDown(host.dispose);
      final program = Timeline('Youth sunday', const [
        Segment(
          'Welcome <script>',
          2,
          speaker: 'Original speaker',
          notes: 'PRIVATE NOTE',
        ),
      ], DisplaySettings());
      await host.act('load', value: program);
      await host.act('start');
      p.at = after(60);
      await host.act('end');
      final report = ServiceReport.fromJson(
        jsonDecode(jsonEncode(host.state.reports.single.toJson())),
      );
      final html = reportServiceHtml(report);
      expect(html, contains(serviceDateLabel(start.wall)));
      expect(html, contains('Original speaker'));
      expect(html, contains('Welcome &lt;script&gt;'));
      expect(html, isNot(contains('PRIVATE NOTE')));
      expect(html, contains('Actual'));
      expect(
        reportServiceHtml(report, fullReport: false, privateNotes: true),
        contains('PRIVATE NOTE'),
      );
      final old = report.toJson()..remove('program');
      expect(
        reportServiceHtml(ServiceReport.fromJson(old)),
        contains('Older record'),
      );
    },
  );

  test(
    'Approved stage ACK gates messages; warnings return to latest timer and stop sharing closes all peers but preserves approvals',
    () async {
      final p = FakePort(),
          host = AppController(p),
          stage = PairHub(),
          operator = PairHub();
      await host.initialize(startTicker: false);
      addTearDown(() async {
        await stage.stop();
        await operator.stop();
        await host.pairing.stop();
        stage.dispose();
        operator.dispose();
        host.dispose();
      });
      await host.act('load', value: timeline());
      await host.act('start');
      await host.selectDestination('mobile');
      expect(await host.sendQuickMessage(defaultQuickMessages.first), false);
      await host.pairing.host('127.0.0.1');
      await stage.join(host.pairing.code!.encode(), 'Stage phone', 'stage');
      await until(() => host.pairing.peers.isNotEmpty);
      expect(host.stageConnected, false);
      await host.pairing.approve(host.pairing.peers.single);
      await until(() => host.stageConnected);
      expect(host.displayConnection, DisplayConnection.stageConnected);
      expect(
        await host.sendQuickMessage(
          const QuickMessage(
            headline: 'NOTICE',
            body: 'Please wait',
            bold: true,
            seconds: 5,
          ),
        ),
        true,
      );
      await until(() => stage.snapshot?['quickMessage'] != null);
      expect(stage.snapshot!['quickMessage']['bold'], true);
      expect(jsonEncode(stage.snapshot), isNot(contains('notes')));
      await host.setSharedWarnings(const [
        WarningRule(598, TextLayout('WARNING'), destination: 'stage'),
      ]);
      p.at = after(2);
      await host.tick();
      expect(host.state.session.warningSeen, isNotEmpty);
      expect(host.state.session.automaticCue, isNull);
      p.at = after(6);
      await host.tick();
      await host.pairing.publish();
      await until(() => stage.snapshot?['quickMessage'] == null);
      expect(stage.snapshot!['displayText'], '09:54');
      await operator.join(host.pairing.code!.encode(), 'Operator', 'operator');
      await until(() => host.pairing.peers.length == 2);
      await host.pairing.approve(host.pairing.peers.last);
      await until(() => operator.snapshot != null);
      final savedDevices = host.pairing.savedDevices.map((d) => d.id).toSet();
      await host.stopSharing();
      await until(() => stage.stale && operator.stale);
      expect(host.pairing.hosting, false);
      expect(host.pairing.peers, isEmpty);
      expect(host.pairing.code, isNull);
      expect(host.pairing.savedDevices.map((d) => d.id).toSet(), savedDevices);
      expect(host.state.session.active, true);
      expect(host.stageConnected, false);
    },
  );

  test(
    'Quick messages are discarded on a stage disconnect and cannot replay on reconnection',
    () async {
      final p = FakePort(), host = AppController(p), stage = PairHub();
      await host.initialize(startTicker: false);
      addTearDown(() async {
        await stage.stop();
        await host.pairing.stop();
        stage.dispose();
        host.dispose();
      });
      await host.act('load', value: timeline());
      await host.act('start');
      await host.selectDestination('mobile');
      await host.pairing.host('127.0.0.1');
      await stage.join(host.pairing.code!.encode(), 'Stage', 'stage');
      await until(() => host.pairing.peers.isNotEmpty);
      await host.pairing.approve(host.pairing.peers.single);
      await until(() => host.stageConnected);
      await host.sendQuickMessage(
        const QuickMessage(body: 'Do not replay', seconds: 0),
      );
      await stage.stop();
      await until(() => host.pairing.peers.isEmpty);
      await stage.join(host.pairing.code!.encode(), 'Stage', 'stage');
      await until(() => host.pairing.peers.isNotEmpty);
      await host.pairing.approve(host.pairing.peers.single);
      await until(() => host.stageConnected);
      expect(host.currentQuickMessage, isNull);
      expect(stage.snapshot?.containsKey('quickMessage'), false);
    },
  );
}
