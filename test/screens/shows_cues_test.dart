import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/confidence_monitor.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// "Shows cues": each group says whether its screens face the person
/// speaking (cues, warning cues and quick messages show) or the room
/// (they never do).
void main() {
  setUpAll(loadAppFonts);

  Future<AppController> ready() async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.act(
      'load',
      value: Timeline('Sunday', const [
        Segment('Worship', 20),
        Segment('Sermon', 30),
      ], DisplaySettings()),
    );
    await c.act('start');
    await c.lyrics.save(
      LyricItem(
        id: 'well',
        kind: 'song',
        title: 'It Is Well',
        words:
            'Verse 1\nWhen peace like a river attendeth my way\nWhen sorrows like sea billows roll\n\nChorus\nIt is well with my soul',
      ),
    );
    c.lyrics.show('well', 0);
    return c;
  }

  const banner = TextLayout('WRAP UP', screenPosition: 'bottom');
  const full = TextLayout('WRAP UP');

  Future<void> warning(AppController c) => c.commit((draft, at) {
    draft.session
      ..automaticCue = const TextLayout('2 MIN LEFT')
      ..automaticCueAt = at;
  });

  test(
    'the migration: Stage shows cues, Church Auditorium does not; new groups do not',
    () async {
      final c = await ready();
      expect(c.screens.setup.byId('stage')!.cues, isTrue);
      expect(c.screens.setup.byId('room')!.cues, isFalse);
      final id = await c.screens.addGroup('Choir');
      expect(c.screens.setup.byId(id)!.cues, isFalse);
      final split = migrateScreens(
        self: (layout: 'timer', slides: false),
        web: (layout: 'next', slides: false),
        paired: const [(id: 'a', layout: 'timer'), (id: 'b', layout: 'only')],
        pairedSlides: false,
      );
      expect(
        {for (final g in split.groups) g.name: g.cues},
        {
          'Church Auditorium': false,
          'Web screens': false,
          'Stage': true,
          'Stage 2': true,
        },
      );
    },
  );

  test('scenes leave Shows cues alone', () async {
    final c = await ready();
    final scene = (await c.screens.saveScene('Worship'))!;
    await c.screens.setCues('room', true);
    await c.screens.setShow('room', 'timer');
    await c.screens.applyScene(scene);
    expect(c.screens.setup.byId('room')!.cues, isTrue);
    expect(c.screens.setup.byId('room')!.show, 'slides');
    expect(
      c.screens.setup.sceneById(scene)!.toJson().toString(),
      isNot(contains('cues')),
    );
  });

  for (final show in screenShows.keys) {
    for (final on in [true, false]) {
      for (final (kind, start)
          in <(String, Future<void> Function(AppController))>[
            ('a banner cue', (c) => c.act('cue', value: banner)),
            ('a full-screen cue', (c) => c.act('cue', value: full)),
            ('a warning cue', warning),
          ]) {
        test(
          '“${screenShows[show]}”, cues ${on ? 'on' : 'off'}: $kind',
          () async {
            final c = await ready();
            await c.screens.setShow('room', show);
            await c.screens.setCues('room', on);
            final before = c.stageWindowSnapshot();
            await start(c);
            final data = c.stageWindowSnapshot();
            expect(data.containsKey('plain'), isFalse, reason: 'never sent');
            if (on) {
              expect(data['cue'], isTrue);
              expect(data['displayText'], isNot(before['displayText']));
              expect(data['displayIsTimer'], isFalse);
            } else {
              expect(data.containsKey('cue'), isFalse);
              // Exactly what it showed without the cue (the time has not moved).
              for (final key in stageCueKeys) {
                expect(data[key], before[key], reason: key);
              }
            }
            // The slide or monitor stays for a group showing slides.
            expect(data.containsKey('lyrics'), show == 'slides');
            expect(data.containsKey('confidence'), show == 'monitor');
            // The LED sign is the session's, cue or not.
            expect(
              c.state.session.intended(c.now)?.text,
              isNot(contains('peace')),
            );
          },
        );
      }
      test(
        '“${screenShows[show]}”, cues ${on ? 'on' : 'off'}: a quick message',
        () async {
          final c = await ready();
          await c.screens.setShow('room', show);
          await c.screens.setCues('room', on);
          final data = c.screens.decorate(
            {
              ...c.pairedSnapshot(false),
              'quickMessage': const QuickMessage(body: 'Two minutes').toJson(),
              'messageId': 'm1',
            },
            thisScreenKey,
            LyricTarget.second,
          );
          expect(data.containsKey('quickMessage'), on);
          expect(data.containsKey('messageId'), on);
        },
      );
    }
  }

  test('cues off: the web view gets no cue fields either', () async {
    final c = await ready();
    await c.screens.setShow('room', 'timer');
    await c.act('cue', value: banner);
    final view = viewFor(
      WebRole.stage,
      c.webStageSnapshot(),
      c.webStageSettings,
    );
    expect(view.containsKey('banner'), isFalse);
    expect(view['countdown'], isNotNull);
  });

  Future<void> pump(WidgetTester t, Json data, Size size) async {
    setScreen(t, size);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: stageBackdropOf(data),
          body: StageSurface(data: data, stale: false),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
  }

  for (final (name, cue, size) in [
    ('slide-cue-banner-wide', full, const Size(1920, 1080)),
    (
      'slide-cue-top-phone',
      const TextLayout('2 MIN', screenPosition: 'top'),
      const Size(800, 450),
    ),
  ]) {
    testWidgets('golden: a slide with a cue over it, $name', (t) async {
      late Json data;
      await t.runAsync(() async {
        final c = await ready();
        await c.screens.setCues('room', true);
        await c.act('cue', value: cue);
        data = c.stageWindowSnapshot()..remove('lyrics');
        data['lyrics'] = {
          ...c.stageWindowSnapshot()['lyrics'] as Map,
          'bg': 'ocean',
        }..remove('picture');
      });
      await pump(t, data, size);
      expect(find.byKey(const ValueKey('slide-cue')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric-stage')), findsOneWidget);
      expect(
        find.text('WRAP UP').evaluate().isNotEmpty ||
            find.text('2 MIN').evaluate().isNotEmpty,
        isTrue,
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/screens-$name.png'),
      );
    });
  }

  for (final (name, size) in [
    ('wide', const Size(1920, 1080)),
    ('phone', const Size(390, 800)),
  ]) {
    testWidgets('golden: the confidence monitor with a cue, $name', (t) async {
      late Json data;
      await t.runAsync(() async {
        final c = await ready();
        await c.screens.setShow('stage', 'monitor');
        await c.screens.move(thisScreenKey, 'stage');
        await c.act(
          'cue',
          value: const TextLayout('WRAP UP', screenColor: 'amber'),
        );
        data = c.stageWindowSnapshot();
      });
      await pump(t, data, size);
      expect(find.byType(ConfidenceMonitor), findsOneWidget);
      expect(find.byKey(const ValueKey('confidence-cue')), findsOneWidget);
      expect(find.text('VERSE 1'), findsOneWidget, reason: 'the words stay');
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/confidence-cue-$name.png'),
      );
    });
  }
}
