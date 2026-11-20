import 'dart:ui' show PointerDeviceKind;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/date_range_dialog.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort, sunday;
import '../support/widget_setup.dart';

/// The calendar grid that filters reports by date in a wide window.
void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  final today = DateTime(2026, 11, 20);
  Finder day(int y, int m, int d) => find.byKey(ValueKey('day-$y-$m-$d'));
  Finder month(int y, int m) => find.byKey(ValueKey('month-$y-$m'));
  const apply = ValueKey('date-range-apply');
  const dialog = ValueKey('date-range-dialog');
  bool canApply(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(apply)).onPressed != null;
  String summary(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('date-range-summary'))).data!;

  /// The dialog on its own, over an empty page. The first element is the
  /// result once it closes; the second says whether it has closed.
  Future<List<Object?>> open(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
    DateTime? first,
    DateTime? last,
    DateTimeRange? initial,
    String theme = 'midnight_lime',
    bool highContrast = false,
  }) async {
    setScreen(t, size);
    final result = <Object?>[null, false];
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(
          theme,
          appearance: AppearancePreferences(highContrast: highContrast),
          size: size,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result[0] = await showDateRangeDialog(
                  context,
                  title: 'Filter service dates',
                  firstDate: first ?? DateTime(2026),
                  lastDate: last ?? DateTime(2027, 12, 31),
                  today: today,
                  initial: initial,
                );
                result[1] = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    return result;
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyEvent(key);
    await t.pumpAndSettle();
  }

  testWidgets('two clicks choose a range, and Apply returns it', (t) async {
    final result = await open(t);
    // Last month and this month, side by side.
    expect(month(2026, 10), findsOneWidget);
    expect(month(2026, 11), findsOneWidget);
    expect(
      t.getTopLeft(month(2026, 10)).dx,
      lessThan(t.getTopLeft(month(2026, 11)).dx),
    );
    expect(canApply(t), isFalse);
    expect(summary(t), 'Choose the first day, then the last.');

    await t.tap(day(2026, 11, 3));
    await t.pumpAndSettle();
    expect(canApply(t), isFalse);
    expect(summary(t), 'From 3 November 2026. Choose the last day.');

    await t.tap(day(2026, 11, 16));
    await t.pumpAndSettle();
    expect(canApply(t), isTrue);
    expect(summary(t), '3 November to 16 November 2026');

    await t.tap(find.byKey(apply));
    await t.pumpAndSettle();
    expect(
      result[0],
      DateTimeRange(start: DateTime(2026, 11, 3), end: DateTime(2026, 11, 16)),
    );
  });

  testWidgets('a third click starts again, and an earlier day swaps', (
    t,
  ) async {
    final result = await open(t);
    await t.tap(day(2026, 11, 3));
    await t.tap(day(2026, 11, 16));
    await t.pumpAndSettle();
    await t.tap(day(2026, 11, 10));
    await t.pumpAndSettle();
    expect(canApply(t), isFalse);
    expect(summary(t), 'From 10 November 2026. Choose the last day.');
    // The second click is before the first: the range runs between them.
    await t.tap(day(2026, 10, 28));
    await t.pumpAndSettle();
    expect(summary(t), '28 October to 10 November 2026');
    // One day is a range too.
    await t.tap(day(2026, 11, 8));
    await t.tap(day(2026, 11, 8));
    await t.pumpAndSettle();
    expect(summary(t), '8 November 2026');
    await t.tap(find.byKey(apply));
    await t.pumpAndSettle();
    expect(
      result[0],
      DateTimeRange(start: DateTime(2026, 11, 8), end: DateTime(2026, 11, 8)),
    );
  });

  testWidgets('Cancel and Esc return nothing', (t) async {
    var result = await open(t);
    await t.tap(day(2026, 11, 3));
    await t.tap(day(2026, 11, 16));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(result, [null, true]);

    result = await open(t);
    await press(t, LogicalKeyboardKey.escape);
    expect(find.byKey(dialog), findsNothing);
    expect(result, [null, true]);
  });

  test('the ready-made ranges for a fixed today', () {
    final ranges = {
      for (final (label, range) in dateRangeShortcuts(
        today,
        first: DateTime(2020),
        last: DateTime(2027, 12, 31),
      ))
        label: range,
    };
    expect(ranges.keys, [
      'Last 4 weeks',
      'This month',
      'Last month',
      'This year',
    ]);
    DateTimeRange r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);
    expect(
      ranges['Last 4 weeks'],
      r(DateTime(2026, 10, 24), DateTime(2026, 11, 20)),
    );
    expect(ranges['Last 4 weeks']!.duration.inDays, 27);
    expect(
      ranges['This month'],
      r(DateTime(2026, 11, 1), DateTime(2026, 11, 30)),
    );
    expect(
      ranges['Last month'],
      r(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
    );
    expect(
      ranges['This year'],
      r(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
    );
    // January looks back into the year before.
    final january = dateRangeShortcuts(
      DateTime(2027, 1, 5),
      first: DateTime(2020),
      last: DateTime(2028),
    );
    expect(january[2].$2, r(DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
    // Ranges stop at the bounds, and one wholly outside them is left out.
    final bounded = dateRangeShortcuts(
      today,
      first: DateTime(2026, 11, 10),
      last: DateTime(2026, 11, 25),
    );
    expect(
      [for (final (label, _) in bounded) label],
      ['Last 4 weeks', 'This month', 'This year'],
    );
    expect(bounded[1].$2, r(DateTime(2026, 11, 10), DateTime(2026, 11, 25)));
  });

  testWidgets('a shortcut fills its range; All dates clears the filter', (
    t,
  ) async {
    var result = await open(t);
    await t.tap(find.text('Last month'));
    await t.pumpAndSettle();
    expect(summary(t), '1 October to 31 October 2026');
    expect(canApply(t), isTrue);
    await t.tap(find.text('This year'));
    await t.pumpAndSettle();
    expect(summary(t), '1 January to 31 December 2026');
    await t.tap(find.text('Last 4 weeks'));
    await t.pumpAndSettle();
    expect(summary(t), '24 October to 20 November 2026');
    // The range is in view.
    expect(day(2026, 10, 24), findsOneWidget);
    expect(day(2026, 11, 20), findsOneWidget);
    await t.tap(find.byKey(apply));
    await t.pumpAndSettle();
    expect(
      result[0],
      DateTimeRange(start: DateTime(2026, 10, 24), end: DateTime(2026, 11, 20)),
    );

    result = await open(
      t,
      initial: DateTimeRange(
        start: DateTime(2026, 11, 3),
        end: DateTime(2026, 11, 16),
      ),
    );
    expect(summary(t), '3 November to 16 November 2026');
    await t.tap(find.text('All dates'));
    await t.pumpAndSettle();
    expect(summary(t), 'All dates');
    expect(canApply(t), isTrue);
    await t.tap(find.byKey(apply));
    await t.pumpAndSettle();
    expect(identical(result[0], allDates), isTrue);
  });

  testWidgets('days outside the bounds cannot be chosen', (t) async {
    await open(t, first: DateTime(2026, 10, 10), last: DateTime(2026, 11, 25));
    await t.tap(day(2026, 10, 5));
    await t.pumpAndSettle();
    expect(summary(t), 'Choose the first day, then the last.');
    await t.tap(day(2026, 10, 12));
    await t.tap(day(2026, 11, 28));
    await t.pumpAndSettle();
    expect(summary(t), 'From 12 October 2026. Choose the last day.');
    expect(canApply(t), isFalse);
    // Nor reached with the keyboard: the ring stops at the last day.
    await press(t, LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 12; i++) {
      await press(t, LogicalKeyboardKey.arrowDown);
    }
    await press(t, LogicalKeyboardKey.enter);
    expect(summary(t), '12 October to 25 November 2026');
    // The only two months allowed are showing, so neither arrow works.
    for (final key in const ['month-back', 'month-forward']) {
      expect(t.widget<IconButton>(find.byKey(ValueKey(key))).onPressed, isNull);
    }
  });

  testWidgets('the arrows turn the months', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Next month'));
    await t.pumpAndSettle();
    expect(month(2026, 10), findsNothing);
    expect(month(2026, 11), findsOneWidget);
    expect(month(2026, 12), findsOneWidget);
    await t.tap(find.byTooltip('Previous month'));
    await t.tap(find.byTooltip('Previous month'));
    await t.pumpAndSettle();
    expect(month(2026, 9), findsOneWidget);
    expect(month(2026, 10), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    // A range can run across a turn of the page.
    await t.tap(day(2026, 9, 14));
    await t.tap(find.byTooltip('Next month'));
    await t.tap(find.byTooltip('Next month'));
    await t.pumpAndSettle();
    await t.tap(day(2026, 12, 2));
    await t.pumpAndSettle();
    expect(summary(t), '14 September to 2 December 2026');
  });

  testWidgets('weeks start on the day Flutter\'s picker uses', (t) async {
    await open(t);
    final words = MaterialLocalizations.of(t.element(find.byKey(dialog)));
    // 1 November 2026 is a Sunday.
    final sunday = t.getCenter(day(2026, 11, 1)).dx;
    final monday = t.getCenter(day(2026, 11, 2)).dx;
    final saturday = t.getCenter(day(2026, 11, 7)).dx;
    if (words.firstDayOfWeekIndex == 0) {
      expect(sunday, lessThan(monday));
      expect(saturday - sunday, 6 * 40);
    } else {
      expect(monday, lessThan(sunday));
    }
    // One row for a week, and cells big enough to click.
    expect(t.getCenter(day(2026, 11, 1)).dy, t.getCenter(day(2026, 11, 7)).dy);
    expect(t.getSize(day(2026, 11, 1)).shortestSide, greaterThanOrEqualTo(36));
  });

  testWidgets('the keyboard chooses a range', (t) async {
    final result = await open(t);
    // The first key shows the ring on today; the next ones move it.
    await press(t, LogicalKeyboardKey.arrowLeft);
    await press(t, LogicalKeyboardKey.arrowLeft);
    await press(t, LogicalKeyboardKey.arrowUp);
    await press(t, LogicalKeyboardKey.enter);
    expect(summary(t), 'From 12 November 2026. Choose the last day.');
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.arrowRight);
    await press(t, LogicalKeyboardKey.space);
    expect(summary(t), '12 November to 20 November 2026');
    // Page Up and Page Down move a month and bring it into view.
    await press(t, LogicalKeyboardKey.pageUp);
    await press(t, LogicalKeyboardKey.pageUp);
    expect(month(2026, 9), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(summary(t), 'From 20 September 2026. Choose the last day.');
    await press(t, LogicalKeyboardKey.pageDown);
    await press(t, LogicalKeyboardKey.pageDown);
    await press(t, LogicalKeyboardKey.pageDown);
    expect(month(2026, 12), findsOneWidget);
    await press(t, LogicalKeyboardKey.enter);
    expect(summary(t), '20 September to 20 December 2026');
    // Tab reaches Apply, and Enter presses it.
    for (var i = 0; i < 20 && result[1] == false; i++) {
      await press(t, LogicalKeyboardKey.tab);
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null &&
          find
              .descendant(
                of: find.byKey(apply),
                matching: find.byElementPredicate((e) => e == focused),
              )
              .evaluate()
              .isNotEmpty) {
        await press(t, LogicalKeyboardKey.enter);
      }
    }
    expect(
      result[0],
      DateTimeRange(start: DateTime(2026, 9, 20), end: DateTime(2026, 12, 20)),
    );
  });

  testWidgets('pointing after the first click previews the range', (t) async {
    await open(t);
    await t.tap(day(2026, 11, 3));
    await t.pumpAndSettle();
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(day(2026, 11, 12)));
    await t.pumpAndSettle();
    bool filled(int d) => find
        .descendant(of: day(2026, 11, d), matching: find.byType(DecoratedBox))
        .evaluate()
        .any((e) {
          final box = (e.widget as DecoratedBox).decoration as BoxDecoration;
          return box.shape == BoxShape.rectangle && box.color != null;
        });
    expect(filled(8), isTrue);
    expect(filled(12), isTrue);
    expect(filled(13), isFalse);
    // Nothing is chosen until the click.
    expect(canApply(t), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('one month in a small window, and every theme draws', (t) async {
    for (final size in const [
      Size(1200, 600),
      Size(1366, 768),
      Size(1920, 1080),
      Size(2560, 1440),
      Size(820, 520),
    ]) {
      for (final (theme, contrast) in const [
        ('midnight_lime', false),
        ('morning_sky', false),
        ('paper_ink', false),
        ('midnight_lime', true),
        ('paper_ink', true),
      ]) {
        await open(t, size: size, theme: theme, highContrast: contrast);
        expect(t.takeException(), isNull, reason: '$size $theme');
        final box = t.getRect(
          find
              .descendant(
                of: find.byKey(dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(box.width, lessThanOrEqualTo(900));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(size.height));
        expect((box.center.dx - size.width / 2).abs(), lessThan(1));
        // Two months wherever a wide window has the room for them.
        expect(
          find.byTooltip('Next month').evaluate().length,
          1,
          reason: '$size',
        );
        expect(
          month(2026, 10),
          size.width >= 1200 ? findsOneWidget : findsNothing,
        );
        await t.tap(day(2026, 11, 3));
        await t.tap(day(2026, 11, 16));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$size $theme');
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
      }
    }
  });

  /// The app in a window of [size], with four weekly services saved up
  /// to Sunday 15 November 2026 and Reports open.
  Future<AppController> reports(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
    String theme = 'midnight_lime',
  }) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final base = DateTime(2026, 10, 25, 9).millisecondsSinceEpoch;
    Stamp at(int seconds) =>
        Stamp(100000 + seconds * 1000, base + seconds * 1000, 'boot-1');
    port.at = at(0);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      );
      draft.themeId = theme;
      draft.templates.clear();
      draft.saveTemplate(sunday());
    });
    var seconds = 0;
    for (var n = 0; n < 4; n++) {
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      for (final step in [340 + n * 20, 1330 - n * 60, 2300 + n * 90, 560]) {
        seconds += step;
        port.at = at(seconds);
        await c.tick();
        await c.act('advance');
      }
      seconds += 280;
      port.at = at(seconds);
      await c.tick();
      await c.act('end');
      seconds = (n + 1) * 7 * 86400;
      port.at = at(seconds);
      await c.tick();
    }
    // Friday 20 November.
    port.at = at(26 * 86400);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final reportsTab = find.byKey(const ValueKey('desktop-tab-2'));
    await t.tap(
      reportsTab.evaluate().isEmpty ? find.text('Reports').last : reportsTab,
    );
    await t.pumpAndSettle();
    return c;
  }

  const filter = ValueKey('report-date-filter');

  testWidgets('the reports filter is the calendar grid at full HD', (t) async {
    await reports(t);
    expect(find.byType(ReportListRow), findsNWidgets(4));
    await t.tap(find.byKey(filter));
    await t.pumpAndSettle();
    expect(find.byKey(dialog), findsOneWidget);
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(find.text('Filter service dates'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    await t.tap(day(2026, 11, 1));
    await t.tap(day(2026, 11, 8));
    await t.pumpAndSettle();
    await t.tap(find.byKey(apply));
    await t.pumpAndSettle();
    expect(find.byKey(dialog), findsNothing);
    expect(find.byType(ReportListRow), findsNWidgets(2));
    expect(find.text('1/11 – 8/11'), findsOneWidget);
    // Opened again it shows the range, and All dates clears it.
    await t.tap(find.byKey(filter));
    await t.pumpAndSettle();
    expect(summary(t), '1 November to 8 November 2026');
    await t.tap(find.text('All dates'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(apply));
    await t.pumpAndSettle();
    expect(find.byType(ReportListRow), findsNWidgets(4));
    expect(find.byTooltip('Clear date filter'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a phone keeps the full-screen picker', (t) async {
    desktopWording = false;
    await reports(t, size: const Size(430, 1000));
    await t.tap(find.byKey(filter));
    await t.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(find.byKey(dialog), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('nothing overflows at the smallest desktop size', (t) async {
    await reports(t, size: const Size(1200, 600));
    await t.tap(find.byKey(filter));
    await t.pumpAndSettle();
    expect(find.byKey(dialog), findsOneWidget);
    expect(t.takeException(), isNull);
    final box = t.getRect(
      find
          .descendant(of: find.byKey(dialog), matching: find.byType(Material))
          .first,
    );
    expect(box.top, greaterThanOrEqualTo(0));
    expect(box.bottom, lessThanOrEqualTo(600));
    for (final label in const ['This year', 'Last month', 'Last 4 weeks']) {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: label);
    }
    await t.tap(find.byTooltip('Previous month'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  for (final (theme, name) in const [
    ('midnight_lime', 'desktop-date-range'),
    ('morning_sky', 'desktop-date-range-light'),
  ]) {
    testWidgets('the calendar grid in $theme', (t) async {
      await reports(t, theme: theme);
      await t.tap(find.byKey(filter));
      await t.pumpAndSettle();
      await t.tap(day(2026, 10, 28));
      await t.tap(day(2026, 11, 15));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(TimerApp),
        matchesGoldenFile('../goldens/$name.png'),
      );
    });
  }
}
