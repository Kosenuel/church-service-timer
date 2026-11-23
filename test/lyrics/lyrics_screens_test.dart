import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/pairing/paired_screen.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class _Wire implements PairWire {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5),
  Segment('Sermon', 40),
], DisplaySettings());

Future<AppController> ready({bool running = true}) async {
  final c = AppController(FakePort());
  await c.initialize(startTicker: false);
  await c.lyrics.save(
    LyricItem(
      id: 'amazing',
      kind: 'song',
      title: 'Amazing Grace',
      words:
          'Verse 1\nAmazing grace\nHow sweet the sound\n\nVerse 2\nTwas grace',
    ),
  );
  if (running) {
    await c.act('load', value: sunday());
    await c.act('start');
  }
  return c;
}

Json withoutLyrics(Json j) => {...j}..remove('lyrics');

void main() {
  group('Send to', () {
    test(
      'stage screens are off by default and really keep the countdown',
      () async {
        final c = await ready();
        final peer = PairPeer('phone', 'Pulpit phone', 'stage', _Wire());
        final before = c.decoratePairedSnapshot(peer, c.pairedSnapshot(false));
        c.lyrics.show('amazing', 0);
        final stage = c.decoratePairedSnapshot(peer, c.pairedSnapshot(false));
        expect(stage.containsKey('lyrics'), isFalse);
        expect(stage['displayIsTimer'], isTrue);
        expect(
          jsonEncode(stage),
          jsonEncode(before),
          reason: 'nothing else changes for the speaker',
        );
        // The second screen and web screens do get the slide.
        expect(c.stageWindowSnapshot()['lyrics'], isA<Map>());
        expect(c.webStageSnapshot()['lyrics'], isA<Map>());
        // Ticked, stage screens get it too.
        await c.lyrics.setLook(c.lyrics.look.copyWith(toStage: true));
        expect(
          c.decoratePairedSnapshot(peer, c.pairedSnapshot(false))['lyrics'],
          isA<Map>(),
        );
        // A phone only following the rundown never does.
        final operator = PairPeer('op', 'Operator', 'operator', _Wire());
        expect(
          c
              .decoratePairedSnapshot(operator, c.pairedSnapshot(false))
              .containsKey('lyrics'),
          isFalse,
        );
      },
    );

    test('unticked screens get nothing; the LED sign never does', () async {
      final c = await ready();
      await c.lyrics.setLook(
        c.lyrics.look.copyWith(toSecond: false, toWeb: false),
      );
      c.lyrics.show('amazing', 1);
      expect(c.stageWindowSnapshot().containsKey('lyrics'), isFalse);
      expect(c.webStageSnapshot().containsKey('lyrics'), isFalse);
      // The sign's output is the session's, which lyrics never touch.
      expect(c.state.session.intended(c.now)?.text, isNot(contains('grace')));
      expect(
        c.lyrics.previewField(),
        isA<Map>(),
        reason: 'the operator still sees it',
      );
    });

    test('Clear lyrics gives each screen back exactly what it had', () async {
      final c = await ready();
      final window = withoutLyrics(c.stageWindowSnapshot());
      final web = withoutLyrics(c.webStageSnapshot());
      c.lyrics.show('amazing', 0);
      expect(
        withoutLyrics(c.stageWindowSnapshot()),
        window,
        reason: 'the countdown is still sent underneath',
      );
      c.lyrics.clear();
      expect(c.stageWindowSnapshot(), window);
      expect(c.webStageSnapshot(), web);
    });

    test(
      'the chip shows the time left while a service runs, and only then',
      () async {
        final c = await ready();
        c.lyrics.show('amazing', 0);
        expect(
          c.stageWindowSnapshot()['lyrics']['chip'],
          c.state.session.formatted(c.now),
        );
        await c.lyrics.setLook(c.lyrics.look.copyWith(chip: false));
        expect(
          (c.stageWindowSnapshot()['lyrics'] as Map).containsKey('chip'),
          isFalse,
        );
        final idle = await ready(running: false);
        idle.lyrics.show('amazing', 0);
        expect(
          idle.stageWindowSnapshot()['lyrics'],
          isA<Map>(),
          reason: 'lyrics need no service',
        );
        expect(
          (idle.stageWindowSnapshot()['lyrics'] as Map).containsKey('chip'),
          isFalse,
        );
      },
    );

    test(
      'ending the service keeps the songs; Black covers, then gives back',
      () async {
        final c = await ready();
        c.lyrics.show('amazing', 1);
        c.lyrics.toggleBlack();
        expect(c.stageWindowSnapshot()['lyrics']['black'], isTrue);
        expect(
          (c.stageWindowSnapshot()['lyrics'] as Map).containsKey('text'),
          isFalse,
        );
        c.lyrics.toggleBlack();
        expect(c.stageWindowSnapshot()['lyrics']['text'], 'Twas grace');
        await c.act('end');
        expect(c.state.lyrics.byId('amazing'), isNotNull);
        expect(c.lyrics.statusLine, 'Amazing Grace · Verse 2');
      },
    );

    test('Your picture is not sent to paired stage screens', () async {
      final c = await ready();
      await c.port.saveLyricPicture(
        base64Decode(
          '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
        ),
      );
      await c.lyrics.loadPicture();
      await c.lyrics.setLook(
        c.lyrics.look.copyWith(background: 'custom:abc', toStage: true),
      );
      c.lyrics.show('amazing', 0);
      expect(c.lyrics.field(LyricTarget.second)!['bg'], 'custom:abc');
      expect(c.lyrics.field(LyricTarget.web)!['bg'], 'custom:abc');
      expect(c.lyrics.field(LyricTarget.stage)!['bg'], lyricPictureStandIn);
    });
  });

  group('older screens', () {
    test(
      'the slide is one new optional field; everything else is as before',
      () async {
        final c = await ready();
        await c.lyrics.setLook(c.lyrics.look.copyWith(toStage: true));
        final peer = PairPeer('phone', 'Pulpit phone', 'stage', _Wire());
        final before = c.decoratePairedSnapshot(peer, c.pairedSnapshot(false));
        c.lyrics.show('amazing', 0);
        final after = c.decoratePairedSnapshot(peer, c.pairedSnapshot(false));
        // An older app reads the countdown fields it always did, and they
        // say "countdown", so it keeps showing the countdown.
        expect(withoutLyrics(after), before);
        expect(after['displayIsTimer'], isTrue);
        expect(after['blank'], isFalse);
      },
    );

    testWidgets('a screen that gets no slide shows its countdown', (t) async {
      await loadAppFonts();
      setScreen(t, const Size(960, 540));
      final c = await t.runAsync(ready);
      c!.lyrics.show('amazing', 0);
      final peer = PairPeer('phone', 'Pulpit phone', 'stage', _Wire());
      // As a phone gets it while the host shares to stage screens.
      final data = c.decoratePairedSnapshot(peer, c.pairedSnapshot(false))
        ..['stageSharing'] = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StageSurface(data: data, stale: false)),
        ),
      );
      expect(find.byKey(const ValueKey('lyric-stage')), findsNothing);
      expect(
        find.byType(StageMessage),
        findsOneWidget,
        reason: 'the countdown',
      );
    });

    test('web screens get only known values; other views get none', () async {
      final c = await ready();
      c.lyrics.show('amazing', 0);
      final s = c.webStageSnapshot();
      final settings = const WebStageSettings(
        orderCode: '4821',
        localName: 'grace',
      );
      final stage = viewFor(WebRole.stage, s, settings);
      expect(stage['lyrics']['text'], 'Amazing grace\nHow sweet the sound');
      expect(stage['lyrics']['bg'], 'mountain_dusk');
      expect(
        viewFor(WebRole.order, s, settings).containsKey('lyrics'),
        isFalse,
      );
      expect(
        viewFor(WebRole.overview, s, settings).containsKey('lyrics'),
        isFalse,
      );
    });
  });

  group('backups', () {
    test(
      'stored songs and the look round-trip; Your picture stays here',
      () async {
        final c = await ready(running: false);
        await c.lyrics.setLook(
          c.lyrics.look.copyWith(
            background: 'custom:abc',
            dim: 55,
            toStage: true,
          ),
        );
        final raw = exportBackup(c.state, c.now);
        expect(jsonDecode(raw)['schemaVersion'], 12);
        final back = importBackup(raw, c.now);
        expect(back.lyrics.byId('amazing')!.title, 'Amazing Grace');
        expect(back.lyrics.look.dim, 55);
        expect(back.lyrics.look.toStage, isTrue);
        expect(back.lyrics.look.background, lyricPictureStandIn);
        final restored = await ready(running: false);
        await restored.lyrics.delete('amazing');
        expect(await restored.restoreBackup(back), isTrue);
        expect(restored.state.lyrics.byId('amazing'), isNotNull);
      },
    );

    test(
      'a backup without songs stays at its old version and leaves songs alone',
      () async {
        final empty = AppState.fresh(const Stamp(0, 0, 'test'));
        final raw = exportBackup(empty, const Stamp(0, 0, 'test'));
        expect(jsonDecode(raw)['schemaVersion'], lessThan(12));
        expect((jsonDecode(raw)['data'] as Map).containsKey('lyrics'), isFalse);
        final c = await ready(running: false);
        expect(await c.restoreBackup(importBackup(raw, c.now)), isTrue);
        expect(c.state.lyrics.byId('amazing'), isNotNull);
      },
    );
  });

  test(
    'every bundled photo is CC0 or public domain, credited and at most 1920 × 1080',
    () {
      final credits =
          (jsonDecode(
                    File(
                      'assets/lyrics/photos/credits.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map>();
      expect(
        [for (final c in credits) c['id']],
        [for (final p in lyricPhotos) p.id],
      );
      final files = Directory(
        'assets/lyrics/photos',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.jpg'));
      expect(
        files.length,
        lyricPhotos.length,
        reason: 'no photo without a credit',
      );
      for (final c in credits) {
        expect(
          const {'CC0', 'Public domain'},
          contains(c['license']),
          reason: '${c['id']}',
        );
        expect('${c['author']}', isNotEmpty);
        expect(
          '${c['source']}',
          startsWith('https://commons.wikimedia.org/wiki/File:'),
        );
        final file = File('assets/lyrics/photos/${c['id']}.jpg');
        // A starry sky compresses least; the rest are well under.
        expect(file.lengthSync(), lessThan(750000));
        final thumb = img.decodeJpg(
          File('assets/lyrics/photos/thumbs/${c['id']}.jpg').readAsBytesSync(),
        )!;
        expect(
          [thumb.width, thumb.height],
          [320, 180],
          reason: 'the picker never decodes full HD',
        );
        expect(const {'nature', 'people'}, contains(c['kind']));
        final image = img.decodeJpg(file.readAsBytesSync())!;
        expect(image.width, lessThanOrEqualTo(1920));
        expect(image.height, lessThanOrEqualTo(1080));
      }
      expect(
        File('docs/LYRICS-PHOTOS.md').readAsStringSync(),
        contains(credits.first['source']),
      );
    },
  );
}
