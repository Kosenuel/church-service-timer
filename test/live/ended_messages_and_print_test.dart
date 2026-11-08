import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import '../support/fake_port.dart';
import '../support/waiting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(AppController, FakePort, PairHub)> endedHost() async {
    final port = FakePort();
    final c = AppController(port), receiver = PairHub();
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline());
    await c.act('start');
    await c.selectDestination('mobile');
    await c.pairing.host('127.0.0.1');
    await receiver.join(c.pairing.code!.encode(), 'Stage screen', 'stage');
    await c.pairing.approve(c.pairing.peers.single);
    await until(() => c.stageConnected);
    port.at = after(20);
    await c.act('end');
    addTearDown(() async {
      await receiver.stop();
      await c.pairing.stop();
      receiver.dispose();
      c.dispose();
    });
    return (c, port, receiver);
  }

  test(
    'Ended messages require confirmation and restore the end screen without changing the report',
    () async {
      final (c, port, receiver) = await endedHost();
      final before = jsonEncode(c.state.toJson());
      const message = QuickMessage(body: 'Please remain seated', seconds: 5);
      expect(await c.sendQuickMessage(message), false);
      expect(
        await c.sendQuickMessage(message, confirmedEndedSession: 'old-service'),
        false,
      );
      expect(
        await c.sendQuickMessage(
          message,
          confirmedEndedSession: c.state.session.id,
        ),
        true,
      );
      await until(() => receiver.snapshot?['quickMessage'] != null);
      expect(receiver.snapshot!['phase'], 'ended');
      expect(receiver.snapshot!['quickMessage']['body'], message.body);
      expect(jsonEncode(c.state.toJson()), before);
      port.at = after(26);
      await c.tick();
      await c.pairing.publish();
      await until(() => receiver.snapshot?['quickMessage'] == null);
      expect(receiver.snapshot!['displayText'], 'Hallelujah');
      expect(c.state.session.active, false);
      expect(jsonEncode(c.state.toJson()), before);
    },
  );

  test(
    'Ended message overlays deliberate blanking and clearing restores blank without saving',
    () async {
      final (c, _, receiver) = await endedHost();
      await c.act('blank');
      final before = jsonEncode(c.state.toJson());
      expect(
        await c.sendQuickMessage(
          const QuickMessage(body: 'Thank you', seconds: 0),
          confirmedEndedSession: c.state.session.id,
        ),
        true,
      );
      await until(() => receiver.snapshot?['quickMessage'] != null);
      expect(receiver.snapshot!['blank'], false);
      expect(c.state.session.outputBlank, true);
      await c.dismissQuickMessage();
      await until(() => receiver.snapshot?['quickMessage'] == null);
      expect(receiver.snapshot!['blank'], true);
      expect(jsonEncode(c.state.toJson()), before);
    },
  );

  test(
    'Ended messages stay blocked when stage sharing stops and never replay after reconnect',
    () async {
      final (c, _, receiver) = await endedHost();
      final id = c.pairing.peers.single.id;
      final service = c.state.session.id;
      expect(
        await c.sendQuickMessage(
          const QuickMessage(body: 'Final notice', seconds: 0),
          confirmedEndedSession: service,
        ),
        true,
      );
      await c.pairing.disconnectDevice(id);
      await until(() => receiver.pausedByHost);
      expect(
        await c.sendQuickMessage(
          const QuickMessage(body: 'Do not send'),
          confirmedEndedSession: service,
        ),
        false,
      );
      await c.pairing.reconnectDevice(id);
      await until(() => c.stageConnected);
      expect(c.currentQuickMessage, null);
      expect(receiver.snapshot!['quickMessage'], null);
      await c.act('load', value: timeline());
      expect(
        await c.sendQuickMessage(
          const QuickMessage(body: 'Old confirmation'),
          confirmedEndedSession: service,
        ),
        false,
      );
    },
  );

  test(
    'Live and historical rundown prints remove planned start and keep dates, speakers and private-note rules',
    () async {
      final (c, _, _) = await endedHost();
      for (final html in [
        serviceSheetHtml(
          timeline(),
          'Example church',
          serviceDate: after(0).wall,
        ),
        reportServiceHtml(c.state.reports.single, fullReport: false),
        reportServiceHtml(c.state.reports.single),
      ]) {
        expect(html, isNot(contains('Planned start')));
        expect(html, isNot(contains('<td>+')));
        expect(html, contains('service-date'));
        expect(html, contains('Segment / speaker'));
        expect(html, contains('Private notes excluded'));
      }
    },
  );
}
