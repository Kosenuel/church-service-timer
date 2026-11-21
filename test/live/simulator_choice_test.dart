import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_preview.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/waiting.dart';
import '../support/steady_time.dart';
import '../support/widget_setup.dart';
import '../windows/second_screen_live_test.dart' show SecondPort;
import 'desktop_layout_test.dart' show DesktopFakePort, sunday;

const desktopLayouts = [
  'mission_control',
  'three_panes',
  'dial',
  'keys',
  'classic',
];

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  const stagePreview = ValueKey('stage-simulator-preview');
  const chipMenu = ValueKey('simulator-kind-menu');
  const header = ValueKey('display-preview-header');
  final matrix = find.byType(LedMatrix);

  /// A controller on [port], with the Simulator standing in for [kind]
  /// and Sunday's service loaded, and started unless [start] is false.
  Future<AppController> service(
    WidgetTester t,
    DevicePort port, {
    String kind = 'stage',
    String? layout,
    bool start = true,
  }) async {
    desktopWording = port.isDesktop;
    late AppController c;
    await t.runAsync(() async {
      c = AppController(port);
      await c.initialize(startTicker: false);
      if (layout != null) {
        await c.commit(
          (draft, _) => draft.appearance = draft.appearance.copyWith(
            desktopLayout: layout,
          ),
        );
      }
      await c.setSimulatorKind(kind);
      await c.act('load', value: sunday());
      if (start) await c.act('start');
    });
    return c;
  }

  Future<void> show(WidgetTester t, AppController c) async {
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
  }

  /// What the stage simulator's preview is drawing.
  Json shown(WidgetTester t) => t
      .widget<StageSurface>(
        find.descendant(
          of: find.byKey(stagePreview),
          matching: find.byType(StageSurface),
        ),
      )
      .data;

  Finder inHeader(String text) =>
      find.descendant(of: find.byKey(header), matching: find.text(text));

  /// Chooses [label] from the menu under the chip beside Display preview.
  Future<void> chooseFromChip(WidgetTester t, String label) async {
    await t.ensureVisible(find.byKey(chipMenu));
    await t.pumpAndSettle();
    await t.tap(find.byKey(chipMenu));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(CheckedPopupMenuItem<String>, label));
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
  }

  group('the remembered choice', () {
    test('is an LED sign unless a stage screen was chosen', () {
      final fresh = AppState.fresh(start);
      expect(fresh.simulatorKind, 'led');
      final saved = fresh.toJson();
      expect(
        AppState.fromJson({...saved}..remove('simulatorKind')).simulatorKind,
        'led',
      );
      expect(
        AppState.fromJson({
          ...saved,
          'simulatorKind': 'hologram',
        }).simulatorKind,
        'led',
      );
      expect(
        AppState.fromJson({...saved, 'simulatorKind': 'stage'}).simulatorKind,
        'stage',
      );
      expect(simulatorNameOf('led'), 'LED simulator');
      expect(simulatorNameOf('stage'), 'Stage simulator');
    });

    test('is kept when the app is opened again', () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      expect(c.state.simulatorKind, 'led');
      expect(c.stageSimulator, false);
      expect(await c.setSimulatorKind('hologram'), false);
      expect(await c.setSimulatorKind('stage'), true);
      expect(c.stageSimulator, true);
      expect(c.simulatorName, 'Stage simulator');
      c.dispose();
      final again = AppController(port);
      await again.initialize(startTicker: false);
      expect(again.state.simulatorKind, 'stage');
      again.dispose();
    });

    test(
      'belongs to this device: backups neither carry nor change it',
      () async {
        final c = AppController(FakePort());
        await c.initialize(startTicker: false);
        await c.setSimulatorKind('stage');
        final raw = exportBackup(c.state, start);
        expect(
          (jsonDecode(raw)['data'] as Map).containsKey('simulatorKind'),
          false,
        );
        // A backup from a device that simulates an LED sign.
        final other = importBackup(
          exportBackup(AppState.fresh(start)..churchName = 'Grace', start),
          start,
        );
        expect(other.simulatorKind, 'led');
        expect(await c.restoreBackup(other), true);
        expect(c.state.churchName, 'Grace');
        expect(c.state.simulatorKind, 'stage');
        c.dispose();
      },
    );

    test(
      'a stage screen is simulated only while the Simulator is the display',
      () async {
        final c = AppController(FakePort());
        await c.initialize(startTicker: false);
        await c.setSimulatorKind('stage');
        expect(c.previewsAsStageScreen, true);
        await c.selectDestination('mobile');
        expect(c.stageSimulator, false);
        expect(c.previewsAsStageScreen, true);
        await c.selectDestination('simulator');
        await c.setSimulatorKind('led');
        expect(c.previewsAsStageScreen, false);
        c.dispose();
      },
    );
  });

  group('the chips', () {
    testWidgets('read LED simulator, then Stage simulator', (t) async {
      setScreen(t, const Size(1366, 768));
      final c = await service(t, DesktopFakePort(), kind: 'led');
      await show(t, c);
      final top = find.byKey(const ValueKey('header-connection'));
      expect(
        find.descendant(of: top, matching: find.text('LED simulator')),
        findsOneWidget,
      );
      expect(inHeader('LED simulator'), findsOneWidget);
      expect(find.text('Simulator'), findsNothing);

      await t.runAsync(() => c.setSimulatorKind('stage'));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: top, matching: find.text('Stage simulator')),
        findsOneWidget,
      );
      expect(inHeader('Stage simulator'), findsOneWidget);
      expect(inHeader('LED simulator'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the one beside Display preview changes what is simulated', (
      t,
    ) async {
      setScreen(t, const Size(1366, 768));
      final c = await service(t, DesktopFakePort(), kind: 'led');
      await show(t, c);
      expect(matrix, findsOneWidget);
      expect(find.byKey(stagePreview), findsNothing);

      await chooseFromChip(t, 'Simulate a stage screen');
      expect(c.state.simulatorKind, 'stage');
      expect(matrix, findsNothing);
      expect(find.byKey(stagePreview), findsOneWidget);
      // Nothing was asked, and the service carried on.
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.state.session.active, true);

      await chooseFromChip(t, 'Simulate an LED sign');
      expect(c.state.simulatorKind, 'led');
      expect(matrix, findsOneWidget);
      expect(find.byKey(stagePreview), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a phone can change it there too', (t) async {
      setScreen(t);
      final c = await service(t, FakePort(), kind: 'led');
      await show(t, c);
      await chooseFromChip(t, 'Simulate a stage screen');
      expect(c.state.simulatorKind, 'stage');
      expect(inHeader('Stage simulator'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Lock controls leaves it as words only', (t) async {
      setScreen(t, const Size(1366, 768));
      final c = await service(t, DesktopFakePort(), kind: 'led');
      await show(t, c);
      expect(find.byKey(chipMenu), findsOneWidget);
      final home = t.state<HomeState>(find.byType(Home));
      home.refreshHome(() => home.controlsLocked = true);
      await t.pump();
      expect(find.byKey(chipMenu), findsNothing);
      expect(inHeader('LED simulator'), findsOneWidget);
      await t.tap(inHeader('LED simulator'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text('Simulate a stage screen'), findsNothing);
      expect(c.state.simulatorKind, 'led');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a real display’s chip has no such menu', (t) async {
      setScreen(t);
      final c = await service(t, FakePort());
      await t.runAsync(() => c.selectDestination('mobile'));
      await show(t, c);
      expect(find.byKey(chipMenu), findsNothing);
      expect(find.byKey(stagePreview), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Choose display', () {
    const choice = ValueKey('simulator-kind');

    Future<void> open(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('header-connection')));
      await t.pumpAndSettle();
    }

    testWidgets('offers Simulate under the Simulator, and remembers it', (
      t,
    ) async {
      setScreen(t);
      final c = await service(t, FakePort(), kind: 'led', start: false);
      await show(t, c);
      await open(t);
      expect(find.text('Simulate'), findsOneWidget);
      final button = find.byKey(choice);
      expect(
        find.descendant(of: button, matching: find.text('LED sign')),
        findsOneWidget,
      );
      expect(
        t.getTopLeft(button).dy,
        greaterThan(
          t.getTopLeft(find.byKey(const ValueKey('destination-simulator'))).dy,
        ),
      );
      await t.ensureVisible(button);
      await t.runAsync(() async {
        await t.tap(
          find.descendant(of: button, matching: find.text('Stage screen')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(c.state.simulatorKind, 'stage');
      // Still on the page, with nothing asked.
      expect(find.byKey(choice), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('hides Simulate while another display is chosen', (t) async {
      setScreen(t);
      final c = await service(t, FakePort(), start: false);
      await t.runAsync(() => c.selectDestination('mobile'));
      await show(t, c);
      await open(t);
      expect(
        find.byKey(const ValueKey('destination-simulator')),
        findsOneWidget,
      );
      expect(find.byKey(choice), findsNothing);
      expect(find.text('Simulate'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('its pane shows the stage simulator on a PC', (t) async {
      setScreen(t, const Size(1366, 768));
      final c = await service(t, DesktopFakePort());
      await show(t, c);
      await open(t);
      expect(find.text('ON THE DISPLAY NOW'), findsOneWidget);
      expect(find.byKey(choice), findsOneWidget);
      expect(find.byKey(stagePreview), findsOneWidget);
      expect(matrix, findsNothing);
      expect(inHeader('Stage simulator'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('the stage simulator on Live', () {
    testWidgets('holds the time still as it counts, before and during a '
        'service', (t) async {
      setScreen(t, const Size(1366, 768));
      final port = DesktopFakePort();
      final c = await service(t, port, start: false);
      // A service due to start in 48 minutes and 4 seconds.
      await t.runAsync(
        () => c.act('schedule', value: c.now.wall + (48 * 60 + 4) * 1000),
      );
      await show(t, c);
      Future<void> at(int seconds) async {
        port.at = after(seconds);
        await t.runAsync(c.tick);
        await t.pump();
        await t.pump();
      }

      final pre = {'48:03': 1, '47:58': 6, '11:11': 2213, '20:01': 1683};
      await expectTimeHoldsStill(
        t,
        find.byKey(stagePreview),
        pre.keys.toList(),
        (time) async {
          await at(pre[time]!);
          expect(shown(t)['outputMode'], 'Pre-service');
        },
      );
      // The service starts; its first segment is five minutes long.
      port.at = after(2884);
      await t.runAsync(() => c.act('start'));
      final running = {'04:44': 2884 + 16, '03:58': 2884 + 62};
      running['03:11'] = 2884 + 109;
      running['02:30'] = 2884 + 150;
      await expectTimeHoldsStill(
        t,
        find.byKey(stagePreview),
        running.keys.toList(),
        (time) async {
          await at(running[time]!);
          expect(shown(t)['displayIsTimer'], true);
        },
      );
      // In the face the app carries, as stage screens are.
      expectBundledFont(t, find.byKey(stagePreview));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('follows the countdown, a cue and Blank', (t) async {
      setScreen(t, const Size(1366, 768));
      final port = DesktopFakePort();
      final c = await service(t, port);
      await show(t, c);
      expect(matrix, findsNothing);
      // The timer only, in a 16:9 box.
      expect(shown(t)['stageLayout'], 'timer');
      expect(shown(t)['displayIsTimer'], true);
      expect(shown(t)['remaining'], '05:00');
      final box = t.getSize(find.byKey(stagePreview));
      expect(box.width / box.height, closeTo(16 / 9, .01));
      // The sign's size means nothing here.
      expect(find.textContaining('32 × 16'), findsNothing);

      // A five-minute segment does not start with its 5 MIN LEFT warning.
      port.at = after(40);
      await t.runAsync(c.tick);
      await t.pump();
      expect(shown(t)['displayIsTimer'], true);
      expect(shown(t)['displayText'], '04:20');
      port.at = after(60);
      await t.runAsync(c.tick);
      await t.pumpAndSettle();
      expect(shown(t)['remaining'], '04:00');
      expect(shown(t)['displayText'], '04:00');
      // 2 MIN LEFT comes in a banner under the countdown, for 12 seconds.
      port.at = after(180);
      await t.runAsync(c.tick);
      await t.pump();
      expect(shown(t)['displayText'], '2 MIN LEFT');
      expect(shown(t)['cuePosition'], 'bottom');
      port.at = after(200);
      await t.runAsync(c.tick);
      await t.pumpAndSettle();
      expect(shown(t)['displayText'], '01:40');

      expect(
        await t.runAsync(
          () => c.act(
            'cue',
            value: const TextLayout('AMEN', bold: true, effect: 'static'),
          ),
        ),
        true,
      );
      await t.pumpAndSettle();
      expect(shown(t)['displayText'], 'AMEN');
      expect(shown(t)['bold'], true);
      expect(shown(t)['displayIsTimer'], false);
      expect(
        find.descendant(
          of: find.byKey(stagePreview),
          matching: find.text('AMEN'),
        ),
        findsOneWidget,
      );

      await t.runAsync(() => c.act('clearCue'));
      await t.runAsync(() => c.act('blank'));
      await t.pumpAndSettle();
      expect(shown(t)['blank'], true);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('keeps the sign’s size line for the LED simulator', (t) async {
      setScreen(t);
      final c = await service(t, FakePort(), kind: 'led');
      await show(t, c);
      expect(find.textContaining('32 × 16'), findsOneWidget);
      await t.runAsync(() => c.setSimulatorKind('stage'));
      await t.pumpAndSettle();
      expect(find.textContaining('32 × 16'), findsNothing);
      expect(find.byKey(stagePreview), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('is in the focused operator view', (t) async {
      setScreen(t);
      final c = await service(t, FakePort());
      await show(t, c);
      final home = t.state<HomeState>(find.byType(Home));
      home.setFocused(true);
      await t.pumpAndSettle();
      expect(find.byKey(stagePreview), findsOneWidget);
      expect(matrix, findsNothing);
      expect(inHeader('Stage simulator'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('fits every layout at every usual size', (t) async {
      for (final size in const [
        Size(320, 568),
        Size(820, 1180),
        Size(1366, 768),
        Size(1920, 1080),
        Size(2560, 1440),
      ]) {
        final desktop = size.width >= 1366;
        for (final layout in desktop ? desktopLayouts : const [null]) {
          for (final started in const [true, false]) {
            setScreen(t, size);
            final c = await service(
              t,
              desktop ? DesktopFakePort() : FakePort(),
              layout: layout,
              start: started,
            );
            await show(t, c);
            final why = '$layout at $size, started: $started';
            expect(t.takeException(), isNull, reason: why);
            expect(find.byKey(stagePreview), findsOneWidget, reason: why);
            expect(matrix, findsNothing, reason: why);
            expect(inHeader('Stage simulator'), findsOneWidget, reason: why);
            await t.pumpWidget(const SizedBox());
          }
        }
      }
    });

    testWidgets('Live at full HD with the stage simulator', (t) async {
      setScreen(t, const Size(1920, 1080));
      final port = DesktopFakePort();
      final c = await service(t, port, layout: 'mission_control');
      port.at = after(95);
      await t.runAsync(c.tick);
      await show(t, c);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-stage-simulator-live.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  });

  group('a second screen that is showing', () {
    const copy = ValueKey('second-screen-preview');

    testWidgets('takes the place of either simulator', (t) async {
      for (final kind in const ['stage', 'led']) {
        setScreen(t, const Size(1366, 768));
        final port = SecondPort();
        final c = await service(t, port, kind: kind, layout: 'three_panes');
        await show(t, c);
        final button = t.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('live-second-screen-show')),
        );
        late StageFeed feed;
        await t.runAsync(() async {
          button.onPressed!();
          await until(() => port.launcher.launches.isNotEmpty);
          final args = port.launcher.launches.last;
          feed = StageFeed();
          await feed.connect(
            int.parse(stageArgument(args, 'port')!),
            stageArgument(args, 'token')!,
          );
          await until(() => feed.data != null);
        });
        await t.pumpAndSettle();
        expect(find.byKey(copy), findsOneWidget, reason: kind);
        expect(find.byKey(stagePreview), findsNothing, reason: kind);
        expect(matrix, findsNothing, reason: kind);
        // The chip names the second screen and has no menu.
        expect(inHeader('Second screen'), findsOneWidget, reason: kind);
        expect(find.byKey(chipMenu), findsNothing, reason: kind);

        // Stop brings the chosen simulator back.
        final stop = t.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('live-second-screen-stop')),
        );
        await t.runAsync(() async {
          stop.onPressed!();
          await until(() => feed.closed);
        });
        await t.pumpAndSettle();
        expect(find.byKey(copy), findsNothing, reason: kind);
        expect(
          find.byKey(stagePreview),
          kind == 'stage' ? findsOneWidget : findsNothing,
        );
        expect(matrix, kind == 'led' ? findsOneWidget : findsNothing);
        expect(t.takeException(), isNull, reason: kind);
        await t.runAsync(() => port.stageOutput.close());
        feed.dispose();
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  group('Manage cues', () {
    const kindSwitch = ValueKey('cue-preview-kind');
    const cueStage = ValueKey('cue-stage-preview');
    final dialogMatrix = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(LedMatrix),
    );

    /// Opens the editor for the first saved cue from Manage cues on Live.
    Future<AppController> editor(
      WidgetTester t,
      DevicePort port, {
      String kind = 'led',
      String? destination,
      Size size = const Size(430, 1000),
      bool still = false,
    }) async {
      setScreen(t, size);
      final c = await service(t, port, kind: kind, start: false);
      // A cue that holds still, for a picture of it.
      if (still) {
        await t.runAsync(
          () => c.commit(
            (draft, _) => draft.stageCues = [
              const TextLayout('AMEN', bold: true, effect: 'static'),
              ...draft.stageCues.skip(1),
            ],
          ),
        );
      }
      if (destination != null) {
        await t.runAsync(() => c.selectDestination(destination));
      }
      await show(t, c);
      await t.ensureVisible(find.text('Manage cues'));
      await t.pumpAndSettle();
      await t.tap(find.text('Manage cues'));
      await t.pumpAndSettle();
      await t.tap(find.text(c.state.stageCues.first.text).first);
      // The preview may be moving, so the page never comes to rest.
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      return c;
    }

    Future<void> choose(WidgetTester t, String label) async {
      await t.tap(
        find.descendant(of: find.byKey(kindSwitch), matching: find.text(label)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }

    Json cueShown(WidgetTester t) => t
        .widget<StageSurface>(
          find.descendant(
            of: find.byKey(cueStage),
            matching: find.byType(StageSurface),
          ),
        )
        .data;

    testWidgets('the editor shows a cue as the sign or as a stage screen', (
      t,
    ) async {
      final c = await editor(t, FakePort());
      final cue = c.state.stageCues.first;
      // The LED simulator is the display, so it starts on the sign.
      expect(find.byKey(kindSwitch), findsOneWidget);
      expect(dialogMatrix, findsOneWidget);
      expect(find.byKey(cueStage), findsNothing);

      await choose(t, 'Stage screen');
      expect(dialogMatrix, findsNothing);
      expect(find.text('NOT TESTED ON SIGN · simulator preview'), findsNothing);
      // The same picture a stage screen draws for a cue.
      expect(cueShown(t)['displayText'], cue.text);
      // WRAP UP pulses: an older screen is sent it steady.
      expect(cueShown(t)['effect'], cue.compatibleEffect);
      expect(cueShown(t)['screenEffect'], 'pulse');
      expect(cueShown(t)['bold'], cue.bold);
      // WRAP UP is a banner, over a sample countdown.
      expect(cueShown(t)['cuePosition'], 'bottom');
      expect(
        find.descendant(
          of: find.byKey(cueStage),
          matching: find.byType(StageMessage),
        ),
        findsNWidgets(2),
      );
      final box = t.getSize(find.byKey(cueStage));
      expect(box.width / box.height, closeTo(16 / 9, .01));

      // It follows the typing (each word fits the sign, for Pulse).
      await t.enterText(find.byType(TextField).first, 'TWO MINS');
      await t.pump(const Duration(milliseconds: 100));
      expect(cueShown(t)['displayText'], 'TWO MINS');

      await choose(t, 'LED sign');
      expect(dialogMatrix, findsOneWidget);
      expect(find.byKey(cueStage), findsNothing);
      // Looking is not saving.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.stageCues.first.text, cue.text);
      expect(c.state.simulatorKind, 'led');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('starts on the stage screen with the stage simulator', (
      t,
    ) async {
      await editor(t, FakePort(), kind: 'stage');
      expect(find.byKey(cueStage), findsOneWidget);
      expect(dialogMatrix, findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('starts on the stage screen with stage screens', (t) async {
      await editor(t, FakePort(), destination: 'mobile');
      expect(find.byKey(cueStage), findsOneWidget);
      expect(dialogMatrix, findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('other text editors keep the sign preview alone', (t) async {
      setScreen(t);
      await t.pumpWidget(
        const MaterialApp(
          home: TextComposer(
            initial: TextLayout('THANK YOU'),
            title: 'End screen',
            button: 'Save',
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(CuePreviewSwitch), findsNothing);
      expect(find.byType(LedMatrix), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('fits a small phone and wide windows', (t) async {
      for (final size in const [
        Size(320, 568),
        Size(1366, 768),
        Size(1920, 1080),
        Size(2560, 1440),
      ]) {
        final desktop = size.width >= 1366;
        await editor(
          t,
          desktop ? DesktopFakePort() : FakePort(),
          kind: 'stage',
          size: size,
        );
        expect(find.byKey(cueStage), findsOneWidget, reason: '$size');
        expect(t.takeException(), isNull, reason: '$size');
        await choose(t, 'LED sign');
        expect(t.takeException(), isNull, reason: '$size');
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the stage preview on a PC', (t) async {
      await editor(
        t,
        DesktopFakePort(),
        kind: 'stage',
        size: const Size(1366, 768),
        still: true,
      );
      expect(find.byKey(cueStage), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-cue-stage-preview.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the stage preview on a phone', (t) async {
      await editor(t, FakePort(), kind: 'stage', still: true);
      expect(find.byKey(cueStage), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/cue-stage-preview-phone.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  });
}
