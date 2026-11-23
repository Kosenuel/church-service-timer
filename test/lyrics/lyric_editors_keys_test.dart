import 'package:church_service_timer/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';
import 'lyrics_page_test.dart' show openLyrics, settle;

Finder field(String key) => find.byKey(ValueKey(key));

String textOf(WidgetTester t, String key) =>
    t.widget<TextField>(field(key)).controller!.text;

/// The key of the field that has the keyboard, or null.
String? focusedKey(WidgetTester t) {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return null;
  final owner = focus.findAncestorWidgetOfExactType<TextField>();
  final k = owner?.key;
  return k is ValueKey<String> ? k.value : null;
}

Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pump();
}

Future<void> chord(
  WidgetTester t,
  LogicalKeyboardKey mod,
  LogicalKeyboardKey key,
) async {
  await t.sendKeyDownEvent(mod);
  await t.sendKeyEvent(key);
  await t.sendKeyUpEvent(mod);
  await t.pump();
}

/// Clears the field with Ctrl+A and Backspace, types [text] the way the
/// keyboard does, and checks the field holds exactly that.
Future<void> clearAndRetype(WidgetTester t, String key, String text) async {
  await t.tap(field(key));
  await t.pump();
  expect(textOf(t, key), isNotEmpty, reason: '$key starts with something');
  await chord(t, LogicalKeyboardKey.control, LogicalKeyboardKey.keyA);
  await press(t, LogicalKeyboardKey.backspace);
  expect(textOf(t, key), '', reason: '$key is empty after select all + delete');
  await t.pump(const Duration(milliseconds: 300));
  expect(textOf(t, key), '', reason: '$key stays empty');
  // Typing character by character, as the keyboard does.
  var typed = '';
  for (final ch in text.split('')) {
    typed += ch;
    await t.enterText(field(key), typed);
    await t.pump(const Duration(milliseconds: 300));
    expect(textOf(t, key), typed);
  }
  // Backspace to empty, one key at a time.
  for (var i = 0; i < text.length; i++) {
    await press(t, LogicalKeyboardKey.backspace);
    await t.pump(const Duration(milliseconds: 300));
  }
  expect(textOf(t, key), '', reason: '$key empty after backspacing');
  await t.enterText(field(key), 'last ${key.split('-').last}');
  await t.pump(const Duration(milliseconds: 300));
  expect(textOf(t, key), 'last ${key.split('-').last}');
}

