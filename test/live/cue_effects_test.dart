import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import '../support/fake_port.dart';
import '../support/w2_port.dart' as w2;
import '../support/widget_setup.dart';

Json roundTrip(TextLayout l) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(l.toJson())));

Future<AppController> running([FakePort? port]) async {
  final c = AppController(port ?? FakePort());
  await c.initialize(startTicker: false);
  await c.act(
    'load',
    value: Timeline('Service', const [Segment('Talk', 5)], DisplaySettings()),
  );
  await c.act('start');
  return c;
}

/// A full-screen cue, as a host sends it to screens.
Json cue(String effect, {String? color, Json? more}) => {
  'phase': 'active',
  'stageSharing': true,
  'stageLayout': 'timer',
  'displayText': 'WRAP UP',
  'displayIsTimer': false,
  'outputMode': 'Cue',
  'bold': true,
  ...stageEffectFields(TextLayout('WRAP UP', effect: effect)),
  'cueColor': ?color,
  ...?more,
};

/// The same cue as a banner over a countdown.
Json bannered(String effect, {String position = 'bottom', Json? more}) => cue(
  effect,
  color: '#ffa833',
  more: {
    'cuePosition': position,
    'underText': '12:34',
    'underMode': 'Countdown',
    'paused': true,
    ...?more,
  },
);

