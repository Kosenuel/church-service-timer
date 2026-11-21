import 'dart:convert';

import 'package:church_service_timer/app/auto_update_check.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/update_checker.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'update_notice_test.dart' show UpdatePort, release;

const day = 24 * 60 * 60;

/// Lets an automatic check started without being awaited finish.
Future<void> settle(AppController c) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  while (c.autoUpdate.asking || c.busy) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<(AppController, UpdatePort)> ready(
  String? reply, {
  bool on = false,
}) async {
  final port = UpdatePort(reply);
  final c = AppController(port);
  await c.initialize(startTicker: false);
  if (on) {
    await c.commit((draft, _) => draft.autoUpdate.enabled = true);
  }
  return (c, port);
}

void main() {
  setUpAll(loadAppFonts);

  group('the automatic check', () {
    test('is off to begin with and asks nothing', () async {
      expect(AppState.fresh(start).autoUpdate.enabled, isFalse);
      final (c, port) = await ready(release('v0.33.0'));
      expect(c.autoUpdate.enabled, isFalse);
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, isEmpty);
      expect(c.autoUpdate.notice, isNull);
      c.dispose();
    });

    test('once on, asks once and then waits a day', () async {
      final (c, port) = await ready(release('v0.33.0'));
      expect(await c.autoUpdate.setEnabled(true), isTrue);
      await settle(c);
      expect(port.asked, [latestReleaseUrl]);
      expect(c.state.autoUpdate.checkedWall, start.wall);
      expect(c.state.autoUpdate.found, '0.33.0');
      expect(c.autoUpdate.notice, '0.33.0');
      // Not again within the day.
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      port.at = after(day - 60);
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, hasLength(1));
      port.at = after(day);
      expect(await c.autoUpdate.checkIfDue(), isTrue);
      expect(port.asked, hasLength(2));
      // A clock set back is not allowed to stop checks for ever.
      port.at = after(10);
      expect(await c.autoUpdate.checkIfDue(), isTrue);
      expect(port.asked, hasLength(3));
      c.dispose();
    });

    test('the same or an older version shows nothing', () async {
      for (final tag in ['v0.32.0', 'v0.31.4']) {
        final (c, port) = await ready(release(tag), on: true);
        expect(await c.autoUpdate.checkIfDue(), isTrue);
        expect(port.asked, hasLength(1));
        expect(c.state.autoUpdate.found, isNull);
        expect(c.autoUpdate.notice, isNull);
        c.dispose();
      }
    });

    test('an up-to-date answer clears an earlier find', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      await c.autoUpdate.checkIfDue();
      expect(c.autoUpdate.notice, '0.33.0');
      port.reply = release('v0.32.0');
      port.at = after(day);
      await c.autoUpdate.checkIfDue();
      expect(c.autoUpdate.notice, isNull);
      c.dispose();
    });

    test('a failed check is silent and waits a day', () async {
      final (c, port) = await ready(null, on: true);
      expect(c.error, isNull);
      expect(await c.autoUpdate.checkIfDue(), isTrue);
      expect(port.asked, hasLength(1));
      expect(c.error, isNull);
      expect(c.state.autoUpdate.found, isNull);
      expect(c.state.autoUpdate.checkedWall, start.wall);
      expect(c.autoUpdate.notice, isNull);
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      // A fetch that throws is just as quiet.
      final quiet = AppController(_ThrowingPort());
      await quiet.initialize(startTicker: false);
      await quiet.commit((draft, _) => draft.autoUpdate.enabled = true);
      expect(await quiet.autoUpdate.checkIfDue(), isTrue);
      expect(quiet.error, isNull);
      expect(quiet.autoUpdate.notice, isNull);
      quiet.dispose();
      c.dispose();
    });

    test('a failed check keeps what an earlier one found', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      await c.autoUpdate.checkIfDue();
      port.reply = null;
      port.at = after(day);
      await c.autoUpdate.checkIfDue();
      expect(port.asked, hasLength(2));
      expect(c.autoUpdate.notice, '0.33.0');
      c.dispose();
    });

    test('is skipped during a service, and asks when it ends', () async {
      final (c, port) = await ready(release('v0.33.0'));
      await c.act('load', value: timeline());
      // Set up on Live counts as running.
      await c.autoUpdate.setEnabled(true);
      await settle(c);
      expect(port.asked, isEmpty);
      await c.act('start');
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, isEmpty);
      port.at = after(20);
      await c.tick();
      await c.act('end');
      await settle(c);
      expect(c.liveSession.active, isFalse);
      expect(port.asked, [latestReleaseUrl]);
      c.dispose();
    });

    test('is skipped during a quick timer', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      await c.startQuickTimer(const QuickTimerChoice('Offering', 300));
      expect(c.state.session.quickTimer, isTrue);
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, isEmpty);
      await c.act('end');
      await settle(c);
      expect(port.asked, hasLength(1));
      c.dispose();
    });

    test('is skipped during a rehearsal', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      await c.act('load', value: timeline());
      await c.act('rate', value: 10);
      await c.act('start');
      expect(c.state.session.rehearsal, isTrue);
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, isEmpty);
      c.dispose();
    });

    test('is skipped while Check this service is open', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      c.autoUpdate.serviceCheckOpened();
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, isEmpty);
      c.autoUpdate.serviceCheckClosed();
      await settle(c);
      expect(port.asked, hasLength(1));
      c.dispose();
    });

    test('is skipped while the controls are locked', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      c.uiLocked = true;
      c.autoUpdate.lockChanged();
      expect(await c.autoUpdate.checkIfDue(), isFalse);
      expect(port.asked, isEmpty);
      c.uiLocked = false;
      c.autoUpdate.lockChanged();
      await settle(c);
      expect(port.asked, hasLength(1));
      c.dispose();
    });

    test('Not now hides that version only', () async {
      final (c, port) = await ready(release('v0.33.0'), on: true);
      await c.autoUpdate.checkIfDue();
      expect(c.autoUpdate.notice, '0.33.0');
      await c.autoUpdate.dismiss('0.33.0');
      expect(c.autoUpdate.notice, isNull);
      port.at = after(day);
      await c.autoUpdate.checkIfDue();
      expect(c.autoUpdate.notice, isNull);
      port.reply = release('v0.34.0');
      port.at = after(2 * day);
      await c.autoUpdate.checkIfDue();
      expect(c.autoUpdate.notice, '0.34.0');
      // Switching the check off hides the notice too.
      await c.autoUpdate.setEnabled(false);
      expect(c.autoUpdate.notice, isNull);
      c.dispose();
    });

    test('is kept on this device, not in backups', () async {
      final (c, _) = await ready(release('v0.33.0'), on: true);
      await c.autoUpdate.checkIfDue();
      await c.autoUpdate.dismiss('0.33.0');
      final saved = AppState.fromJson(c.state.toJson()).autoUpdate;
      expect(saved.enabled, isTrue);
      expect(saved.checkedWall, start.wall);
      expect(saved.found, '0.33.0');
      expect(saved.dismissed, '0.33.0');
      final backup = exportBackup(c.state, start);
      expect(backup, isNot(contains('autoUpdate')));
      expect(backup, isNot(contains('checkedWall')));
      // Restoring a backup leaves this device's choice alone.
      expect(await c.restoreBackup(importBackup(backup, start)), isTrue);
      expect(c.state.autoUpdate.enabled, isTrue);
      expect(c.state.autoUpdate.checkedWall, start.wall);
      c.dispose();
    });

    test('reads anything unexpected as off', () {
      for (final value in [
        null,
        'on',
        {'enabled': 'yes', 'checkedWall': -1, 'found': 'v1', 'dismissed': 3},
      ]) {
        final read = AutoUpdateSettings.fromJson(value);
        expect(read.enabled, isFalse);
        expect(read.checkedWall, isNull);
        expect(read.found, isNull);
        expect(read.dismissed, isNull);
      }
    });
  });

  group('on screen', () {
    testWidgets('waits after the app starts before asking', (t) async {
      setScreen(t, const Size(430, 1000));
      final port = UpdatePort(release('v0.33.0'));
      port.data = jsonEncode(
        (AppState.fresh(start)..autoUpdate.enabled = true).toJson(),
      );
      final c = AppController(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(c.ready, isTrue);
      await t.pump(const Duration(seconds: 20));
      expect(port.asked, isEmpty);
      await t.pump(AutoUpdateCheck.startDelay);
      await t.pumpAndSettle();
      expect(port.asked, [latestReleaseUrl]);
      expect(
        find.byKey(const ValueKey('update-available-notice')),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('off, nothing is asked however long the app runs', (t) async {
      setScreen(t, const Size(430, 1000));
      final port = UpdatePort(release('v0.33.0'));
      final c = AppController(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.pump(const Duration(minutes: 5));
      expect(port.asked, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    Future<(AppController, UpdatePort)> live(
      WidgetTester t, {
      Size size = const Size(430, 1000),
      bool desktop = false,
    }) async {
      setScreen(t, size);
      final port = UpdatePort(release('v0.33.0'));
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((draft, _) {
        draft.churchName = 'Grace Community Church';
        draft.autoUpdate
          ..enabled = true
          ..checkedWall = start.wall
          ..found = '0.33.0';
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      return (c, port);
    }

    Finder notice() => find.byKey(const ValueKey('update-available-notice'));

    testWidgets('shows on Live while standing by', (t) async {
      await live(t);
      expect(notice(), findsOneWidget);
      expect(find.text('Version 0.33.0 is available'), findsOneWidget);
      expect(find.text('See update'), findsOneWidget);
      expect(find.text('Not now'), findsWidgets);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(TimerApp),
        matchesGoldenFile('../goldens/update-notice-live-phone.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('shows on a 1366 × 768 Live while standing by', (t) async {
      await live(t, size: const Size(1366, 768));
      expect(notice(), findsOneWidget);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(TimerApp),
        matchesGoldenFile('../goldens/update-notice-live-1366.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('is not shown during a service or with controls locked', (
      t,
    ) async {
      final (c, _) = await live(t);
      await c.act('load', value: timeline());
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      await c.act('start');
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      await c.act('end');
      await t.pumpAndSettle();
      expect(notice(), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Not now hides it until a newer version', (t) async {
      final (c, _) = await live(t);
      await t.tap(find.byKey(const ValueKey('update-notice-later')));
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      expect(c.state.autoUpdate.dismissed, '0.33.0');
      await c.commit((draft, _) => draft.autoUpdate.found = '0.34.0');
      await t.pumpAndSettle();
      expect(find.text('Version 0.34.0 is available'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('See update opens Check for updates', (t) async {
      final (_, port) = await live(t);
      expect(port.asked, isEmpty);
      await t.tap(find.byKey(const ValueKey('update-notice-see')));
      await t.pumpAndSettle();
      expect(find.text('Check for updates'), findsWidgets);
      expect(find.text('Version 0.33.0 is available'), findsOneWidget);
      expect(find.text('Open the download page'), findsOneWidget);
      expect(port.asked, [latestReleaseUrl]);
      await t.pumpWidget(const SizedBox());
    });

    Future<(AppController, UpdatePort)> about(WidgetTester t, Size size) async {
      setScreen(t, size);
      final port = UpdatePort(release('v0.33.0'));
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((draft, _) {
        draft.churchName = 'Grace Community Church';
        draft.appearance = draft.appearance.copyWith(
          desktopLayout: 'three_panes',
        );
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('About', skipOffstage: false));
      await t.pumpAndSettle();
      await t.tap(find.text('About'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('about-auto-update')));
      await t.pumpAndSettle();
      return (c, port);
    }

    for (final (name, size) in const [
      ('phone', Size(430, 1000)),
      ('1366', Size(1366, 768)),
    ]) {
      testWidgets('Settings › About has the switch, off ($name)', (t) async {
        final (c, port) = await about(t, size);
        expect(find.text('Check for updates automatically'), findsOneWidget);
        expect(
          find.text(
            'Once a day, when no service is running. Nothing is downloaded or installed without asking.',
          ),
          findsOneWidget,
        );
        final toggle = find.byKey(const ValueKey('about-auto-update'));
        expect(t.widget<SwitchListTile>(toggle).value, isFalse);
        expect(t.takeException(), isNull);
        // In a wide window only the rows, not the release notes beside
        // them, which change with every release.
        await expectLater(
          name == 'phone'
              ? find.byType(TimerApp)
              : find
                    .ancestor(of: toggle, matching: find.byType(AppPanel))
                    .first,
          matchesGoldenFile('../goldens/auto-update-about-$name.png'),
        );
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(c.state.autoUpdate.enabled, isTrue);
        expect(t.widget<SwitchListTile>(toggle).value, isTrue);
        // Switched on with nothing running, it asks straight away.
        expect(port.asked, [latestReleaseUrl]);
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(c.state.autoUpdate.enabled, isFalse);
        await t.pumpWidget(const SizedBox());
      });
    }
  });
}

class _ThrowingPort extends FakePort {
  @override
  Future<String> installedVersion() async => '0.32.0 (37)';
  @override
  UpdateChecker get updateChecker =>
      UpdateChecker((_) async => throw Exception('no route'));
}
