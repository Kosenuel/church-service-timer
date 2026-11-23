import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import '../domain/feature_cases.dart' show epoch;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class AwakePort extends FakePort {
  final calls = <bool>[];
  bool failAwake = false;
  bool get held => calls.isNotEmpty && calls.last;

  /// The changes the device was told about, without repeats.
  List<bool> get changes => [
    for (var i = 0; i < calls.length; i++)
      if (i == 0 || calls[i] != calls[i - 1]) calls[i],
  ];
  @override
  Future<void> setKeepScreenAwake(bool enabled) async {
    if (failAwake) throw Exception('Window not available');
    calls.add(enabled);
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<(AppController, AwakePort)> open({bool dispose = true}) async {
    final port = AwakePort()..at = epoch;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    if (dispose) addTearDown(c.dispose);
    return (c, port);
  }

  group('the screen is held only while there is a job', () {
    test(
      'a new install lets the screen sleep until a service starts',
      () async {
        final (c, port) = await open();
        expect(c.state.screenAwake, 'service');
        expect(port.held, isFalse);
        expect(c.wantsScreenAwake, isFalse);
      },
    );

    test('start, pause, resume and end of a service', () async {
      final (c, port) = await open();
      await c.act('load', value: timeline());
      // Loaded and waiting to start: still idle.
      expect(port.held, isFalse);
      await c.act('start');
      expect(port.held, isTrue);
      await c.act('pause');
      expect(c.state.session.paused, isTrue);
      expect(port.held, isTrue, reason: 'paused mid-service');
      await c.act('pause');
      expect(port.held, isTrue);
      await c.act('end');
      expect(port.held, isFalse, reason: 'released when the service ends');
      expect(port.changes, [false, true, false]);
      // Not re-sent on every change of the service.
      expect(port.calls.where((x) => x).length, 1);
    });

    test('a quick timer holds the screen while it runs', () async {
      final (c, port) = await open();
      expect(
        await c.startQuickTimer(const QuickTimerChoice('Offering', 300)),
        isTrue,
      );
      expect(c.state.session.quickTimer, isTrue);
      expect(port.held, isTrue);
      await c.act('end');
      expect(port.held, isFalse);
    });

    test(
      'a countdown to a scheduled start holds it; a bare Ready does not',
      () async {
        final (c, port) = await open();
        await c.act('load', value: timeline());
        expect(port.held, isFalse);
        await c.act('schedule', value: c.now.wall + 10 * 60000);
        expect(port.held, isTrue);
        await c.act('cancelReady');
        expect(port.held, isFalse);
      },
    );

    test(
      'Never lets the screen sleep during a service; Always holds it idle',
      () async {
        final (c, port) = await open();
        await c.commit((d, _) => d.screenAwake = 'never');
        await c.act('load', value: timeline());
        await c.act('start');
        expect(port.held, isFalse);
        await c.act('end');
        await c.commit((d, _) => d.screenAwake = 'always');
        expect(port.held, isTrue, reason: 'idle but always');
        await c.commit((d, _) => d.screenAwake = 'service');
        expect(port.held, isFalse);
      },
    );

    test('a stage screen stays awake whatever the setting says', () async {
      final (c, port) = await open();
      await c.commit((d, _) => d.screenAwake = 'never');
      c.pairing.mode = 'stage';
      await c.syncDeviceSettings();
      expect(port.held, isTrue);
      c.pairing.mode = 'off';
      await c.syncDeviceSettings();
      expect(port.held, isFalse);
    });

    test(
      'sharing to other screens holds the screen; an operator view alone does not',
      () async {
        final (c, port) = await open();
        c.pairing.mode = 'operator';
        await c.syncDeviceSettings();
        expect(port.held, isFalse);
        c.pairing.mode = 'viewer';
        await c.syncDeviceSettings();
        expect(port.held, isTrue);
      },
    );
  });

  group('slides on the screens count as the job', () {
    Future<(AppController, AwakePort)> withSong() async {
      final (c, port) = await open();
      await c.lyrics.save(
        LyricItem(
          id: 'amazing',
          kind: 'song',
          title: 'Amazing Grace',
          words: 'Verse 1\nAmazing grace\n\nVerse 2\nHow sweet the sound',
        ),
      );
      return (c, port);
    }

    test(
      'a slide holds the screen with no service, clearing lets go',
      () async {
        final (c, port) = await withSong();
        expect(port.held, isFalse);
        c.lyrics.show('amazing', 0);
        await pumpEventQueue();
        expect(c.wantsScreenAwake, isTrue);
        expect(port.held, isTrue);
        c.lyrics.clear();
        await pumpEventQueue();
        expect(c.wantsScreenAwake, isFalse);
        expect(port.held, isFalse);
      },
    );

    test(
      'Black from the Slides page holds it too, until the slide is gone',
      () async {
        final (c, port) = await withSong();
        c.lyrics.toggleBlack();
        await pumpEventQueue();
        expect(port.held, isTrue);
        c.lyrics.toggleBlack();
        await pumpEventQueue();
        expect(port.held, isFalse);
      },
    );

    test('clearing keeps the screen while a service still runs', () async {
      final (c, port) = await withSong();
      await c.act('load', value: timeline());
      await c.act('start');
      c.lyrics.show('amazing', 0);
      await pumpEventQueue();
      c.lyrics.clear();
      await pumpEventQueue();
      expect(port.held, isTrue, reason: 'the service is running');
      await c.act('end');
      expect(port.held, isFalse);
    });

    test('a slide no group shows does not hold it', () async {
      final (c, port) = await withSong();
      for (final g in c.screens.setup.groups) {
        await c.screens.setShow(g.id, 'timer');
      }
      c.lyrics.show('amazing', 0);
      await pumpEventQueue();
      expect(c.lyrics.showing, isTrue);
      expect(port.held, isFalse);
    });

    test('Never still lets the screen sleep with a slide up', () async {
      final (c, port) = await withSong();
      await c.commit((d, _) => d.screenAwake = 'never');
      c.lyrics.show('amazing', 0);
      await pumpEventQueue();
      expect(port.held, isFalse);
    });
  });

  group('saved data', () {
    Json old(Object? awake) {
      final j = AppState.fresh(epoch).toJson()..remove('keepScreenAlways');
      if (awake == null) {
        j.remove('keepScreenAwake');
      } else {
        j['keepScreenAwake'] = awake;
      }
      return j;
    }

    test('data from before the change reads as While a service is running', () {
      expect(AppState.fromJson(old(null)).screenAwake, 'service');
      expect(AppState.fromJson(old(true)).screenAwake, 'service');
    });

    test('an old saved Off stays Never', () {
      expect(AppState.fromJson(old(false)).screenAwake, 'never');
    });

    test(
      'all three choices survive a round trip, and Always stays out of backups',
      () {
        for (final choice in screenAwakeChoices) {
          final a = AppState.fresh(epoch)..screenAwake = choice;
          final b = AppState.fromJson(
            jsonDecode(jsonEncode(a.toJson())) as Json,
          );
          expect(b.screenAwake, choice);
        }
        final a = AppState.fresh(epoch)..screenAwake = 'always';
        expect(exportBackup(a, epoch), isNot(contains('keepScreenAlways')));
        expect(
          () => AppState.fresh(epoch).screenAwake = 'sometimes',
          throwsA(anything),
        );
      },
    );
  });

  group('Settings', () {
    testWidgets('idle on each main page keeps nothing held', (t) async {
      setScreen(t, const Size(390, 900));
      final (c, port) = await open(dispose: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await t.tap(find.byType(NavigationDestination).at(i));
        await t.pumpAndSettle();
        expect(port.held, isFalse, reason: 'page $i');
      }
      await t.pumpWidget(const SizedBox());
    });

    Future<AppController> openSettings(
      WidgetTester t,
      AwakePort port, {
      Size size = const Size(390, 900),
    }) async {
      setScreen(t, size);
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(4));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('screen-awake')));
      await t.pumpAndSettle();
      return c;
    }

    Future<void> close(WidgetTester t, AppController c) async {
      await t.pumpWidget(const SizedBox());
    }

    final menu = find.byKey(const ValueKey('screen-awake-menu'));

    testWidgets('is one row that names the current choice', (t) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      expect(find.text('Keep screen awake'), findsOneWidget);
      expect(find.text('While a service is running'), findsOneWidget);
      // The other choices and their notes are in the menu, not on the page.
      expect(find.text('Always'), findsNothing);
      expect(find.text('Never'), findsNothing);
      expect(find.text('Recommended.'), findsNothing);
      await close(t, c);
    });

    testWidgets('opens a menu of three notes, ticks the current one', (
      t,
    ) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      await t.tap(menu);
      await t.pumpAndSettle();
      expect(find.text('Always'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
      expect(find.text('Recommended.'), findsOneWidget);
      expect(
        find.text('Stays on whenever the app is open. Uses more battery.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The screen can sleep, even during a service. A stage screen still stays on.',
        ),
        findsOneWidget,
      );
      CheckedPopupMenuItem<String> item(String v) =>
          t.widget(find.byKey(ValueKey('screen-awake-$v')));
      expect(item('service').checked, isTrue);
      expect(item('always').checked, isFalse);
      expect(item('never').checked, isFalse);
      await close(t, c);
    });

    testWidgets('choosing each option applies and saves it at once', (t) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      final subtitles = {
        'always': 'Always',
        'never': 'Never',
        'service': 'While a service is running',
      };
      for (final value in ['always', 'never', 'service']) {
        await t.tap(menu);
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('screen-awake-$value')));
        await t.pumpAndSettle();
        expect(c.state.screenAwake, value);
        expect(
          port.held,
          value == 'always',
          reason: 'idle: only Always holds the screen',
        );
        // The row now names it, and the menu is closed.
        expect(find.text(subtitles[value]!), findsOneWidget);
        expect(find.byKey(const ValueKey('screen-awake-never')), findsNothing);
        // Saved: a fresh start reads the same choice back.
        final restart = AppController(port);
        await restart.initialize(startTicker: false);
        expect(restart.state.screenAwake, value);
        restart.dispose();
      }
      await close(t, c);
    });

    testWidgets('cannot be opened while the app is busy', (t) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      c.busy = true;
      // ignore: invalid_use_of_protected_member
      c.notifyListeners();
      await t.pumpAndSettle();
      await t.tap(menu, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('screen-awake-always')), findsNothing);
      expect(c.state.screenAwake, 'service');
      c.busy = false;
      // ignore: invalid_use_of_protected_member
      c.notifyListeners();
      await t.pumpAndSettle();
      await t.tap(menu);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('screen-awake-always')), findsOneWidget);
      await close(t, c);
    });

    testWidgets('works from the keyboard and tells a screen reader', (t) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      final handle = t.ensureSemantics();
      expect(
        t.getSemantics(menu),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasExpandedState: true,
          hasSelectedState: true,
          tooltip: 'Choose when the screen stays awake',
          label: 'Keep screen awake\nWhile a service is running',
        ),
      );
      handle.dispose();
      // Focus the row, open it with Enter, move down and choose with Enter.
      bool onRow() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<PopupMenuButton<String>>()
              ?.key ==
          const ValueKey('screen-awake-menu');
      for (var i = 0; i < 60 && !onRow(); i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
      }
      expect(onRow(), isTrue, reason: 'Tab reaches the row');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('screen-awake-always')), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(c.state.screenAwake, 'always');
      await close(t, c);
    });

    testWidgets('shows the error and a retry under the row', (t) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      port.failAwake = true;
      await c.commit((d, _) => d.screenAwake = 'always');
      await t.pumpAndSettle();
      expect(c.deviceSettingsError, isNotNull);
      expect(find.text(c.deviceSettingsError!), findsOneWidget);
      expect(find.text('Retry screen setting'), findsOneWidget);
      port.failAwake = false;
      await t.tap(find.text('Retry screen setting'));
      await t.pumpAndSettle();
      expect(c.deviceSettingsError, isNull);
      expect(find.text('Retry screen setting'), findsNothing);
      await close(t, c);
    });

    for (final scale in [1.0, 1.6]) {
      testWidgets('fits a 360-wide phone at text scale $scale', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final port = AwakePort()..at = epoch;
        final c = await openSettings(t, port, size: const Size(360, 780));
        expect(t.takeException(), isNull);
        await t.tap(menu);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final menuRect = t.getRect(
          find.byKey(const ValueKey('screen-awake-never')),
        );
        expect(menuRect.left, greaterThanOrEqualTo(0));
        expect(menuRect.right, lessThanOrEqualTo(360));
        if (scale == 1.0) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../goldens/settings-screen-awake-menu-phone.png',
            ),
          );
        }
        await t.tap(find.byKey(const ValueKey('screen-awake-never')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await close(t, c);
      });
    }

    testWidgets('settings search finds it and opens the same row', (t) async {
      final port = AwakePort()..at = epoch;
      final c = await openSettings(t, port);
      await t.enterText(find.byKey(const ValueKey('settings-search')), 'awake');
      await t.pumpAndSettle();
      expect(
        find.text('While a service is running, always or never'),
        findsOneWidget,
      );
      await t.tap(find.text('Keep screen awake'));
      await t.pumpAndSettle();
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('screen-awake-always')));
      await t.pumpAndSettle();
      expect(c.state.screenAwake, 'always');
      await close(t, c);
    });
  });
}
