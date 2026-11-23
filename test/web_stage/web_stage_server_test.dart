import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/web_stage/mdns_responder.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter_test/flutter_test.dart';

Json snapshot({String phase = 'active'}) => {
  'church': 'Grace Chapel',
  'service': 'Sunday',
  'phase': phase,
  'index': 1,
  'segment': 'Sermon',
  'nextSegment': 'Closing',
  'remaining': '12:30',
  'overtime': false,
  'paused': false,
  'stageSharing': true,
  'displayText': '12:30',
  'variance': '2 min behind',
  'behind': true,
  'finish': '12:05',
  'quickMessage': {'headline': 'Wrap up', 'body': '2 minutes'},
  'rundown': [
    {
      'name': 'Welcome',
      'minutes': 5,
      'seconds': 0,
      'speaker': 'Pastor Ade',
      'notes': 'Secret',
    },
    {
      'name': 'Sermon',
      'minutes': 30,
      'seconds': 0,
      'speaker': 'Rev. Bello',
      'notes': 'Secret',
    },
    {
      'name': 'Closing',
      'minutes': 5,
      'seconds': 0,
      'speaker': '',
      'notes': 'Secret',
    },
  ],
};

void main() {
  late WebStageServer server;
  var settings = const WebStageSettings(orderCode: '4821', localName: 'grace');
  final client = HttpClient();

  Future<(int, Json)> call(String path, [Json? body]) async {
    final uri = Uri.parse('http://127.0.0.1:${server.port}$path');
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
      text.startsWith('{')
          ? jsonDecode(text) as Json
          : <String, dynamic>{'html': text},
    );
  }

  setUp(() async {
    settings = const WebStageSettings(orderCode: '4821', localName: 'grace');
    server = WebStageServer(settings: () => settings, snapshot: snapshot);
    await server.start('127.0.0.1');
  });
  tearDown(() => server.stop());

  test('The page is served, with no outside resources', () async {
    final (status, body) = await call('/');
    expect(status, 200);
    expect(body['html'], contains('Order of service'));
    expect(body['html'], isNot(contains('http')), reason: 'Works offline');
  });

  test('The page moves scrolling cues on every frame, by the time', () async {
    final (_, body) = await call('/');
    final html = body['html'] as String;
    // One place moves scrolling text: the stage's cue and a banner's.
    final from = html.indexOf('function startScroll(');
    expect(from, greaterThan(0));
    final scroll = html.substring(from, html.indexOf('\n}\n', from));
    expect(scroll, contains('requestAnimationFrame(frame)'));
    // Moved by its transform alone, by the time since the last frame.
    expect(scroll, contains("run.style.transform = 'translate3d("));
    expect(scroll, contains('(now - lane.last) / 1000 * speed'));
    expect(scroll, isNot(contains('setInterval')));
    expect(scroll, isNot(contains('.left')));
    // Measured once, not on every frame.
    expect('offsetWidth'.allMatches(scroll).length, 1);
    // The same text carries on from where it was.
    expect(scroll, contains('old.text === text'));
    expect(html, contains("startScroll('stage', run,"));
    expect(html, contains("startScroll('band', run,"));
    expect(html, contains('will-change:transform'));
    expect(html, isNot(contains('m.elapsed * speed')));
  });

  test(
    'The order code opens Order of service, with no times or notes',
    () async {
      final (status, join) = await call('/api/join', {
        'code': '4821',
        'role': 'stage',
      });
      expect(status, 200);
      expect(
        join['role'],
        'order',
        reason: 'The order code never opens a team role',
      );
      expect(join['team'], false);
      final (_, state) = await call('/api/state?token=${join['token']}');
      expect(state['rundown'], [
        {'name': 'Welcome'},
        {'name': 'Sermon'},
        {'name': 'Closing'},
      ]);
      final text = jsonEncode(state);
      for (final hidden in [
        '12:30',
        'remaining',
        'minutes',
        'Secret',
        'behind',
        'Rev. Bello',
      ]) {
        expect(text, isNot(contains(hidden)));
      }
      settings = settings.copyWith(showSpeakers: true);
      final (_, withSpeakers) = await call('/api/state?token=${join['token']}');
      expect(withSpeakers['rundown'][1], {
        'name': 'Sermon',
        'speaker': 'Rev. Bello',
      });
    },
  );

  test('Switching up from Order of service needs the team code', () async {
    final (_, join) = await call('/api/join', {'code': '4821'});
    final token = join['token'];
    final (denied, _) = await call('/api/role', {
      'token': token,
      'role': 'stage',
      'code': '4821',
    });
    expect(denied, 403);
    final (ok, up) = await call('/api/role', {
      'token': token,
      'role': 'stage',
      'code': server.teamCode,
    });
    expect(ok, 200);
    expect(up['team'], true);
    // Once on the team, all three roles are free.
    for (final role in ['overview', 'order', 'stage']) {
      final (s, _) = await call('/api/role', {'token': token, 'role': role});
      expect(s, 200);
    }
  });

  test('The team code opens all three roles; views carry no notes', () async {
    final (_, join) = await call('/api/join', {
      'code': server.teamCode,
      'role': 'overview',
    });
    expect(join['role'], 'overview');
    final token = join['token'];
    final (_, overview) = await call('/api/state?token=$token');
    expect(overview['remaining'], '12:30');
    expect(overview['variance'], '2 min behind');
    expect(overview['finish'], '12:05');
    expect(overview['rundown'][1]['speaker'], 'Rev. Bello');
    await call('/api/role', {'token': token, 'role': 'stage'});
    final (_, stage) = await call('/api/state?token=$token');
    expect(stage['displayText'], '12:30');
    expect(stage['effect'], 'static');
    expect(stage['speed'], inInclusiveRange(1, 60));
    expect(stage['message']['headline'], 'Wrap up');
    expect(stage['message']['palette'], 'white');
    expect(jsonEncode(overview) + jsonEncode(stage), isNot(contains('Secret')));
  });

  test('Wrong codes lock a browser out for a while', () async {
    for (var i = 0; i < 5; i++) {
      final (s, _) = await call('/api/join', {'code': '0000'});
      expect(s, 403);
    }
    final (locked, _) = await call('/api/join', {'code': '4821'});
    expect(locked, 429, reason: 'Even the right code waits after five misses');
  });

  test('New codes sign out team browsers; order viewers stay', () async {
    final (_, team) = await call('/api/join', {'code': server.teamCode});
    final (_, order) = await call('/api/join', {'code': '4821'});
    final old = server.teamCode;
    server.newCodes();
    expect(server.teamCode, isNot(old));
    final (gone, _) = await call('/api/state?token=${team['token']}');
    expect(gone, 401);
    final (still, _) = await call('/api/state?token=${order['token']}');
    expect(still, 200);
    final (oldCode, _) = await call('/api/join', {'code': old});
    expect(oldCode, 403);
  });

  test('Open, code and off modes for the order of service', () async {
    final (needs, _) = await call('/api/join', {'code': ''});
    expect(needs, 403);
    settings = settings.copyWith(orderAccess: OrderAccess.open);
    final (open, j) = await call('/api/join', {'code': ''});
    expect(open, 200);
    expect(j['role'], 'order');
    settings = settings.copyWith(orderAccess: OrderAccess.off);
    final (off, _) = await call('/api/join', {'code': '4821'});
    expect(off, 403);
    final (after, _) = await call('/api/state?token=${j['token']}');
    expect(after, 401, reason: 'Turning it off stops existing order viewers');
    final (team, _) = await call('/api/join', {'code': server.teamCode});
    expect(team, 200, reason: 'The team code still works');
  });

  test('Removing a device signs it out', () async {
    final (_, j) = await call('/api/join', {'code': server.teamCode});
    await call('/api/state?token=${j['token']}');
    expect(server.activeDevices.single.label, contains('·'));
    server.remove(j['token'] as String);
    final (s, _) = await call('/api/state?token=${j['token']}');
    expect(s, 401);
  });

  test('Lyric photos are served only to browsers that joined', () async {
    server.lyricImage = (kind, id) async => kind == 'photo' && id == 'candle'
        ? File('assets/lyrics/photos/candle.jpg').readAsBytesSync()
        : null;
    Future<HttpClientResponse> get(String path) async => (await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    )).close();
    expect((await get('/lyrics/photo?id=candle&token=nobody')).statusCode, 404);
    final (_, join) = await call('/api/join', {
      'code': server.teamCode,
      'role': 'stage',
    });
    final token = join['token'];
    final res = await get('/lyrics/photo?id=candle&token=$token');
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'image/jpeg');
    await res.drain<void>();
    expect(
      (await get('/lyrics/photo?id=../secret&token=$token')).statusCode,
      404,
    );
    expect(
      (await get('/lyrics/picture?name=other&token=$token')).statusCode,
      404,
    );
  });

  test(
    'The page draws lyric slides itself, with nothing from the internet',
    () async {
      final (_, body) = await call('/');
      final html = body['html'] as String;
      expect(html, isNot(contains('http')));
      for (final part in [
        'function renderLyrics(',
        'function lyDraw(',
        'function lyFit(',
        '/lyrics/photo?id=',
        'prefers-reduced-motion',
      ]) {
        expect(html, contains(part));
      }
      // The same twelve designs as the app.
      for (final id in lyricDrawnBackgrounds.keys.where((k) => k != 'black')) {
        expect(html, contains("id === '$id'"), reason: id);
      }
    },
  );

  test('A lyric slide reaches Stage displays only, checked', () async {
    final view = viewFor(WebRole.stage, {
      ...snapshot(),
      'lyrics': {
        'key': 'a',
        'kind': 'song',
        'text': 'Amazing grace',
        'bg': 'aurora',
        'dim': 70,
        'size': 'm',
        'align': 'center',
        'motion': true,
        'chip': '12:30',
      },
    }, settings);
    expect(view['lyrics']['text'], 'Amazing grace');
    expect(view['lyrics']['chip'], '12:30');
    expect(
      viewFor(WebRole.order, {
        ...snapshot(),
        'lyrics': {'text': 'x'},
      }, settings).containsKey('lyrics'),
      isFalse,
    );
    expect(
      viewFor(WebRole.overview, {
        ...snapshot(),
        'lyrics': {'text': 'x'},
      }, settings).containsKey('lyrics'),
      isFalse,
    );
    final odd = webLyrics({
      'bg': '<script>',
      'dim': 900,
      'size': 'huge',
      'chip': 'soon',
      'text': 'x',
    });
    expect(odd['bg'], 'black');
    expect(odd['dim'], 90);
    expect(odd['size'], 'm');
    expect(odd.containsKey('chip'), isFalse);
  });

  test('Church names become short, easy .local names', () {
    expect(localNameFor('Grace Chapel'), 'grace-chapel');
    expect(localNameFor('Grace Community Church'), 'grace-community');
    expect(localNameFor("St. Mary's Cathedral"), 'st-marys-cathedral');
    expect(localNameFor('Église Évangélique de Paris'), 'eglise-evangelique');
    expect(localNameFor('Word & Spirit  Assembly'), 'word-spirit-assembly');
    expect(localNameFor('  Christ   Embassy  '), 'christ-embassy');
    expect(
      localNameFor('The Redeemed Christian Church of God, Victory Parish'),
      'rccg-victory',
    );
    expect(localNameFor('Winners Chapel International'), 'winners');
    expect(localNameFor('Deeper Life Bible Church'), 'deeper-life-bible');
    expect(localNameFor('Church'), 'church');
    expect(localNameFor('The Church'), 'church');
    expect(localNameFor('教会'), 'church-timer');
    expect(localNameFor(''), 'church-timer');
    for (final name in [
      'Mountain of Fire and Miracles Ministries International Headquarters',
      'Seventh-day Adventist Church Mount Zion Congregation',
      'Christ Apostolic Church Worldwide Oke Ayo Region Ibadan',
    ]) {
      final short = localNameFor(name);
      expect(
        short.length,
        lessThanOrEqualTo(localNameShortLimit),
        reason: short,
      );
      expect(validLocalName(short), isTrue, reason: short);
    }
    // Typed names are tidied but not shortened.
    expect(localNameFrom('Grace Church Lagos'), 'grace-church-lagos');
    expect(validLocalName('Grace Church'), isFalse);
    expect(validOrderCode('GRACE'), isTrue);
    expect(validOrderCode('12'), isFalse);
  });

  test('The responder answers questions for its own name only', () {
    // A query for grace-chapel.local, type A, asking for a unicast reply.
    final query = <int>[0x12, 0x34, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];
    for (final l in ['grace-chapel', 'local']) {
      query.addAll([l.length, ...l.codeUnits]);
    }
    query.addAll([0, 0, 1, 0x80, 1]);
    final q = parseQuery(Uint8List.fromList(query))!;
    expect(q.id, 0x1234);
    expect(q.asks('grace-chapel.local'), isTrue);
    expect(q.asks('other.local'), isFalse);
    expect(q.unicast, isTrue);
    final a = answer('grace-chapel', InternetAddress('192.168.1.23'));
    expect(a.sublist(a.length - 4), [192, 168, 1, 23]);
    expect(a[2] & 0x80, 0x80, reason: 'A response');
    final (name, _) = readName(a, 12);
    expect(name, 'grace-chapel.local');
    // A reply to itself is not a question.
    expect(parseQuery(a), isNull);
  });
}
