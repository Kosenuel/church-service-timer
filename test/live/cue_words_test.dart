import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import '../support/fake_port.dart';
import '../support/w2_port.dart' as w2;
import '../support/widget_setup.dart';

/// Three words, each fitting the sign on its own but no two together.
const threeWords = TextLayout('WRAP UP NOW', effect: 'flash');

/// The spec's example, in the square font, where "UP NOW" fits together.
const squareWords = TextLayout(
  'PLEASE WRAP UP NOW',
  effect: 'flash',
  font: 'i-proton_sq_matrix',
);

TextLayout steady(TextLayout l, String text) => TextLayout(
  text,
  effect: 'static',
  bold: l.bold,
  italic: l.italic,
  height: l.height,
  font: l.font,
  align: l.align,
);

/// A cue as a host sends it to screens, with its groups of words.
Json words(TextLayout l, {Json? more}) => {
  'phase': 'active',
  'stageSharing': true,
  'stageLayout': 'timer',
  'displayText': l.text,
  'displayIsTimer': false,
  'outputMode': 'Cue',
  'bold': l.bold,
  ...stageEffectFields(l),
  'screenWords': ?stageWordGroupsOf(l),
  if (l.screenWrap) 'screenWrap': true,
  ...?more,
};

Future<void> stage(
  WidgetTester t,
  Json data, {
  Size size = const Size(1920, 1080),
  double textScale = 1,
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
}

final wordGroup = find.byKey(const ValueKey('stage-word-group'));
String shown(WidgetTester t) => t.widget<Text>(wordGroup).data!;
double opacity(WidgetTester t) => t
    .widget<Opacity>(
      find
          .ancestor(
            of: wordGroup,
            matching: find.byKey(const ValueKey('stage-cue-opacity')),
          )
          .first,
    )
    .opacity;

void main() {
  setUpAll(loadAppFonts);

  group('Splitting into groups of words', () {
    test('the largest runs of whole words that fit', () {
      expect(groupWords('PLEASE WRAP UP NOW', (t) => t.length <= 7), [
        'PLEASE',
        'WRAP UP',
        'NOW',
      ]);
      expect(groupWords('  A  B C ', (t) => t.length <= 3), ['A B', 'C']);
      expect(groupWords('A TOOLONG B', (t) => t.length <= 4), isNull);
      expect(signWordGroups(squareWords), ['PLEASE', 'WRAP', 'UP NOW']);
      expect(signWordGroups(threeWords), ['WRAP', 'UP', 'NOW']);
      for (final l in [squareWords, threeWords]) {
        final groups = signWordGroups(l)!;
        expect(groups.join(' '), l.text);
        for (var i = 0; i < groups.length; i++) {
          expect(textWidth(steady(l, groups[i])), lessThanOrEqualTo(32));
          // Taking the next word too would not fit.
          if (i + 1 < groups.length) {
            final more = '${groups[i]} ${groups[i + 1].split(' ').first}';
            expect(textWidth(steady(l, more)), greaterThan(32));
          }
        }
      }
    });

    test('only Flash and Pulse, and only text too wide for the sign', () {
      expect(signWordGroups(const TextLayout('AMEN', effect: 'flash')), null);
      for (final effect in ['static', 'scroll', 'flashHold', 'slideIn']) {
        expect(
          signWordGroups(TextLayout(threeWords.text, effect: effect)),
          isNull,
          reason: effect,
        );
      }
      expect(signWordGroups(TextLayout(threeWords.text, effect: 'pulse')), [
        'WRAP',
        'UP',
        'NOW',
      ]);
    });

    test('long text may be Flash or Pulse; too long or too wide may not', () {
      validateLayout(threeWords);
      validateLayout(TextLayout(threeWords.text, effect: 'pulse'));
      validateLayout(squareWords);
      // A word wider than the sign still has to fit.
      expect(
        () => validateLayout(
          const TextLayout('PLEASE WRAP UP NOW', effect: 'flash'),
        ),
        throwsA(
          predicate(
            (e) => '$e'.contains('pixels wide and must fit the LED sign'),
          ),
        ),
      );
      // More than 60 characters: choose Scroll long text.
      final long = TextLayout('GO ${'NOW ' * 15}'.trim(), effect: 'pulse');
      expect(long.text.length, greaterThan(60));
      expect(
        () => validateLayout(long),
        throwsA(
          predicate(
            (e) =>
                '$e'.contains('a few words at a time, up to 60 characters') &&
                '$e'.contains('Scroll long text'),
          ),
        ),
      );
      validateLayout(TextLayout('GO ${'NOW ' * 14}'.trim(), effect: 'pulse'));
      // Every other effect must still fit.
      expect(
        () => validateLayout(TextLayout(threeWords.text, effect: 'flashHold')),
        throwsA(anything),
      );
      expect(
        () => validateLayout(TextLayout(threeWords.text, effect: 'static')),
        throwsA(anything),
      );
    });

    test('the timing on screens and the sign', () {
      // Flash: on, off, on, off for each group; a longer pause at the end.
      expect(wordGroupCycleMs('flash', 3), 6300);
      expect(wordGroupCycleMs('pulse', 3), 6000);
      final flash = [
        for (var ms = 250; ms < 6300; ms += 500) wordGroupAt('flash', 3, ms),
      ];
      expect(flash.map((s) => s.index), [
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        2,
      ]);
      expect(flash.map((s) => s.opacity), [
        1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, //
      ]);
      expect(wordGroupAt('flash', 3, 6300 + 250), (index: 0, opacity: 1.0));
      // Pulse fades each group in and out.
      expect(wordGroupAt('pulse', 3, 0).opacity, 0);
      expect(wordGroupAt('pulse', 3, 1000).opacity, closeTo(1, 1e-9));
      expect(wordGroupAt('pulse', 3, 3000), (index: 1, opacity: 1.0));
      expect(wordGroupAt('pulse', 3, 6000).index, 0);
    });
  });

  group('On the LED sign', () {
    test('it steps through the groups by itself', () {
      final l = threeWords;
      Matcher showing(String text) => equals(renderPixels(steady(l, text), 0));
      final blank = List.filled(512, false);
      expect(renderPixels(l, 250), showing('WRAP'));
      expect(renderPixels(l, 750), blank);
      expect(renderPixels(l, 1250), showing('WRAP'));
      expect(renderPixels(l, 2250), showing('UP'));
      expect(renderPixels(l, 4250), showing('NOW'));
      // The pause after the last group, then round again.
      expect(renderPixels(l, 5600), blank);
      expect(renderPixels(l, 6200), blank);
      expect(renderPixels(l, 6350), showing('WRAP'));
      // Pulse cannot dim on the sign: each group lights for about 1.3 s.
      final pulse = TextLayout(l.text, effect: 'pulse');
      final lit = [
        for (var ms = 0; ms < 2000; ms += 100)
          renderPixels(pulse, ms).contains(true),
      ];
      expect(lit.where((on) => on).length, 13);
      expect(lit.first, isFalse);
      expect(renderPixels(pulse, 1000), showing('WRAP'));
      expect(renderPixels(pulse, 3000), showing('UP'));
    });

    test('the sign is sent one round of frames that it loops', () async {
      final port = w2.W2Port();
      final c = await w2.setup(port);
      addTearDown(c.dispose);
      int count(Uint8List bytes) => ByteData.sublistView(bytes).getUint16(143);
      List<bool> frame(Uint8List bytes, int f) {
        final offset = 140 + 27 + count(bytes) * 2 + f * 64;
        return [
          for (var p = 0; p < 512; p++)
            bytes[offset + p ~/ 8] & (1 << (7 - p % 8)) != 0,
        ];
      }

      for (final l in [
        threeWords,
        TextLayout(threeWords.text, effect: 'pulse'),
      ]) {
        expect(await c.act('cue', value: l), true);
        await w2.flush();
        final sent = port.sent.last.bytes;
        final frames = wordGroupCycleMs(l.effect, 3) ~/ wordGroupFrameMs;
        expect(count(sent), frames, reason: l.effect);
        // A tenth of a second a frame (the controller counts in halves).
        expect(ByteData.sublistView(sent).getUint16(164), 50);
        for (final f in [0, 3, 7, 12, 22, 45, frames - 1]) {
          expect(
            frame(sent, f),
            renderPixels(l, f * wordGroupFrameMs),
            reason: '${l.effect} frame $f',
          );
        }
      }
      // At most 60 characters is at most 603 of the sign's 2048 frames.
      expect(wordGroupCycleMs('flash', 30) ~/ wordGroupFrameMs, 603);
    });

    test('the LED simulator shows it moving', () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act(
        'load',
        value: Timeline('Service', const [
          Segment('Talk', 5),
        ], DisplaySettings()),
      );
      await c.act('start');
      await c.act('cue', value: threeWords);
      final sim = c.simulator;
      expect(sim.moving, isTrue);
      final at = sim.deliveredAt;
      expect(sim.pixelsAt(at + 250), renderPixels(threeWords, 250));
      expect(
        sim.pixelsAt(at + 2250),
        renderPixels(steady(threeWords, 'UP'), 0),
      );
      expect(sim.nextChangeAfter(at + 250), at + 300);
    });
  });

  group('On screens', () {
    test(
      'the host sends the groups; older screens see the whole text',
      () async {
        final c = AppController(FakePort());
        await c.initialize(startTicker: false);
        addTearDown(c.dispose);
        await c.act(
          'load',
          value: Timeline('Service', const [
            Segment('Talk', 5),
          ], DisplaySettings()),
        );
        await c.act('start');
        await c.act('cue', value: threeWords);
        final snapshot = c.pairedSnapshot(false);
        expect(snapshot['screenWords'], ['WRAP', 'UP', 'NOW']);
        // An older screen knows the effect and the whole text.
        expect(snapshot['effect'], 'flash');
        expect(snapshot['displayText'], 'WRAP UP NOW');
        await c.act('cue', value: TextLayout(threeWords.text, effect: 'pulse'));
        final pulse = c.pairedSnapshot(false);
        expect(pulse['effect'], 'static');
        expect(pulse['screenEffect'], 'pulse');
        expect(pulse['screenWords'], ['WRAP', 'UP', 'NOW']);
        // Text that fits has no groups.
        await c.act('cue', value: const TextLayout('AMEN', effect: 'flash'));
        expect(c.pairedSnapshot(false).containsKey('screenWords'), isFalse);
      },
    );

    testWidgets('Flash steps through the groups in time with the sign', (
      t,
    ) async {
      await stage(t, words(threeWords));
      await t.pump(const Duration(milliseconds: 250));
      expect(shown(t), 'WRAP');
      expect(opacity(t), 1);
      await t.pump(const Duration(milliseconds: 500));
      expect(opacity(t), 0);
      await t.pump(const Duration(milliseconds: 500));
      expect((shown(t), opacity(t)), ('WRAP', 1));
      await t.pump(const Duration(milliseconds: 1000));
      expect((shown(t), opacity(t)), ('UP', 1));
      await t.pump(const Duration(milliseconds: 2000));
      expect((shown(t), opacity(t)), ('NOW', 1));
      // The pause, then round again.
      await t.pump(const Duration(milliseconds: 1500));
      expect(opacity(t), 0);
      await t.pump(const Duration(milliseconds: 600));
      expect((shown(t), opacity(t)), ('WRAP', 1));
      // Every group is the same size: as large as the widest fits.
      final sizes = <double>{};
      for (var i = 0; i < 3; i++) {
        sizes.add(t.getRect(wordGroup).height);
        await t.pump(const Duration(milliseconds: 2000));
      }
      expect(sizes.length, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('Pulse fades each group in and out', (t) async {
      await stage(t, words(TextLayout(threeWords.text, effect: 'pulse')));
      await t.pump(const Duration(milliseconds: 50));
      expect(opacity(t), lessThan(.05));
      await t.pump(const Duration(milliseconds: 950));
      expect(shown(t), 'WRAP');
      expect(opacity(t), closeTo(1, .01));
      await t.pump(const Duration(milliseconds: 2000));
      expect(shown(t), 'UP');
      expect(opacity(t), closeTo(1, .01));
      await t.pump(const Duration(milliseconds: 1000));
      expect(opacity(t), lessThan(.05));
    });

    testWidgets('with Wrap long text the whole message shows at once', (
      t,
    ) async {
      await stage(
        t,
        words(
          const TextLayout('WRAP UP NOW', effect: 'flash', screenWrap: true),
        ),
      );
      await t.pump(const Duration(milliseconds: 250));
      expect(wordGroup, findsNothing);
      expect(find.byKey(const ValueKey('stage-wrapped')), findsOne);
      expect(find.text('WRAP UP NOW'), findsOne);
      expect(t.takeException(), isNull);
    });

    testWidgets('in a banner, a group at a time in the band', (t) async {
      await stage(
        t,
        words(
          threeWords,
          more: {
            'cueColor': '#ffa833',
            'cuePosition': 'top',
            'underText': '12:34',
            'underMode': 'Countdown',
          },
        ),
      );
      await t.pump(const Duration(milliseconds: 250));
      final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
      expect(shown(t), 'WRAP');
      expect(band.contains(t.getRect(wordGroup).center), isTrue);
      // The countdown under the banner is plain.
      expect(
        stageUnderBanner(words(threeWords)).containsKey('screenWords'),
        false,
      );
      expect(find.byKey(const ValueKey('stage-time-width')), findsOne);
      expect(t.takeException(), isNull);
    });

    testWidgets('an older screen flashes the whole text', (t) async {
      // A snapshot from this version read by an older one is the same
      // snapshot without the groups.
      await stage(t, words(threeWords)..remove('screenWords'));
      await t.pump(const Duration(milliseconds: 250));
      expect(wordGroup, findsNothing);
      expect(find.text('WRAP UP NOW'), findsOne);
      await t.pump(const Duration(milliseconds: 500));
      expect(
        t
            .widget<Opacity>(find.byKey(const ValueKey('stage-cue-opacity')))
            .opacity,
        0,
      );
      // Nonsense in place of the groups is ignored too.
      await stage(t, {
        ...words(threeWords),
        'screenWords': [1, 2],
      });
      await t.pump(const Duration(milliseconds: 250));
      expect(wordGroup, findsNothing);
      expect(find.text('WRAP UP NOW'), findsOne);
    });

    for (final (size, scale) in [
      (const Size(320, 568), 1.6),
      (const Size(1920, 1080), 1.0),
    ]) {
      testWidgets(
        'no overflow at ${size.width.round()}×${size.height.round()}',
        (t) async {
          for (final l in [
            squareWords,
            TextLayout(threeWords.text, effect: 'pulse'),
          ]) {
            await stage(t, words(l), size: size, textScale: scale);
            for (var ms = 0; ms < 6400; ms += 400) {
              await t.pump(const Duration(milliseconds: 400));
              expect(t.takeException(), isNull);
              final r = t.getRect(wordGroup);
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(size.width));
            }
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }

    test('the web page is given the groups and steps through them', () {
      const settings = WebStageSettings(orderCode: '1234', localName: 'church');
      final view = viewFor(WebRole.stage, words(threeWords), settings);
      expect(view['words'], ['WRAP', 'UP', 'NOW']);
      expect(view['effect'], 'flash');
      final band = viewFor(
        WebRole.stage,
        words(
          threeWords,
          more: {
            'cuePosition': 'bottom',
            'underText': '12:34',
            'underMode': 'Countdown',
          },
        ),
        settings,
      );
      expect((band['banner'] as Map)['words'], ['WRAP', 'UP', 'NOW']);
      expect(band.containsKey('words'), isFalse);
      expect(
        viewFor(
          WebRole.stage,
          words(const TextLayout('AMEN')),
          settings,
        ).containsKey('words'),
        isFalse,
      );
      for (final part in [
        'function wordAt(kind, count, ms)',
        "count * 2000 + (kind === 'flash' ? 300 : 0)",
        'function wordsOf(s, wrap)',
        'if (!ok || wrap) return null;',
        'function fitWords',
        'stepWords(m, label, bandGroup)',
        "Object.assign({}, s, { effect: 'words', group })",
      ]) {
        expect(webStagePage, contains(part), reason: part);
      }
      // Its timing matches the app's.
      expect(wordGroupMs, 2000);
      expect(wordGroupPauseMs - 500, 300);
      expect(jsonEncode(view['words']), '["WRAP","UP","NOW"]');
    });
  });

  group('The cue editor', () {
    test('Flash and Pulse need not fit, and say so', () {
      String label(String v) =>
          effectChoices.firstWhere((o) => o.value == v).label;
      String hint(String v) =>
          effectChoices.firstWhere((o) => o.value == v).hint!;
      expect(label('flash'), 'Flash');
      expect(label('pulse'), 'Pulse');
      expect(label('static'), 'Static (must fit)');
      expect(label('flashHold'), 'Flash then hold (must fit)');
      for (final v in ['flash', 'pulse']) {
        expect(hint(v), contains('Long text shows a few words at a time'));
      }
      for (final v in ['static', 'flashHold', 'slideIn', 'bar']) {
        expect(hint(v), isNot(contains('few words')));
      }
    });

    testWidgets('the previews show it a few words at a time', (t) async {
      setScreen(t, const Size(1366, 768));
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('midnight_lime', size: const Size(1366, 768)),
          home: const Scaffold(
            body: TextComposer(
              initial: threeWords,
              title: 'Edit stage cue',
              button: 'Save cue',
              stagePreviewFirst: true,
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      // No error: Save is there to press.
      expect(find.textContaining('pixels wide'), findsNothing);
      expect(shown(t), 'WRAP');
      await t.pump(const Duration(milliseconds: 2000));
      expect(shown(t), 'UP');
      await t.tap(find.text('LED sign'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(LedMatrix), findsOne);
      expect(t.takeException(), isNull);
    });
  });

  group('Goldens', () {
    testWidgets('the LED simulator showing a group of words', (t) async {
      setScreen(t, const Size(640, 320));
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: LedMatrix(pixels: renderPixels(squareWords, 4250)),
            ),
          ),
        ),
      );
      expect(
        renderPixels(squareWords, 4250),
        renderPixels(steady(squareWords, 'UP NOW'), 0),
      );
      await expectLater(
        find.byType(LedMatrix),
        matchesGoldenFile('../goldens/led-cue-words-group.png'),
      );
    });

    testWidgets('a stage screen showing a group of words', (t) async {
      await stage(
        t,
        words(
          const TextLayout(
            'PLEASE WRAP UP NOW',
            effect: 'flash',
            font: 'i-proton_sq_matrix',
            screenColor: 'red',
          ),
          more: {'cueColor': '#ff4d4d', 'bold': true},
        ),
      );
      await t.pump(const Duration(milliseconds: 4250));
      expect(shown(t), 'UP NOW');
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-words-flash-1080.png'),
      );
    });
  });
}
