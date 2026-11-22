import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_preview.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'desktop_layout_test.dart' show DesktopFakePort, sunday;

/// The Send message composer, the end screen and the zero screen follow
/// the simulator as the cue editor does: a switch over the preview that
/// starts on the display in use.
void main() {
  setUpAll(loadAppFonts);

  const kindSwitch = ValueKey('cue-preview-kind');
  const cueStage = ValueKey('cue-stage-preview');
  const onScreens = ValueKey('on-screens');
  const onLed = ValueKey('on-led-sign');
  final dialogMatrix = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(LedMatrix),
  );

  Future<AppController> service(
    WidgetTester t,
    DevicePort port, {
    String kind = 'led',
    String? destination,
    bool start = true,
  }) async {
    late AppController c;
    await t.runAsync(() async {
      c = AppController(port);
      await c.initialize(startTicker: false);
      await c.setSimulatorKind(kind);
      await c.act('load', value: sunday());
      if (start) await c.act('start');
      if (destination != null) await c.selectDestination(destination);
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> press(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(f);
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> choose(WidgetTester t, String label) async {
    await t.tap(
      find.descendant(of: find.byKey(kindSwitch), matching: find.text(label)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<AppController> composer(
    WidgetTester t,
    DevicePort port, {
    String kind = 'led',
    String? destination,
    Size size = const Size(430, 1000),
    String text = 'Thank you',
  }) async {
    setScreen(t, size);
    final c = await service(t, port, kind: kind, destination: destination);
    if (destination != null) {
      // No screen or sign is connected, so the button is off; open the
      // composer the way the button does.
      unawaited(t.state<HomeState>(find.byType(Home)).sendStageMessage());
      await t.pump();
    } else {
      final button = find.text('Send message');
      await t.ensureVisible(button.first);
      await t.pumpAndSettle();
      await t.tap(button.first);
    }
    await settle(t);
    if (text != 'Thank you') {
      await t.enterText(find.byType(TextField).first, text);
      await settle(t);
    }
    return c;
  }

  /// Holds the message still, so a picture of it is the same each time.
  Future<void> holdStill(WidgetTester t) async {
    await press(t, find.byKey(const ValueKey('effect-choice')));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Static (must fit)').last);
    await settle(t);
    await t.ensureVisible(find.byKey(kindSwitch));
    await settle(t);
  }

  Json stageData(WidgetTester t) => t
      .widget<StageSurface>(
        find.descendant(
          of: find.byKey(cueStage),
          matching: find.byType(StageSurface),
        ),
      )
      .data;

  group('Send message', () {
    testWidgets('starts on the sign with the LED simulator', (t) async {
      await composer(t, FakePort());
      expect(find.byKey(kindSwitch), findsOneWidget);
      expect(dialogMatrix, findsOneWidget);
      expect(find.byKey(cueStage), findsNothing);
      expect(find.byKey(onLed), findsOneWidget);
      expect(find.byKey(onScreens), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('starts on the stage screen with the stage simulator', (
      t,
    ) async {
      await composer(t, FakePort(), kind: 'stage');
      expect(find.byKey(cueStage), findsOneWidget);
      expect(dialogMatrix, findsNothing);
      expect(find.byKey(onScreens), findsOneWidget);
      expect(find.byKey(onLed), findsNothing);
      expect(stageData(t)['displayText'], 'Thank you');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('starts on the stage screen with stage screens in use', (
      t,
    ) async {
      await composer(t, FakePort(), destination: 'mobile');
      expect(find.byKey(cueStage), findsOneWidget);
      expect(dialogMatrix, findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('starts on the sign with an LED sign in use', (t) async {
      await composer(t, FakePort(), kind: 'stage', destination: 'led');
      expect(find.byKey(cueStage), findsNothing);
      expect(dialogMatrix, findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the switch shows the other display and its settings', (
      t,
    ) async {
      await composer(t, FakePort(), kind: 'stage');
      await choose(t, 'LED sign');
      expect(dialogMatrix, findsOneWidget);
      expect(find.byKey(cueStage), findsNothing);
      expect(find.byKey(onLed), findsOneWidget);
      expect(find.byKey(onScreens), findsNothing);
      expect(find.text('Display font'), findsOneWidget);
      await choose(t, 'Stage screen');
      expect(find.byKey(cueStage), findsOneWidget);
      expect(find.byKey(onScreens), findsOneWidget);
      expect(find.text('Display font'), findsNothing);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a message set up for screens is sent with those settings', (
      t,
    ) async {
      final c = await composer(t, FakePort(), kind: 'stage');
      await press(t, find.byKey(const ValueKey('screen-color-green')));
      await t.pump(const Duration(milliseconds: 100));
      await t.ensureVisible(find.byKey(const ValueKey('screen-position-top')));
      await press(t, find.byKey(const ValueKey('screen-position-top')));
      await t.pump(const Duration(milliseconds: 100));
      expect(stageData(t)['cuePosition'], 'top');
      // Looking at the sign and back keeps what was set.
      await choose(t, 'LED sign');
      await choose(t, 'Stage screen');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      await t.tap(find.text('Send message').last);
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await settle(t);
      final sent = c.state.session.alert!;
      expect(sent.text, 'Thank you');
      expect(sent.screenColor, 'green');
      expect(sent.screenPosition, 'top');
      expect(c.state.session.alertIsMessage, isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a message set up for the sign keeps its sign settings', (
      t,
    ) async {
      final c = await composer(t, FakePort());
      await t.tap(find.widgetWithText(FilterChip, 'Tall · 14 px'));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      await t.tap(find.text('Send message').last);
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await settle(t);
      expect(c.state.session.alert!.height, 2);
      expect(c.state.session.alert!.screenPosition, 'full');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('fits a small phone and wide windows', (t) async {
      for (final size in const [Size(320, 568), Size(1366, 768)]) {
        await composer(
          t,
          size.width > 1000 ? DesktopFakePort() : FakePort(),
          kind: 'stage',
          size: size,
        );
        expect(find.byKey(cueStage), findsOneWidget, reason: '$size');
        await choose(t, 'LED sign');
        expect(t.takeException(), isNull, reason: '$size');
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the composer on a phone, as a stage screen', (t) async {
      await composer(t, FakePort(), kind: 'stage', text: 'Amen');
      await holdStill(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/send-message-stage-phone.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the composer at 1366 by 768, as a stage screen', (t) async {
      await composer(
        t,
        DesktopFakePort(),
        kind: 'stage',
        size: const Size(1366, 768),
        text: 'Amen',
      );
      await holdStill(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-send-message-stage.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  });

  group('End screen and zero screen', () {
    Future<AppController> section(
      WidgetTester t,
      String name, {
      String kind = 'led',
    }) async {
      setScreen(t, const Size(430, 1000));
      final c = await service(t, FakePort(), kind: kind);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Display settings'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text(name));
      await t.tap(find.text(name));
      await t.pumpAndSettle();
      return c;
    }

    for (final kind in const ['led', 'stage']) {
      testWidgets('the end screen editor starts on the $kind side', (t) async {
        final c = await section(t, 'Default end screen', kind: kind);
        await t.ensureVisible(find.text('Edit end screen'));
        await t.tap(find.text('Edit end screen'));
        await settle(t);
        expect(find.byType(CuePreviewSwitch), findsOneWidget);
        expect(
          find.byKey(cueStage),
          kind == 'stage' ? findsOneWidget : findsNothing,
        );
        expect(dialogMatrix, kind == 'stage' ? findsNothing : findsOneWidget);
        await choose(t, kind == 'stage' ? 'LED sign' : 'Stage screen');
        expect(
          find.byKey(cueStage),
          kind == 'stage' ? findsNothing : findsOneWidget,
        );
        // Saving from the stage side keeps the screen settings.
        await choose(t, 'Stage screen');
        await press(t, find.byKey(const ValueKey('screen-color-amber')));
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.text('Save end screen'));
        await t.pumpAndSettle();
        expect(c.state.defaults.end!.screenColor, 'amber');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });

      testWidgets('the zero screen editor starts on the $kind side', (t) async {
        final c = await section(t, 'At zero', kind: kind);
        await t.tap(find.text('Custom text'));
        await settle(t);
        expect(find.byType(CuePreviewSwitch), findsOneWidget);
        expect(
          find.byKey(cueStage),
          kind == 'stage' ? findsOneWidget : findsNothing,
        );
        expect(dialogMatrix, kind == 'stage' ? findsNothing : findsOneWidget);
        await choose(t, 'Stage screen');
        await press(t, find.byKey(const ValueKey('screen-color-red')));
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.text('Save zero screen'));
        await t.pumpAndSettle();
        expect(c.state.defaults.zero!.screenColor, 'red');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }

    for (final stage in const [false, true]) {
      testWidgets('the program end screen editor, stage first: $stage', (
        t,
      ) async {
        setScreen(t);
        final c = AppController(FakePort());
        await t.runAsync(() => c.initialize(startTicker: false));
        await t.pumpWidget(
          MaterialApp(
            home: TemplateEditor(
              initial: c.state.templates.first,
              existingNames: const {},
              stagePreviewFirst: stage,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('edit-end-screen')));
        await t.tap(find.byKey(const ValueKey('edit-end-screen')));
        await settle(t);
        expect(find.byKey(cueStage), stage ? findsOneWidget : findsNothing);
        expect(dialogMatrix, stage ? findsNothing : findsOneWidget);
        await choose(t, stage ? 'LED sign' : 'Stage screen');
        expect(find.byKey(cueStage), stage ? findsNothing : findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      });
    }
  });
}
