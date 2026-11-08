import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:church_service_timer/pairing/pairing.dart';
import '../support/fake_port.dart';
import '../support/pairing.dart';
import '../support/waiting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes HTTP; these tests talk to a real local server.
  setUpAll(() => HttpOverrides.global = null);

  Future<
    (AppController, FakePort, Future<(int, Json)> Function(String, [Json?]))
  >
  host() async {
    final port = FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    expect(await c.selectDestination('mobile'), isTrue);
    await c.pairing.host('127.0.0.1');
    addTearDown(c.pairing.stop);
    await eventually(() => c.webStage.running);
    final client = HttpClient();
    Future<(int, Json)> call(String path, [Json? body]) async {
      final uri = Uri.parse('${c.webStageUrl}$path');
      final req = body == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      return (
        res.statusCode,
        jsonDecode(await res.transform(utf8.decoder).join()) as Json,
      );
    }

    return (c, port, call);
  }

  Future<String> join(
    AppController c,
    Future<(int, Json)> Function(String, [Json?]) call, {
    bool team = true,
  }) async {
    final (_, j) = await call('/api/join', {
      'code': team ? c.webStage.teamCode : c.state.webStage['orderCode'],
      'role': team ? 'stage' : 'order',
    });
    return j['token'] as String;
  }

  test('Requests are off by default and only open during a service', () async {
    final (c, _, call) = await host();
    final token = await join(c, call);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    var (_, state) = await call('/api/state?token=$token');
    expect(state.containsKey('requests'), isFalse);
    var (status, _) = await call('/api/request', {
      'token': token,
      'kind': 'mic',
    });
    expect(status, 409);
    expect(c.stageRequests.open, isEmpty);

    await c.commit((d, _) => d.stageRequests = true);
    (_, state) = await call('/api/state?token=$token');
    expect(state['requests'], isTrue);
    await c.act('end');
    (_, state) = await call('/api/state?token=$token');
    expect(state.containsKey('requests'), isFalse);
  });

  test(
    'A team Stage display asks for time; Add 2 min adjusts and is logged',
    () async {
      final (c, port, call) = await host();
      await c.commit((d, _) => d.stageRequests = true);
      final token = await join(c, call);
      final guest = await join(c, call, team: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      final heard = <String>[];
      c.stageRequests.onRequest = (r) => heard.add(r.label);

      // Guests and unknown kinds are refused.
      expect(
        (await call('/api/request', {'token': guest, 'kind': 'time'})).$1,
        409,
      );
      expect(
        (await call('/api/request', {'token': token, 'kind': 'hello'})).$1,
        409,
      );

      expect(
        (await call('/api/request', {'token': token, 'kind': 'time'})).$1,
        200,
      );
      expect(heard, ['Need 2 minutes']);
      final request = c.stageRequests.open.single;
      expect(request.screenName, contains('(web)'));
      var (_, state) = await call('/api/state?token=$token');
      expect(state['request']['state'], 'sent');

      // A second request within 5 seconds is ignored.
      expect(
        (await call('/api/request', {'token': token, 'kind': 'mic'})).$1,
        409,
      );

      final before = c.state.session.remaining(c.now);
      expect(await c.stageRequests.addTime(request.id), isTrue);
      expect(c.state.session.remaining(c.now) - before, 120000);
      expect(c.stageRequests.open, isEmpty);
      (_, state) = await call('/api/state?token=$token');
      expect(state['request']['state'], 'added');
      expect(
        c.state.session.events.map((e) => e.message),
        containsAll([
          contains('Stage request · Need 2 minutes'),
          contains('2 minutes added'),
        ]),
      );

      // After 5 seconds a new request replaces the old one; it expires
      // after two minutes.
      port.at = after(6);
      await c.tick();
      expect(
        (await call('/api/request', {'token': token, 'kind': 'mic'})).$1,
        200,
      );
      expect(c.stageRequests.open.single.label, 'Microphone issue');
      await c.stageRequests.acknowledge(c.stageRequests.open.single.id);
      (_, state) = await call('/api/state?token=$token');
      expect(state['request']['state'], 'seen');
      port.at = after(140);
      await c.tick();
      (_, state) = await call('/api/state?token=$token');
      expect(state.containsKey('request'), isFalse);
    },
  );

  test('A paired stage screen sends a request and sees it answered', () async {
    final (c, _, _) = await host();
    await c.commit((d, _) => d.stageRequests = true);
    final screen = PairHub();
    addTearDown(() async {
      await screen.stop();
      screen.dispose();
    });
    final id = await pair(c.pairing, screen);
    screen.showStage(true);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await c.pairing.publish();
    await eventually(() => screen.snapshot?['stageRequests'] == true);
    await screen.sendStageRequest('finish');
    await eventually(() => c.stageRequests.open.isNotEmpty);
    expect(c.stageRequests.open.single.screenId, id);
    expect(c.stageRequests.open.single.label, 'Ready to finish');
    await eventually(
      () => screen.snapshot?['stageRequest']?['state'] == 'sent',
    );
    await c.stageRequests.acknowledge(c.stageRequests.open.single.id);
    await eventually(
      () => screen.snapshot?['stageRequest']?['state'] == 'seen',
    );
  });
}
