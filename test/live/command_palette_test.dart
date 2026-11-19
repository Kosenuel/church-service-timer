import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class DesktopFakePort extends FakePort {
  @override
  bool get isDesktop => true;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': false,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

/// A Sunday service part-way through its third segment, running late.
Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5, speaker: 'Deacon Ruth'),
  Segment('Praise & Worship', 20, speaker: 'Worship team'),
  Segment('Sermon', 40, speaker: 'Pastor Samuel'),
  Segment('Response', 10, speaker: 'Worship team'),
  Segment('Closing', 5),
], DisplaySettings());

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<(AppController, FakePort)> running(
    WidgetTester t, {
    String layout = 'three_panes',
    FakePort? on,
    List<int> advanceAfter = const [340, 1330],
    int then = 1642,
    bool start = true,
  }) async {
    setScreen(t, const Size(1366, 768));
    final port = on ?? DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: layout),
    );
    if (start) {
      await c.act('load', value: sunday());
      await c.act('start');
      var at = 0;
      for (final seconds in advanceAfter) {
        at += seconds;
        port.at = after(at);
        await c.tick();
        await c.act('advance');
      }
      port.at = after(at + then);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  Future<void> control(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(key);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t) => control(t, LogicalKeyboardKey.keyK);

  final palette = find.byKey(const ValueKey('command-palette'));
  final search = find.byKey(const ValueKey('command-search'));
  Finder command(String id) => find.byKey(ValueKey('command-$id'));

  testWidgets('Ctrl+K opens the palette with suggestions for now', (t) async {
    await running(t);
    expect(palette, findsNothing);
    await open(t);
    expect(palette, findsOneWidget);
    // The service is behind, so Recover time is offered first of all.
    expect(find.text('Suggested now'), findsOneWidget);
    final dialog = t.widget<CommandPaletteDialog>(
      find.byType(CommandPaletteDialog),
    );
    expect(dialog.suggested, contains('recover'));
    expect(
      t.getTopLeft(command('recover')).dy,
      lessThan(t.getTopLeft(command('adjust')).dy),
    );
    // The next segment is named with its length, and keys show at the right.
    expect(
      find.descendant(
        of: command('next'),
        matching: find.textContaining(
          'Response · ${sunday().segments[3].durationText}',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: command('pause'), matching: find.text('Space')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: command('cue-0'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/command-palette.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('typing filters on words, in any case and any order', (t) async {
    await running(t);
    await open(t);
    await t.enterText(search, 'TIME rec');
    await t.pumpAndSettle();
    expect(command('recover'), findsOneWidget);
    expect(command('pause'), findsNothing);
    expect(find.text('Suggested now'), findsNothing);
    // A later segment can be found by its name.
    await t.enterText(search, 'closing');
    await t.pumpAndSettle();
    expect(command('jump-4'), findsOneWidget);
    await t.enterText(search, 'zzzz');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-none')), findsOneWidget);
    // Enter with nothing listed leaves the palette open.
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(palette, findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Pause from the palette still asks, and waits for the answer', (
    t,
  ) async {
    final (c, _) = await running(t);
    await open(t);
    await t.enterText(search, 'pause');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(palette, findsNothing);
    expect(find.text('Pause Sermon?'), findsOneWidget);
    expect(c.state.session.paused, isFalse);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    // A click works as well as Enter.
    await open(t);
    await t.tap(command('pause'));
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    await t.tap(find.text('Confirm pause'));
    await t.pumpAndSettle();
    expect(c.state.session.paused, isTrue);
    // Now the same line offers Resume.
    await open(t);
    expect(
      find.descendant(
        of: command('pause'),
        matching: find.textContaining('Resume timer', findRichText: true),
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('arrow keys move, and Enter runs the line they land on', (
    t,
  ) async {
    final (c, _) = await running(t);
    await open(t);
    await t.enterText(search, 'jump to');
    await t.pumpAndSettle();
    // Jump to segment, then Response, then Closing.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Jump to Closing?'), findsOneWidget);
    expect(c.state.session.index, 2);
    await t.tap(find.text('Jump to segment'));
    await t.pumpAndSettle();
    expect(c.state.session.index, 4);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a cue command sends the cue, then offers the way back', (
    t,
  ) async {
    final (c, _) = await running(t);
    final cue = c.state.stageCues[1];
    await open(t);
    expect(command('show-timer'), findsNothing);
    await t.enterText(search, 'cue ${cue.text}');
    await t.pumpAndSettle();
    expect(command('cue-1'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.state.session.alert?.text, cue.text);
    expect(c.state.session.outputMode(c.now), 'Cue');
    await open(t);
    // The cue on stage is not offered again; Show timer leads the list.
    expect(command('cue-1'), findsNothing);
    expect(command('cue-0'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.state.session.outputMode(c.now), 'Countdown');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Esc closes the palette and nothing runs', (t) async {
    final (c, _) = await running(t);
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(palette, findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(c.state.session.paused, isFalse);
    expect(c.state.session.index, 2);
    // Space typed into the search field is a space, not Pause.
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.textContaining('Press again'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing opens while the controls are locked', (t) async {
    await running(t);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    await open(t);
    expect(palette, findsNothing);
    final home = t.state<HomeState>(find.byType(Home));
    expect(home.paletteCommands(), isEmpty);
    await home.openCommandPalette();
    await t.pumpAndSettle();
    expect(palette, findsNothing);
    // Nor is it in the Live menu.
    await t.tap(find.byKey(const ValueKey('live-menu')));
    await t.pumpAndSettle();
    expect(find.text('Commands'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing opens on a phone or tablet', (t) async {
    desktopWording = false;
    final (c, _) = await running(t, on: FakePort());
    await open(t);
    expect(palette, findsNothing);
    await t.tap(find.byKey(const ValueKey('live-menu')));
    await t.pumpAndSettle();
    expect(find.text('Commands'), findsNothing);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    // The new letter keys are a computer's too.
    for (final key in [
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyJ,
    ]) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
    }
    await control(t, LogicalKeyboardKey.keyL);
    expect(find.byType(TextComposer), findsNothing);
    expect(find.byType(TemplateEditor), findsNothing);
    expect(find.byType(TimeRecoveryPage), findsNothing);
    expect(find.text('Jump to segment'), findsNothing);
    expect(c.uiLocked, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing opens while typing or under a dialog', (t) async {
    await running(t);
    // Under a dialog.
    await t.tap(find.byKey(const ValueKey('pause-resume')));
    await t.pumpAndSettle();
    expect(find.text('Pause Sermon?'), findsOneWidget);
    await open(t);
    expect(palette, findsNothing);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    // Typing in a field on the home screen: the Settings search.
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    await t.tap(find.byType(TextField).first);
    await t.pumpAndSettle();
    await open(t);
    expect(palette, findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('it opens from any tab and from the Live menu', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    await open(t);
    expect(palette, findsOneWidget);
    // Programs is where we are, so it is not offered.
    expect(command('go-1'), findsNothing);
    await t.enterText(search, 'go live');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('live-menu')));
    await t.pumpAndSettle();
    expect(find.text('Commands'), findsOneWidget);
    expect(find.text('Ctrl K'), findsOneWidget);
    await t.tap(find.text('Commands'));
    await t.pumpAndSettle();
    expect(palette, findsOneWidget);
    // End service keeps its confirmation.
    await t.enterText(search, 'end');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    expect(c.state.session.active, isTrue);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('commands that cannot be used now are not listed', (t) async {
    // The final segment.
    final (c, _) = await running(
      t,
      advanceAfter: const [300, 1200, 2400, 600],
      then: 30,
    );
    expect(c.state.session.index, 4);
    final home = t.state<HomeState>(find.byType(Home));
    var ids = home.paletteCommands().map((e) => e.id).toList();
    expect(ids, isNot(contains('next')));
    expect(ids, isNot(contains('jump')));
    expect(ids.where((id) => id.startsWith('jump-')), isEmpty);
    expect(ids, isNot(contains('start')));
    expect(ids, isNot(contains('quick-timer')));
    expect(ids, containsAll(['pause', 'adjust', 'end', 'undo', 'recover']));
    await open(t);
    expect(command('next'), findsNothing);
    expect(command('pause'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    // J has nowhere to jump to.
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pumpAndSettle();
    expect(find.text('Jump to segment'), findsNothing);
    // Once the service has ended the timer commands go, Start comes back.
    await c.act('end');
    await t.pumpAndSettle();
    ids = home.paletteCommands().map((e) => e.id).toList();
    expect(ids, isNot(contains('pause')));
    expect(ids, isNot(contains('end')));
    expect(ids, isNot(contains('lock')));
    expect(ids, containsAll(['start', 'quick-timer']));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('standing by offers Start service and Quick timer', (t) async {
    await running(t, start: false);
    await open(t);
    expect(palette, findsOneWidget);
    expect(find.text('Suggested now'), findsOneWidget);
    expect(command('start'), findsOneWidget);
    expect(command('quick-timer'), findsOneWidget);
    expect(command('pause'), findsNothing);
    expect(command('lock'), findsNothing);
    await t.tap(command('start'));
    await t.pumpAndSettle();
    expect(find.text('Start a service'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl+L locks the controls and cannot unlock them', (t) async {
    final (c, _) = await running(t);
    // L on its own does nothing.
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    await t.pumpAndSettle();
    expect(c.uiLocked, isFalse);
    await control(t, LogicalKeyboardKey.keyL);
    expect(c.uiLocked, isTrue);
    expect(
      find.byKey(const ValueKey('controls-locked-banner')),
      findsOneWidget,
    );
    await control(t, LogicalKeyboardKey.keyL);
    expect(c.uiLocked, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.keyM);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.byType(TextComposer), findsNothing);
    await t.longPress(find.byKey(const ValueKey('unlock-controls')));
    await t.pumpAndSettle();
    expect(c.uiLocked, isFalse);
    // Lock controls from the palette does the same.
    await open(t);
    await t.enterText(search, 'lock');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.uiLocked, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('M, E, R and J open what their buttons open', (t) async {
    final (c, _) = await running(t);
    final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
    await t.sendKeyEvent(LogicalKeyboardKey.keyM);
    await t.pumpAndSettle();
    expect(find.byType(TextComposer), findsOneWidget);
    // Letters typed in the message are letters, not shortcuts.
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pumpAndSettle();
    expect(find.text('Jump to segment'), findsNothing);
    navigator.pop();
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.keyE);
    await t.pumpAndSettle();
    expect(find.byType(TemplateEditor), findsOneWidget);
    navigator.pop();
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.pumpAndSettle();
    expect(find.byType(TimeRecoveryPage), findsOneWidget);
    navigator.pop();
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pumpAndSettle();
    expect(find.text('Jump to segment'), findsOneWidget);
    await t.tap(find.widgetWithText(ListTile, 'Closing'));
    await t.pumpAndSettle();
    // The jump still asks.
    expect(find.text('Jump to Closing?'), findsOneWidget);
    expect(c.state.session.index, 2);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    // Ctrl+M belongs to another feature and does nothing here.
    await control(t, LogicalKeyboardKey.keyM);
    expect(find.byType(TextComposer), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the keys show on the buttons and in the legend, on one line', (
    t,
  ) async {
    await running(t);
    Finder hint(String label, String key) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.text(key),
    );
    expect(hint('Edit upcoming', 'E'), findsOneWidget);
    expect(hint('Recover time', 'R'), findsOneWidget);
    await t.pumpWidget(const SizedBox());

    // Mission control keeps the side rail, so its legend is 1286 wide.
    await running(t, layout: 'mission_control');
    final legend = find.byKey(const ValueKey('key-legend'));
    expect(t.getSize(legend).height, 28);
    expect(t.getSize(legend).width, lessThanOrEqualTo(1286));
    for (final words in ['Ctrl K  Commands', 'Ctrl L  Lock', 'M  Message']) {
      final item = find.descendant(
        of: legend,
        matching: find.text(words, findRichText: true),
      );
      expect(item, findsOneWidget, reason: words);
      expect(t.getSize(item).height, lessThan(20), reason: words);
    }
    expect(hint('Edit upcoming', 'E'), findsOneWidget);
    expect(hint('Recover time', 'R'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