void main() {
  setUpAll(loadAppFonts);

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    group('$platform', () {
      void testOn(String name, Future<void> Function(WidgetTester) body) =>
          testWidgets(name, (t) async {
            debugDefaultTargetPlatformOverride = platform;
            try {
              await body(t);
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          });

      testOn('song fields clear and retype', (t) async {
        await openLyrics(t, size: const Size(1366, 900));
        await openEditor(t, 'amazing');
        for (final k in [
          'lyrics-editor-title',
          'lyrics-editor-by',
          'lyrics-editor-words',
        ]) {
          await clearAndRetype(t, k, 'New ${k.split('-').last}');
        }
        expect(t.takeException(), isNull);
      });

      testOn('announcement fields clear and retype', (t) async {
        final c = await openLyrics(t, size: const Size(1366, 900));
        await openNew(t, 'lyrics-add-announcement');
        for (final k in [
          'lyrics-editor-title',
          'lyrics-editor-words',
          'lyrics-editor-detail',
        ]) {
          await t.enterText(field(k), 'Something to clear');
          await clearAndRetype(t, k, 'Fresh ${k.split('-').last}');
        }
        expect(c.lyrics.showing, isFalse);
      });

      testOn('Bible fields clear and retype', (t) async {
        await openLyrics(t, size: const Size(1366, 900));
        await openNew(t, 'lyrics-add-scripture');
        await t.enterText(field('lyrics-editor-reference'), 'John 3:16');
        await clearAndRetype(t, 'lyrics-editor-reference', 'Psalm 23');
        await t.tap(find.text('Paste your own'));
        await settle(t);
        for (final k in [
          'lyrics-editor-title',
          'lyrics-editor-version',
          'lyrics-editor-words',
        ]) {
          await t.enterText(field(k), 'Something to clear');
          await clearAndRetype(t, k, 'Fresh ${k.split('-').last}');
        }
      });

      testOn('b and Space type in a field with a slide showing', (t) async {
        final c = await openLyrics(t, size: const Size(1366, 900));
        await t.tap(field('lyrics-item-amazing'));
        await press(t, LogicalKeyboardKey.arrowRight);
        expect(c.lyrics.showing, isTrue);
        final index = c.lyrics.index;
        await openNew(t, 'lyrics-add-announcement');
        await t.tap(field('lyrics-editor-words'));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
        await t.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(c.lyrics.black, isFalse);
        expect(c.lyrics.showing, isTrue);
        expect(c.lyrics.index, index);
      });

      testOn('Enter and Space press the focused choice and button', (t) async {
        await openLyrics(t, size: const Size(1366, 900));
        await openNew(t, 'lyrics-add-scripture');
        // Tab to Paste your own (the second stop in the source control).
        for (var i = 0; i < 3; i++) {
          await press(t, LogicalKeyboardKey.tab);
        }
        await press(t, LogicalKeyboardKey.space);
        await settle(t);
        expect(field('lyrics-editor-version'), findsOneWidget);
      });

      testOn('the library search box clears and retypes; keys stay typing', (
        t,
      ) async {
        final c = await openLyrics(t, size: const Size(1366, 900));
        await t.tap(field('lyrics-item-amazing'));
        await press(t, LogicalKeyboardKey.arrowRight);
        expect(c.lyrics.showing, isTrue);
        await t.enterText(field('lyrics-search'), 'grace');
        await t.pump();
        await chord(t, LogicalKeyboardKey.control, LogicalKeyboardKey.keyA);
        await press(t, LogicalKeyboardKey.backspace);
        expect(textOf(t, 'lyrics-search'), '');
        await t.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
        await t.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
        await t.enterText(field('lyrics-search'), 'holy');
        await t.pump();
        expect(textOf(t, 'lyrics-search'), 'holy');
        expect(c.lyrics.black, isFalse);
        expect(c.lyrics.showing, isTrue);
      });

      testOn('the app-wide key handler lets every typing key through', (
        t,
      ) async {
        // On Windows a key the app handles never reaches the text field.
        await openLyrics(t, size: const Size(1366, 900));
        await openNew(t, 'lyrics-add-announcement');
        await t.tap(field('lyrics-editor-words'));
        await t.pump();
        final h = t.state<HomeState>(find.byType(Home, skipOffstage: false));
        for (final (key, phys, ch) in [
          (LogicalKeyboardKey.keyB, PhysicalKeyboardKey.keyB, 'b'),
          (LogicalKeyboardKey.space, PhysicalKeyboardKey.space, ' '),
          (LogicalKeyboardKey.backspace, PhysicalKeyboardKey.backspace, null),
          (LogicalKeyboardKey.delete, PhysicalKeyboardKey.delete, null),
          (LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab, null),
          (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter, null),
          (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight, null),
          (LogicalKeyboardKey.slash, PhysicalKeyboardKey.slash, '?'),
        ]) {
          expect(
            h.onClickerKey(
              KeyDownEvent(
                physicalKey: phys,
                logicalKey: key,
                character: ch,
                timeStamp: Duration.zero,
              ),
            ),
            isFalse,
            reason: '$key must reach the field',
          );
        }
      });

      testOn('Tab walks the song editor', (t) async {
        await openLyrics(t, size: const Size(1366, 900));
        await openNew(t, 'lyrics-add-song');
        await t.tap(field('lyrics-editor-title'));
        await t.pump();
        final seen = <String?>[focusedKey(t)];
        for (var i = 0; i < 3; i++) {
          await press(t, LogicalKeyboardKey.tab);
          seen.add(focusedKey(t));
        }
        expect(seen, [
          'lyrics-editor-title',
          'lyrics-editor-by',
          'lyrics-editor-words',
          // Tab leaves the words field and does not type a tab.
          null,
        ]);
        expect(textOf(t, 'lyrics-editor-words'), isNot(contains('\t')));
        // Shift+Tab goes back into it.
        await chord2(t, LogicalKeyboardKey.shift, LogicalKeyboardKey.tab);
        expect(focusedKey(t), 'lyrics-editor-words');
      });
    });
  }
}

Future<void> chord2(
  WidgetTester t,
  LogicalKeyboardKey mod,
  LogicalKeyboardKey key,
) => chord(t, mod, key);

Future<void> openNew(WidgetTester t, String button) async {
  await t.tap(field(button));
  await settle(t);
}

Future<void> openEditor(WidgetTester t, String id) async {
  await t.tap(field('lyrics-item-menu-$id'));
  await settle(t);
  await t.tap(find.text('Edit'));
  await settle(t);
}
