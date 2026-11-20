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
import 'desktop_layout_test.dart' show DesktopFakePort;

Json roundTrip(TextLayout l) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(l.toJson())));

Future<void> composer(
  WidgetTester t,
  TextLayout initial, {
  Size size = const Size(430, 1000),
  double textScale = 1,
  String theme = 'midnight_lime',
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(theme, size: size),
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
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

TextLayout edited(WidgetTester t) =>
    (t.state(find.byType(TextComposer)) as dynamic).layout as TextLayout;

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

double luminance(int rgb) => Color(0xff000000 | rgb).computeLuminance();

void main() {
  setUpAll(loadAppFonts);

  group('A cue’s colour and position on screens', () {
    test('are white and full screen until chosen, and left out of files', () {
      const cue = TextLayout('WRAP UP');
      expect(cue.screenColor, 'white');
      expect(cue.screenPosition, 'full');
      expect(cue.bannerOnScreens, isFalse);
      expect(cue.toJson().keys.toSet(), {
        'text',
        'bold',
        'italic',
        'effect',
        'align',
        'speed',
        'height',
        'font',
      });
      // Chosen and then put back, the file is as it was.
      expect(
        roundTrip(const TextLayout('WRAP UP', screenColor: 'white')),
        roundTrip(cue),
      );
    });

    test('round-trip once chosen', () {
      for (final color in screenColorNames) {
        for (final position in screenPositions) {
          final cue = TextLayout(
            'WRAP UP',
            screenColor: color,
            screenPosition: position,
          );
          final back = TextLayout.fromJson(roundTrip(cue));
          expect(back.screenColor, color);
          expect(back.screenPosition, position);
          expect(back.bannerOnScreens, position != 'full');
          expect(roundTrip(back), roundTrip(cue));
        }
      }
      expect(
        roundTrip(
          const TextLayout(
            'GO',
            screenColor: 'amber',
            screenPosition: 'bottom',
          ),
        ),
        containsPair('screenColor', 'amber'),
      );
    });

    test('a cue saved by an earlier version loads as it looked', () {
      final old = TextLayout.fromJson({
        'text': 'MIC LOW',
        'bold': true,
        'italic': false,
        'effect': 'flash',
        'align': 'center',
        'speed': 12,
        'height': 1,
        'font': 'i-proton_matrix',
      });
      expect(old.screenColor, 'white');
      expect(old.screenPosition, 'full');
    });

    test('accept only the fixed choices', () {
      for (final bad in ['blue', '#ff0000', '', 'Amber']) {
        expect(
          () => TextLayout('GO', screenColor: bad).validate(),
          throwsA(anything),
        );
        expect(
          () => TextLayout.fromJson({
            ...roundTrip(const TextLayout('GO')),
            'screenColor': bad,
          }),
          throwsA(anything),
        );
      }
      for (final bad in ['middle', 'left', '', 'Top']) {
        expect(
          () => TextLayout('GO', screenPosition: bad).validate(),
          throwsA(anything),
        );
      }
      expect(
        () => TextLayout.fromJson({
          ...roundTrip(const TextLayout('GO')),
          'screenPosition': 3,
        }),
        throwsA(anything),
      );
    });

    test('the colours read on black and are far apart', () {
      double contrastOnBlack(int rgb) => (luminance(rgb) + .05) / .05;
      final all = {
        ...screenCueColors,
        for (final p in appPalettes) 'accent ${p.id}': stageAccentRgb(p.id),
      };
      for (final e in all.entries) {
        expect(contrastOnBlack(e.value), greaterThan(6), reason: e.key);
      }
      // The four fixed colours differ clearly in hue or brightness.
      final fixed = screenCueColors.values.toList();
      for (var i = 0; i < fixed.length; i++) {
        for (var j = i + 1; j < fixed.length; j++) {
          final a = Color(0xff000000 | fixed[i]),
              b = Color(0xff000000 | fixed[j]);
          final distance =
              (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
          expect(distance, greaterThan(.4), reason: '$i $j');
        }
      }
      expect(stageColorHex(0x4ade80), '#4ade80');
      expect(stageColorHex(0x00000a), '#00000a');
      expect(stageCueRgb({'cueColor': '#FFC247'}), 0xffc247);
      for (final bad in [null, 'red', '#fff', '#ggggggg', 7, 'url(x)']) {
        expect(stageCueRgb({'cueColor': bad}), isNull);
      }
    });
  });

  group('Sending a cue', () {
    test('a plain cue leaves the snapshot as it was', () async {
      final c = await running();
      addTearDown(c.dispose);
      await c.act('cue', value: const TextLayout('WRAP UP'));
      final paired = c.pairedSnapshot(false);
      for (final key in ['cueColor', 'cuePosition', 'underText', 'underMode']) {
        expect(paired.containsKey(key), isFalse, reason: key);
      }
      expect(stageBannerPosition(paired), isNull);
    });

    test(
      'colour and banner travel beside the fields older screens read',
      () async {
        final c = await running();
        addTearDown(c.dispose);
        const cue = TextLayout(
          'AMEN',
          bold: true,
          effect: 'flash',
          screenColor: 'amber',
          screenPosition: 'bottom',
        );
        expect(await c.act('cue', value: cue), true);
        for (final snapshot in [
          c.pairedSnapshot(false),
          c.stageWindowSnapshot(),
        ]) {
          // What an older paired screen reads: the cue, full screen, white.
          expect(snapshot['displayText'], 'AMEN');
          expect(snapshot['effect'], 'flash');
          expect(snapshot['bold'], true);
          expect(snapshot['displayIsTimer'], false);
          expect(snapshot['cueColor'], '#ffc247');
          expect(snapshot['cuePosition'], 'bottom');
          expect(snapshot['underText'], '05:00');
          expect(snapshot['underMode'], 'Countdown');
          expect(stageBannerPosition(snapshot), 'bottom');
          final under = stageUnderBanner(snapshot);
          expect(under['displayText'], '05:00');
          expect(under['displayIsTimer'], true);
          expect(under['effect'], 'static');
          expect(under.containsKey('cueColor'), isFalse);
          final text = stageBannerText(snapshot);
          expect(text['displayText'], 'AMEN');
          expect(text['cueColor'], '#ffc247');
        }
        // The LED sign is sent the same cue as ever.
        final sign = c.state.session.intended(c.now)!;
        expect(sign.text, 'AMEN');
        expect(sign.effect, 'flash');
      },
    );

    test(
      'a banner sits over the clock, and fills the screen after the end',
      () async {
        final c = await running();
        addTearDown(c.dispose);
        await c.act('clock');
        expect(c.state.session.showClock, isTrue);
        const cue = TextLayout(
          'MIC LOW',
          screenPosition: 'top',
          screenColor: 'red',
        );
        await c.act('cue', value: cue);
        var snapshot = c.pairedSnapshot(false);
        expect(snapshot['cuePosition'], 'top');
        expect(snapshot['underMode'], 'Clock');
        expect(snapshot['underText'], stageClockText(c.now.wall, '24h'));
        expect(stageUnderBanner(snapshot)['displayIsTimer'], false);
        await c.act('end');
        await c.act('cue', value: cue);
        snapshot = c.pairedSnapshot(false);
        expect(snapshot['displayText'], 'MIC LOW');
        expect(snapshot['cueColor'], '#ff4d4d');
        expect(snapshot.containsKey('cuePosition'), isFalse);
        expect(stageBannerPosition(snapshot), isNull);
      },
    );

    test(
      'the theme colour is the host’s accent, made readable on black',
      () async {
        final c = await running();
        addTearDown(c.dispose);
        await c.act(
          'cue',
          value: const TextLayout('GO', screenColor: 'accent'),
        );
        expect(
          c.pairedSnapshot(false)['cueColor'],
          stageColorHex(stageAccentRgb(c.state.themeId)),
        );
        // A bright accent is used as it is; a dark one is lightened.
        expect(
          stageAccentRgb('midnight_lime'),
          paletteFor('midnight_lime').accent.toARGB32() & 0xffffff,
        );
        final meadow = paletteFor('meadow').accent;
        expect(
          luminance(stageAccentRgb('meadow')),
          greaterThan(meadow.computeLuminance()),
        );
      },
    );

    test('a web screen is given the countdown and the banner', () {
      const settings = WebStageSettings(orderCode: '1234', localName: 'church');
      Json view(Json extra) => viewFor(WebRole.stage, {
        'phase': 'active',
        'stageSharing': true,
        'displayText': 'WRAP UP',
        'effect': 'scroll',
        'bold': true,
        'speed': 8,
        'screenSpeed': 30,
        'outputMode': 'Cue',
        'displayIsTimer': false,
        ...extra,
      }, settings);
      final plain = view({});
      expect(plain.containsKey('banner'), isFalse);
      expect(plain.containsKey('color'), isFalse);
      expect(plain['displayText'], 'WRAP UP');
      final red = view({'cueColor': '#ff4d4d'});
      expect(red['color'], '#ff4d4d');
      expect(red['displayText'], 'WRAP UP');
      // Nothing but a checked colour reaches the page.
      expect(view({'cueColor': 'red;x'}).containsKey('color'), isFalse);
      final banner = view({
        'cueColor': '#ffc247',
        'cuePosition': 'bottom',
        'underText': '04:10',
        'underMode': 'Countdown',
      });
      expect(banner['displayText'], '04:10');
      expect(banner['effect'], 'static');
      expect(banner['bold'], false);
      expect(banner['ticking'], true);
      expect(banner.containsKey('color'), isFalse);
      expect(banner['speed'], 30);
      expect(banner['banner'], {
        'text': 'WRAP UP',
        'position': 'bottom',
        'color': '#ffc247',
        'bold': true,
        'italic': false,
        'effect': 'scroll',
      });
      expect(
        view({
          'cuePosition': 'side',
          'underText': '04:10',
        }).containsKey('banner'),
        isFalse,
      );
      // The page draws the band and builds it with textContent only.
      expect(webStagePage, contains('id="stageBand"'));
      expect(webStagePage, contains('function renderBand'));
      expect(webStagePage, isNot(contains('innerHTML')));
    });
  });

  group('The cue editor', () {
    testWidgets('has the choices for screens under one heading', (t) async {
      await composer(t, const TextLayout('WRAP UP'));
      expect(find.text('ON SCREENS'), findsOne);
      for (final label in [
        'White',
        'Amber',
        'Red',
        'Green',
        'Theme colour',
        'Full screen',
        'Banner at the top',
        'Banner at the bottom',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOne, reason: label);
      }
      ChoiceChip chip(String key) =>
          t.widget<ChoiceChip>(find.byKey(ValueKey(key)));
      expect(chip('screen-color-white').selected, isTrue);
      expect(chip('screen-position-full').selected, isTrue);
      expect(find.text('The cue takes the place of the countdown.'), findsOne);

      await t.ensureVisible(find.byKey(const ValueKey('screen-color-amber')));
      await t.tap(find.byKey(const ValueKey('screen-color-amber')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('screen-position-top')));
      await t.tap(find.byKey(const ValueKey('screen-position-top')));
      await t.pump();
      expect(chip('screen-color-amber').selected, isTrue);
      expect(chip('screen-color-white').selected, isFalse);
      expect(chip('screen-position-top').selected, isTrue);
      expect(find.textContaining('the countdown stays in view'), findsOne);
      expect(edited(t).screenColor, 'amber');
      expect(edited(t).screenPosition, 'top');
      // The LED sign's own settings are untouched.
      expect(
        roundTrip(edited(t))
          ..remove('screenColor')
          ..remove('screenPosition'),
        roundTrip(const TextLayout('WRAP UP')),
      );
      // The speed on screens lives under the same heading.
      expect(
        find.descendant(
          of: find.byType(ScreenCueControls),
          matching: find.byType(ScreenSpeedControl),
        ),
        findsOne,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('keeps a saved colour and position, with no colour picker', (
      t,
    ) async {
      await composer(
        t,
        const TextLayout(
          'AMEN',
          effect: 'static',
          screenColor: 'green',
          screenPosition: 'bottom',
        ),
      );
      ChoiceChip chip(String key) =>
          t.widget<ChoiceChip>(find.byKey(ValueKey(key)));
      expect(chip('screen-color-green').selected, isTrue);
      expect(chip('screen-position-bottom').selected, isTrue);
      expect(find.byType(ScreenSpeedControl), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ScreenCueControls),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      expect(edited(t).screenColor, 'green');
      expect(edited(t).screenPosition, 'bottom');
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
              'PLEASE WRAP UP NOW',
              screenSpeed: 48,
              screenColor: 'accent',
              screenPosition: 'bottom',
            ),
            size: size,
            textScale: scale,
          );
          expect(t.takeException(), isNull);
          final dialog = t.getRect(find.byType(AlertDialog));
          for (final chip in find.byType(ChoiceChip).evaluate()) {
            await t.ensureVisible(find.byWidget(chip.widget));
            await t.pump();
            final box = t.getRect(find.byWidget(chip.widget));
            expect(box.left, greaterThanOrEqualTo(dialog.left));
            expect(box.right, lessThanOrEqualTo(dialog.right));
          }
          await t.ensureVisible(
            find.byKey(const ValueKey('screen-speed-same')),
          );
          await t.pump();
          expect(t.takeException(), isNull);
          // A dialog, not a column stretched across a wide window.
          expect(
            t.getSize(find.byKey(const ValueKey('on-screens'))).width,
            lessThanOrEqualTo(520),
          );
        },
      );
    }

    for (final (name, size) in [
      ('cue-editor-screens-phone', const Size(390, 844)),
      ('desktop-cue-editor-screens', const Size(1366, 768)),
    ]) {
      testWidgets('shows the choices for screens ($name)', (t) async {
        await composer(
          t,
          const TextLayout(
            'WRAP UP',
            bold: true,
            screenSpeed: 30,
            screenColor: 'amber',
            screenPosition: 'bottom',
          ),
          size: size,
        );
        // The heading at the top of the dialog's own scrolling area.
        await Scrollable.ensureVisible(
          t.element(find.byKey(const ValueKey('on-screens'))),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/$name.png'),
        );
      });
    }
  });

  test(
    'a PC host sends the same colour and banner to its second screen',
    () async {
      final c = await running(DesktopFakePort());
      addTearDown(c.dispose);
      await c.act(
        'cue',
        value: const TextLayout(
          'WRAP UP',
          screenColor: 'green',
          screenPosition: 'top',
        ),
      );
      final window = c.stageWindowSnapshot();
      expect(window['cueColor'], '#4ade80');
      expect(stageBannerPosition(window), 'top');
    },
  );
}
