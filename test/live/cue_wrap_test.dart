import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_screen_controls.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

Json roundTrip(TextLayout l) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(l.toJson())));

/// The cue editor, with the preview switch when [stageFirst] is given.
Future<void> composer(
  WidgetTester t,
  TextLayout initial, {
  bool? stageFirst,
  Size size = const Size(430, 1000),
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
          stagePreviewFirst: stageFirst,
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

TextLayout edited(WidgetTester t) =>
    (t.state(find.byType(TextComposer)) as dynamic).layout as TextLayout;

Future<void> choose(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(
      of: find.byKey(const ValueKey('cue-preview-kind')),
      matching: find.text(label),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

/// A stage screen showing [data].
Future<void> stage(
  WidgetTester t,
  Json data, {
  Size size = const Size(1920, 1080),
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

Json cue(String text, {String effect = 'static', Json? more}) => {
  'phase': 'active',
  'stageSharing': true,
  'displayText': text,
  'effect': effect,
  'speed': 12,
  'displayIsTimer': false,
  'outputMode': 'Cue',
  'bold': true,
  'screenWrap': true,
  ...?more,
};

const banner = <String, dynamic>{
  'cuePosition': 'bottom',
  'underText': '12:34',
  'underMode': 'Countdown',
  'cueColor': '#ffc247',
};

final wrapped = find.byKey(const ValueKey('stage-wrapped'));

/// The wrapped text's font size and how many lines it is drawn on.
(double, int) wrappedLines(WidgetTester t) {
  final text = t.widget<Text>(wrapped);
  final size = text.style!.fontSize!;
  final height = t.getSize(wrapped).height;
  return (size, (height / (size * 1.1)).round());
}

void main() {
  setUpAll(loadAppFonts);

  group('Wrap long text, in files', () {
    test('is off until chosen and then left out of files', () {
      const plain = TextLayout('WRAP UP');
      expect(plain.screenWrap, isFalse);
      expect(plain.toJson().containsKey('screenWrap'), isFalse);
      expect(
        roundTrip(const TextLayout('WRAP UP', screenWrap: false)),
        roundTrip(plain),
      );
    });

    test('round-trips once chosen', () {
      const on = TextLayout('PLEASE COME FORWARD', screenWrap: true);
      expect(roundTrip(on), containsPair('screenWrap', true));
      final back = TextLayout.fromJson(roundTrip(on));
      expect(back.screenWrap, isTrue);
      expect(roundTrip(back), roundTrip(on));
      expect(styleSummary(on), contains('wrapped on screens'));
    });

    test('a cue from an earlier version loads unwrapped', () {
      final old = TextLayout.fromJson(roundTrip(const TextLayout('MIC LOW')));
      expect(old.screenWrap, isFalse);
    });

    test('accepts only true or false', () {
      for (final bad in ['yes', 1, 'true']) {
        expect(
          () => TextLayout.fromJson({
            ...roundTrip(const TextLayout('GO')),
            'screenWrap': bad,
          }),
          throwsA(anything),
          reason: '$bad',
        );
      }
    });
  });

  group('Sending a wrapped cue', () {
    Future<AppController> running() async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act(
        'load',
        value: Timeline('Service', const [
          Segment('Talk', 5),
        ], DisplaySettings()),
      );
      await c.act('start');
      return c;
    }

    test('adds one field beside those older screens read', () async {
      final c = await running();
      addTearDown(c.dispose);
      await c.act('cue', value: const TextLayout('WRAP UP'));
      expect(c.pairedSnapshot(false).containsKey('screenWrap'), isFalse);
      await c.act(
        'cue',
        value: const TextLayout(
          'PLEASE COME FORWARD FOR PRAYER',
          screenWrap: true,
          screenPosition: 'top',
        ),
      );
      for (final s in [c.pairedSnapshot(false), c.stageWindowSnapshot()]) {
        expect(s['screenWrap'], true);
        // Older screens still find the cue scrolling as before.
        expect(s['effect'], 'scroll');
        expect(s['displayText'], 'PLEASE COME FORWARD FOR PRAYER');
        expect(stageWrapsText(stageBannerText(s)), isTrue);
        // The countdown under the banner is never wrapped.
        expect(stageUnderBanner(s).containsKey('screenWrap'), isFalse);
      }
      // The LED sign is sent the same cue.
      expect(c.state.session.intended(c.now)!.effect, 'scroll');
    });

    test('applies to cues, not the countdown or clock', () {
      expect(stageWrapsText(cue('GO')), isTrue);
      expect(stageWrapsText(cue('GO', effect: 'scroll')), isTrue);
      expect(stageWrapsText(cue('GO', effect: 'flash')), isTrue);
      expect(stageWrapsText({...cue('GO'), 'screenWrap': null}), isFalse);
      expect(stageWrapsText({...cue('12:00'), 'displayIsTimer': true}), false);
      expect(stageWrapsText({...cue('12:00'), 'outputMode': 'Clock'}), false);
    });

    test('a web screen is told to wrap, full screen or in a banner', () {
      const settings = WebStageSettings(orderCode: '1234', localName: 'church');
      Json view(Json data) => viewFor(WebRole.stage, data, settings);
      final full = view(cue('PLEASE COME FORWARD', effect: 'scroll'));
      expect(full['wrap'], true);
      expect(full['effect'], 'scroll');
      expect(
        view({...cue('GO'), 'screenWrap': false}).containsKey('wrap'),
        false,
      );
      final band = view({...cue('PLEASE COME FORWARD'), ...banner});
      expect(band.containsKey('wrap'), isFalse);
      expect((band['banner'] as Map)['wrap'], true);
      expect(
        (view({...cue('GO'), ...banner, 'screenWrap': null})['banner'] as Map)
            .containsKey('wrap'),
        isFalse,
      );
      // The page wraps the text itself, falling back to scrolling.
      expect(webStagePage, contains('function wrapSize'));
      expect(webStagePage, contains('wrapSize(text, 3,'));
      expect(webStagePage, contains('wrapSize(label, 2,'));
      expect(webStagePage, isNot(contains('innerHTML')));
    });
  });

  group('A stage screen', () {
    testWidgets('wraps a long cue onto up to 3 large lines', (t) async {
      await stage(t, cue('PLEASE MAKE YOUR WAY TO THE FRONT FOR PRAYER'));
      expect(t.takeException(), isNull);
      expect(wrapped, findsOne);
      final (size, lines) = wrappedLines(t);
      expect(lines, inInclusiveRange(2, 3));
      // Far larger than the one shrunken line it used to be.
      expect(size, greaterThan(180));
      final box = t.getRect(wrapped);
      expect(box.center.dx, closeTo(960, 1));
      expect(box.center.dy, closeTo(540, 1));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(1920));
    });

    testWidgets('holds a wrapped scrolling cue still', (t) async {
      await stage(t, cue('PLEASE COME FORWARD', effect: 'scroll'));
      expect(wrapped, findsOne);
      final before = t.getRect(wrapped);
      await t.pump(const Duration(seconds: 1));
      expect(t.getRect(wrapped), before);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('keeps a short cue as large as before', (t) async {
      await stage(t, cue('AMEN'));
      final (size, lines) = wrappedLines(t);
      expect(lines, 1);
      expect(size, greaterThan(400));
    });

    testWidgets('wraps onto at most 2 lines in a banner', (t) async {
      await stage(t, {
        ...cue('PLEASE MAKE YOUR WAY TO THE FRONT NOW'),
        ...banner,
      });
      expect(t.takeException(), isNull);
      expect(wrapped, findsOne);
      final (size, lines) = wrappedLines(t);
      expect(lines, inInclusiveRange(1, 2));
      final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
      final text = t.getRect(wrapped);
      expect(text.top, greaterThanOrEqualTo(band.top));
      expect(text.bottom, lessThanOrEqualTo(band.bottom));
      expect(size, greaterThan(40));
      // The countdown is still there.
      expect(find.byKey(const ValueKey('stage-time-width')), findsOne);
    });

    testWidgets('scrolls text too long to wrap at a readable size', (t) async {
      final long = List.filled(16, 'PLEASE').join(' ');
      await stage(t, cue(long));
      expect(wrapped, findsNothing);
      final words = find.text(long);
      expect(words, findsOne);
      final before = t.getRect(words).left;
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.getRect(words).left, lessThan(before));
      expect(t.takeException(), isNull);
    });

    test('the size is never below the minimum', () {
      const style = TextStyle(fontSize: 900, fontWeight: FontWeight.bold);
      final size = stageWrapSize(
        'PLEASE COME FORWARD',
        style,
        width: 1800,
        height: 1000,
        lines: 3,
        min: 120,
        max: 900,
      );
      expect(size, isNotNull);
      expect(size, greaterThanOrEqualTo(120));
      expect(
        stageWrapSize(
          List.filled(30, 'WORD').join(' '),
          style,
          width: 1800,
          height: 1000,
          lines: 3,
          min: 120,
          max: 900,
        ),
        isNull,
      );
      // A word too wide for a line of its own does not fit.
      expect(
        stageWrapSize(
          'SUPERCALIFRAGILISTIC',
          style,
          width: 400,
          height: 1000,
          lines: 3,
          min: 120,
          max: 900,
        ),
        isNull,
      );
    });

    testWidgets('a two-line wrapped cue at full HD', (t) async {
      await stage(t, cue('WELCOME EVERYONE'));
      expect(wrappedLines(t).$2, 2);
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-wrapped-1080.png'),
      );
    });

    testWidgets('a wrapped cue on a phone', (t) async {
      await stage(
        t,
        cue('THE CAR PARK GATE CLOSES IN TEN MINUTES'),
        size: const Size(844, 390),
      );
      expect(t.takeException(), isNull);
      expect(wrapped, findsOne);
      expect(wrappedLines(t).$2, inInclusiveRange(2, 3));
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-wrapped-phone.png'),
      );
    });
  });

  group('Wrapped with a newer effect', () {
    const long = 'PLEASE MAKE YOUR WAY TO THE FRONT FOR PRAYER';
    Json effectCue(String effect, {Json? more}) => {
      ...cue(long, more: more),
      ...stageEffectFields(
        TextLayout(long, effect: effect),
        time: (total: 60000, left: 30000),
      ),
    };
    Future<void> show(WidgetTester t, Json data) async {
      setScreen(t, const Size(1920, 1080));
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

    Finder around(String key) =>
        find.ancestor(of: wrapped, matching: find.byKey(ValueKey(key)));

    test('wraps every newer effect, and leaves the countdown alone', () {
      for (final effect in screenEffects) {
        final data = effectCue(effect);
        expect(data['effect'], 'static', reason: effect);
        expect(stageWrapsText(data), isTrue, reason: effect);
      }
    });

    testWidgets('pulse dims and brightens the wrapped block', (t) async {
      await show(t, effectCue('pulse'));
      expect(wrapped, findsOne);
      expect(around('stage-cue-opacity'), findsOne);
      double opacity() =>
          t.widget<Opacity>(around('stage-cue-opacity')).opacity;
      final first = opacity();
      await t.pump(const Duration(milliseconds: 1000));
      expect(opacity(), isNot(first));
      expect(wrappedLines(t).$2, inInclusiveRange(2, 3));
    });

    testWidgets('flash then hold flashes the block, then holds', (t) async {
      await show(t, effectCue('flashHold'));
      await t.pump(const Duration(milliseconds: 600));
      expect(t.widget<Opacity>(around('stage-cue-opacity')).opacity, 0);
      await t.pump(const Duration(milliseconds: 3000));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<Opacity>(around('stage-cue-opacity')).opacity, 1);
      expect(wrapped, findsOne);
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('slide in moves the whole block up into place', (t) async {
      await show(t, effectCue('slideIn'));
      await t.pump(const Duration(milliseconds: 100));
      final moving = t.getRect(wrapped);
      expect(around('stage-cue-slide'), findsOne);
      await t.pump(const Duration(milliseconds: 400));
      final still = t.getRect(wrapped);
      expect(moving.top, greaterThan(still.top));
      expect(moving.height, closeTo(still.height, .01));
      expect(still.center.dy, closeTo(540, 2));
    });

    testWidgets('the countdown bar sits under the wrapped block', (t) async {
      await show(t, effectCue('bar'));
      await t.pump(const Duration(milliseconds: 100));
      final bar = t.getRect(find.byKey(const ValueKey('stage-cue-bar')));
      final text = t.getRect(wrapped);
      expect(text.bottom, lessThanOrEqualTo(bar.top));
      expect(wrappedLines(t).$2, inInclusiveRange(2, 3));
      expect(t.takeException(), isNull);
    });

    testWidgets('screen flash lights the screen behind the block', (t) async {
      await show(t, effectCue('screenFlash'));
      await t.pump(const Duration(milliseconds: 100));
      expect(wrapped, findsOne);
      Color? flash() =>
          (t
                      .widget<DecoratedBox>(
                        find.byKey(const ValueKey('stage-screen-flash')).first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      // A tint behind the block; the cue keeps its own colour.
      expect(flash(), isNot(Colors.transparent));
      expect(t.widget<Text>(wrapped).style!.color, Colors.white);
      await t.pump(const Duration(milliseconds: 700));
      expect(flash(), Colors.transparent);
      expect(wrappedLines(t).$2, inInclusiveRange(2, 3));
    });

    testWidgets('keeps to 2 lines in a banner with each effect', (t) async {
      for (final effect in screenEffects) {
        await show(t, {...effectCue(effect), ...banner});
        await t.pump(const Duration(milliseconds: 100));
        await t.pump(const Duration(seconds: 4));
        expect(wrapped, findsOne, reason: effect);
        expect(wrappedLines(t).$2, inInclusiveRange(1, 2), reason: effect);
        final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
        final text = t.getRect(wrapped);
        expect(text.top, greaterThanOrEqualTo(band.top), reason: effect);
        expect(text.bottom, lessThanOrEqualTo(band.bottom), reason: effect);
        expect(t.takeException(), isNull, reason: effect);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('too long to wrap, it still scrolls', (t) async {
      final words = List.filled(16, 'PLEASE').join(' ');
      for (final effect in ['pulse', 'slideIn', 'bar']) {
        await show(t, {...effectCue(effect), 'displayText': words});
        await t.pump(const Duration(milliseconds: 100));
        expect(wrapped, findsNothing, reason: effect);
        final before = t.getRect(find.text(words)).left;
        await t.pump(const Duration(milliseconds: 500));
        expect(t.getRect(find.text(words)).left, lessThan(before));
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a wrapped cue sliding in, at full HD', (t) async {
      await show(t, effectCue('slideIn', more: {'cueColor': '#ffc247'}));
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-wrapped-slide-in-1080.png'),
      );
    });

    testWidgets('a wrapped cue with a countdown bar, at full HD', (t) async {
      await show(t, effectCue('bar', more: {'cueColor': '#4ade80'}));
      await t.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-cue-wrapped-bar-1080.png'),
      );
    });

    test('the web page wraps the newer effects as one block', () {
      const settings = WebStageSettings(orderCode: '1234', localName: 'church');
      for (final effect in screenEffects) {
        final full = viewFor(WebRole.stage, effectCue(effect), settings);
        expect(full['wrap'], true, reason: effect);
        expect(full['screenEffect'], effect, reason: effect);
        final band =
            viewFor(WebRole.stage, {
                  ...effectCue(effect),
                  ...banner,
                }, settings)['banner']
                as Map;
        expect(band['wrap'], true, reason: effect);
        expect(band['screenEffect'], effect, reason: effect);
      }
      // Clear of the bar; the fallback drops the effect and bar.
      expect(webStagePage, contains("fx === 'bar' ? h * 0.74"));
      expect(webStagePage, contains('scrollsInstead'));
    });
  });

  group('The cue editor', () {
    final led = find.byKey(const ValueKey('on-led-sign'));
    final screens = find.byKey(const ValueKey('on-screens'));

    testWidgets('shows the settings for the display the preview shows', (
      t,
    ) async {
      await composer(t, const TextLayout('WRAP UP'), stageFirst: true);
      expect(screens, findsOne);
      expect(led, findsNothing);
      expect(find.text('Tall · 14 px'), findsNothing);
      expect(
        find.text(
          'Showing settings for the stage screen. Switch to LED sign to change how the sign shows it.',
        ),
        findsOne,
      );
      void shared() {
        for (final label in ['Bold', 'Italic']) {
          expect(find.widgetWithText(FilterChip, label), findsOne);
        }
        expect(find.text('Effect'), findsOne);
        expect(find.text('Display text'), findsOne);
      }

      shared();
      await choose(t, 'LED sign');
      expect(led, findsOne);
      expect(screens, findsNothing);
      expect(find.text('ON THE LED SIGN'), findsOne);
      for (final label in [
        'Display font',
        'Tall · 14 px',
        'Alignment (text that fits)',
        'Speed on the LED sign: 12 pixels / second',
      ]) {
        expect(
          find.descendant(of: led, matching: find.text(label)),
          findsOne,
          reason: label,
        );
      }
      expect(
        find.textContaining('Showing settings for the LED sign'),
        findsOne,
      );
      shared();
      // Hidden settings are kept.
      await t.tap(find.text('Tall · 14 px'));
      await t.pump();
      await choose(t, 'Stage screen');
      expect(edited(t).height, 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('starts on the LED sign with the sign', (t) async {
      await composer(t, const TextLayout('WRAP UP'), stageFirst: false);
      expect(led, findsOne);
      expect(screens, findsNothing);
    });

    testWidgets('other text editors keep their layout', (t) async {
      await composer(t, const TextLayout('THANK YOU'));
      expect(led, findsNothing);
      expect(screens, findsOne);
      expect(find.text('Tall · 14 px'), findsOne);
      expect(find.text('Display font'), findsOne);
      expect(find.byKey(const ValueKey('cue-preview-note')), findsNothing);
    });

    testWidgets('wraps long text, with a warning when it is long', (t) async {
      await composer(t, const TextLayout('WRAP UP'), stageFirst: true);
      final warning = find.byKey(const ValueKey('screen-wrap-warning'));
      expect(edited(t).screenWrap, isFalse);
      await t.ensureVisible(find.byKey(const ValueKey('screen-wrap')));
      await t.tap(find.byKey(const ValueKey('screen-wrap')));
      await t.pump();
      expect(edited(t).screenWrap, isTrue);
      expect(warning, findsNothing);
      // The preview wraps it too.
      expect(
        t.widget<StageSurface>(find.byType(StageSurface)).data['screenWrap'],
        true,
      );
      await t.enterText(
        find.byType(TextField).first,
        'PLEASE MOVE YOUR CARS FROM THE FRONT OF THE BUILDING STRAIGHT AWAY',
      );
      await t.pump();
      expect(warning, findsOne);
      expect(
        find.text(
          'Long text is hard to read from a distance. Keep it shorter, or let it scroll instead.',
        ),
        findsOne,
      );
      // A warning only: it can still be saved.
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save cue'))
            .onPressed,
        isNotNull,
      );
      await t.ensureVisible(find.byKey(const ValueKey('screen-wrap')));
      await t.tap(find.byKey(const ValueKey('screen-wrap')));
      await t.pump();
      expect(warning, findsNothing);
      expect(edited(t).toJson().containsKey('screenWrap'), isFalse);
    });

    for (final (size, scale) in [
      (const Size(320, 568), 1.6),
      (const Size(1366, 768), 1.0),
      (const Size(1920, 1080), 1.0),
    ]) {
      testWidgets(
        'fits ${size.width.round()}×${size.height.round()} at text scale $scale',
        (t) async {
          await composer(
            t,
            const TextLayout(
              'PLEASE MOVE YOUR CARS FROM THE FRONT OF THE BUILDING STRAIGHT AWAY',
              screenWrap: true,
              screenPosition: 'bottom',
            ),
            stageFirst: true,
            size: size,
            textScale: scale,
          );
          for (final kind in ['LED sign', 'Stage screen']) {
            await t.ensureVisible(
              find.byKey(const ValueKey('cue-preview-kind')),
            );
            await choose(t, kind);
            expect(t.takeException(), isNull, reason: kind);
            final dialog = t.getRect(find.byType(AlertDialog));
            final group = kind == 'LED sign' ? led : screens;
            await t.ensureVisible(group);
            await t.pump();
            final box = t.getRect(group);
            expect(box.left, greaterThanOrEqualTo(dialog.left));
            expect(box.right, lessThanOrEqualTo(dialog.right));
            expect(box.width, lessThanOrEqualTo(520));
            expect(t.takeException(), isNull, reason: kind);
          }
          await t.ensureVisible(
            find.byKey(const ValueKey('screen-wrap-warning')),
          );
          await t.pump();
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets('the stage screen settings on a PC', (t) async {
      await composer(
        t,
        const TextLayout(
          'PLEASE COME FORWARD FOR PRAYER',
          bold: true,
          screenWrap: true,
          screenColor: 'amber',
        ),
        stageFirst: true,
        size: const Size(1366, 768),
      );
      await Scrollable.ensureVisible(t.element(screens));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-cue-editor-stage-settings.png'),
      );
    });

    testWidgets('the LED sign settings on a PC', (t) async {
      await composer(
        t,
        const TextLayout('WRAP UP', bold: true),
        stageFirst: false,
        size: const Size(1366, 768),
      );
      await Scrollable.ensureVisible(t.element(led), alignment: .5);
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      expect(find.byType(ScreenCueControls), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-cue-editor-led-settings.png'),
      );
    });
  });
}
