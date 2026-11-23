import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/web_stage/mdns_responder.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/waiting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes HTTP; these tests talk to a real local server.
  setUpAll(() => HttpOverrides.global = null);

  test(
    'A web Stage display counts as a connected stage and gets messages',
    () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      // Web screens join Church Auditorium, which shows no messages until asked to.
      await c.screens.setCues('room', true);
      final joined = <String>[];
      c.onWebJoined = joined.add;
      expect(await c.selectDestination('mobile'), isTrue);
      await c.pairing.host('127.0.0.1');
      await eventually(() => c.webStage.running);
      expect(c.stageConnected, isFalse);
      final client = HttpClient();
      Future<Json> call(String path, [Json? body]) async {
        final uri = Uri.parse('${c.webStageUrl}$path');
        final req = body == null
            ? await client.getUrl(uri)
            : await client.postUrl(uri);
        if (body != null) req.write(jsonEncode(body));
        return jsonDecode(
              await (await req.close()).transform(utf8.decoder).join(),
            )
            as Json;
      }

      final join = await call('/api/join', {
        'code': c.webStage.teamCode,
        'role': 'stage',
      });
      final token = join['token'] as String;
      expect(joined.single, contains('Stage display'));
      await call('/api/state?token=$token');
      // The host now sees a stage screen: cue buttons and messages are on.
      expect(c.stageConnected, isTrue);
      expect(c.stageScreens.single.id, 'web:$token');
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      expect(
        await c.sendQuickMessage(
          const QuickMessage(
            headline: 'Wrap up',
            body: '2 minutes',
            palette: 'amber',
            align: 'left',
            bold: true,
            requestSeen: true,
          ),
        ),
        isTrue,
        reason: c.error,
      );
      final shown = await call('/api/state?token=$token');
      // The colours and style reach the browser as the paired screens show.
      expect(shown['message'], {
        'headline': 'Wrap up',
        'body': '2 minutes',
        'palette': 'amber',
        'align': 'left',
        'bold': true,
        'italic': false,
        'scale': 1.0,
      });
      // A web screen cannot tap Seen; covering it counts as every stage.
      expect(c.quickMessages.coversEveryStage, isTrue);
      // A second display not chosen as a recipient does not see it.
      final other = await call('/api/join', {
        'code': c.webStage.teamCode,
        'role': 'stage',
      });
      final hidden = await call('/api/state?token=${other['token']}');
      expect(hidden.containsKey('message'), isFalse);
      await c.pairing.stop();
    },
  );

  networkChangeTests();

  test('The name responder answers a direct question and counts it', () async {
    final responder = MdnsResponder(listenPort: 0);
    final started = await responder.start('grace-chapel', '127.0.0.1');
    addTearDown(responder.stop);
    if (!started) {
      markTestSkipped('UDP sockets unavailable here');
      return;
    }
    final asker = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(asker.close);
    final reply = Completer<Uint8List>();
    asker.listen((e) {
      final d = asker.receive();
      if (d != null && !reply.isCompleted) reply.complete(d.data);
    });
    final query = <int>[0xAB, 0xCD, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];
    for (final l in ['grace-chapel', 'local']) {
      query.addAll([l.length, ...l.codeUnits]);
    }
    query.addAll([0, 0, 1, 0, 1]);
    asker.send(query, InternetAddress.loopbackIPv4, responder.boundPort!);
    final bytes = await reply.future.timeout(const Duration(seconds: 3));
    // A direct (one-shot) question gets its own id back, with the address.
    expect(bytes[0] << 8 | bytes[1], 0xABCD);
    expect(bytes.sublist(bytes.length - 4), [127, 0, 0, 1]);
    expect(responder.answered, 1);
  });
}

class MovingPort extends FakePort {
  String address = '127.0.0.2';
  @override
  Future<String> localNetworkAddress() async => address;
}

void networkChangeTests() {
  test(
    'A network change shares again, keeping the team code and browsers',
    () async {
      final port = MovingPort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      final notes = <String>[];
      c.onWebJoined = notes.add;
      await c.pairing.host(port.address);
      await eventually(() => c.webStage.running);
      final code = c.webStage.teamCode;
      final client = HttpClient();
      Future<(int, Json)> call(String base, String path, [Json? body]) async {
        final uri = Uri.parse('$base$path');
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

      final (_, join) = await call(c.webStageUrl!, '/api/join', {'code': code});
      // The phone moves to another network.
      port.address = '127.0.0.3';
      port.at = Stamp(port.at.mono + 11000, port.at.wall + 11000, port.at.boot);
      await c.tick();
      await eventually(
        () =>
            c.pairing.code?.address == '127.0.0.3' &&
            c.webStage.address == '127.0.0.3',
      );
      expect(c.webStageUrl, startsWith('http://127.0.0.3:'));
      expect(c.webStage.teamCode, code, reason: 'Team code kept');
      final (status, _) = await call(
        c.webStageUrl!,
        '/api/state?token=${join['token']}',
      );
      expect(
        status,
        200,
        reason: 'A joined browser carries on at the new address',
      );
      expect(notes.last, contains('Network changed'));
      await c.pairing.stop();
    },
  );
}
