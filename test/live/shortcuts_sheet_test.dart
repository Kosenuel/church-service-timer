import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/clicker_controls.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/live/shortcuts_sheet.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../windows/mini_timer_test.dart' show DesktopPort, FakeMiniWindow;
import 'desktop_layout_test.dart' show sunday;

/// The shortcuts sheet, and the list behind it: what it says each key
/// does is held to what the app does with that key.
void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  const full = Size(1920, 1080);

  /// A service in its second segment on a computer, with everything a key
  /// could need: a segment change to undo, later segments, nine cues, a
  /// display and a mini timer window.
  Future<AppController> running(
    WidgetTester t, {
    Size size = full,
    bool start = true,
  }) async {
    setScreen(t, size);
    final port = DesktopPort()..mini = FakeMiniWindow(t, size);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    // These pages were laid out and photographed under Three panes; the
    // default is covered in test/live/desktop_layout_test.dart.
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      ),
    );
    await c.commit(
      (draft, _) =>
          draft.stageCues = [for (var i = 1; i <= 9; i++) TextLayout('CUE $i')],
    );
    if (start) {
      await c.act('load', value: sunday());
      await c.act('start');
      port.at = after(340);
      await c.tick();
      await c.act('advance');
      port.at = after(700);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));
  final sheet = find.byKey(const ValueKey('shortcuts-sheet'));

  /// Shift and /, as a keyboard sends a question mark.
  Future<void> questionMark(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
    await t.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyEvent(key);
    await t.pumpAndSettle();
  }

  KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  testWidgets('? opens the sheet and Esc closes it', (t) async {
    final c = await running(t);
    final revision = c.state.session.revision;
    expect(sheet, findsNothing);
    await questionMark(t);
    expect(sheet, findsOneWidget);
    // A centred dialog in a wide window, with the three groups.
    expect(find.byKey(const ValueKey('wide-sheet-dialog')), findsOneWidget);
    for (final group in ShortcutGroup.values) {
      expect(find.text(group.title.toUpperCase()), findsOneWidget);
    }
    // The two rules, a line each.
    expect(find.text(shortcutsConfirmRule), findsOneWidget);
    expect(find.text(shortcutsLockRule), findsOneWidget);
    // Every shortcut has its row, with its keys as key caps.
    for (final s in shortcuts) {
      final row = find.byKey(ValueKey('shortcut-${s.id}'));
      expect(row, findsOneWidget, reason: s.id);
      expect(
        find.descendant(of: row, matching: find.text(s.action)),
        findsOneWidget,
      );
      for (final cap in s.caps.expand((keys) => keys)) {
        expect(
          find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (w) => w is KeyCap && w.text == cap,
            ),
          ),
          findsOneWidget,
          reason: '${s.id} $cap',
        );
      }
    }
    // A second ? does not stack another sheet on top.
    await questionMark(t);
    expect(sheet, findsOneWidget);
    await press(t, LogicalKeyboardKey.escape);
    expect(sheet, findsNothing);
    expect(c.state.session.revision, revision);
    expect(t.takeException(), isNull);
  });

  testWidgets('F1 opens it too, on any tab and before a service', (t) async {
    await running(t, start: false);
    await press(t, LogicalKeyboardKey.f1);
    expect(sheet, findsOneWidget);
    await press(t, LogicalKeyboardKey.escape);
    expect(sheet, findsNothing);
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    await press(t, LogicalKeyboardKey.f1);
    expect(sheet, findsOneWidget);
    // Close also closes it.
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('? typed into a text field is left for the field', (t) async {
    await running(t);
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    await t.tap(find.byType(TextField).first);
    await t.pumpAndSettle();
    expect(home(t).typingInField, isTrue);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // Not handled, so the key goes on to type its character.
    expect(home(t).onClickerKey(down(LogicalKeyboardKey.slash)), isFalse);
    expect(home(t).onClickerKey(down(LogicalKeyboardKey.f1)), isFalse);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await questionMark(t);
    await press(t, LogicalKeyboardKey.f1);
    expect(sheet, findsNothing);
    await t.enterText(find.byType(TextField).first, 'clock?');
    await t.pumpAndSettle();
    expect(find.text('clock?'), findsOneWidget);
    expect(sheet, findsNothing);
  });

  testWidgets('locked controls block ? and F1', (t) async {
    await running(t);
    home(t).lockControls();
    await t.pumpAndSettle();
    await questionMark(t);
    await press(t, LogicalKeyboardKey.f1);
    expect(sheet, findsNothing);
    expect(home(t).shortcutsSheetAvailable, isFalse);
    // Nor do Commands or the menu offer it.
    expect(home(t).paletteCommands(), isEmpty);
    await home(t).openShortcutsSheet();
    await t.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('a phone or tablet has no sheet', (t) async {
    desktopWording = false;
    setScreen(t);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await questionMark(t);
    await press(t, LogicalKeyboardKey.f1);
    expect(sheet, findsNothing);
  });

  testWidgets('Commands, the Live menu and Settings search open it', (t) async {
    await running(t);
    // Commands.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('command-search')),
      'keyboard short',
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-shortcuts')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(sheet, findsOneWidget);
    await press(t, LogicalKeyboardKey.escape);
    expect(sheet, findsNothing);
    // The Live menu.
    await t.tap(find.byKey(const ValueKey('live-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Keyboard shortcuts'));
    await t.pumpAndSettle();
    expect(sheet, findsOneWidget);
    await press(t, LogicalKeyboardKey.escape);
    // Settings search, by any of the words someone might try.
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    for (final word in ['shortcuts', 'keyboard', 'clicker', 'pedal', 'test']) {
      await t.enterText(find.byType(TextField).first, word);
      await t.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget, reason: word);
      expect(
        find.text('Test a clicker or pedal'),
        findsOneWidget,
        reason: word,
      );
    }
    await t.tap(find.text('Keyboard shortcuts'));
    await t.pumpAndSettle();
    expect(sheet, findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('the list is what the app does', () {
    /// Whether Live, a question, a notice, the lock, a cue or the mini
    /// timer shows that the key did something.
    bool somethingHappened(WidgetTester t, AppController c) =>
        ModalRoute.of(home(t).context)?.isCurrent != true ||
        find.byType(SnackBar).evaluate().isNotEmpty ||
        home(t).controlsLocked ||
        home(t).miniTimer ||
        home(t).hostFullScreen.showing ||
        c.state.session.alert != null;

    testWidgets('a key that is not listed does nothing', (t) async {
      final c = await running(t);
      final before = c.state.session.toJson().toString();
      var listed = 0;
      for (final control in [false, true]) {
        for (final shift in [false, true]) {
          if (control) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          for (final key in LogicalKeyboardKey.knownLogicalKeys) {
            final s = shortcutFor(key, control: control, shift: shift);
            if (s != null && !s.inDialogs) {
              listed++;
              continue;
            }
            expect(
              home(t).onClickerKey(down(key)),
              isFalse,
              reason:
                  '${keyName(key, control: control, shift: shift)} does something on Live but is not in shortcuts.dart',
            );
          }
          if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          if (control) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
      }
      await t.pumpAndSettle();
      expect(listed, greaterThan(40));
      expect(somethingHappened(t, c), isFalse);
      expect(c.state.session.toJson().toString(), before);
      expect(t.takeException(), isNull);
    });

    for (final s in shortcuts.where((s) => !s.inDialogs)) {
      testWidgets('${s.id}: every listed key does it', (t) async {
        expect(s.presses, isNotEmpty);
        for (final p in s.presses) {
          for (final control
              in p.control == null ? [false, true] : [p.control!]) {
            final c = await running(t);
            final name = keyName(p.key, control: control, shift: p.shift);
            expect(somethingHappened(t, c), isFalse, reason: name);
            if (control) {
              await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            }
            if (p.shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            final handled = home(t).onClickerKey(down(p.key));
            if (p.shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            if (control) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await t.pumpAndSettle();
            expect(
              handled,
              isTrue,
              reason: '$name is listed for ${s.action} but does nothing',
            );
            expect(somethingHappened(t, c), isTrue, reason: name);
            // A timer action has only asked: the timer is as it was.
            if (s.timerAction) {
              expect(c.state.session.paused, isFalse, reason: name);
              expect(c.state.session.index, 1, reason: name);
            }
            t.takeException();
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 5));
          }
        }
      });
    }

    test('the classifiers and the list name the same keys', () {
      for (final control in [false, true]) {
        for (final shift in [false, true]) {
          for (final key in LogicalKeyboardKey.knownLogicalKeys) {
            final claimed =
                isCommandPaletteKey(key, control: control) ||
                isMiniTimerKey(key, control: control) ||
                isFullScreenKey(key) ||
                isShortcutsSheetKey(key, shift: shift) ||
                clickerActionFor(key) != null ||
                desktopLiveActionFor(key, control: control) != null ||
                desktopCueIndexFor(key, control: control) != null;
            final s = shortcutFor(key, control: control, shift: shift);
            expect(
              s != null && !s.inDialogs,
              claimed,
              reason: keyName(key, control: control, shift: shift),
            );
          }
        }
      }
    });

    test('each shortcut is listed once and worded for the sheet', () {
      expect(shortcuts.map((s) => s.id).toSet().length, shortcuts.length);
      for (final s in shortcuts) {
        expect(s.caps, isNotEmpty, reason: s.id);
        expect(s.action, isNotEmpty, reason: s.id);
        expect(s.confirm, isNotEmpty, reason: s.id);
        expect(s.when, endsWith('.'), reason: s.id);
      }
      // Every group has something under it.
      for (final group in ShortcutGroup.values) {
        expect(shortcuts.where((s) => s.group == group), isNotEmpty);
      }
      // The clicker's keys are the ones a phone answers to.
      expect(shortcuts.where((s) => s.clicker).map((s) => s.id), [
        'pause',
        'next',
      ]);
    });

    testWidgets('Commands shows the same key beside each command', (t) async {
      await running(t);
      final commands = home(t).paletteCommands();
      final withKeys = {
        for (final command in commands)
          if (command.keys != null) command.id: command.keys!,
      };
      for (final id in [
        'pause',
        'next',
        'adjust',
        'undo',
        'jump',
        'recover',
        'edit-upcoming',
        'message',
        'lock',
        'mini',
        'fullscreen',
        'shortcuts',
      ]) {
        expect(withKeys.remove(id), shortcutHint(id), reason: id);
      }
      // What is left is the cues, numbered as their keys are.
      final cue = shortcut('cue');
      expect(withKeys, hasLength(9));
      for (final entry in withKeys.entries) {
        final index = int.parse(entry.key.substring('cue-'.length));
        expect(entry.value, '${index + 1}');
        expect(
          desktopCueIndexFor(cue.presses[index * 2].key, control: false),
          index,
        );
      }
    });

    test('docs/WINDOWS.md has a row for each, worded the same', () {
      final doc = File('docs/WINDOWS.md').readAsStringSync();
      for (final s in shortcuts) {
        final keys = s.caps
            .map((keys) => '**${keys.join('+')}**')
            .join(' ${s.joiner} ');
        final confirm =
            '${s.confirm[0].toUpperCase()}${s.confirm.substring(1)}';
        expect(doc, contains('| $keys | ${s.action} | $confirm |'));
      }
    });
  });

  testWidgets('looks right in a full HD window', (t) async {
    await running(t);
    await questionMark(t);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-shortcuts-sheet.png'),
    );
  });

  testWidgets('fits the smallest and the largest window', (t) async {
    for (final size in const [
      Size(1200, 600),
      Size(1366, 768),
      Size(2560, 1440),
    ]) {
      await running(t, size: size);
      await questionMark(t);
      expect(sheet, findsOneWidget, reason: '$size');
      expect(t.takeException(), isNull, reason: '$size');
      // Inside the window, and no wider than a dialog should be.
      final box = t.getRect(find.byKey(const ValueKey('wide-sheet-dialog')));
      expect(box.width, lessThanOrEqualTo(size.width));
      expect(box.height, lessThanOrEqualTo(size.height));
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('one column, with large text, in a narrow window', (t) async {
    for (final (size, scale) in const [
      (Size(320, 640), 2.0),
      (Size(700, 500), 1.3),
    ]) {
      setScreen(t, size);
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme('midnight_lime'),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(body: ShortcutsSheetView()),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$size');
      expect(find.text(shortcuts.first.action), findsOneWidget);
    }
  });
}
