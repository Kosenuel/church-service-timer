import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/app/warning_notifications.dart';
import 'domain_test.dart' show FakePort, start, after, timeline, running;
import 'revision_16_test.dart' show eventually, PairMemoryStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Old state defaults to watermark on and warnings clear after 30 seconds',
    () {
      final old = AppState.fresh(start).toJson()
        ..['version'] = 10
        ..remove('notificationClearSeconds')
        ..remove('printPreferences')
        ..remove('editDrafts');
      final state = AppState.fromJson(old);
      expect(state.printPreferences.watermark, true);
      expect(state.printPreferences.inkSaving, false);
      expect(state.notificationClearSeconds, 30);
      expect(state.editDrafts, isEmpty);
      state.printPreferences = const PrintPreferences(
        watermark: false,
        inkSaving: true,
      );
      state.notificationClearSeconds = 0;
      state.editDrafts['quick-message'] = const QuickMessage(
        body: 'PRIVATE DRAFT',
      ).toJson();
      final backup = exportBackup(state, start);
      expect(backup, isNot(contains('PRIVATE DRAFT')));
      final restored = importBackup(backup, start);
      expect(restored.printPreferences.watermark, false);
      expect(restored.printPreferences.inkSaving, true);
      expect(restored.notificationClearSeconds, 0);
      expect(restored.editDrafts, isEmpty);
      expect(() => notificationTimeoutValue(31), throwsA(isA<RuleError>()));
    },
  );

  test(
    'Draft failures retain pending edits and retry restores unsent content only',
    () async {
      final p = FakePort(), c = AppController(FakePort());
      c.dispose();
      final controller = AppController(p);
      await controller.initialize(startTicker: false);
      addTearDown(controller.dispose);
      final before = jsonEncode(controller.state.session.toJson());
      p.fail = true;
      controller.queueEditDraft(
        'quick-message',
        const QuickMessage(body: 'Unsent', requestSeen: true).toJson(),
      );
      await controller.flushEditDrafts();
      expect(controller.draftError, isNotNull);
      p.fail = false;
      await controller.flushEditDrafts();
      expect(controller.draftError, isNull);
      expect(jsonEncode(controller.state.session.toJson()), before);
      final loaded = AppState.fromJson(jsonDecode(p.data!));
      final message = messageFromDraft(loaded.editDrafts['quick-message']!);
      expect(message.body, 'Unsent');
      expect(message.requestSeen, true);
      expect(controller.currentQuickMessage, null);
      controller.queueEditDraft('quick-message', null);
      await controller.flushEditDrafts();
      expect(controller.state.editDrafts, isEmpty);
    },
  );

  test(
    'Recovery preserves current/completed segments, protection and one-minute minimum',
    () {
      final s = running();
      s.timeline = Timeline('Sunday', const [
        Segment('Current', 10),
        Segment('Prayer', 5, protected: true),
        Segment('Talk', 8),
        Segment('Closing', 2),
      ], DisplaySettings());
      final before = jsonEncode(s.toJson());
      final proposal = timeRecoveryPlan(s, 6);
      expect(proposal.map((e) => e.minutes), [5, 2, 2]);
      expect(proposal.first.protected, true);
      expect(jsonEncode(s.toJson()), before);
      expect(() => timeRecoveryPlan(s, 9), throwsA(isA<RuleError>()));
      expect(() => timeRecoveryPlan(s, 0), throwsA(isA<RuleError>()));
      expect(Segment.fromJson(proposal.first.toJson()).protected, true);
    },
  );

  test(
    'Duration insights exclude pauses, rehearsals, incomplete and uncertain records',
    () {
      final program = Timeline('Youth Sunday', const [
        Segment('Message', 5),
      ], DisplaySettings());
      ServiceReport record(
        int n,
        int active, {
        int rate = 1,
        bool uncertain = false,
        bool incomplete = false,
      }) => ServiceReport(
        '$n',
        program.name,
        start.wall,
        start.wall + n * 1000,
        active + 60000,
        rate,
        uncertain,
        [
          ReportRow(
            'Message',
            300000,
            incomplete ? null : active + 60000,
            60000,
            0,
          ),
        ],
        program: program,
      );
      final reports = [
        record(1, 360000),
        record(2, 420000),
        record(3, 390000),
        record(4, 10000, rate: 10),
        record(5, 10000, uncertain: true),
        record(6, 10000, incomplete: true),
      ];
      final before = jsonEncode(reports.map((e) => e.toJson()).toList());
      final insight = durationInsights(program, reports).single;
      expect(insight.samples, 3);
      expect(insight.suggestedMinutes, 7);
      expect(insight.exceeded, 3);
      expect(durationInsights(program, reports.take(2).toList()), isEmpty);
      expect(program.segments.single.minutes, 5);
      expect(jsonEncode(reports.map((e) => e.toJson()).toList()), before);
    },
  );

  test(
    'Warning expiry settings and scope follow segment and end transitions',
    () {
      final s = running();
      final plan = warningNotificationPlan(s, start);
      expect(plan['clearSeconds'], 30);
      final next = transition(s, 'advance', after(10));
      expect(
        warningNotificationPlan(next, after(10), clearSeconds: 60)['scope'],
        isNot(plan['scope']),
      );
      final ended = warningNotificationPlan(
        transition(next, 'end', after(20)),
        after(20),
        clearSeconds: 0,
      );
      expect(ended['alarms'], isEmpty);
      expect(ended['notice'], null);
      expect(ended['clearSeconds'], 0);
    },
  );

  test(
    'Screen grouping/layout survive restart and a failed write rolls back',
    () async {
      final store = PairMemoryStore(), client = PairHub();
      final hub = store.hub();
      addTearDown(() async {
        await client.stop();
        await hub.stop();
        client.dispose();
        hub.dispose();
      });
      await hub.host('127.0.0.1');
      await client.join(hub.code!.encode(), 'Choir screen', 'stage');
      await hub.approve(hub.peers.last);
      final id = hub.peers.last.id;
      await hub.configureScreen(id, group: 'choir', layout: 'next');
      final memory = jsonDecode(store.value!);
      expect(memory['devices'].single['group'], 'choir');
      expect(memory['devices'].single['layout'], 'next');
      store.fail = true;
      await expectLater(
        hub.configureScreen(id, group: 'media', layout: 'current'),
        throwsStateError,
      );
      expect(hub.savedDevices.single.group, 'choir');
      expect(hub.savedDevices.single.layout, 'next');
      final restored = store.hub();
      await restored.restoreMemory();
      expect(restored.savedDevices.single.layout, 'next');
      restored.dispose();
    },
  );

  test(
    'Three encrypted stage links isolate targeted messages, explicit Seen, and reconnect replay',
    () async {
      final port = FakePort();
      final host = AppController(port);
      final clients = List.generate(3, (_) => PairHub());
      await host.initialize(startTicker: false);
      addTearDown(() async {
        for (final client in clients) {
          await client.stop();
          client.dispose();
        }
        await host.pairing.stop();
        host.dispose();
      });
      await host.act('load', value: timeline());
      await host.act('start');
      await host.selectDestination('mobile');
      await host.pairing.host('127.0.0.1');
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        await clients[i].join(
          host.pairing.code!.encode(),
          'Screen $i',
          'stage',
        );
        await host.pairing.approve(host.pairing.peers.last);
        ids.add(host.pairing.peers.last.id);
        await eventually(() => !clients[i].stale);
      }
      await eventually(() => host.pairing.syncedStagePeers.length == 3);
      await host.pairing.configureScreen(
        ids[0],
        group: 'preacher',
        layout: 'current',
      );
      await host.pairing.configureScreen(
        ids[1],
        group: 'choir',
        layout: 'next',
      );
      expect(
        await host.sendQuickMessage(
          const QuickMessage(body: 'Choir only', requestSeen: true, seconds: 0),
          recipientIds: {ids[1]},
        ),
        true,
      );
      await eventually(() => clients[1].snapshot?['quickMessage'] != null);
      expect(clients[0].snapshot?['quickMessage'], null);
      expect(clients[2].snapshot?['quickMessage'], null);
      expect(clients[1].snapshot?['stageLayout'], 'next');
      expect(jsonEncode(clients[1].snapshot), isNot(contains('notes')));
      expect(host.quickSeen, isEmpty); // Transport ACK must never mean Seen.
      await eventually(
        () =>
            host.pairing.peerFor(ids[1])!.acknowledgedSnapshot?['messageId'] ==
            host.quickMessageId,
      );
      host.receiveMessageSeen(
        host.pairing.peerFor(ids[0])!,
        host.quickMessageId!,
      );
      expect(host.quickSeen, isEmpty);
      await clients[1].acknowledgeMessage();
      await eventually(() => host.quickSeen.contains(ids[1]));
      await eventually(() => clients[1].snapshot?['messageSeen'] == true);
      final oldId = host.quickMessageId!;
      expect(
        await host.sendQuickMessage(
          const QuickMessage(
            body: 'All screens',
            requestSeen: true,
            seconds: 5,
          ),
        ),
        true,
      );
      host.receiveMessageSeen(host.pairing.peerFor(ids[1])!, oldId);
      expect(host.quickSeen, isEmpty);
      await eventually(
        () => clients.every(
          (p) => p.snapshot?['quickMessage']?['body'] == 'All screens',
        ),
      );
      await host.pairing.disconnectDevice(ids[1]);
      await eventually(() => clients[1].pausedByHost);
      await host.pairing.reconnectDevice(ids[1]);
      await eventually(() => host.pairing.syncedStagePeers.length == 3);
      expect(clients[1].snapshot?['quickMessage'], null);
      expect(clients[0].snapshot?['quickMessage']?['body'], 'All screens');
      port.at = after(6);
      await host.tick();
      await host.pairing.publish();
      await eventually(
        () => clients.every((p) => p.snapshot?['quickMessage'] == null),
      );
      expect(clients[0].snapshot?['displayText'], '09:54');
      expect(clients[0].snapshot?['stageLayout'], 'current');
    },
  );
}