Future<void> stage(
  WidgetTester t,
  Json data, {
  Size size = const Size(1920, 1080),
  bool reducedMotion = false,
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
}

/// Shows [data] in place of what the screen shows now, as a new snapshot.
Future<void> next(WidgetTester t, Json data) async {
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
}

double opacityOf(WidgetTester t, [String text = 'WRAP UP']) => t
    .widget<Opacity>(
      find
          .ancestor(
            of: text == '12:34' ? find.byType(ClockText) : find.text(text),
            matching: find.byKey(const ValueKey('stage-cue-opacity')),
          )
          .first,
    )
    .opacity;

BoxDecoration flashOf(WidgetTester t, {bool band = false}) =>
    t
            .widget<DecoratedBox>(
              band
                  ? find.descendant(
                      of: find.byKey(const ValueKey('stage-banner')),
                      matching: find.byKey(
                        const ValueKey('stage-screen-flash'),
                      ),
                    )
                  : find.byKey(const ValueKey('stage-screen-flash')).first,
            )
            .decoration
        as BoxDecoration;

Color textColor(WidgetTester t, [String text = 'WRAP UP']) =>
    t.widget<Text>(find.text(text)).style!.color!;

double barWidth(WidgetTester t) =>
    t.getSize(find.byKey(const ValueKey('stage-cue-bar'))).width;

void main() {
  setUpAll(loadAppFonts);

  group('The effect a cue is saved with', () {
    test('each new effect is kept, and plain cues are as they were', () {
      for (final effect in screenEffects) {
        final l = TextLayout('AMEN', effect: effect);
        final back = TextLayout.fromJson(roundTrip(l));
        expect(back.effect, effect);
        expect(roundTrip(back), roundTrip(l));
        expect(l.compatibleEffect, 'static', reason: effect);
        expect(l.screenEffect, effect);
      }
      // A cue saved by an earlier version opens unchanged.
      final old = {
        'text': 'AMEN',
        'bold': false,
        'italic': false,
        'effect': 'flash',
        'align': 'center',
        'speed': 12,
        'height': 1,
        'font': 'i-proton_matrix',
      };
      final read = TextLayout.fromJson(old);
      expect(read.effect, 'flash');
      expect(read.compatibleEffect, 'flash');
      expect(read.screenEffect, isNull);
      expect(roundTrip(read), old);
      // An effect this version does not know is refused.
      expect(
        () => TextLayout.fromJson({...old, 'effect': 'sparkle'}),
        throwsA(anything),
      );
    });

    test('the new effects must fit the LED sign, as static text does', () {
      for (final effect in screenEffects) {
        expect(
          () => validateLayout(
            TextLayout('PLEASE WRAP UP NOW THANK YOU', effect: effect),
          ),
          throwsA(anything),
          reason: effect,
        );
        validateLayout(TextLayout('AMEN', effect: effect));
      }
    });

    test('summaries name the effect in plain words', () {
      expect(
        styleSummary(const TextLayout('AMEN', effect: 'flashHold')),
        contains('flash then hold'),
      );
      expect(
        styleSummary(const TextLayout('AMEN', effect: 'static')),
        contains('static'),
      );
    });
  });

  group('What a host sends to screens', () {
    test('older screens are sent an effect they know', () async {
      final c = await running();
      addTearDown(c.dispose);
      for (final effect in screenEffects) {
        await c.act('cue', value: TextLayout('AMEN', effect: effect));
        for (final snapshot in [
          c.pairedSnapshot(false),
          c.stageWindowSnapshot(),
        ]) {
          // An earlier version reads 'effect' and shows the cue steady.
          expect(snapshot['effect'], 'static', reason: effect);
          expect(snapshot['screenEffect'], effect);
        }
      }
      await c.act('cue', value: const TextLayout('AMEN', effect: 'flash'));
      expect(c.pairedSnapshot(false)['effect'], 'flash');
      expect(c.pairedSnapshot(false).containsKey('screenEffect'), isFalse);
      // The sign is sent the cue itself.
      await c.act('cue', value: const TextLayout('AMEN', effect: 'flashHold'));
      expect(c.state.session.intended(c.now)!.effect, 'flashHold');
    });

    test('a countdown bar has a time only when the cue has one', () async {
      final port = FakePort();
      final c = await running(port);
      addTearDown(c.dispose);
      const bar = TextLayout('AMEN', effect: 'bar');
      await c.act('cue', value: bar);
      var snapshot = c.pairedSnapshot(false);
      expect(snapshot['screenEffect'], 'bar');
      expect(snapshot.containsKey('cueTotalMs'), isFalse);
      expect(stageCueTime(snapshot), isNull);

      await c.act('message', value: const StageOutputMessage(bar, seconds: 30));
      port.at = after(10);
      await c.tick();
      snapshot = c.pairedSnapshot(false);
      expect(snapshot['cueTotalMs'], 30000);
      expect(snapshot['cueLeftMs'], 20000);
      expect(stageCueTime(snapshot), (total: 30000, left: 20000));
      // Under a banner the countdown never carries the cue's effect.
      final under = stageUnderBanner({...snapshot, 'cuePosition': 'top'});
      for (final key in ['screenEffect', 'cueTotalMs', 'cueLeftMs']) {
        expect(under.containsKey(key), isFalse, reason: key);
      }
    });

    test('an automatic warning runs its bar over its own time', () async {
      final port = FakePort();
      final c = AppController(port);
      addTearDown(c.dispose);
      await c.initialize(startTicker: false);
      expect(
        await c.setSharedWarnings(const [
          WarningRule(
            240,
            TextLayout('WRAP UP', effect: 'bar', screenColor: 'amber'),
            destination: 'stage',
            durationSeconds: 20,
          ),
        ]),
        true,
      );
      await c.act(
        'load',
        value: Timeline('Service', const [
          Segment('Talk', 5),
        ], c.state.defaults),
      );
      await c.act('start');
      port.at = after(61);
      await c.tick();
      await Future<void>.delayed(Duration.zero);
      await c.tick();
      final snapshot = c.pairedSnapshot(false);
      expect(snapshot['displayText'], 'WRAP UP');
      expect(snapshot['effect'], 'static');
      expect(snapshot['screenEffect'], 'bar');
      expect(snapshot['cueTotalMs'], 20000);
      expect(snapshot['cueLeftMs'], inInclusiveRange(18000, 20000));
    });

    test('a web screen is given each effect, never for the countdown', () {
      const settings = WebStageSettings(orderCode: '1234', localName: 'church');
      Json view(Json data) => viewFor(WebRole.stage, data, settings);
      final pulse = view(cue('pulse'));
      expect(pulse['effect'], 'static');
      expect(pulse['screenEffect'], 'pulse');
      expect(pulse.containsKey('cueTime'), isFalse);
      final bar = view(
        cue('bar', more: {'cueTotalMs': 8000, 'cueLeftMs': 6000}),
      );
      expect(bar['screenEffect'], 'bar');
      expect(bar['cueTime'], {'total': 8000, 'left': 6000});
      // A bar with no time to run over is not sent at all.
      expect(view(cue('bar')).containsKey('screenEffect'), isFalse);
      // Nothing unknown reaches the page.
      expect(
        view({
          ...cue('pulse'),
          'screenEffect': 'x;y',
        }).containsKey('screenEffect'),
        isFalse,
      );
      final band = view(bannered('screenFlash'));
      expect(band.containsKey('screenEffect'), isFalse);
      expect(band['displayText'], '12:34');
      expect((band['banner'] as Map)['screenEffect'], 'screenFlash');
      expect((band['banner'] as Map)['effect'], 'static');
      final bandBar = view(
        bannered('bar', more: {'cueTotalMs': 8000, 'cueLeftMs': 8000}),
      );
      expect((bandBar['banner'] as Map)['cueTime'], {
        'total': 8000,
        'left': 8000,
      });
      expect(bandBar.containsKey('cueTime'), isFalse);
      // The page draws each one, and keeps still with reduced motion.
      for (final part in [
        '@keyframes fx-pulse',
        '@keyframes fx-flash3',
        '.fx-slideIn',
        '.fx-screenFlash',
        'function setBar',
        'prefers-reduced-motion: reduce',
      ]) {
        expect(webStagePage, contains(part));
      }
      expect(webStagePage, isNot(contains('innerHTML')));
    });
  });

  group('On screens', () {
    testWidgets('pulse brightens and dims every two seconds', (t) async {
      await stage(t, cue('pulse'));
      await t.pump();
      expect(opacityOf(t), closeTo(1, .01));
      await t.pump(const Duration(milliseconds: 500));
      expect(opacityOf(t), closeTo(.775, .02));
      await t.pump(const Duration(milliseconds: 500));
      expect(opacityOf(t), closeTo(.55, .02));
      await t.pump(const Duration(milliseconds: 1000));
      expect(opacityOf(t), closeTo(1, .02));
      expect(t.takeException(), isNull);
    });

    testWidgets('flash then hold flashes three times and stays', (t) async {
      await stage(t, cue('flashHold'));
      await t.pump();
      final seen = <double>[];
      for (var ms = 250; ms <= 4000; ms += 500) {
        await t.pump(const Duration(milliseconds: 500));
        seen.add(opacityOf(t));
      }
      // Seen at 0.75 s, 1.25 s and so on: off, on, off, on, off, then on.
      expect(seen.take(6), [0, 1, 0, 1, 0, 1]);
      expect(seen.skip(6), everyElement(1));
      // Nothing is left animating once it holds.
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('slide in comes up from the bottom in 300 ms', (t) async {
      await stage(t, cue('slideIn'));
      await t.pump();
      double offset() => t
          .widget<Transform>(find.byKey(const ValueKey('stage-cue-slide')))
          .transform
          .getTranslation()
          .y;
      expect(offset(), greaterThan(900));
      await t.pump(const Duration(milliseconds: 150));
      expect(offset(), inExclusiveRange(0, 300));
      await t.pump(const Duration(milliseconds: 200));
      expect(offset(), 0);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('slide in simply appears with reduced motion', (t) async {
      await stage(t, cue('slideIn'), reducedMotion: true);
      await t.pump();
      expect(
        t
            .widget<Transform>(find.byKey(const ValueKey('stage-cue-slide')))
            .transform
            .getTranslation()
            .y,
        0,
      );
    });

    testWidgets('a countdown bar empties over the cue’s time', (t) async {
      final data = cue(
        'bar',
        color: '#ffa833',
        more: {'cueTotalMs': 10000, 'cueLeftMs': 10000},
      );
      await stage(t, data);
      await t.pump();
      final full = barWidth(t);
      // Four fifths of the screen, inside its margin.
      expect(full, closeTo((1920 - 24) * .8, 1));
      await t.pump(const Duration(seconds: 5));
      expect(barWidth(t), closeTo(full / 2, full * .02));
      // A new snapshot puts it where the host says, and it runs on.
      await next(t, {...data, 'cueLeftMs': 2000});
      await t.pump();
      expect(barWidth(t), closeTo(full * .2, full * .02));
      await t.pump(const Duration(seconds: 3));
      expect(barWidth(t), 0);
      expect(t.binding.hasScheduledFrame, isFalse);
      // The bar is in the cue's colour.
      final fill =
          t
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('stage-cue-bar')),
                  )
                  .decoration
              as BoxDecoration;
      expect(fill.color, const Color(0xffffa833));
    });

    testWidgets('a cue shown until cleared has no bar', (t) async {
      await stage(t, cue('bar', color: '#ffa833'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('stage-cue-bar')), findsNothing);
      expect(find.text('WRAP UP'), findsOne);
    });

    testWidgets('screen flash lights the screen once', (t) async {
      await stage(t, cue('screenFlash', color: '#4ade80'));
      await t.pump(const Duration(milliseconds: 100));
      // A deep tint of the cue's colour; the words are warm white over it,
      // as green on green would not read.
      expect(
        flashOf(t).color,
        Color.lerp(Colors.black, const Color(0xff4ade80), .32),
      );
      expect(textColor(t), const Color(0xfffff4dc));
      // Then it settles to the coloured cue's charcoal, with green words.
      await t.pump(const Duration(milliseconds: 600));
      expect(flashOf(t).color, const Color(0xff1a1712));
      expect(textColor(t), const Color(0xff4ade80));
      expect(t.binding.hasScheduledFrame, isFalse);
      // The next snapshot of the same cue does not flash again.
      await next(t, cue('screenFlash', color: '#4ade80'));
      await t.pump(const Duration(milliseconds: 100));
      expect(flashOf(t).color, const Color(0xff1a1712));
    });

    testWidgets('a white cue flashes red', (t) async {
      await stage(t, cue('screenFlash'));
      await t.pump(const Duration(milliseconds: 100));
      expect(
        flashOf(t).color,
        Color.lerp(Colors.black, const Color(0xffff4d4d), .32),
      );
    });

    testWidgets('screen flash with reduced motion is a coloured edge', (
      t,
    ) async {
      await stage(t, cue('screenFlash', color: '#ffa833'), reducedMotion: true);
      await t.pump(const Duration(milliseconds: 100));
      final box = flashOf(t);
      expect(box.color, const Color(0xff1a1712));
      expect((box.border! as Border).top.color, const Color(0xffffa833));
      expect(textColor(t), const Color(0xfffff4dc));
    });

    testWidgets('an older screen shows a newer effect steady', (t) async {
      // A snapshot from a later version, with an effect not known here.
      await stage(t, {...cue('static'), 'screenEffect': 'sparkle'});
      await t.pump(const Duration(seconds: 1));
      expect(opacityOf(t), 1);
      expect(find.byKey(const ValueKey('stage-cue-bar')), findsNothing);
      expect(find.byKey(const ValueKey('stage-cue-slide')), findsNothing);
      expect(t.binding.hasScheduledFrame, isFalse);
    });
  });

  group('In a banner', () {
    Rect time(WidgetTester t) =>
        t.getRect(find.byKey(const ValueKey('stage-time-width')));

    testWidgets('no effect moves or resizes the countdown', (t) async {
      await stage(t, bannered('static'));
      await t.pump(const Duration(milliseconds: 400));
      final steady = time(t);
      for (final effect in screenEffects) {
        await stage(
          t,
          bannered(effect, more: {'cueTotalMs': 8000, 'cueLeftMs': 8000}),
        );
        for (var ms = 0; ms < 3200; ms += 100) {
          await t.pump(const Duration(milliseconds: 100));
          if (ms >= 300) expect(time(t), steady, reason: '$effect at $ms ms');
          expect(
            t.widget<Text>(find.byKey(const ValueKey('stage-time-width'))).data,
            '00:00',
          );
        }
        expect(
          t.widget<ClockText>(find.byType(ClockText)).style.color,
          Colors.white,
          reason: effect,
        );
        expect(opacityOf(t, '12:34'), 1, reason: effect);
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('effects apply to the band', (t) async {
      await stage(t, bannered('pulse'));
      await t.pump(const Duration(milliseconds: 1000));
      expect(opacityOf(t), closeTo(.55, .02));
      expect(opacityOf(t, '12:34'), 1);

      await stage(t, bannered('screenFlash'));
      await t.pump(const Duration(milliseconds: 100));
      expect(
        flashOf(t, band: true).color,
        Color.lerp(Colors.black, const Color(0xffffa833), .32),
      );
      expect(textColor(t), const Color(0xffffa833));
      // The rest of the screen stays black.
      expect(flashOf(t).color, Colors.transparent);
      await t.pump(const Duration(milliseconds: 700));
      expect(flashOf(t, band: true).color, isNot(const Color(0xffffa833)));

      await stage(
        t,
        bannered('bar', more: {'cueTotalMs': 8000, 'cueLeftMs': 8000}),
      );
      await t.pump(const Duration(milliseconds: 400));
      final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
      final bar = t.getRect(find.byKey(const ValueKey('stage-cue-bar')));
      expect(band.contains(bar.center), isTrue);
    });

    testWidgets('a top banner slides in from the top', (t) async {
      await stage(t, bannered('slideIn', position: 'top'));
      await t.pump(const Duration(milliseconds: 50));
      expect(
        t
            .widget<Transform>(find.byKey(const ValueKey('stage-cue-slide')))
            .transform
            .getTranslation()
            .y,
        lessThan(0),
      );
    });
  });

  group('On the LED sign', () {
    bool lit(TextLayout l, int ms) => renderPixels(l, ms).contains(true);

    test('only flash then hold moves; the rest are steady', () {
      const hold = TextLayout('AMEN', effect: 'flashHold');
      expect(
        [for (var ms = 250; ms < 4000; ms += 500) lit(hold, ms)],
        [true, false, true, false, true, false, true, true],
      );
      expect(lit(hold, 60000), isTrue);
      // The controller's loop comes round again after five minutes.
      expect(lit(hold, flashHoldCycleMs + 750), isFalse);
      for (final effect in ['pulse', 'slideIn', 'bar', 'screenFlash']) {
        final l = TextLayout('AMEN', effect: effect);
        expect(l.steadyOnSign, isTrue);
        for (var ms = 0; ms < 4000; ms += 250) {
          expect(
            renderPixels(l, ms),
            renderPixels(const TextLayout('AMEN', effect: 'static'), 0),
          );
        }
      }
      expect(hold.steadyOnSign, isFalse);
    });

    test('the sign is sent three flashes and a long hold', () async {
      final port = w2.W2Port();
      final c = await w2.setup(port);
      addTearDown(c.dispose);
      int frames(Uint8List bytes) => ByteData.sublistView(bytes).getUint16(143);
      expect(
        await c.act(
          'cue',
          value: const TextLayout('AMEN', effect: 'flashHold'),
        ),
        true,
      );
      await w2.flush();
      final sent = port.sent.last.bytes;
      expect(frames(sent), flashHoldCycleMs ~/ 500);
      // Half a second a frame, as for Flash.
      expect(ByteData.sublistView(sent).getUint16(164), 250);
      for (final effect in ['pulse', 'slideIn', 'bar', 'screenFlash']) {
        await c.act('cue', value: TextLayout('AMEN', effect: effect));
        await w2.flush();
        expect(frames(port.sent.last.bytes), 1, reason: effect);
      }
    });
  });

  group('The cue editor', () {
    Future<void> composer(
      WidgetTester t,
      TextLayout initial, {
      Size size = const Size(1366, 768),
      double textScale = 1,
    }) async {
      setScreen(t, size);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('midnight_lime', size: size),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: TextComposer(
              initial: initial,
              title: 'Edit stage cue',
              button: 'Save cue',
              stagePreviewFirst: true,
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
    }

    Future<void> openEffects(WidgetTester t) async {
      await t.ensureVisible(find.byKey(const ValueKey('effect-choice')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('effect-choice')));
      await t.pumpAndSettle();
    }

    testWidgets('lists every effect with a line saying what it does', (
      t,
    ) async {
      await composer(t, const TextLayout('WRAP UP', effect: 'static'));
      await openEffects(t);
      for (final option in effectChoices) {
        expect(find.text(option.label), findsWidgets, reason: option.label);
        expect(find.text(option.hint!), findsOne, reason: option.hint);
      }
      for (final effect in ['pulse', 'slideIn', 'bar', 'screenFlash']) {
        expect(
          effectChoices.firstWhere((o) => o.value == effect).hint,
          contains('steady on the LED sign'),
        );
      }
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-cue-effect-list.png'),
      );
      await t.tap(find.text('Countdown bar (must fit)'));
      await t.pumpAndSettle();
      final edited =
          (t.state(find.byType(TextComposer)) as dynamic).layout as TextLayout;
      expect(edited.effect, 'bar');
      expect(
        find.textContaining('a cue shown until cleared has no bar'),
        findsOne,
      );
    });

    testWidgets('the previews show the chosen effect', (t) async {
      await composer(t, const TextLayout('AMEN', effect: 'pulse'));
      await t.pump(const Duration(milliseconds: 1000));
      expect(opacityOf(t, 'AMEN'), closeTo(.55, .03));
      await t.pumpWidget(const SizedBox());
      await composer(t, const TextLayout('AMEN', effect: 'bar'));
      await t.pump(const Duration(seconds: 2));
      // A sample bar, as the cue has no time of its own yet.
      expect(find.byKey(const ValueKey('stage-cue-bar')), findsOne);
      await t.tap(find.text('LED sign'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(LedMatrix), findsOne);
      expect(t.takeException(), isNull);
    });

    for (final (size, scale) in [
      (const Size(320, 568), 1.6),
      (const Size(1366, 768), 1.0),
      (const Size(1920, 1080), 1.0),
    ]) {
      testWidgets(
        'the effect list fits ${size.width.round()}×${size.height.round()} at text scale $scale',
        (t) async {
          await composer(
            t,
            const TextLayout('AMEN', effect: 'screenFlash'),
            size: size,
            textScale: scale,
          );
          await t.ensureVisible(find.byKey(const ValueKey('effect-choice')));
          await t.pump();
          expect(t.takeException(), isNull);
          await openEffects(t);
          for (final option in effectChoices) {
            await t.ensureVisible(find.text(option.hint!));
            await t.pump();
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  });

  group('Goldens', () {
    testWidgets('a stage screen mid-pulse', (t) async {
      await stage(t, cue('pulse', color: '#ff4d4d'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-pulse.png'),
      );
    });

    testWidgets('a countdown bar under an amber cue', (t) async {
      await stage(
        t,
        cue(
          'bar',
          color: '#ffa833',
          more: {'cueTotalMs': 10000, 'cueLeftMs': 6500},
        ),
      );
      await t.pump();
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-bar-1080.png'),
      );
    });

    testWidgets('the whole-screen flash', (t) async {
      await stage(t, cue('screenFlash', color: '#ffa833'));
      await t.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-screen-flash.png'),
      );
    });
  });
}
