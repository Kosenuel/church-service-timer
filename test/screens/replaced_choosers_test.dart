import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lyrics/lyrics_page_test.dart' show openLyrics, settle;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../windows/second_screen_live_test.dart' show SecondPort;

class _Port extends SecondPort {
  @override
  Future<String?> loadPairing() async => jsonEncode({
    'version': 1,
    'hostId': 'host',
    'port': 0,
    'devices': [
      SavedPairDevice(
        'tab',
        'Stage tablet',
        'stage',
        pairRandom(32),
        lastSeen: DateTime(2026, 11, 22, 10, 30).millisecondsSinceEpoch,
      ).toJson(),
    ],
    'client': null,
  });
}

/// The old layout choosers and the Slides page's Send to boxes now show
/// the screen's group, with the way to the Screens panel.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  group('the Slides page', () {
    testWidgets('says which groups show slides', (t) async {
      final c = await openLyrics(t, size: const Size(1920, 1080));
      c.lyrics.selectedId = 'amazing';
      c.lyrics.show('amazing', 0);
      await settle(t);
      expect(find.byKey(const ValueKey('lyrics-send-second')), findsNothing);
      // The Screens row says which groups; opened, it leads to Screens.
      final header = find.byKey(const ValueKey('lyrics-screens-row-header'));
      expect(
        find.descendant(of: header, matching: find.text('Church Auditorium')),
        findsOneWidget,
      );
      await t.ensureVisible(header);
      await t.tap(header);
      await settle(t);
      expect(find.byKey(const ValueKey('lyrics-groups')), findsOneWidget);
      expect(find.text('Church Auditorium'), findsWidgets);
      final line = find.byKey(const ValueKey('lyrics-groups'));
      await t.ensureVisible(line);
      await settle(t);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/screens-lyrics-groups-1920.png'),
      );
      await t.tap(find.byKey(const ValueKey('lyrics-open-screens')));
      await settle(t);
      expect(find.byType(ScreensPage), findsOneWidget);
    });

    testWidgets(
      'with no group showing slides, says so and fixes it in one tap',
      (t) async {
        final c = await openLyrics(t, size: const Size(1920, 1080));
        await t.runAsync(() => c.screens.setShow('room', 'timer'));
        c.lyrics.selectedId = 'amazing';
        await settle(t);
        expect(find.text('No screens are showing slides.'), findsNWidgets(2));
        expect(
          find.byKey(const ValueKey('lyrics-no-groups-top')),
          findsOneWidget,
          reason: 'beside what is on the screens, where the operator looks',
        );
        final fix = find.byKey(const ValueKey('lyrics-fix-groups'));
        await t.ensureVisible(fix);
        await settle(t);
        expect(find.text('Show slides in Church Auditorium'), findsNWidgets(2));
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/screens-lyrics-no-groups-1920.png'),
        );
        await t.runAsync(() async {
          await t.tap(fix);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await settle(t);
        expect(c.screens.groupOf(thisScreenKey).show, 'slides');
        expect(find.text('No screens are showing slides.'), findsNothing);
      },
    );

    testWidgets('a phone at text 1.6 fits the new line', (t) async {
      final c = await openLyrics(
        t,
        size: const Size(360, 780),
        desktop: false,
        textScale: 1.6,
      );
      await t.runAsync(() => c.screens.setShow('room', 'timer'));
      c.lyrics.selectedId = 'amazing';
      await settle(t);
      expect(t.takeException(), isNull);
    });
  });

  group('Settings › Screens & devices', () {
    Future<AppController> settings(WidgetTester t, Size size) async {
      setScreen(t, size);
      desktopWording = true;
      late AppController c;
      await t.runAsync(() async {
        c = AppController(_Port());
        await c.initialize(startTicker: false);
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings').first);
      await t.pumpAndSettle();
      final row = find.text('Screens & devices');
      await t.ensureVisible(row.first);
      await t.pumpAndSettle();
      await t.tap(row.first);
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('the second screen shows its group, not its own tiles', (
      t,
    ) async {
      await settings(t, const Size(1366, 768));
      expect(
        find.byKey(const ValueKey('second-screen-layout-timer')),
        findsNothing,
      );
      final note = find.byKey(const ValueKey('screen-group-note-this'));
      await t.ensureVisible(note);
      await t.pumpAndSettle();
      expect(
        find.textContaining('shows Slides', findRichText: true),
        findsWidgets,
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/screens-settings-second-screen-1366.png'),
      );
      await t.tap(find.byKey(const ValueKey('open-screens-this')));
      await t.pumpAndSettle();
      expect(find.byType(ScreensPage), findsOneWidget);
    });

    testWidgets('a paired screen\'s options: its group, and Message group', (
      t,
    ) async {
      final c = await settings(t, const Size(1366, 768));
      final row = find.byKey(const ValueKey('paired-tab'));
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(of: row, matching: find.byTooltip('Device actions')),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Screen options'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('screen-layout-timer')), findsNothing);
      expect(find.text('Message group'), findsOneWidget);
      expect(
        find.textContaining('Shows what Stage shows: Timer only, with cues'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(AlertDialog),
        matchesGoldenFile('../goldens/screens-paired-dialog.png'),
      );
      // Move it to Church Auditorium and save.
      // The name is too long for chips, so the field opens a list.
      await t.tap(find.byKey(const ValueKey('screen-options-group')));
      await t.pumpAndSettle();
      await t.tap(find.text('Church Auditorium').last);
      await t.pumpAndSettle();
      await t.pumpAndSettle();
      expect(
        find.textContaining('Shows what Church Auditorium shows'),
        findsOneWidget,
      );
      await t.runAsync(() async {
        await t.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(find.textContaining('Could not save'), findsNothing);
      expect(c.screens.groupOf('pair:tab').name, 'Church Auditorium');
    });
  });

  testWidgets('Choose display: the stage simulator shows its group', (t) async {
    setScreen(t, const Size(430, 932));
    late AppController c;
    await t.runAsync(() async {
      c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.setSimulatorKind('stage');
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('header-connection')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('simulator-layout-next')), findsNothing);
    expect(
      find.byKey(const ValueKey('screen-group-note-this')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
