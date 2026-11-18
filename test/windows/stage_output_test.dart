import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:church_service_timer/windows/stage_output_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/waiting.dart';
import '../support/widget_setup.dart';

class FakeChild implements StageChild {
  final _exit = Completer<void>();
  bool killed = false;
  @override
  Future<void> get exited => _exit.future;
  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete();
  }
}

/// Stands in for Windows: two screens, and "starting the second copy"
/// only records how it was started.
class FakeLauncher implements StageOutputLauncher {
  List<StageMonitor> screens = [
    (index: 0, rect: [0, 0, 1920, 1080], primary: true),
    (index: 1, rect: [1920, 0, 3200, 720], primary: false),
  ];
  final launches = <List<String>>[];
  final children = <FakeChild>[];
  bool fail = false;
  @override
  List<StageMonitor> monitors() => screens;
  @override
  Future<StageChild> launch(List<String> arguments) async {
    if (fail) throw StateError('cannot start');
    launches.add(arguments);
    final child = FakeChild();
    children.add(child);
    return child;
  }
}

class StagePort extends FakePort {
  final launcher = FakeLauncher();
  @override
  late final StageOutputHost stageOutput = StageOutputHost(launcher);
  @override
  bool get isDesktop => true;
}

void main() {
  group('the main app\'s side', () {
    late FakeLauncher launcher;
    late StageOutputHost host;
    setUp(() {
      launcher = FakeLauncher();
      host = StageOutputHost(launcher);
    });
    tearDown(() => host.close());

    Future<StageFeed> window() async {
      final args = launcher.launches.last;
      final feed = StageFeed();
      await feed.connect(
        int.parse(stageArgument(args, 'port')!),
        stageArgument(args, 'token')!,
      );
      await until(() => host.connected);
      return feed;
    }

    test('starts the second copy for the chosen screen', () async {
      await host.show(launcher.screens[1]);
      expect(host.open, isTrue);
      expect(host.monitor, 1);
      expect(host.connected, isFalse);
      final args = launcher.launches.single;
      expect(args.first, '--stage-output');
      expect(stageRect(args), [1920, 0, 3200, 720]);
      expect(args, contains('--topmost'));
      expect(stageArgument(args, 'token')!.length, 32);
      // On the main screen it must not sit above the operator's controls.
      await host.show(launcher.screens[0]);
      expect(launcher.launches.last, isNot(contains('--topmost')));
      expect(launcher.children.first.killed, isTrue);
    });

    test('sends the picture once the window connects, then changes', () async {
      await host.show(launcher.screens[1]);
      host.send({'remaining': '10:00'});
      final feed = await window();
      await until(() => feed.data != null);
      expect(feed.data, {'remaining': '10:00'});
      host.send({'remaining': '09:59'});
      await until(() => feed.data?['remaining'] == '09:59');
      expect(feed.stale, isFalse);
      feed.dispose();
    });

    test('an unchanged picture is repeated only as a heartbeat', () async {
      await host.show(launcher.screens[1]);
      final feed = await window();
      var received = 0;
      feed.addListener(() => received++);
      for (var i = 0; i < 20; i++) {
        host.send({'remaining': '10:00'});
      }
      await until(() => received > 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, 1);
      feed.dispose();
    });

    test('a connection without the token is refused', () async {
      await host.show(launcher.screens[1]);
      final port = int.parse(stageArgument(launcher.launches.last, 'port')!);
      final intruder = StageFeed();
      await intruder.connect(port, 'not-the-token');
      await until(() => intruder.closed);
      expect(host.connected, isFalse);
      host.send({'remaining': '10:00'});
      expect(intruder.data, isNull);
      // The real window still gets in afterwards.
      final feed = await window();
      await until(() => feed.data != null);
      feed.dispose();
      intruder.dispose();
    });

    test('only listens on this computer', () async {
      await host.show(launcher.screens[1]);
      final port = int.parse(stageArgument(launcher.launches.last, 'port')!);
      final addresses = [
        for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        ))
          ...i.addresses,
      ];
      for (final address in addresses) {
        await expectLater(
          Socket.connect(address, port, timeout: const Duration(seconds: 1)),
          throwsA(anything),
          reason: address.address,
        );
      }
    });

    test(
      'closing here closes the window, and the window closing is noticed',
      () async {
        await host.show(launcher.screens[1]);
        var feed = await window();
        await host.close();
        await until(() => feed.closed);
        expect(host.open, isFalse);
        expect(launcher.children.last.killed, isTrue);
        feed.dispose();

        // Esc on the stage window ends that copy.
        await host.show(launcher.screens[1]);
        feed = await window();
        var changes = 0;
        host.addListener(() => changes++);
        launcher.children.last.kill();
        await until(() => !host.open);
        expect(changes, greaterThan(0));
        expect(host.connected, isFalse);
        feed.dispose();
      },
    );

    test('a failure to start is reported and leaves nothing open', () async {
      launcher.fail = true;
      await host.show(launcher.screens[1]);
      expect(host.open, isFalse);
      expect(host.error, isNotNull);
      launcher.fail = false;
      await host.show(launcher.screens[1]);
      expect(host.error, isNull);
      expect(host.open, isTrue);
    });

    test('command-line values are read strictly', () {
      const args = ['--stage-output', '--port=5123', '--rect=0,0,1280,720'];
      expect(stageArgument(args, 'port'), '5123');
      expect(stageArgument(args, 'token'), isNull);
      expect(stageRect(args), [0, 0, 1280, 720]);
      expect(stageRect(['--rect=0,0,10,10']), isNull);
      expect(stageRect(['--rect=a,b,c,d']), isNull);
      expect(stageRect(['--rect=1,2,3']), isNull);
      expect(stageRect([]), isNull);
    });
  });

  group('the stage window', () {
    setUpAll(loadAppFonts);

    testWidgets('shows the timer, marks it when the app goes quiet, and '
        'closes on Esc', (t) async {
      setScreen(t, const Size(1280, 720));
      final feed = StageFeed();
      var closed = 0;
      await t.pumpWidget(StageOutputApp(feed: feed, onClose: () => closed++));
      expect(find.text('Waiting for Church Service Timer…'), findsOneWidget);

      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      feed.receive(jsonEncode(c.stageWindowSnapshot()));
      await t.pumpAndSettle();
      expect(find.text('Waiting for Church Service Timer…'), findsNothing);
      expect(find.byType(StageSurface), findsOneWidget);
      // The display is the Simulator, yet the window still shows the stage.
      expect(c.destination, 'simulator');
      expect(find.textContaining('not sending to stage screens'), findsNothing);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/windows-stage-window.png'),
      );

      feed.receive('{not json');
      await t.pump();
      expect(find.byType(StageSurface), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      feed.dispose();
    });

    testWidgets('a blank screen is black and a message replaces the timer', (
      t,
    ) async {
      setScreen(t, const Size(1280, 720));
      final feed = StageFeed();
      await t.pumpWidget(StageOutputApp(feed: feed, onClose: () {}));
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await c.act('blank');
      final blank = c.stageWindowSnapshot();
      expect(blank['blank'], isTrue);
      expect(blank['stageSharing'], isTrue);
      expect(blank.containsKey('rundown'), isFalse);
      feed.receive(jsonEncode(blank));
      await t.pumpAndSettle();
      expect(find.byType(Text), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      feed.dispose();
    });
  });

  group('in the app', () {
    testWidgets('Screens & devices offers the second screen and follows the '
        'service', (t) async {
      setScreen(t, const Size(1366, 900));
      final port = StagePort();
      late AppController c;
      await t.runAsync(() async {
        c = AppController(port);
        await c.initialize(startTicker: false);
        await c.act('load', value: c.state.templates.first);
        await c.act('start');
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final home = t.state<HomeState>(find.byType(Home));
      unawaited(
        home.openSettingsDetail('Screens & devices', home.screensAndDevices),
      );
      await t.pumpAndSettle();
      expect(find.text('Second screen'), findsOneWidget);
      // Only the screen that is not the operator's own is offered.
      expect(find.text('Screen 2 · 1280 × 720'), findsOneWidget);
      expect(find.textContaining('Screen 1'), findsNothing);

      late StageFeed feed;
      await t.runAsync(() async {
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('second-screen-show-1')),
            )
            .onPressed!();
        await until(() => port.launcher.launches.isNotEmpty);
        final args = port.launcher.launches.single;
        feed = StageFeed();
        await feed.connect(
          int.parse(stageArgument(args, 'port')!),
          stageArgument(args, 'token')!,
        );
        await until(() => feed.data != null);
      });
      await t.pumpAndSettle();
      expect(feed.data!['stageSharing'], isTrue);
      expect(feed.data!['remaining'], c.stageWindowSnapshot()['remaining']);
      expect(find.textContaining('Showing the stage output'), findsOneWidget);

      // A change in the service reaches the window without being asked.
      await t.runAsync(() async {
        await c.act('pause');
        await until(() => feed.data?['paused'] == true);
      });

      await t.runAsync(() async {
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('second-screen-stop-1')),
            )
            .onPressed!();
        await until(() => feed.closed);
      });
      await t.pumpAndSettle();
      expect(find.text('Not showing'), findsOneWidget);
      feed.dispose();
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('with one screen it explains how to add another', (t) async {
      setScreen(t, const Size(1366, 900));
      final port = StagePort()
        ..launcher.screens = [
          (index: 0, rect: [0, 0, 1920, 1080], primary: true),
        ];
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final home = t.state<HomeState>(find.byType(Home));
      unawaited(
        home.openSettingsDetail('Screens & devices', home.screensAndDevices),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('No second screen found'), findsOneWidget);
      expect(find.textContaining('Windows + P'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a phone has no second screen panel', (t) async {
      setScreen(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final home = t.state<HomeState>(find.byType(Home));
      unawaited(
        home.openSettingsDetail('Screens & devices', home.screensAndDevices),
      );
      await t.pumpAndSettle();
      expect(find.text('Second screen'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
