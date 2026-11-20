import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_preview.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The automatic warning editor, opened from Settings › Warnings & alerts:
/// two columns in a wide window, one in a narrower one, and the whole
/// screen on a phone.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  /// The warnings in these tests: one that scrolls once, one that holds
  /// still, and one at 00:00.
  final rules = [
    const WarningRule(120, TextLayout('2 MIN LEFT'), destination: 'stage'),
    const WarningRule(
      30,
      TextLayout('PLEASE WRAP UP', bold: true),
      destination: 'stage',
      scrollOnce: true,
    ),
    const WarningRule(
      0,
      TextLayout('STOP', bold: true, effect: 'static'),
      destination: 'operator',
    ),
  ];

  Future<void> frames(WidgetTester t, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app on Warnings & alerts at [size]: a computer from 1200 wide.
  Future<AppController> warnings(
    WidgetTester t,
    Size size, {
    bool stage = false,
    double textScale = 1,
  }) async {
    setScreen(t, size);
    if (textScale != 1) {
      t.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final desktop = size.width >= 1200;
    desktopWording = desktop;
    final c = AppController(desktop ? DesktopFakePort() : FakePort());
    await c.initialize(startTicker: false);
    if (desktop) {
      await c.commit(
        (draft, _) => draft.appearance = draft.appearance.copyWith(
          desktopLayout: 'three_panes',
        ),
      );
    }
    await c.setSharedWarnings(rules);
    if (stage) await c.setSimulatorKind('stage');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final tab = find.byKey(const ValueKey('desktop-tab-3'));
    if (tab.evaluate().isNotEmpty) {
      await t.tap(tab);
    } else if (find.byType(NavigationDestination).evaluate().isNotEmpty) {
      await t.tap(find.byType(NavigationDestination).at(3));
    } else {
      await t.tap(find.text('Settings').first);
    }
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Warnings & alerts'));
    await t.pumpAndSettle();
    await t.tap(find.text('Warnings & alerts'));
    await t.pumpAndSettle();
    return c;
  }

  /// Opens the warning at [index] in the list.
  Future<void> open(WidgetTester t, int index) async {
    final card = find.byKey(ValueKey('warning-rule-$index'));
    await t.ensureVisible(card);
    await t.pumpAndSettle();
    await t.tap(card);
    await frames(t);
    expect(find.byType(WarningEditor), findsOneWidget);
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/warning-editor-$name.png'),
    );
  }

  Finder scrollable(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Scrollable),
  );

  /// Chooses [minutes]:[seconds] in the time picker that is open.
  Future<void> pick(WidgetTester t, int minutes, int seconds) async {
    for (final (i, value) in [minutes, seconds].indexed) {
      await t.tapAt(t.getCenter(find.byType(CupertinoPicker).at(i)));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '$value');
      await t.tap(find.text('Use value'));
      await t.pumpAndSettle();
    }
    final label =
        'Use ${'$minutes'.padLeft(2, '0')}:${'$seconds'.padLeft(2, '0')}';
    await t.tap(find.text(label));
    await frames(t);
  }

  Finder inEditor(Finder f) =>
      find.descendant(of: find.byType(WarningEditor), matching: f);

  Text textOf(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key)));

  testWidgets('a wide window has two columns that fit without scrolling', (
    t,
  ) async {
    await warnings(t, const Size(1366, 768));
    await open(t, 1);
    expect(find.byKey(const ValueKey('warning-editor-two-columns')), findsOne);
    expect(find.text('Edit warning'), findsOne);
    for (final label in [
      'WHEN',
      'WHAT IT SHOWS',
      'WHERE',
      'HOW LONG',
      'ON OR OFF',
    ]) {
      expect(find.text(label), findsOne, reason: label);
    }
    // WHEN and WHAT IT SHOWS on the left, the rest on the right.
    final left = t.getTopLeft(find.text('WHEN')).dx;
    expect(t.getTopLeft(find.text('WHAT IT SHOWS')).dx, left);
    for (final label in ['WHERE', 'HOW LONG', 'ON OR OFF']) {
      expect(t.getTopLeft(find.text(label)).dx, greaterThan(left + 300));
    }
    expect(inEditor(find.text('00:30')), findsOne);
    expect(find.text('left'), findsOne);
    expect(find.text('Change'), findsOne);
    expect(
      find.text(
        'Fires once in each segment when the countdown reaches this time, never as a segment starts.',
      ),
      findsOne,
    );
    // Amber under a minute, as on the list's card.
    final time = t.widget<Text>(inEditor(find.text('00:30')));
    final colors = appColors(t.element(inEditor(find.text('00:30'))));
    expect(time.style!.color, colors.warning);
    // The preview plays by itself: no Play preview.
    expect(find.byType(CuePreviewSwitch), findsOne);
    expect(find.text('Play preview'), findsNothing);
    expect(textOf(t, 'warning-text').data, 'PLEASE WRAP UP');
    expect(
      textOf(t, 'warning-look').data,
      'Bold · Scrolling · I-Proton Matrix',
    );
    expect(find.text('Edit text and style'), findsOne);
    expect(inEditor(find.text('Operator only')), findsOne);
    expect(inEditor(find.text('Operator and stage')), findsOne);
    expect(find.text('Stays up for'), findsOne);
    expect(find.text('Scroll once, then back to the timer'), findsOne);
    expect(find.text('The timer keeps running underneath.'), findsOne);
    expect(find.text('Warning on'), findsOne);
    expect(find.text('Fires in every service and rehearsal.'), findsOne);
    expect(find.text('Delete warning'), findsOne);
    expect(find.text('Cancel'), findsOne);
    expect(find.text('Save warning'), findsOne);
    // Delete at the bottom left, Save at the right.
    expect(
      t.getCenter(find.text('Delete warning')).dx,
      lessThan(t.getCenter(find.text('Cancel')).dx),
    );
    expect(
      t.getCenter(find.text('Delete warning')).dy,
      moreOrLessEquals(t.getCenter(find.text('Save warning')).dy, epsilon: 1),
    );
    final scroll = t.state<ScrollableState>(
      scrollable('warning-editor-two-columns'),
    );
    expect(scroll.position.maxScrollExtent, 0);
    await shot(t, 'desktop-1366');
  });

  testWidgets('the stage screen preview fits a wide window too', (t) async {
    await warnings(t, const Size(1366, 768), stage: true);
    await open(t, 1);
    expect(find.byKey(const ValueKey('cue-stage-preview')), findsOne);
    final scroll = t.state<ScrollableState>(
      scrollable('warning-editor-two-columns'),
    );
    expect(scroll.position.maxScrollExtent, 0);
    await frames(t, 12);
    await shot(t, 'desktop-1366-stage-screen');
    // The text editor starts on the preview chosen here.
    await t.tap(find.text('LED sign'));
    await frames(t);
    await t.tap(find.text('Edit text and style'));
    await frames(t);
    expect(find.byType(TextComposer), findsOne);
    expect(find.byKey(const ValueKey('cue-stage-preview')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a full HD window has two columns that fit', (t) async {
    await warnings(t, const Size(1920, 1080));
    await open(t, 1);
    expect(find.byKey(const ValueKey('warning-editor-two-columns')), findsOne);
    final scroll = t.state<ScrollableState>(
      scrollable('warning-editor-two-columns'),
    );
    expect(scroll.position.maxScrollExtent, 0);
    await shot(t, 'desktop-1920');
  });

  testWidgets('a narrower window has one column in the same order', (t) async {
    await warnings(t, const Size(900, 900));
    await open(t, 1);
    expect(find.byKey(const ValueKey('warning-editor')), findsOne);
    expect(
      find.byKey(const ValueKey('warning-editor-two-columns')),
      findsNothing,
    );
    final x = t.getTopLeft(find.text('WHEN')).dx;
    var y = 0.0;
    for (final label in [
      'WHEN',
      'WHAT IT SHOWS',
      'WHERE',
      'HOW LONG',
      'ON OR OFF',
    ]) {
      final at = t.getTopLeft(find.text(label));
      expect(at.dx, x, reason: label);
      expect(at.dy, greaterThan(y), reason: label);
      y = at.dy;
    }
    expect(
      t.getCenter(find.text('Delete warning')).dx,
      lessThan(t.getCenter(find.text('Save warning')).dx),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('a phone has the whole screen with Save in the top bar', (
    t,
  ) async {
    await warnings(t, const Size(390, 844));
    await open(t, 1);
    expect(find.byKey(const ValueKey('warning-editor-full-screen')), findsOne);
    final bar = find.byType(AppBar).last;
    expect(
      find.descendant(of: bar, matching: find.text('Edit warning')),
      findsOne,
    );
    expect(find.descendant(of: bar, matching: find.text('Save')), findsOne);
    expect(find.byTooltip('Cancel'), findsOne);
    expect(find.text('Save warning'), findsNothing);
    await shot(t, 'phone');
    await t.drag(
      scrollable('warning-editor-full-screen'),
      const Offset(0, -3000),
    );
    await frames(t);
    // Delete is at the end of the content.
    expect(find.text('Delete warning'), findsOne);
    expect(
      t.getTopLeft(find.text('Delete warning')).dy,
      greaterThan(t.getTopLeft(find.text('Warning on')).dy),
    );
    await shot(t, 'phone-end');
    // ✕ leaves without saving.
    await t.tap(find.byTooltip('Cancel'));
    await frames(t);
    expect(find.byType(WarningEditor), findsNothing);
  });

  testWidgets('a small phone with large text does not overflow', (t) async {
    await warnings(t, const Size(320, 568), textScale: 1.6);
    await open(t, 1);
    expect(t.takeException(), isNull);
    // The pencil stands alone, and the preview's choices stay on one line.
    expect(find.text('Change'), findsNothing);
    expect(
      t.getSize(find.text('Stage screen')).height,
      t.getSize(find.text('LED sign')).height,
    );
    await shot(t, 'phone-320-large-text');
    await t.drag(
      scrollable('warning-editor-full-screen'),
      const Offset(0, -4000),
    );
    await frames(t);
    expect(find.text('Delete warning'), findsOne);
    expect(t.takeException(), isNull);
  });

  testWidgets('a time another warning uses is caught before Save', (t) async {
    final c = await warnings(t, const Size(390, 844));
    await t.tap(find.text('Add'));
    await frames(t);
    expect(find.text('New warning'), findsOne);
    expect(find.text('Delete warning'), findsNothing);
    await t.tap(find.byKey(const ValueKey('warning-time')));
    await t.pumpAndSettle();
    await pick(t, 2, 0);
    expect(inEditor(find.text('02:00')), findsOne);
    expect(
      find.text(
        'Another warning already fires at 02:00. Choose a different time.',
      ),
      findsOne,
    );
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('warning-save')))
          .onPressed,
      isNull,
    );
    await shot(t, 'phone-clash');
    // Another time clears it, and Save adds the warning.
    await t.tap(find.byKey(const ValueKey('warning-time')));
    await t.pumpAndSettle();
    await pick(t, 1, 30);
    expect(find.byKey(const ValueKey('warning-time-clash')), findsNothing);
    await t.tap(find.byKey(const ValueKey('warning-save')));
    await frames(t);
    expect(find.byType(WarningEditor), findsNothing);
    expect(c.state.defaults.warnings.map((w) => w.seconds), [120, 30, 0, 90]);
  });

  testWidgets('Scroll once is only for scrolling text and sets the time', (
    t,
  ) async {
    final c = await warnings(t, const Size(1366, 768));
    await open(t, 1);
    expect(find.byKey(const ValueKey('warning-scroll-once')), findsOne);
    expect(textOf(t, 'warning-stays-up-value').data, startsWith('about '));
    expect(
      find.text('Set by one scroll. Turn off Scroll once to choose a time.'),
      findsOne,
    );
    final staysUp = find.byKey(const ValueKey('warning-stays-up'));
    expect(t.widget<InkWell>(staysUp).onTap, isNull);
    // Off, the time is chosen again.
    await t.tap(find.text('Scroll once, then back to the timer'));
    await frames(t, 2);
    expect(textOf(t, 'warning-stays-up-value').data, '8 s');
    expect(t.widget<InkWell>(staysUp).onTap, isNotNull);
    await t.tap(staysUp);
    await t.pumpAndSettle();
    expect(find.text('Stays up for'), findsNWidgets(2));
    await pick(t, 0, 12);
    expect(textOf(t, 'warning-stays-up-value').data, '12 s');
    await t.tap(find.text('Save warning'));
    await frames(t);
    final saved = c.state.defaults.warnings[1];
    expect(saved.scrollOnce, isFalse);
    expect(saved.durationSeconds, 12);
    expect(saved.cue.text, 'PLEASE WRAP UP');

    // Text that holds still has no Scroll once.
    await open(t, 2);
    expect(find.byKey(const ValueKey('warning-scroll-once')), findsNothing);
    expect(t.widget<InkWell>(staysUp).onTap, isNotNull);
    // Red at 00:00, and the stage keeps the timer for Operator only.
    final time = t.widget<Text>(inEditor(find.text('00:00')));
    expect(time.style!.color, appColors(t.element(staysUp)).error);
    expect(find.byKey(const ValueKey('warning-operator-note')), findsOne);
    expect(t.takeException(), isNull);
  });

  testWidgets('Where and On or off are saved with the warning', (t) async {
    final c = await warnings(t, const Size(1366, 768));
    await open(t, 0);
    await t.tap(find.byKey(const ValueKey('warning-where-operator')));
    await frames(t, 2);
    expect(find.byKey(const ValueKey('warning-operator-note')), findsOne);
    await t.tap(find.byKey(const ValueKey('warning-enabled')));
    await frames(t, 2);
    expect(find.text('Warning off'), findsOne);
    expect(find.text('Kept in the list but never fires.'), findsOne);
    // Cancel keeps it as it was.
    await t.tap(find.text('Cancel'));
    await frames(t);
    expect(c.state.defaults.warnings.first.enabled, isTrue);
    expect(c.state.defaults.warnings.first.destination, 'stage');

    await open(t, 0);
    await t.tap(find.byKey(const ValueKey('warning-where-operator')));
    await t.tap(find.byKey(const ValueKey('warning-enabled')));
    await frames(t, 2);
    await t.tap(find.text('Save warning'));
    await frames(t);
    final saved = c.state.defaults.warnings.first;
    expect(saved.enabled, isFalse);
    expect(saved.destination, 'operator');
    expect(saved.seconds, 120);
    // The list's switch shows the same, and the JSON is the same shape.
    final card = find.byKey(const ValueKey('warning-rule-0'));
    expect(
      t
          .widget<Switch>(
            find.descendant(of: card, matching: find.byType(Switch)),
          )
          .value,
      isFalse,
    );
    expect(saved.toJson().keys, rules.first.toJson().keys);
    // On again, as the card's switch would.
    await open(t, 0);
    expect(find.text('Warning off'), findsOne);
    await t.tap(find.byKey(const ValueKey('warning-enabled')));
    await frames(t, 2);
    await t.tap(find.text('Save warning'));
    await frames(t);
    expect(c.state.defaults.warnings.first.enabled, isTrue);
  });

  testWidgets('Delete warning asks first, then deletes it', (t) async {
    final c = await warnings(t, const Size(1366, 768));
    await open(t, 1);
    await t.tap(find.byKey(const ValueKey('warning-delete')));
    await frames(t);
    expect(find.text('Delete warning for all services?'), findsOne);
    // Cancel keeps it, and the editor.
    await t.tap(find.text('Cancel').last);
    await frames(t);
    expect(c.state.defaults.warnings, hasLength(3));
    expect(find.byType(WarningEditor), findsOne);
    await t.tap(find.byKey(const ValueKey('warning-delete')));
    await frames(t);
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete warning'),
      ),
    );
    await frames(t);
    expect(find.byType(WarningEditor), findsNothing);
    expect(c.state.defaults.warnings.map((w) => w.seconds), [120, 0]);
    expect(t.takeException(), isNull);
  });

  testWidgets('Lock controls keeps Settings, and so the editor, out of reach', (
    t,
  ) async {
    setScreen(t, const Size(390, 844));
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    t.state<HomeState>(find.byType(Home)).lockControls();
    await t.pumpAndSettle();
    await t.tap(find.byType(NavigationDestination).at(3));
    await t.pumpAndSettle();
    expect(find.text('Warnings & alerts'), findsNothing);
    expect(find.byType(WarningEditor), findsNothing);
    expect(t.takeException(), isNull);
  });
}
