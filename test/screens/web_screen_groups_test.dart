import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';

/// Web screens in groups, through the host's own web server: a browser
/// names its group when it joins (remembered, or from a per-group link),
/// gets what that group shows, and keeps the group it is moved to.
void main() {
  late AppController c;
  final client = HttpClient();

  Future<(int, Json)> call(String path, [Json? body]) async {
    final uri = Uri.parse('http://127.0.0.1:${c.webStage.port}$path');
    final req = body == null
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (
      res.statusCode,
      text.startsWith('{') ? jsonDecode(text) as Json : <String, dynamic>{},
    );
  }

  setUp(() async {
    c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act(
      'load',
      value: Timeline('Sunday', const [
        Segment('Worship', 20),
        Segment('Sermon', 30),
      ], DisplaySettings()),
    );
    await c.act('start');
    await c.webStage.start('127.0.0.1');
  });
  tearDown(() async {
    await c.webStage.stop();
    c.dispose();
  });

  Future<String> join({String? group}) async {
    final (status, body) = await call('/api/join', {
      'code': c.webStage.teamCode,
      'role': 'stage',
      'group': ?group,
    });
    expect(status, 200);
    return body['token'] as String;
  }

  test('a browser naming no group joins the default one', () async {
    final token = await join();
    final (_, state) = await call('/api/state?token=$token');
    expect(state['group'], {'id': 'room', 'name': 'Room 1'});
    expect(state['show'], 'slides');
  });

  test('a per-group link or remembered group puts it there', () async {
    await c.screens.setShow('stage', 'monitor');
    final token = await join(group: 'stage');
    var (_, state) = await call('/api/state?token=$token');
    expect(state['group'], {'id': 'stage', 'name': 'Stage'});
    expect(state['show'], 'monitor');
    expect(state.containsKey('confidence'), isFalse, reason: 'no slide yet');
    await c.lyrics.save(
      LyricItem(
        id: 'well',
        kind: 'song',
        title: 'It Is Well',
        words: 'Verse 1\nWhen peace like a river\n\nChorus\nIt is well',
      ),
    );
    c.lyrics.show('well', 0);
    (_, state) = await call('/api/state?token=$token');
    expect(state['confidence']['text'], 'When peace like a river');
    expect(state['confidence']['next'], {
      'label': 'Chorus',
      'line': 'It is well',
    });
    expect(state['confidence']['time']['active'], isTrue);
    expect(state['confidence']['time']['text'], matches(stageTimePattern));
    // The countdown's layout is still there for an older page.
    expect(state['layout'], 'timer');
    expect(state.containsKey('lyrics'), isFalse);
  });

  test('a group that no longer exists is the default group', () async {
    final token = await join(group: 'gone-away');
    final (_, state) = await call('/api/state?token=$token');
    expect(state['group']['id'], 'room');
  });

  test('moved in the panel, it says so, and the page keeps it', () async {
    final token = await join();
    await c.screens.move('web:$token', 'stage');
    final (_, state) = await call('/api/state?token=$token');
    expect(state['group']['id'], 'stage');
    expect(state['show'], 'timer');
    // The page stores the group it is told and names it when it joins.
    expect(webStagePage, contains("localStorage.setItem('cst-group'"));
    expect(
      webStagePage,
      contains("role: role && role !== 'order' ? role : 'stage', group"),
    );
    expect(webStagePage, contains("get('group')"));
  });

  test('an order-of-service browser has no group', () async {
    final (_, body) = await call('/api/join', {
      'code': c.webStageSettings.orderCode,
    });
    final (_, state) = await call('/api/state?token=${body['token']}');
    expect(state.containsKey('group'), isFalse);
    expect(state.containsKey('confidence'), isFalse);
  });

  test('the page draws the confidence monitor and gives way to a message', () {
    expect(webStagePage, contains('function renderMonitor(s)'));
    expect(webStagePage, contains("s.sharing && !s.message ? s.confidence"));
  });
}
