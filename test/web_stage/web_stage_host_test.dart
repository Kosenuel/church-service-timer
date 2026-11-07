import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/web_stage/mdns_responder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;
import '../pairing/saved_devices_test.dart' show eventually;

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
          const QuickMessage(headline: 'Wrap up', body: '2 minutes'),
        ),
        isTrue,
        reason: c.error,
      );
      final shown = await call('/api/state?token=$token');
      expect(shown['message'], {'headline': 'Wrap up', 'body': '2 minutes'});
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
