import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// A Sunday service with speakers and private notes.
Timeline harvest() => Timeline('Harvest Sunday', const [
  Segment(
    'Welcome',
    5,
    speaker: 'Deacon Ruth',
    notes: 'Notices first: youth camp forms are due.',
  ),
  Segment('Praise & Worship', 20, speaker: 'Worship team'),
  Segment('Offering', 7, seconds: 30, notes: 'Ushers ready before the song.'),
  Segment(
    'Sermon',
    40,
    speaker: 'Pastor Samuel',
    notes: 'Altar call follows. Band back on stage at 5:00 left.',
  ),
  Segment('Response', 10, speaker: 'Worship team'),
  Segment('Closing', 5),
], DisplaySettings());

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  /// The app on the Programs tab with [harvest] saved.
  Future<AppController> programs(
    WidgetTester t, {
    Size size = const Size(1366, 768),
    String? layout,
    String? theme,
    bool running = false,
  }) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    final saved = await c.commit((draft, at) {
      if (layout != null) {
        draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
      }
      if (theme != null) draft.themeId = theme;
      draft.saveTemplate(harvest());
      draft.programLibrary.favourites.add(draft.templates.last.id);
    });
    expect(saved, isTrue);
    if (running) {
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      port.at = after(90);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final tab = find.byKey(const ValueKey('desktop-tab-1'));
    await t.tap(tab.evaluate().isEmpty ? find.text('Programs') : tab);
    await t.pumpAndSettle();
    return c;
  }

  Future<void> choose(WidgetTester t, String name) async {
    final row = find.byKey(ValueKey('template-row:$name'));
    // Each column scrolls on its own; bring the row clear of the New
    // program button in a short window.
    if (t.getRect(row).bottom > t.view.physicalSize.height - 100) {
      await t.drag(
        find.byKey(const ValueKey('programs-list-pane')),
        const Offset(0, -240),
      );
      await t.pumpAndSettle();
    }
    await t.tap(row);
    await t.pumpAndSettle();
  }

  List<String?> row(WidgetTester t, int i) => t
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey('program-table-row-$i')),
          matching: find.byType(Text),
        ),
      )
      .map((w) => w.data)
      .toList();

  const columns = [
    'programs-desktop',
    'programs-list-pane',
    'programs-summary-pane',
  ];

  for (final size in const [Size(1366, 768), Size(1920, 1080)]) {
    testWidgets('three columns at ${size.width.round()} wide', (t) async {
      final c = await programs(t, size: size);
      expect(t.takeException(), isNull);
      for (final key in columns) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('master-detail')), findsNothing);
      // The page itself never scrolls under the header; its columns do.
      await t.drag(
        find.byKey(const ValueKey('programs-table-empty')),
        const Offset(0, -200),
      );
      await t.pumpAndSettle();
      expect(t.state<HomeState>(find.byType(Home)).homeScroll.offset, 0);
      // The list keeps its search, filters and rows.
      expect(find.byKey(const ValueKey('program-search')), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Rehearsals'), findsOneWidget);
      for (final p in c.state.templates) {
        expect(find.byKey(ValueKey('template-row:${p.name}')), findsOneWidget);
      }
      expect(find.text('Choose a program on the left'), findsOneWidget);
      // The list and the summary keep their widths; the table has the rest.
      final list = t.getSize(find.byKey(const ValueKey('programs-list-pane')));
      final summary = t.getSize(
        find.byKey(const ValueKey('programs-summary-pane')),
      );
      expect(list.width, inInclusiveRange(300, 360));
      expect(summary.width, inInclusiveRange(320, 380));
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('every desktop layout shows the three columns', (t) async {
    for (final layout in ['three_panes', 'mission_control', 'dial', 'keys']) {
      await programs(t, layout: layout);
      await choose(t, 'Harvest Sunday');
      expect(t.takeException(), isNull, reason: layout);
      expect(
        find.byKey(const ValueKey('programs-desktop')),
        findsOneWidget,
        reason: layout,
      );
      expect(find.byKey(const ValueKey('program-table')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a narrow window keeps the list and detail page', (t) async {
    await programs(t, size: const Size(1100, 768));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('master-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('programs-desktop')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the Classic layout keeps the list and detail page', (t) async {
    await programs(t, layout: 'classic');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('master-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('programs-desktop')), findsNothing);
    expect(find.byKey(const ValueKey('new-template')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('choosing a program fills the table and the summary', (t) async {
    await programs(t);
    await choose(t, 'Harvest Sunday');
    expect(t.takeException(), isNull);
    expect(find.text('Choose a program on the left'), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('program-table-name'))).data,
      'Harvest Sunday',
    );
    expect(row(t, 0), [
      '1',
      'Welcome',
      '5 min',
      'Deacon Ruth',
      'Notices first: youth camp forms are due.',
    ]);
    expect(row(t, 1), ['2', 'Praise & Worship', '20 min', 'Worship team', '–']);
    expect(row(t, 2), [
      '3',
      'Offering',
      '7 min 30 s',
      '–',
      'Ushers ready before the song.',
    ]);
    expect(row(t, 5), ['6', 'Closing', '5 min', '–', '–']);
    for (final heading in [
      'SEGMENT',
      'MINUTES',
      'SPEAKER',
      'PRIVATE NOTE',
      'SHAPE',
      'PAST SERVICES',
      'END SCREEN',
      'WARNINGS',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    for (final key in ['program-table-total', 'program-summary-total']) {
      expect(t.widget<Text>(find.byKey(ValueKey(key))).data, '1 h 27 min 30 s');
    }
    expect(
      find.textContaining('Edits take effect the next time you load'),
      findsOneWidget,
    );
    // Pin and the menu are the detail card's own.
    expect(find.byTooltip('Unpin program'), findsOneWidget);
    await t.tap(find.byTooltip('Program options'));
    await t.pumpAndSettle();
    for (final item in ['Duplicate', 'Version history', 'Delete program']) {
      expect(find.text(item), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Load into Live loads the program and opens Live', (t) async {
    final c = await programs(t);
    await choose(t, 'Harvest Sunday');
    await t.tap(find.byKey(const ValueKey('load-into-live')));
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    expect(c.state.session.timeline!.name, 'Harvest Sunday');
    expect(find.byKey(const ValueKey('programs-desktop')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Load into Live is disabled while a service runs', (t) async {
    final c = await programs(t, running: true);
    await choose(t, 'Harvest Sunday');
    expect(t.takeException(), isNull);
    final load = t.widget<FilledButton>(
      find.byKey(const ValueKey('load-into-live')),
    );
    expect(load.onPressed, isNull);
    expect(
      find.text('End the current service before loading another program.'),
      findsOneWidget,
    );
    final running = c.state.session.timeline!.name;
    await t.tap(
      find.byKey(const ValueKey('load-into-live')),
      warnIfMissed: false,
    );
    await t.pumpAndSettle();
    expect(c.state.session.timeline!.name, running);
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  Future<void> saveEditor(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.text('Save changes'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(TemplateEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Save changes'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await t.pumpAndSettle();
  }

  testWidgets('Edit program opens the editor and saving updates the table', (
    t,
  ) async {
    final c = await programs(t);
    await choose(t, 'Harvest Sunday');
    final id = c.state.templates.last.id;
    await t.tap(find.byKey(const ValueKey('edit-program')));
    await t.pumpAndSettle();
    expect(find.byType(TemplateEditor), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextField, 'Program name'),
      'Easter Sunday',
    );
    // Welcome gives up its speaker in the editor's own segment dialog.
    // (The name also shows in the running order beside the form.)
    await t.tap(find.text('Welcome').first);
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Deacon Ruth'),
      'Sister Joy',
    );
    await t.tap(find.widgetWithText(FilledButton, 'Save segment'));
    await t.pumpAndSettle();
    await saveEditor(t);
    expect(t.takeException(), isNull);
    expect(find.byType(TemplateEditor), findsNothing);
    // The same program, saved through the editor, with its history kept.
    expect(c.state.templates.last.id, id);
    expect(c.state.templates.last.name, 'Easter Sunday');
    expect(c.state.versionsOf(id), hasLength(1));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('program-table-name'))).data,
      'Easter Sunday',
    );
    expect(row(t, 0).sublist(0, 4), ['1', 'Welcome', '5 min', 'Sister Joy']);
    expect(
      find.byKey(const ValueKey('template-row:Easter Sunday')),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('double-clicking a row opens the same editor', (t) async {
    await programs(t);
    await choose(t, 'Harvest Sunday');
    final target = t.getCenter(
      find.byKey(const ValueKey('program-table-row-3')),
    );
    await t.tapAt(target);
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(target);
    await t.pumpAndSettle();
    expect(find.byType(TemplateEditor), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('editing never changes the running service', (t) async {
    final c = await programs(t, running: true);
    final running = c.state.templates.first;
    final before = c.state.session.timeline!.toJson();
    await choose(t, running.name);
    await t.tap(find.byKey(const ValueKey('edit-program')));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Program name'),
      'Renamed while live',
    );
    await saveEditor(t);
    expect(c.state.templates.first.name, 'Renamed while live');
    expect(c.state.session.timeline!.toJson(), before);
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('New program and selection stay clear of the table', (t) async {
    final c = await programs(t, size: const Size(1200, 600));
    await choose(t, 'Harvest Sunday');
    expect(t.takeException(), isNull);
    final table = t.getRect(find.byKey(const ValueKey('program-table')));
    final create = find.byKey(const ValueKey('new-template'));
    expect(create.hitTestable(), findsOneWidget);
    expect(t.getRect(create).overlaps(table), isFalse);
    // The last row scrolls fully into view.
    await t.drag(
      find.byKey(const ValueKey('program-table-rows')),
      const Offset(0, -600),
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('program-table-row-5')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('program-table-total')).hitTestable(),
      findsOneWidget,
    );
    // Selecting: the bar takes its own strip under the three columns.
    await t.longPress(
      find.byKey(const ValueKey('template-row:Harvest Sunday')),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(create, findsNothing);
    final bar = t.getRect(find.byKey(const ValueKey('selection-bar-programs')));
    expect(
      t.getRect(find.byKey(const ValueKey('program-table'))).bottom,
      lessThanOrEqualTo(bar.top),
    );
    expect(find.text('1 selected'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('pin-selected-programs')));
    await t.pumpAndSettle();
    expect(c.state.programLibrary.favourites, isEmpty);
    await t.drag(
      find.byKey(const ValueKey('programs-list-pane')),
      const Offset(0, 400),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('done-selecting-programs')));
    await t.pumpAndSettle();
    expect(create.hitTestable(), findsOneWidget);
    // New program opens the editor for a new program.
    await t.tap(create);
    await t.pumpAndSettle();
    expect(find.byType(TemplateEditor), findsOneWidget);
    expect(find.text('Create program'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing overflows at the smallest desktop window', (t) async {
    for (final layout in ['three_panes', 'mission_control', 'keys']) {
      await programs(
        t,
        size: const Size(1200, 600),
        layout: layout,
        running: layout == 'mission_control',
      );
      expect(t.takeException(), isNull, reason: layout);
      await choose(t, 'Harvest Sunday');
      expect(t.takeException(), isNull, reason: layout);
      expect(find.byKey(const ValueKey('program-table')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('search that hides the open program empties the table', (
    t,
  ) async {
    await programs(t);
    await choose(t, 'Harvest Sunday');
    await t.enterText(find.byKey(const ValueKey('program-search')), 'zzzz');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('programs-no-match')), findsOneWidget);
    expect(find.byKey(const ValueKey('program-table')), findsNothing);
    expect(find.text('Choose a program on the left'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('no programs at all', (t) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    // These pages were laid out and photographed under Three panes; the
    // default is covered in test/live/desktop_layout_test.dart.
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      ),
    );
    await c.commit((draft, _) => draft.templates = []);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('programs-empty')), findsOneWidget);
    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create program'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a start time set in Live gives the planned finish', (t) async {
    final c = await programs(t);
    await c.act('load', value: c.state.templates.first);
    await c.act('schedule', value: start.wall + 30 * 60000);
    await t.pumpAndSettle();
    await choose(t, 'Harvest Sunday');
    expect(
      t.widget<Text>(find.byKey(const ValueKey('program-summary-finish'))).data,
      clockLabel(start.wall + 30 * 60000 + 5250000),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Programs at laptop size', (t) async {
    await programs(t, layout: 'three_panes', theme: 'midnight_lime');
    await choose(t, 'Harvest Sunday');
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-programs.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Programs at full HD in Paper & Ink', (t) async {
    await programs(
      t,
      size: const Size(1920, 1080),
      layout: 'three_panes',
      theme: 'paper_ink',
    );
    await choose(t, 'Harvest Sunday');
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-programs-1080-paper.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
}
