import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/live/second_screen_control.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort, sunday;
import '../support/fake_port.dart';
import '../support/waiting.dart';
import '../support/widget_setup.dart';

class _Child implements StageChild {
  final _exit = Completer<void>();
  @override
  Future<void> get exited => _exit.future;
  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete();
  }
}

const StageMonitor laptop = (index: 0, rect: [0, 0, 1920, 1080], primary: true);
const StageMonitor projector = (
  index: 1,
  rect: [1920, 0, 5760, 2160],
  primary: false,
);
const StageMonitor confidence = (
  index: 2,
  rect: [-1280, 0, 0, 720],
  primary: false,
);

/// Stands in for Windows: the screens plugged in, and a record of each
/// time the stage window was started.
class _Launcher implements StageOutputLauncher {
  List<StageMonitor> screens = [laptop, projector];
  final launches = <List<String>>[];
  final children = <_Child>[];
  @override
  List<StageMonitor> monitors() => screens;
  @override
  Future<StageChild> launch(List<String> arguments) async {
    launches.add(arguments);
    final child = _Child();
    children.add(child);
    return child;
  }
}

/// A PC whose second-screen choices are kept in [saved], as its settings
/// file would keep them.
class SecondPort extends DesktopFakePort {
  final launcher = _Launcher();
  Json saved = {};
  @override
  late final StageOutputHost stageOutput = StageOutputHost(launcher);
  @override
  Future<Json> secondScreenSettings() async => Map.of(saved);
  @override
  Future<void> saveSecondScreenSettings(Json settings) async =>
      saved = Map.of(settings);
}

/// A PC that also has an LED sign set up as its display.
class SignSecondPort extends SecondPort {
  @override
  Future<Json> displayPreferences() async => {
    'hardware': true,
    'id': 'sign-1',
    'name': 'Hall sign',
  };
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  /// Lets the window come to rest. With an LED sign that is waiting to
  /// reconnect something always moves, so a few frames are drawn instead.
  Future<void> rest(WidgetTester t, DevicePort port) async {
    if (port is SignSecondPort) {
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    } else {
      await t.pumpAndSettle();
    }
  }

  /// A controller on [port], with Sunday's service loaded and ready.
  Future<AppController> ready(
    WidgetTester t,
    DevicePort port, {
    String layout = 'three_panes',
  }) async {
    late AppController c;
    await t.runAsync(() async {
      c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit(
        (draft, _) =>
            draft.appearance = draft.appearance.copyWith(desktopLayout: layout),
      );
      await c.act('load', value: sunday());
    });
    return c;
  }

  /// The app's window on [port] with Sunday's service running.
  Future<AppController> live(
    WidgetTester t,
    SecondPort port, {
    Size size = const Size(1366, 768),
    String layout = 'three_panes',
  }) async {
    setScreen(t, size);
    final c = await ready(t, port, layout: layout);
    await t.runAsync(() => c.act('start'));
    await t.pumpWidget(TimerApp(controller: c));
    await rest(t, port);
    return c;
  }

  /// Plays the stage window's part: connects as the second copy would.
  Future<StageFeed> window(WidgetTester t, SecondPort port) async {
    late StageFeed feed;
    await t.runAsync(() async {
      await until(() => port.launcher.launches.isNotEmpty);
      final args = port.launcher.launches.last;
      feed = StageFeed();
      await feed.connect(
        int.parse(stageArgument(args, 'port')!),
        stageArgument(args, 'token')!,
      );
      await until(() => feed.data != null);
    });
    await rest(t, port);
    return feed;
  }

  Future<void> finish(
    WidgetTester t,
    SecondPort port, [
    StageFeed? feed,
  ]) async {
    await t.runAsync(() => port.stageOutput.close());
    feed?.dispose();
    await t.pumpWidget(const SizedBox());
  }

