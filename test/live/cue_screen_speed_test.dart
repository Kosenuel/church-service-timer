import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_screen_controls.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

Json roundTrip(TextLayout l) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(l.toJson())));

Future<void> composer(
  WidgetTester t,
  TextLayout initial, {
  Size size = const Size(430, 1000),
  double textScale = 1,
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
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
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

Future<AppController> running() async {
  final c = AppController(FakePort());
  await c.initialize(startTicker: false);
  // This computer's screen is in Church Auditorium, which shows cues once asked.
  await c.screens.setCues('room', true);
  await c.act(
    'load',
    value: Timeline('Service', const [Segment('Talk', 5)], DisplaySettings()),
  );
  await c.act('start');
  return c;
}

void main() {
  setUpAll(loadAppFonts);

  group('A cue’s speed on screens', () {
    test('follows the LED sign until it is set, and is left out of files', () {
      const cue = TextLayout('WRAP UP', speed: 9);
      expect(cue.screenSpeed, isNull);
      expect(cue.speedOnScreens, 9);
      expect(cue.toJson().containsKey('screenSpeed'), isFalse);
      // Exactly the fields an earlier version wrote, so it still opens there.
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
    });

    test('round-trips once set', () {
      const cue = TextLayout('WRAP UP', speed: 9, screenSpeed: 40);
      final back = TextLayout.fromJson(roundTrip(cue));
      expect(back.speed, 9);
      expect(back.screenSpeed, 40);
      expect(back.speedOnScreens, 40);
      expect(roundTrip(back), roundTrip(cue));
    });

    test('a cue saved by an earlier version loads and follows the sign', () {
      final old = TextLayout.fromJson({
        'text': 'MIC LOW',
        'bold': true,
        'italic': false,
        'effect': 'scroll',
        'align': 'center',
        'speed': 20,
        'height': 1,
        'font': 'i-proton_matrix',
      });
      expect(old.screenSpeed, isNull);
      expect(old.speedOnScreens, 20);
      final settings = DisplaySettings.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(DisplaySettings().toJson())),
        ),
      );
      expect(settings.cues.every((c) => c.screenSpeed == null), isTrue);
    });

    test('is checked like the sign’s speed, up to twice its fastest', () {
      expect(maxScreenSpeed, 48);
      for (final ok in [4, 24, 25, 48]) {
        TextLayout('GO', screenSpeed: ok).validate();
      }
      for (final bad in [3, 0, -1, 49, 200]) {
        expect(
          () => TextLayout('GO', screenSpeed: bad).validate(),
          throwsA(anything),
          reason: '$bad',
        );
        expect(
          () => TextLayout.fromJson({
            ...roundTrip(const TextLayout('GO')),
            'screenSpeed': bad,
          }),
          throwsA(anything),
        );
      }
      expect(
        () => TextLayout.fromJson({
          ...roundTrip(const TextLayout('GO')),
          'screenSpeed': 'fast',
        }),
        throwsA(anything),
      );
      // The sign's own limit is unchanged.
      expect(
        () => const TextLayout('GO', speed: 25).validate(),
        throwsA(anything),
      );
    });
  });

  group('Sending a cue', () {
    test('the snapshot keeps the sign’s speed and adds the screens’', () async {
      final c = await running();
      addTearDown(c.dispose);
      expect(
        await c.act('cue', value: const TextLayout('WRAP UP', speed: 8)),
        true,
      );
      var paired = c.pairedSnapshot(false);
      expect(paired['speed'], 8);
      expect(paired.containsKey('screenSpeed'), isFalse);
      expect(stageScrollSpeed(paired), 8);
      expect(stageScrollSpeed(c.stageWindowSnapshot()), 8);

      expect(
        await c.act(
          'cue',
          value: const TextLayout('WRAP UP', speed: 8, screenSpeed: 44),
        ),
        true,
      );
      paired = c.pairedSnapshot(false);
      // An older paired screen reads only 'speed' and carries on as before.
      expect(paired['speed'], 8);
      expect(paired['screenSpeed'], 44);
      expect(stageScrollSpeed(paired), 44);
      final window = c.stageWindowSnapshot();
      expect(window['speed'], 8);
      expect(stageScrollSpeed(window), 44);
      // The LED sign is still given its own speed.
      expect(c.state.session.intended(c.now)!.speed, 8);
    });

    test('a web screen is given the speed for screens', () {
      const settings = WebStageSettings(orderCode: '1234', localName: 'church');
      Json view(Json extra) => viewFor(WebRole.stage, {
        'phase': 'active',
        'stageSharing': true,
        'displayText': 'WRAP UP',
        'effect': 'scroll',
        ...extra,
      }, settings);
      expect(view({'speed': 8})['speed'], 8);
      expect(view({'speed': 8, 'screenSpeed': 44})['speed'], 44);
      expect(view({})['speed'], 12);
      expect(view({'speed': 8, 'screenSpeed': 4000})['speed'], 60);
    });
  });

  testWidgets('A stage screen scrolls faster with a higher screen speed', (
    t,
  ) async {
    setScreen(t, const Size(1280, 600));
    Future<double> travelled(Json speeds) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: StageMessage(
              // A new key, so each run starts from the right-hand edge.
              key: UniqueKey(),
              data: {'displayText': 'WRAP UP', 'effect': 'scroll', ...speeds},
              stale: false,
              fullscreen: true,
            ),
          ),
        ),
      );
      await t.pump();
      final start = t.getRect(find.text('WRAP UP')).left;
      await t.pump(const Duration(milliseconds: 500));
      return start - t.getRect(find.text('WRAP UP')).left;
    }

    final sign = await travelled({'speed': 12});
    final same = await travelled({'speed': 12, 'screenSpeed': 12});
    final fast = await travelled({'speed': 12, 'screenSpeed': 48});
    final slow = await travelled({'speed': 24, 'screenSpeed': 6});
    expect(sign, greaterThan(0));
    expect(same, closeTo(sign, .5));
    expect(fast, closeTo(sign * 4, 2));
    expect(slow, closeTo(sign / 2, 1));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  group('The cue editor', () {
    testWidgets('has a speed for the sign and a speed for screens', (t) async {
      await composer(t, const TextLayout('WRAP UP', speed: 10));
      expect(find.text('Speed on the LED sign: 10 pixels / second'), findsOne);
      expect(find.text('Speed on screens: same as the LED sign'), findsOne);
      expect(find.byKey(const ValueKey('screen-speed-same')), findsNothing);
      Slider slider(String key) => t.widget<Slider>(find.byKey(ValueKey(key)));
      expect(slider('led-speed').max, 24);
      expect(slider('screen-speed').max, 48);
      expect(slider('screen-speed').value, 10);

      // While it follows the sign, it moves with the sign's slider.
      slider('led-speed').onChanged!(16);
      await t.pump();
      expect(slider('screen-speed').value, 16);
      expect(find.text('Speed on screens: same as the LED sign'), findsOne);

      slider('screen-speed').onChanged!(40);
      await t.pump();
      expect(find.text('Speed on screens: 40'), findsOne);
      expect(find.text('Speed on the LED sign: 16 pixels / second'), findsOne);
      final state = t.state(find.byType(TextComposer)) as dynamic;
      expect((state.layout as TextLayout).speed, 16);
      expect((state.layout as TextLayout).screenSpeed, 40);

      await t.ensureVisible(find.byKey(const ValueKey('screen-speed-same')));
      await t.tap(find.byKey(const ValueKey('screen-speed-same')));
      await t.pump();
      expect(find.text('Speed on screens: same as the LED sign'), findsOne);
      expect((state.layout as TextLayout).screenSpeed, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('shows a saved screen speed, and only for scrolling text', (
      t,
    ) async {
      await composer(
        t,
        const TextLayout('WRAP UP', speed: 10, screenSpeed: 30),
      );
      expect(find.text('Speed on screens: 30'), findsOne);
      expect(find.byKey(const ValueKey('screen-speed-same')), findsOne);
      await t.pumpWidget(const SizedBox());
      await composer(
        t,
        const TextLayout('AMEN', effect: 'static', screenSpeed: 30),
      );
      expect(find.byType(ScreenSpeedControl), findsNothing);
      expect(find.byKey(const ValueKey('led-speed')), findsNothing);
      final state = t.state(find.byType(TextComposer)) as dynamic;
      expect((state.layout as TextLayout).screenSpeed, isNull);
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
            const TextLayout('PLEASE WRAP UP NOW', screenSpeed: 48),
            size: size,
            textScale: scale,
          );
          expect(t.takeException(), isNull);
          await t.ensureVisible(
            find.byKey(const ValueKey('screen-speed-same')),
          );
          await t.pump();
          expect(t.takeException(), isNull);
          final dialog = t.getRect(find.byType(AlertDialog));
          for (final key in [
            'led-speed',
            'screen-speed',
            'screen-speed-same',
          ]) {
            final box = t.getRect(find.byKey(ValueKey(key)));
            expect(box.left, greaterThanOrEqualTo(dialog.left), reason: key);
            expect(box.right, lessThanOrEqualTo(dialog.right), reason: key);
          }
          // A dialog, not a column stretched across a wide window.
          expect(
            t.getSize(find.byKey(const ValueKey('screen-speed'))).width,
            lessThanOrEqualTo(520),
          );
        },
      );
    }
  });
}
