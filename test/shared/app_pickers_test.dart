import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_pickers.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// Friday 20 November 2026, 09:30.
final friday = DateTime(2026, 11, 20, 9, 30);

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  group('dates are written day first', () {
    const words = DayFirstLocalizations();
    test('over the calendar and in full', () {
      expect(words.formatMediumDate(friday), 'Fri 20 Nov 2026');
      expect(words.formatFullDate(friday), 'Friday 20 November 2026');
      expect(words.formatShortMonthDay(friday), '20 Nov');
      expect(words.formatShortDate(friday), '20 Nov 2026');
      expect(words.formatMonthYear(friday), 'November 2026');
    });
    test('when typed: dd/mm/yyyy', () {
      expect(words.formatCompactDate(DateTime(2026, 3, 4)), '04/03/2026');
      expect(words.parseCompactDate('4/3/2026'), DateTime(2026, 3, 4));
      expect(words.parseCompactDate('20/11/2026'), DateTime(2026, 11, 20));
      // Month first, as an American would write it, is refused.
      expect(words.parseCompactDate('11/20/2026'), isNull);
      expect(words.parseCompactDate('31/02/2026'), isNull);
      expect(words.parseCompactDate('20/11/26'), isNull);
      expect(words.parseCompactDate('20-11-2026'), isNull);
      expect(words.parseCompactDate(null), isNull);
      expect(words.dateHelpText, 'dd/mm/yyyy');
    });
  });

  /// The app on Live with a program loaded, on [friday].
  Future<(AppController, HomeState)> app(
    WidgetTester t, {
    required bool desktop,
    Size? size,
    String clock = '24h',
    String theme = 'midnight_lime',
  }) async {
    desktopWording = desktop;
    setScreen(
      t,
      size ?? (desktop ? const Size(1366, 768) : const Size(430, 900)),
    );
    final port = desktop ? DesktopFakePort() : FakePort();
    port.at = Stamp(100000, friday.millisecondsSinceEpoch, 'boot-1');
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.clockFormat = clock;
      draft.themeId = theme;
    });
    await c.act('load', value: c.state.templates.first);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, t.state<HomeState>(find.byType(Home, skipOffstage: false)));
  }

  /// The dialog's colour: the theme's surface, not Material's tint.
  Color? dialogColour(WidgetTester t) => t
      .widget<Material>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      )
      .color;

  Future<void> openServiceDate(WidgetTester t, HomeState home) async {
    home.printServiceSheet(home.c.state.templates.first);
    await t.pumpAndSettle();
    await t.tap(find.text('Service date'));
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  }

  for (final desktop in [false, true]) {
    final where = desktop ? 'on a computer' : 'on a phone';
    testWidgets('Service date is day first in the app\'s colours $where', (
      t,
    ) async {
      final (c, home) = await app(t, desktop: desktop);
      await openServiceDate(t, home);
      expect(find.text('Fri 20 Nov 2026'), findsOneWidget);
      expect(find.text('Fri, Nov 20'), findsNothing);
      expect(find.text('Service date'), findsWidgets);
      final colors = appColors(t.element(find.byType(DatePickerDialog)));
      expect(dialogColour(t), colors.surface);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          desktop
              ? '../goldens/desktop-date-picker.png'
              : '../goldens/date-picker-phone.png',
        ),
      );
      // Choosing a day writes it on the sheet.
      await t.tap(find.text('27'));
      await t.pumpAndSettle();
      expect(find.text('Fri 27 Nov 2026'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.textContaining('27'), findsWidgets);
      expect(c.state.session.active, isFalse);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a short window lays the calendar on its side and the date '
      'still fits', (t) async {
    for (final (desktop, size) in const [
      (true, Size(1200, 600)),
      (false, Size(900, 430)),
    ]) {
      final (_, home) = await app(t, desktop: desktop, size: size);
      await openServiceDate(t, home);
      expect(t.takeException(), isNull, reason: '$size');
      final header = find.text('Fri 20 Nov 2026');
      expect(header, findsOneWidget, reason: '$size');
      // Two lines at most, nothing cut short.
      final paragraph = t.renderObject<RenderParagraph>(
        find.descendant(of: header, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: '$size');
      if (desktop) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/desktop-date-picker-short.png'),
        );
      }
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a typed service date is dd/mm/yyyy', (t) async {
    final (_, home) = await app(t, desktop: true);
    await openServiceDate(t, home);
    await t.tap(find.byIcon(Icons.edit_outlined));
    await t.pumpAndSettle();
    expect(find.text('20/11/2026'), findsOneWidget);
    expect(find.text('dd/mm/yyyy'), findsWidgets);
    await t.enterText(find.byType(TextField), '04/12/2026');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Paper & Ink: the light theme\'s calendar', (t) async {
    final (_, home) = await app(t, desktop: true, theme: 'paper_ink');
    await openServiceDate(t, home);
    final colors = appColors(t.element(find.byType(DatePickerDialog)));
    expect(colors.light, isTrue);
    expect(dialogColour(t), colors.surface);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-date-picker-light.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the pre-service time is 24-hour on a phone', (t) async {
    final (c, _) = await app(t, desktop: false);
    final set = find.text('Set time');
    await t.ensureVisible(set);
    await t.pumpAndSettle();
    await t.tap(set);
    await t.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('Service starts at'), findsOneWidget);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    // The hour after now, and the dial's hours to 23 (it is drawn, not
    // text).
    expect(find.text('10'), findsWidgets);
    expect(
      t
          .widget<MediaQuery>(
            find
                .ancestor(
                  of: find.byType(TimePickerDialog),
                  matching: find.byType(MediaQuery),
                )
                .first,
          )
          .data
          .alwaysUse24HourFormat,
      isTrue,
    );
    expect(
      dialogColour(t),
      appColors(t.element(find.byType(TimePickerDialog))).surface,
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/time-picker-phone.png'),
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.startsAtWall, isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the pre-service time follows a 12-hour clock format', (t) async {
    await app(t, desktop: false, clock: '12h');
    final set = find.text('Set time');
    await t.ensureVisible(set);
    await t.pumpAndSettle();
    await t.tap(set);
    await t.pumpAndSettle();
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('on a computer the pre-service time is typed, 24-hour', (
    t,
  ) async {
    final (c, home) = await app(t, desktop: true);
    home.pickServiceStart();
    await t.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    // Fields to type into, starting at the next hour.
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    expect(find.text('10'), findsWidgets);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-time-picker.png'),
    );
    await t.enterText(fields.first, '18');
    await t.enterText(fields.last, '45');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    if (find.byType(TimePickerDialog).evaluate().isNotEmpty) {
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
    }
    final at = DateTime.fromMillisecondsSinceEpoch(
      c.state.session.startsAtWall!,
    );
    expect((at.hour, at.minute), (18, 45));
    expect(at.day, 20);
    await t.pumpWidget(const SizedBox());
  });

  test('no picker call bypasses the app\'s own', () {
    // Every date and time picker goes through lib/shared/app_pickers.dart,
    // so none is month first, 12-hour against the setting, or tinted.
    final hits = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('app_pickers.dart')) continue;
      final text = file.readAsStringSync();
      for (final call in [
        'showDatePicker(',
        'showTimePicker(',
        'showDateRangePicker(',
      ]) {
        if (text.contains(call)) hits.add('${file.path}: $call');
      }
    }
    expect(hits, isEmpty);
  });
}
