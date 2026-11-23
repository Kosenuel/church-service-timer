import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class _Wire implements PairWire {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Lyrics beside the themed countdown layouts: a slide takes the screen
/// only while it is sent there, its countdown chip says when the service
/// is over time, and Clear slide gives the screen back exactly.
void main() {
  setUpAll(loadAppFonts);

  Future<(AppController, FakePort)> open() async {
    final port = FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.lyrics.save(
      LyricItem(
        id: 'amazing',
        kind: 'song',
        title: 'Amazing Grace',
        words: 'Verse 1\nAmazing grace\nHow sweet the sound',
      ),
    );
    await c.act(
      'load',
      value: Timeline('Sunday Service', const [
        Segment('Welcome', 5),
        Segment('Sermon', 40),
      ], DisplaySettings()),
    );
    await c.act('start');
    return (c, port);
  }

  Future<void> overtime(AppController c, FakePort port) async {
    port.at = after(5 * 60 + 2);
    await c.tick();
    // The "time's up" cue shows for a few seconds; the red screen follows.
    port.at = after(5 * 60 + 42);
    await c.tick();
    expect(c.state.session.overtime(c.now), greaterThan(0));
  }

  for (final layout in stageLayouts.keys) {
    for (final late in [false, true]) {
      final when = late ? 'in overtime' : 'counting down';
      test(
        'Clear slide gives back "${stageLayouts[layout]}" $when exactly',
        () async {
          final (c, port) = await open();
          await c.setSimulatorLayout(layout);
          if (late) await overtime(c, port);
          final peer = PairPeer('phone', 'Pulpit phone', 'stage', _Wire());
          await c.lyrics.setLook(c.lyrics.look.copyWith(toStage: true));
          c.lyrics.clear();
          final sim = jsonEncode(c.stageSimulatorSnapshot());
          final window = jsonEncode(c.stageWindowSnapshot());
          final web = jsonEncode(c.webStageSnapshot());
          final paired = jsonEncode(
            c.decoratePairedSnapshot(peer, c.pairedSnapshot(false)),
          );
          c.lyrics.show('amazing', 0);
          expect(c.stageSimulatorSnapshot()['lyrics'], isA<Map>());
          expect(c.stageSimulatorSnapshot()['stageLayout'], layout);
          expect(c.webStageSnapshot()['lyrics'], isA<Map>());
          expect(
            c.decoratePairedSnapshot(peer, c.pairedSnapshot(false))['lyrics'],
            isA<Map>(),
          );
          c.lyrics.clear();
          expect(jsonEncode(c.stageSimulatorSnapshot()), sim);
          expect(jsonEncode(c.stageWindowSnapshot()), window);
          expect(jsonEncode(c.webStageSnapshot()), web);
          expect(
            jsonEncode(c.decoratePairedSnapshot(peer, c.pairedSnapshot(false))),
            paired,
          );
        },
      );

      testWidgets(
        'the screen shows "${stageLayouts[layout]}" again after Clear slide $when',
        (t) async {
          final (c, port) = await open();
          await c.setSimulatorLayout(layout);
          if (late) await overtime(c, port);
          setScreen(t, const Size(960, 540));
          Future<List<String>> shown(Json data) async {
            await t.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  backgroundColor: stageBackdropOf(data),
                  body: StageSurface(data: data, stale: false),
                ),
              ),
            );
            await t.pump(const Duration(seconds: 2));
            return [
              for (final w in t.widgetList<Text>(find.byType(Text)))
                w.data ?? w.textSpan?.toPlainText() ?? '',
            ];
          }

          final before = c.stageSimulatorSnapshot();
          final countdown = await shown(before);
          expect(find.byKey(const ValueKey('lyric-stage')), findsNothing);
          final backdrop = stageBackdropOf(before);
          if (late && layout != 'only') {
            expect(backdrop, StageColors.overtimeRed);
          }

          c.lyrics.show('amazing', 0);
          final withLyrics = c.stageSimulatorSnapshot();
          await shown(withLyrics);
          expect(find.byKey(const ValueKey('lyric-stage')), findsOneWidget);
          expect(
            stageBackdropOf(withLyrics),
            Colors.black,
            reason: 'the slide paints its own screen, not the theme or red',
          );
          expect(stageFillsScreen(withLyrics), isTrue);

          c.lyrics.clear();
          final after = c.stageSimulatorSnapshot();
          expect(stageBackdropOf(after), backdrop);
          expect(await shown(after), countdown);
          expect(find.byKey(const ValueKey('lyric-stage')), findsNothing);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }

  test('a quick message to a stage screen still covers a slide', () {
    final data = {
      'stageSharing': true,
      'quickMessage': {'text': 'Hello'},
      'lyrics': {'v': 1, 'key': 'k', 'text': 'x'},
    };
    expect(stageLyrics(data), isNull);
    expect(stageHasLyrics(data), isFalse);
    expect(stageBackdropOf(data), Colors.black);
  });

  group('the chip in the corner', () {
    test(
      'says +time and is flagged red in overtime, the time left before',
      () async {
        final (c, port) = await open();
        c.lyrics.show('amazing', 0);
        var chip = c.stageWindowSnapshot()['lyrics'] as Map;
        expect(chip['chipOver'], isFalse);
        expect(chip['chip'], isNot(startsWith('+')));
        await overtime(c, port);
        chip = c.stageWindowSnapshot()['lyrics'] as Map;
        expect(chip['chipOver'], isTrue);
        expect(chip['chip'], startsWith('+'));
        final web = c.webStageSnapshot()['lyrics'] as Map;
        expect(web['chipOver'], isTrue);
        expect(web['chip'], startsWith('+'));
      },
    );

    for (final over in [false, true]) {
      testWidgets(
        'is ${over ? 'a red chip with dark ink in overtime' : 'dark with white digits normally'}',
        (t) async {
          setScreen(t, const Size(960, 540));
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StageSurface(
                  data: {
                    'stageSharing': true,
                    'lyrics': {
                      'v': 1,
                      'key': 'k',
                      'kind': 'song',
                      'label': 'Verse 1',
                      'text': 'Amazing grace\nHow sweet the sound',
                      'bg': 'ocean',
                      'dim': 70,
                      'size': 'm',
                      'align': 'center',
                      'motion': false,
                      'chip': over ? '+0:42' : '4:18',
                      'chipOver': over,
                    },
                  },
                  stale: false,
                ),
              ),
            ),
          );
          await t.pump(const Duration(seconds: 1));
          final chip = find.byKey(const ValueKey('lyric-chip'));
          final box = t.widget<DecoratedBox>(chip).decoration as BoxDecoration;
          final text = t.widget<Text>(
            find.descendant(of: chip, matching: find.byType(Text)),
          );
          if (over) {
            expect(box.color, StageColors.overtimeRed);
            expect(text.style!.color, StageColors.overtimeInk);
            expect(text.data, '+0:42');
            expect(
              contrast(StageColors.overtimeInk, StageColors.overtimeRed),
              greaterThanOrEqualTo(4.5),
            );
          } else {
            expect(box.color!.a, lessThan(1));
            expect(text.style!.color, Colors.white);
          }
          await t.pumpWidget(const SizedBox());
        },
      );
    }

    test('the web page draws the same red chip', () {
      expect(
        webStagePage,
        contains('#lyr .chip.over { background:#e5333a; color:#1a0000;'),
      );
    });
  });
}
