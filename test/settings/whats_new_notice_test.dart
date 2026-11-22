import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/whats_new_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'update_notice_test.dart' show UpdatePort, release;

class VersionPort extends FakePort {
  String version;
  VersionPort(this.version);
  @override
  Future<String> installedVersion() async => version;
}

/// A controller started on [version], after [seen] was kept (null: none).
Future<(AppController, VersionPort)> started(
  String version, {
  Object? seen,
}) async {
  final port = VersionPort(version);
  if (seen != null) {
    final s = AppState.fresh(start);
    final json = s.toJson()..['seenVersion'] = seen;
    port.data = jsonEncode(json);
  }
  final c = AppController(port);
  await c.initialize(startTicker: false);
  return (c, port);
}

void main() {
  setUpAll(loadAppFonts);
  group('rules', () {
    test('a new install shows nothing and records the version', () async {
      final (c, _) = await started('0.36.0 (40)');
      expect(c.whatsNew.notice, isNull);
      expect(c.state.seenVersion, '0.36.0');
      c.dispose();
    });

    test('an existing install with nothing seen shows once', () async {
      final port = VersionPort('0.36.0 (40)');
      final first = AppController(port);
      await first.initialize(startTicker: false);
      first.dispose();
      // The saved state has no seenVersion, as from the previous release.
      final json = jsonDecode(port.data!) as Map<String, dynamic>
        ..remove('seenVersion');
      port.data = jsonEncode(json);
      final c = AppController(port);
      await c.initialize(startTicker: false);
      expect(c.hadSavedState, isTrue);
      expect(c.whatsNew.notice, '0.36.0');
      await c.whatsNew.markSeen();
      expect(c.whatsNew.notice, isNull);
      c.dispose();
    });

    test('a restore on a new install does not show it', () async {
      final (c, _) = await started('0.36.0');
      expect(c.hadSavedState, isFalse);
      final backup = exportBackup(c.state, start);
      expect(await c.restoreBackup(importBackup(backup, start)), isTrue);
      expect(c.whatsNew.notice, isNull);
      c.dispose();
    });

    test('an update from an older version shows once', () async {
      final (c, _) = await started('0.36.0 (40)', seen: '0.35.0');
      expect(c.state.seenVersion, '0.35.0');
      expect(c.whatsNew.notice, '0.36.0');
      expect(await c.whatsNew.markSeen(), isTrue);
      expect(c.whatsNew.notice, isNull);
      expect(c.state.seenVersion, '0.36.0');
      c.dispose();
    });

    test('the same version again shows nothing', () async {
      final (c, _) = await started('0.36.0', seen: '0.36.0');
      expect(c.whatsNew.notice, isNull);
      c.dispose();
    });

    test('a downgrade shows nothing and records the lower version', () async {
      final (c, _) = await started('0.34.0', seen: '0.36.0');
      expect(c.whatsNew.notice, isNull);
      expect(c.state.seenVersion, '0.34.0');
      c.dispose();
    });

    test('a pre-release is older than its release', () async {
      final (c, _) = await started('0.36.0', seen: '0.36.0-beta.1');
      expect(c.whatsNew.notice, '0.36.0');
      c.dispose();
      final (d, _) = await started('0.36.0-beta.2', seen: '0.36.0-beta.1');
      expect(d.whatsNew.notice, '0.36.0-beta.2');
      d.dispose();
      final (e, _) = await started('0.36.0-beta.1', seen: '0.36.0');
      expect(e.whatsNew.notice, isNull);
      expect(e.state.seenVersion, '0.36.0-beta.1');
      e.dispose();
      final a = SemanticVersion.tryParse('0.10.0')!;
      final b = SemanticVersion.tryParse('0.9.0 (3)')!;
      expect(a.compareTo(b), greaterThan(0));
      expect(
        SemanticVersion.tryParse(
          '1.0.0-alpha',
        )!.compareTo(SemanticVersion.tryParse('1.0.0-alpha.1')!),
        lessThan(0),
      );
      expect(SemanticVersion.tryParse('1.0'), isNull);
    });

    test('an unexpected stored value reads as nothing seen', () async {
      for (final bad in ['soon', 3, '1.2', '0.35.0 (7)', '', true]) {
        expect(readSeenVersion(bad), isNull, reason: '$bad');
      }
      // Nothing seen on an existing install: it shows once.
      final (c, _) = await started('0.36.0', seen: 'garbage');
      expect(c.whatsNew.notice, '0.36.0');
      expect(c.state.seenVersion, isNull);
      c.dispose();
    });

    test('is kept on this device, not in backups', () async {
      final (c, _) = await started('0.36.0', seen: '0.35.0');
      final saved = AppState.fromJson(c.state.toJson());
      expect(saved.seenVersion, '0.35.0');
      final backup = exportBackup(c.state, start);
      expect(backup, isNot(contains('seenVersion')));
      // Restoring a backup leaves this device's value alone.
      expect(await c.restoreBackup(importBackup(backup, start)), isTrue);
      expect(c.state.seenVersion, '0.35.0');
      expect(c.whatsNew.notice, '0.36.0');
      c.dispose();
    });
  });

  group('on screen', () {
    Future<(AppController, VersionPort)> live(
      WidgetTester t, {
      Size size = const Size(430, 1000),
      String version = '0.36.0 (40)',
      String? seen = '0.35.0',
    }) async {
      setScreen(t, size);
      final (c, port) = await started(version, seen: seen);
      await c.commit((draft, _) => draft.churchName = 'Grace Community Church');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      return (c, port);
    }

    Finder notice() => find.byKey(const ValueKey('whats-new-notice'));

    testWidgets('shows on Live while standing by (phone)', (t) async {
      await live(t);
      expect(notice(), findsOneWidget);
      expect(find.text('Updated to 0.36.0'), findsOneWidget);
      expect(find.text('See what’s new'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(TimerApp),
        matchesGoldenFile('../goldens/whats-new-notice-live-phone.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('shows on a 1366 × 768 Live', (t) async {
      await live(t, size: const Size(1366, 768));
      expect(notice(), findsOneWidget);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(TimerApp),
        matchesGoldenFile('../goldens/whats-new-notice-live-1366.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a new install shows nothing', (t) async {
      final (c, _) = await live(t, seen: null);
      expect(notice(), findsNothing);
      expect(c.state.seenVersion, '0.36.0');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Dismiss marks it seen', (t) async {
      final (c, _) = await live(t);
      await t.tap(find.byKey(const ValueKey('whats-new-dismiss')));
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      expect(c.state.seenVersion, '0.36.0');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('See what’s new opens the notes at the top and marks seen', (
      t,
    ) async {
      final (c, _) = await live(t);
      await t.tap(find.byKey(const ValueKey('whats-new-see')));
      await t.pumpAndSettle();
      expect(find.byType(WhatsNewPage), findsOneWidget);
      expect(c.state.seenVersion, '0.36.0');
      // The newest release is first, at the top of the page.
      final releases = parseChangelog(File('CHANGELOG.md').readAsStringSync());
      final first = t.getTopLeft(find.text(releases[0].heading)).dy;
      expect(first, lessThan(200));
      expect(t.takeException(), isNull);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a version with no section still reads fine', (t) async {
      await live(t, version: '0.99.0');
      await t.tap(find.byKey(const ValueKey('whats-new-see')));
      await t.pumpAndSettle();
      expect(find.text('Updated to 0.99.0'), findsNothing);
      // The latest section is the first one shown.
      final releases = parseChangelog(File('CHANGELOG.md').readAsStringSync());
      expect(find.text(releases[0].heading), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('asks for the Settings PIN first when one is set', (t) async {
      final (c, _) = await live(t);
      await t.runAsync(() => c.setSettingsPin('2468'));
      c.lockSettings();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('whats-new-see')));
      await t.pumpAndSettle();
      expect(find.byType(WhatsNewPage), findsNothing);
      expect(find.byKey(const ValueKey('pin-field')), findsOneWidget);
      expect(c.state.seenVersion, '0.35.0');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('is kept while a service runs and shown after it', (t) async {
      final (c, _) = await live(t);
      await c.act('load', value: timeline());
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      await c.act('start');
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      expect(c.state.seenVersion, '0.35.0');
      await c.act('end');
      await t.pumpAndSettle();
      expect(notice(), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('is not shown in a rehearsal', (t) async {
      final (c, _) = await live(t);
      await c.act('load', value: timeline());
      await c.act('rate', value: 5);
      await c.act('start');
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('is not shown while joined to another device', (t) async {
      final (c, _) = await live(t);
      c.pairing.mode = 'operator';
      c.notifyChanged();
      await t.pumpAndSettle();
      expect(notice(), findsNothing);
      c.pairing.mode = 'off';
      c.notifyChanged();
      await t.pumpAndSettle();
      expect(c.state.seenVersion, '0.35.0');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('waits behind the update notice, then shows', (t) async {
      setScreen(t);
      final port = UpdatePort(release('v0.37.0'));
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((draft, _) {
        draft.seenVersion = '0.31.0';
        draft.autoUpdate
          ..enabled = true
          ..checkedWall = start.wall
          ..found = '0.37.0';
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('update-available-notice')),
        findsOneWidget,
      );
      expect(notice(), findsNothing);
      await t.tap(find.byKey(const ValueKey('update-notice-later')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('update-available-notice')),
        findsNothing,
      );
      expect(notice(), findsOneWidget);
      expect(find.text('Updated to 0.32.0'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}
