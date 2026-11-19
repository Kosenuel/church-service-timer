import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort, sunday;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// Reports, Programs and what opens from Live, in a wide desktop window:
/// panes beside each other and centred dialogs, not stretched phone pages.
void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull, reason: name);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-$name.png'),
    );
  }

  Future<void> tab(WidgetTester t, int i) async {
    await t.tap(find.byKey(ValueKey('desktop-tab-$i')));
    await t.pumpAndSettle();
  }

  Future<void> menu(WidgetTester t, String tooltip, String item) async {
    await t.tap(find.byTooltip(tooltip));
    await t.pumpAndSettle();
    await t.tap(find.textContaining(item).last);
    await t.pumpAndSettle();
  }

  const sheet = ValueKey('wide-sheet-dialog');
  const pageDialog = ValueKey('wide-page-dialog');

  /// A dialog of sensible width, centred and wholly inside the window.
  void expectDialog(WidgetTester t, Key key) {
    final box = t.getRect(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Material))
          .first,
    );
    final window = t.view.physicalSize;
    expect(box.width, inInclusiveRange(420, 600));
    expect(box.top, greaterThanOrEqualTo(0));
    expect(box.bottom, lessThanOrEqualTo(window.height));
    expect((box.center.dx - window.width / 2).abs(), lessThan(1));
  }

  Future<(AppController, DesktopFakePort)> app(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
    bool run = false,
    int services = 4,
  }) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      );
      draft.templates.clear();
      draft.saveTemplate(sunday());
      draft.saveTemplate(
        Timeline('Midweek Prayer', const [
          Segment('Welcome', 5),
          Segment('Prayer', 30),
          Segment('Word', 20),
          Segment('Closing', 5),
        ], DisplaySettings()),
      );
    });
    var at = 0;
    for (var n = 0; n < services; n++) {
      await c.act(
        'load',
        value: c.state.templates.firstWhere((p) => p.name == 'Sunday Service'),
      );
      await c.act('start');
      for (final seconds in [340 + n * 20, 1330 - n * 60, 2300 + n * 90, 560]) {
        at += seconds;
        port.at = after(at);
        await c.tick();
        await c.act('advance');
      }
      at += 280;
      port.at = after(at);
      await c.tick();
      await c.act('end');
      at += 86400 * 7;
      port.at = after(at);
      await c.tick();
    }
    if (run) {
      await c.act('load', value: sunday());
      await c.act('start');
      for (final seconds in [340, 1330]) {
        at += seconds;
        port.at = after(at);
        await c.tick();
        await c.act('advance');
      }
      port.at = after(at + 1642);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  Future<void> palette(WidgetTester t, String id) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    final f = find.byKey(ValueKey('command-$id'));
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> back(WidgetTester t) async {
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await t.pumpAndSettle();
  }

  testWidgets('a report at 1440p keeps notes and activity beside it', (
    t,
  ) async {
    await app(t, size: const Size(2560, 1440));
    await tab(t, 2);
    const aside = ValueKey('report-aside-pane');
    expect(find.byKey(aside), findsOneWidget);
    expect(find.byKey(const ValueKey('report-activity-list')), findsOneWidget);
    // The activity is open, not folded away.
    expect(find.byKey(const ValueKey('report-activity')), findsNothing);
    expect(find.text('Service ended'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-review-note')), findsOneWidget);
    // The pane reaches the window's right edge; the timings sit beside it.
    expect(t.getRect(find.byKey(aside)).right, 2560);
    expect(
      t.getRect(find.byKey(const ValueKey('report-table'))).right,
      lessThan(t.getRect(find.byKey(aside)).left),
    );
    await shot(t, 'reports-detail-1440');
  });

  testWidgets('a report at full HD, and one column at laptop size', (t) async {
    await app(t);
    await tab(t, 2);
    expect(find.byKey(const ValueKey('report-aside-pane')), findsOneWidget);
    await shot(t, 'reports-detail-1080');
    await app(t, size: const Size(1366, 768));
    await tab(t, 2);
    // Too narrow for the pane: notes and activity stay below, as before.
    expect(find.byKey(const ValueKey('report-aside-pane')), findsNothing);
    expect(find.byKey(const ValueKey('report-activity')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the Graph tab puts totals beside the charts', (t) async {
    await app(t);
    await tab(t, 2);
    await t.tap(find.text('Graph'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-graph-columns')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-open-report')), findsOneWidget);
    await shot(t, 'reports-graph');
    await app(t, size: const Size(1366, 768));
    await tab(t, 2);
    await t.tap(find.text('Graph'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-graph-columns')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('selecting reports keeps the actions together', (t) async {
    await app(t);
    await tab(t, 2);
    await t.tap(find.byKey(const ValueKey('select-reports')));
    await t.pumpAndSettle();
    final share = t.getCenter(
      find.byKey(const ValueKey('share-selected-reports')),
    );
    final delete = t.getCenter(
      find.byKey(const ValueKey('delete-selected-reports')),
    );
    expect(delete.dx - share.dx, lessThan(560));
    await shot(t, 'reports-select');
  });

  testWidgets('Reports with nothing saved', (t) async {
    await app(t, services: 0);
    await tab(t, 2);
    expect(find.text('No reports yet'), findsOneWidget);
    await shot(t, 'reports-empty');
  });

  testWidgets('the program editor shows the running order beside the form', (
    t,
  ) async {
    await app(t);
    await tab(t, 1);
    await t.tap(find.byKey(const ValueKey('template-row:Sunday Service')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('edit-program')));
    await t.pumpAndSettle();
    const total = ValueKey('program-editor-total');
    expect(
      find.byKey(const ValueKey('program-editor-summary')),
      findsOneWidget,
    );
    expect(t.widget<Text>(find.byKey(total)).data, '1 h 20 min');
    // Ordinary-size buttons, and a form that does not span the window.
    expect(
      t.getSize(find.widgetWithText(FilledButton, 'Save changes')).width,
      lessThan(260),
    );
    expect(
      t.getSize(find.widgetWithText(OutlinedButton, 'Add segment')).width,
      lessThan(260),
    );
    expect(
      t.getSize(find.byType(TextField).first).width,
      lessThanOrEqualTo(760),
    );
    await shot(t, 'program-editor');
    // Removing a segment updates the running order at once.
    await t.tap(find.byTooltip('Remove segment').last);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(total)).data, '1 h 15 min');
    expect(t.takeException(), isNull);
  });

  testWidgets('what opens from Programs is a centred dialog', (t) async {
    await app(t);
    await tab(t, 1);
    await t.tap(find.byKey(const ValueKey('template-row:Sunday Service')));
    await t.pumpAndSettle();
    await menu(t, 'Program options', 'Version history');
    expect(find.text('Version history'), findsOneWidget);
    expectDialog(t, pageDialog);
    await shot(t, 'program-history');
    await back(t);
    await menu(t, 'Program options', 'Print order of service');
    expect(find.byKey(const ValueKey('print-sheet')), findsOneWidget);
    expectDialog(t, sheet);
    await shot(t, 'print-sheet');
    // Close is an ordinary button in the corner.
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('print-sheet')), findsNothing);
    await menu(t, 'More program actions', 'Segment library');
    expect(find.text('Segment library'), findsOneWidget);
    expectDialog(t, pageDialog);
    await back(t);
    await menu(t, 'More program actions', 'Export all programs');
    expectDialog(t, sheet);
    await shot(t, 'export-programs');
  });

  testWidgets('Quick timer is a centred dialog', (t) async {
    final (c, _) = await app(t);
    await palette(t, 'quick-timer');
    expect(find.byKey(const ValueKey('quick-timer-sheet')), findsOneWidget);
    expectDialog(t, sheet);
    await shot(t, 'quick-timer');
    // It still starts the timer it shows.
    await t.tap(find.byKey(const ValueKey('quick-timer-start')));
    await t.pumpAndSettle();
    expect(c.liveSession.active, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('Recover time and Edit upcoming are centred dialogs', (t) async {
    final (c, _) = await app(t, run: true, services: 1);
    await palette(t, 'recover');
    expect(find.text('Protect important segments'), findsOneWidget);
    expectDialog(t, pageDialog);
    expect(
      t.getSize(find.widgetWithText(FilledButton, 'Review adjustments')).width,
      lessThan(260),
    );
    await shot(t, 'recover-time');
    // Review first: nothing changes until the reviewed plan is applied.
    final before = c.liveSession.timeline!.segments[3].durationSeconds;
    await t.tap(find.text('Review adjustments'));
    await t.pumpAndSettle();
    expect(c.liveSession.timeline!.segments[3].durationSeconds, before);
    expect(find.text('Apply reviewed adjustments'), findsOneWidget);
    await back(t);

    await palette(t, 'edit-upcoming');
    expect(find.text('Upcoming segments'), findsOneWidget);
    expectDialog(t, pageDialog);
    await shot(t, 'edit-upcoming');
    await t.tap(find.text('Review rundown changes'));
    await t.pumpAndSettle();
    // Nothing changes until the confirmation is accepted.
    expect(find.text('Update upcoming segments?'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('nothing overflows at the smallest desktop size', (t) async {
    const small = Size(1200, 600);
    await app(t, size: small);
    await tab(t, 2);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Graph'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('List'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('select-reports')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await tab(t, 1);
    await t.tap(find.byKey(const ValueKey('template-row:Sunday Service')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('edit-program')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('program-editor-summary')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await back(t);
    for (final (tooltip, item) in const [
      ('Program options', 'Version history'),
      ('Program options', 'Print order of service'),
      ('More program actions', 'Segment library'),
      ('More program actions', 'Export all programs'),
    ]) {
      await menu(t, tooltip, item);
      expect(t.takeException(), isNull, reason: item);
      await back(t);
    }
    await tab(t, 0);
    await palette(t, 'quick-timer');
    expect(t.takeException(), isNull);
    await back(t);

    await app(t, size: small, run: true, services: 1);
    for (final id in [
      'recover',
      'edit-upcoming',
      'adjust',
      'jump',
      'message',
    ]) {
      await palette(t, id);
      expect(t.takeException(), isNull, reason: id);
      await back(t);
    }
    await app(t, size: small, services: 0);
    await tab(t, 2);
    expect(t.takeException(), isNull);
  });
}