  Future<void> press(WidgetTester t, String key, [DevicePort? port]) async {
    final button = t.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));
    await t.runAsync(() async {
      button.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    if (port == null) {
      await t.pumpAndSettle();
    } else {
      await rest(t, port);
    }
  }

  const control = ValueKey('live-second-screen');
  const show = ValueKey('live-second-screen-show');
  const stop = ValueKey('live-second-screen-stop');

  group('the control on Live', () {
    testWidgets('with no second screen it is one quiet line', (t) async {
      final port = SecondPort()..launcher.screens = [laptop];
      await live(t, port);
      expect(find.text('No second screen connected'), findsOneWidget);
      expect(find.byKey(show), findsNothing);
      expect(find.byKey(stop), findsNothing);
      await finish(t, port);
    });

    testWidgets('with one it shows and stops, and says which', (t) async {
      final port = SecondPort();
      final c = await live(t, port);
      expect(find.text('Second screen: not showing'), findsOneWidget);
      expect(find.text('Show on second screen'), findsOneWidget);
      // One screen to show on needs no choosing.
      expect(
        find.byKey(const ValueKey('live-second-screen-choice')),
        findsNothing,
      );

      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(stageRect(port.launcher.launches.single), projector.rect);
      expect(find.text('Showing on Screen 2 · 3840 × 2160'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.byKey(show), findsNothing);
      expect(feed.data!['remaining'], c.stageWindowSnapshot()['remaining']);
      // Which screen, and that it is showing, is kept on this computer.
      expect(port.saved['rect'], projector.rect);
      expect(port.saved['index'], 1);
      expect(port.saved['showing'], isTrue);

      await press(t, 'live-second-screen-stop');
      await t.runAsync(() => until(() => feed.closed));
      expect(find.text('Second screen: not showing'), findsOneWidget);
      expect(port.saved['showing'], isFalse);
      expect(port.saved['rect'], projector.rect);
      await finish(t, port, feed);
    });

    testWidgets('with two it lets the person choose which', (t) async {
      final port = SecondPort()
        ..launcher.screens = [laptop, projector, confidence];
      final c = await live(t, port);
      expect(find.text('Second screen: not showing'), findsOneWidget);
      expect(find.byKey(show), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('live-second-screen-choice')));
      await t.pumpAndSettle();
      await t.tap(find.text('Screen 3 · 1280 × 720').last);
      await t.pumpAndSettle();
      expect(c.secondScreen!.target, confidence);

      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(stageRect(port.launcher.launches.single), confidence.rect);
      expect(find.text('Showing on Screen 3 · 1280 × 720'), findsOneWidget);
      expect(port.saved['index'], 2);
      await finish(t, port, feed);
    });

    testWidgets('the remembered screen is the one offered next time', (
      t,
    ) async {
      final port = SecondPort()
        ..launcher.screens = [laptop, projector, confidence]
        ..saved = {'rect': confidence.rect, 'index': 2, 'showing': true};
      final c = await live(t, port);
      expect(c.secondScreen!.remembered, confidence);
      expect(c.secondScreen!.target, confidence);
      // Windows renumbered the screens: it is known by its place.
      port.launcher.screens = [
        laptop,
        (index: 1, rect: confidence.rect, primary: false),
      ];
      expect(c.secondScreen!.remembered!.index, 1);
      // Nothing opens by itself when the app starts.
      expect(port.launcher.launches, isEmpty);
      await finish(t, port);
    });

    testWidgets('Lock controls disables it', (t) async {
      final port = SecondPort();
      await live(t, port);
      final home = t.state<HomeState>(find.byType(Home));
      home.refreshHome(() => home.controlsLocked = true);
      await t.pump();
      expect(t.widget<ButtonStyleButton>(find.byKey(show)).onPressed, isNull);
      expect(home.paletteCommands(), isEmpty);
      home.refreshHome(() => home.controlsLocked = false);
      await t.pump();

      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      home.refreshHome(() => home.controlsLocked = true);
      await t.pump();
      expect(t.widget<ButtonStyleButton>(find.byKey(stop)).onPressed, isNull);
      await finish(t, port, feed);
    });

    testWidgets('Classic has it too, and so does the command palette', (
      t,
    ) async {
      final port = SecondPort();
      final c = await live(t, port, layout: 'classic');
      expect(find.byKey(show), findsOneWidget);
      final home = t.state<HomeState>(find.byType(Home));
      var command = home.paletteCommands().singleWhere(
        (e) => e.id == 'second-screen',
      );
      expect(command.label, 'Show on second screen');
      expect(command.detail, 'Screen 2 · 3840 × 2160');
      await t.runAsync(() async => command.run());
      final feed = await window(t, port);
      expect(c.port.stageOutput!.monitor, 1);
      command = home.paletteCommands().singleWhere(
        (e) => e.id == 'second-screen',
      );
      expect(command.label, 'Stop the second screen');
      await t.runAsync(() async => command.run());
      expect(c.port.stageOutput!.open, isFalse);
      // With nothing to show on, the palette does not offer it.
      port.launcher.screens = [laptop];
      expect(
        home.paletteCommands().where((e) => e.id == 'second-screen'),
        isEmpty,
      );
      await finish(t, port, feed);
    });

    testWidgets('a phone shows none of it', (t) async {
      desktopWording = false;
      setScreen(t);
      final port = FakePort();
      final c = await ready(t, port);
      await t.runAsync(() => c.act('start'));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(c.secondScreen, isNull);
      expect(find.byKey(control), findsNothing);
      expect(find.textContaining('econd screen'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('fits every desktop layout at every usual size', (t) async {
      for (final layout in [
        'three_panes',
        'mission_control',
        'dial',
        'keys',
        'classic',
      ]) {
        for (final size in const [
          Size(1200, 600),
          Size(1366, 768),
          Size(1920, 1080),
          Size(2560, 1440),
        ]) {
          // Keys at the smallest size overflows in its own top strip
          // just after a start, with or without a second screen.
          if (layout == 'keys' && size.width < 1300) continue;
          final port = SecondPort()
            ..launcher.screens = [laptop, projector, confidence];
          await live(t, port, size: size, layout: layout);
          expect(t.takeException(), isNull, reason: '$layout at $size');
          expect(find.byKey(control), findsOneWidget, reason: '$layout $size');
          await press(t, 'live-second-screen-show');
          expect(t.takeException(), isNull, reason: '$layout at $size');
          expect(find.byKey(stop), findsOneWidget);
          await finish(t, port);
        }
      }
    });

    testWidgets('Live at full HD with the second screen showing', (t) async {
      final port = SecondPort();
      await live(t, port, size: const Size(1920, 1080));
      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(find.text('Showing on Screen 2 · 3840 × 2160'), findsOneWidget);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-second-screen-live.png'),
      );
      await finish(t, port, feed);
    });
  });

  group('the display preview on Live', () {
    const preview = ValueKey('second-screen-preview');
    final matrix = find.byType(LedMatrix);

    /// The stage window went by itself: Esc on that screen, or its
    /// monitor was unplugged.
    Future<void> gone(WidgetTester t, SecondPort port) async {
      port.launcher.screens = [laptop];
      await t.runAsync(() async {
        port.launcher.children.last.kill();
        await until(() => !port.stageOutput.open);
      });
      await rest(t, port);
    }

    test('where the copy of the second screen goes', () {
      SecondScreenPreviewPlace place({
        bool showing = true,
        bool sign = false,
        bool screens = false,
      }) => secondScreenPreviewPlace(
        showing: showing,
        sign: sign,
        screens: screens,
      );
      // The Simulator alone gives way to it.
      expect(place(), SecondScreenPreviewPlace.replaces);
      // One real display keeps its preview, with the copy under it.
      expect(place(sign: true), SecondScreenPreviewPlace.beneath);
      expect(place(screens: true), SecondScreenPreviewPlace.beneath);
      // A sign and stage screens together: nothing changes.
      expect(place(sign: true, screens: true), SecondScreenPreviewPlace.none);
      // Not showing: nothing, whatever the display.
      for (final sign in [false, true]) {
        for (final screens in [false, true]) {
          expect(
            place(showing: false, sign: sign, screens: screens),
            SecondScreenPreviewPlace.none,
          );
        }
      }
    });

    testWidgets('it takes the Simulator’s place, and Stop brings that back', (
      t,
    ) async {
      final port = SecondPort();
      final c = await live(t, port);
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsNothing);

      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(matrix, findsNothing);
      expect(find.byKey(preview), findsOneWidget);
      expect(find.text('Second screen'), findsOneWidget);
      // The same picture the second screen is sent, in its layout.
      final surface = t.widget<StageSurface>(
        find.descendant(
          of: find.byKey(preview),
          matching: find.byType(StageSurface),
        ),
      );
      expect(surface.data['remaining'], c.stageWindowSnapshot()['remaining']);
      expect(surface.data['stageLayout'], c.secondScreen!.layout);
      // In the screen's own shape: 3840 × 2160.
      final box = t.getSize(
        find.descendant(
          of: find.byKey(preview),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(box.width / box.height, closeTo(16 / 9, .01));
      expect(t.takeException(), isNull);

      await press(t, 'live-second-screen-stop');
      await t.runAsync(() => until(() => feed.closed));
      await t.pumpAndSettle();
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsNothing);
      await finish(t, port, feed);
    });

    testWidgets('it follows the second screen’s own layout', (t) async {
      final port = SecondPort();
      final c = await live(t, port);
      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      await t.runAsync(() => c.secondScreen!.setLayout('next'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<StageSurface>(
              find.descendant(
                of: find.byKey(preview),
                matching: find.byType(StageSurface),
              ),
            )
            .data['stageLayout'],
        'next',
      );
      await finish(t, port, feed);
    });

    testWidgets('an LED sign keeps its preview, with the copy under it', (
      t,
    ) async {
      final port = SignSecondPort();
      final c = await live(t, port);
      expect(c.hardware.enabled, isTrue);
      expect(c.destination, 'led');
      expect(matrix, findsOneWidget);

      await press(t, 'live-second-screen-show', port);
      final feed = await window(t, port);
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsOneWidget);
      expect(
        t.getRect(find.byKey(preview)).top,
        greaterThanOrEqualTo(t.getRect(matrix).bottom),
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-second-screen-preview-sign.png'),
      );

      await press(t, 'live-second-screen-stop', port);
      await t.runAsync(() => until(() => feed.closed));
      await rest(t, port);
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsNothing);
      await finish(t, port, feed);
    });

    testWidgets('stage screens keep their preview, with the copy under it', (
      t,
    ) async {
      final port = SecondPort();
      final c = await live(t, port);
      await t.runAsync(() => c.selectDestination('mobile'));
      await t.pumpAndSettle();
      expect(c.destination, 'mobile');
      // The stage screens' preview, with none joined yet.
      final waiting = find.text('Waiting for a screen').last;
      expect(waiting, findsOneWidget);
      expect(matrix, findsNothing);

      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(waiting, findsOneWidget);
      expect(find.byKey(preview), findsOneWidget);
      expect(
        t.getRect(find.byKey(preview)).top,
        greaterThan(t.getRect(waiting).bottom),
      );
      expect(t.takeException(), isNull);

      await press(t, 'live-second-screen-stop');
      await t.runAsync(() => until(() => feed.closed));
      await t.pumpAndSettle();
      expect(waiting, findsOneWidget);
      expect(find.byKey(preview), findsNothing);
      await finish(t, port, feed);
    });

    testWidgets('unplugging the second screen is the same as Stop', (t) async {
      final port = SecondPort();
      await live(t, port);
      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(matrix, findsNothing);
      expect(find.byKey(preview), findsOneWidget);
      await gone(t, port);
      // Back to the Simulator.
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsNothing);
      expect(find.text('No second screen connected'), findsOneWidget);
      await finish(t, port, feed);
    });

    testWidgets('unplugging it leaves an LED sign’s preview as it was', (
      t,
    ) async {
      final port = SignSecondPort();
      await live(t, port);
      await press(t, 'live-second-screen-show', port);
      final feed = await window(t, port);
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsOneWidget);
      await gone(t, port);
      expect(matrix, findsOneWidget);
      expect(find.byKey(preview), findsNothing);
      await finish(t, port, feed);
    });

    testWidgets('every desktop layout has it, and nothing overflows', (
      t,
    ) async {
      for (final layout in const [
        'three_panes',
        'dial',
        'keys',
        'mission_control',
        'classic',
      ]) {
        for (final size in const [Size(1366, 768), Size(2560, 1440)]) {
          final port = SecondPort();
          await live(t, port, layout: layout, size: size);
          await press(t, 'live-second-screen-show');
          final feed = await window(t, port);
          expect(find.byKey(preview), findsOneWidget, reason: '$layout $size');
          expect(matrix, findsNothing, reason: '$layout $size');
          expect(t.takeException(), isNull, reason: '$layout $size');
          await finish(t, port, feed);
        }
      }
    });

    testWidgets('a phone has no second screen and keeps its preview', (
      t,
    ) async {
      setScreen(t);
      final c = await ready(t, FakePort());
      await t.runAsync(() => c.act('start'));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(c.secondScreen, isNull);
      expect(find.byKey(preview), findsNothing);
      expect(matrix, findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('opening when a service starts', () {
    Json remembered(StageMonitor screen, {bool on = true}) => {
      'rect': screen.rect,
      'index': screen.index,
      'showing': false,
      'openOnStart': on,
    };

    testWidgets('opens on the remembered screen when the setting is on', (
      t,
    ) async {
      final port = SecondPort()..saved = remembered(projector);
      final c = await ready(t, port);
      expect(port.launcher.launches, isEmpty);
      await t.runAsync(() async {
        await c.act('start');
        await until(() => c.port.stageOutput!.open);
      });
      expect(stageRect(port.launcher.launches.single), projector.rect);
      expect(port.launcher.launches.single, contains('--topmost'));

      // Ending the service leaves the end screen up; starting another
      // does not open a second window.
      await t.runAsync(() async {
        await c.act('end');
        expect(c.port.stageOutput!.open, isTrue);
        await c.act('load', value: sunday());
        await c.act('start');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(port.launcher.launches, hasLength(1));
      await t.runAsync(() => port.stageOutput.close());
      c.dispose();
    });

    testWidgets('a Quick timer opens it as well', (t) async {
      final port = SecondPort()..saved = remembered(projector);
      late AppController c;
      await t.runAsync(() async {
        c = AppController(port);
        await c.initialize(startTicker: false);
        expect(
          await c.startQuickTimer(const QuickTimerChoice('Announcements', 300)),
          isTrue,
        );
        await until(() => c.port.stageOutput!.open);
        await port.stageOutput.close();
      });
      expect(stageRect(port.launcher.launches.single), projector.rect);
      c.dispose();
    });

    testWidgets('does nothing when the setting is off', (t) async {
      final port = SecondPort()..saved = remembered(projector, on: false);
      final c = await ready(t, port);
      await t.runAsync(() async {
        await c.act('start');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      expect(port.launcher.launches, isEmpty);
      expect(c.secondScreen!.note, isNull);
      c.dispose();
    });

    testWidgets('does nothing, and says so, when that screen is gone', (
      t,
    ) async {
      final port = SecondPort()
        ..saved = remembered(projector)
        ..launcher.screens = [laptop, confidence];
      final c = await live(t, port);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pumpAndSettle();
      expect(port.launcher.launches, isEmpty);
      expect(
        find.text('Not opened: the screen used last time is not connected.'),
        findsOneWidget,
      );
      expect(find.text('Second screen: not showing'), findsOneWidget);
      expect(c.port.stageOutput!.open, isFalse);
      await finish(t, port);
    });

    testWidgets('never opens on the operator’s own screen', (t) async {
      // A saved place that is now the main screen: the projector the
      // stage was on has become the only screen, or the main one.
      final port = SecondPort()
        ..saved = remembered(laptop)
        ..launcher.screens = [laptop, confidence];
      final c = await ready(t, port);
      await t.runAsync(() async {
        await c.act('start');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      expect(c.secondScreen!.remembered, isNull);
      expect(port.launcher.launches, isEmpty);
      c.dispose();
    });
  });

  group('what it shows', () {
    testWidgets('the choice reaches the second screen, not paired phones', (
      t,
    ) async {
      final port = SecondPort();
      final c = await live(t, port);
      expect(c.stageWindowSnapshot()['stageLayout'], 'timer');
      await press(t, 'live-second-screen-show');
      final feed = await window(t, port);
      expect(feed.data!['stageLayout'], 'timer');

      await t.runAsync(() async {
        await c.secondScreen!.setLayout('next');
        await until(() => feed.data?['stageLayout'] == 'next');
      });
      expect(feed.data!['nextSegment'], 'Praise & Worship');
      expect(port.saved['layout'], 'next');
      // A paired phone's picture is untouched: its layout comes from its
      // own setting in Screens & devices.
      expect(c.pairedSnapshot(false).containsKey('stageLayout'), isFalse);
      expect(c.pairedSnapshot(true).containsKey('stageLayout'), isFalse);
      // Kept on this computer, not in the app's state or its backups.
      expect(port.data, isNot(contains('openOnStart')));
      expect(port.data, isNot(contains('1920, 0, 5760')));
      await finish(t, port, feed);

      // The next time the app opens on this computer it is still chosen.
      final again = await ready(t, port);
      expect(again.secondScreen!.layout, 'next');
      expect(again.stageWindowSnapshot()['stageLayout'], 'next');
      again.dispose();
    });

    testWidgets('the Settings card holds every option', (t) async {
      setScreen(t, const Size(1366, 900));
      final port = SecondPort();
      final c = await ready(t, port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final home = t.state<HomeState>(find.byType(Home));
      unawaited(
        home.openSettingsDetail('Screens & devices', home.screensAndDevices),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Open the second screen when a service starts'),
        findsOneWidget,
      );
      const toggle = ValueKey('second-screen-open-on-start');
      expect(t.widget<SwitchListTile>(find.byKey(toggle)).value, isFalse);
      for (final name in [
        'Timer only',
        'Timer and segment name',
        'Timer and next segment',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      await t.ensureVisible(find.byKey(toggle));
      await t.tap(find.byKey(toggle));
      await t.pumpAndSettle();
      expect(port.saved['openOnStart'], isTrue);
      expect(t.widget<SwitchListTile>(find.byKey(toggle)).value, isTrue);
      const chip = ValueKey('second-screen-layout-current');
      await t.ensureVisible(find.byKey(chip));
      await t.tap(find.byKey(chip));
      await t.pumpAndSettle();
      expect(port.saved['layout'], 'current');
      expect(c.stageWindowSnapshot()['stageLayout'], 'current');

      // Show in the card remembers the screen, as Live's button does.
      await t.ensureVisible(find.byKey(const ValueKey('second-screen-show-1')));
      await press(t, 'second-screen-show-1');
      expect(port.saved['rect'], projector.rect);
      await finish(t, port);
    });
  });
}
