import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/whats_new_page.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import '../domain/feature_cases.dart' show epoch, at;
import 'church_profile_and_backup_cases.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class SettingsPort extends FakePort {
  final awakeCalls = <bool>[];
  bool failAwake = false;
  Map<String, dynamic>? backup;
  String? exportedName, exportedContent;
  @override
  Future<void> setKeepScreenAwake(bool enabled) async {
    if (failAwake) throw Exception('Window not available');
    awakeCalls.add(enabled);
  }

  @override
  // A made-up installed version: proves About shows what Android reports.
  Future<String> installedVersion() async => '1.2.3 (45)';
  @override
  Future<Map<String, dynamic>?> pickBackup() async => backup;
  @override
  Future<void> exportFile(String filename, String content) async {
    exportedName = filename;
    exportedContent = content;
  }
}

void main() {
  for (final e in revision07Cases.entries) {
    test(e.key, e.value);
  }
  setUpAll(loadAppFonts);
  // Paper & Ink and the Finish tiles draw the finish photographs.
  setUpAll(FinishTextures.instance.loadAll);
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) =>
      setScreen(t, value);

  Future<AppController> setup(SettingsPort port) async {
    port.at = epoch;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    return c;
  }

  Future<void> settings(WidgetTester t) async {
    await t.tap(find.byType(NavigationDestination).at(4));
    await t.pumpAndSettle();
  }

  test(
    'Source version and launcher name match release metadata; application ID is set',
    () {
      // pubspec "X+N" and appVersion "X (N)" must agree; no edit per release.
      final pubspec = RegExp(
        r'^version: (\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\+(\d+)$',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
      expect(appVersion, '${pubspec.group(1)} (${pubspec.group(2)})');
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="$appName"'),
      );
      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        contains(
          'applicationId = "io.github.immanuelokose.churchservicetimer"',
        ),
      );
    },
  );
  test(
    'Church identity freezes on load and old reports do not change on profile edits',
    () async {
      final c = await setup(SettingsPort());
      await c.commit((a, _) => a.churchName = 'First Church');
      await c.act('load', value: c.state.templates.first);
      await c.commit((a, _) => a.churchName = 'Second Church');
      await c.act('start');
      await c.act('end');
      expect(c.state.reports.last.churchName, 'First Church');
      await c.act('load', value: c.state.templates.first);
      expect(c.state.session.churchName, 'Second Church');
      c.dispose();
    },
  );
  test(
    'Awake setting persists, survives restart, and native failure does not roll back data',
    () async {
      final port = SettingsPort();
      final c = await setup(port);
      // Idle at start: the screen may sleep.
      expect(port.awakeCalls, everyElement(false));
      await c.commit((a, _) => a.screenAwake = 'always');
      expect(port.awakeCalls.last, true);
      await c.commit((a, _) => a.screenAwake = 'never');
      expect(port.awakeCalls.last, false);
      port.failAwake = true;
      expect(await c.commit((a, _) => a.screenAwake = 'always'), true);
      expect(c.deviceSettingsError, isNotNull);
      expect(c.error, isNull);
      port.failAwake = false;
      await c.syncDeviceSettings();
      expect(c.deviceSettingsError, isNull);
      c.dispose();
      final restart = await setup(port);
      expect(restart.state.screenAwake, 'always');
      restart.dispose();
    },
  );
  test(
    'Restore refuses Ready and active services; failed saves preserve data and output',
    () async {
      final port = SettingsPort();
      final c = await setup(port);
      final target = importBackup(
        exportBackup(
          AppState.fresh(epoch)
            ..churchName = 'Restored Church'
            ..themeId = 'warm_ivory',
          epoch,
        ),
        epoch,
      );
      await c.act('load', value: c.state.templates.last);
      expect(await c.restoreBackup(target), false);
      await c.act('start');
      expect(await c.restoreBackup(target), false);
      port.at = at(15);
      await c.act('end');
      final before = jsonEncode(c.state.toJson());
      final pixels = [...c.simulator.pixels];
      port.fail = true;
      expect(await c.restoreBackup(target), false);
      expect(jsonEncode(c.state.toJson()), before);
      expect(c.simulator.pixels, pixels);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.churchName, 'Restored Church');
      expect(c.state.session.phase, 'idle');
      expect(c.themeSelection.value, 'warm_ivory');
      expect(c.simulator.pixels.any((p) => p), false);
      c.dispose();
    },
  );
  test(
    'Unavailable bundled Tinos rasterizer blocks restore without changing saved content',
    () async {
      final c = await setup(SettingsPort());
      final before = jsonEncode(c.state.toJson());
      final target = AppState.fresh(epoch)
        ..stageCues = [const TextLayout('AMEN', font: 'tinos')];
      expect(await c.restoreBackup(target), false);
      expect(jsonEncode(c.state.toJson()), before);
      expect(c.error, contains('Tinos'));
      c.dispose();
    },
  );
  test('All presets maintain readable text and semantic state contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    expect(appPalettes.map((p) => p.id).toSet(), themeIds);
    for (final p in appPalettes) {
      for (final color in [
        p.text,
        p.muted,
        p.accent,
        p.warning,
        p.error,
        p.info,
      ]) {
        expect(
          contrast(color, p.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${p.name}: $color',
        );
      }
    }
  });

  testWidgets(
    'Settings opens grouped display page and shows About author and installed version',
    (t) async {
      size(t);
      final c = await setup(SettingsPort());
      await c.commit((a, _) => a.churchName = 'Grace Community Church');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await settings(t);
      expect(find.text('Display'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/settings-phone.png'),
      );
      await t.tap(find.text('Display settings'));
      await t.pumpAndSettle();
      expect(find.text('At zero'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('About'));
      await t.pumpAndSettle();
      await t.tap(find.text('About'));
      await t.pumpAndSettle();
      expect(find.text('Created by I-Proton'), findsOneWidget);
      expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/about-phone.png'),
      );
      await t.tap(find.byKey(const ValueKey('about-whats-new')));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('What’s new'), findsOneWidget);
      // The newest release in the bundled changelog is shown first.
      final newest = parseChangelog(
        File('CHANGELOG.md').readAsStringSync(),
      ).first.heading;
      expect(find.text(newest), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Church profile saves and displays optional name after restart', (
    t,
  ) async {
    size(t);
    final port = SettingsPort();
    final c = await setup(port);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await settings(t);
    await t.tap(find.text('Church profile'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Grace Chapel');
    await t.tap(find.text('Save church profile'));
    await t.pumpAndSettle();
    expect(c.state.churchName, 'Grace Chapel');
    expect(find.text('Grace Chapel'), findsNWidgets(2));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    final restored = await setup(port);
    expect(restored.state.churchName, 'Grace Chapel');
    restored.dispose();
  });
  testWidgets(
    'Appearance previews immediately, cancels cleanly and saves across restart',
    (t) async {
      size(t);
      final port = SettingsPort();
      final c = await setup(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await settings(t);
      await t.tap(find.text('Appearance'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('theme-warm_ivory')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('theme-warm_ivory')));
      await t.pumpAndSettle();
      expect(c.state.themeId, 'midnight_lime');
      expect(c.themeSelection.value, 'warm_ivory');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/appearance-phone.png'),
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(c.themeSelection.value, 'midnight_lime');
      await t.tap(find.text('Appearance'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('theme-slate_teal')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('theme-slate_teal')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save appearance'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save appearance'));
      await t.pumpAndSettle();
      expect(c.state.themeId, 'slate_teal');
      expect(c.themeSelection.value, 'slate_teal');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = await setup(port);
      expect(restored.themeSelection.value, 'slate_teal');
      restored.dispose();
    },
  );
  testWidgets(
    'Backup UI exports saved setup and requires confirmation before replacement',
    (t) async {
      size(t);
      final port = SettingsPort();
      final c = await setup(port);
      final target = AppState.fresh(epoch)..churchName = 'Restored Chapel';
      port.backup = {
        'name': 'setup.json',
        'content': exportBackup(target, epoch),
      };
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await settings(t);
      await t.ensureVisible(find.text('Backup & restore'));
      await t.pumpAndSettle();
      await t.tap(find.text('Backup & restore'));
      await t.pumpAndSettle();
      await t.tap(find.text('Export backup'));
      await t.pumpAndSettle();
      // No sign passwords are saved, so the option is unavailable.
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('include-passwords')),
            )
            .onChanged,
        isNull,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Export'));
      await t.pumpAndSettle();
      expect(port.exportedName, startsWith('Church-Service-Timer-backup-'));
      expect(jsonDecode(port.exportedContent!)['schemaVersion'], 7);
      expect(importBackup(port.exportedContent!, epoch).churchName, '');
      await t.ensureVisible(find.text('Choose backup to restore'));
      await t.tap(find.text('Choose backup to restore'));
      await t.pumpAndSettle();
      expect(c.state.churchName, '');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.churchName, '');
      await t.tap(find.text('Choose backup to restore'));
      await t.pumpAndSettle();
      await t.tap(find.text('Restore and replace'));
      await t.pumpAndSettle();
      expect(c.state.churchName, 'Restored Chapel');
      expect(c.state.session.phase, 'idle');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final p in appPalettes) {
    testWidgets(
      '${p.name} renders Live, Templates and Reports with matching colors',
      (t) async {
        size(t);
        final port = SettingsPort();
        final c = await setup(port);
        await c.commit((a, _) {
          a.themeId = p.id;
          a.churchName = 'Grace Community Church';
        });
        await c.act('load', value: c.state.templates.first);
        await c.act('start');
        await t.pumpWidget(TimerApp(controller: c));
        await t.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/theme-${p.id}.png'),
        );
        expect(appColors(t.element(find.byType(SegmentGauge))).id, p.id);
        await t.tap(find.byType(NavigationDestination).at(1));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        port.at = at(60);
        await c.act('end');
        await t.tap(find.byType(NavigationDestination).at(3));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Settings and profile fit a narrow screen with enlarged text', (
    t,
  ) async {
    size(t, const Size(320, 1100));
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await setup(SettingsPort());
    await c.commit((a, _) {
      a.themeId = 'warm_ivory';
      a.churchName = 'Grace Community Church International';
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await settings(t);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Church profile'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
