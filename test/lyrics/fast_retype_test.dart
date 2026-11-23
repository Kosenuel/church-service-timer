import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';
import 'lyrics_page_test.dart' show openLyrics, settle;

Finder field(String key) => find.byKey(ValueKey(key));
String textOf(WidgetTester t, String key) =>
    t.widget<TextField>(field(key)).controller!.text;

const quick = Duration(milliseconds: 20);

/// Edits that go A, B, A inside the preview's 260 ms fade, with no pause.
Future<void> hammer(WidgetTester t, String key, {required String a}) async {
  Future<void> set(String v) async {
    await t.enterText(field(key), v);
    await t.pump(quick);
    expect(textOf(t, key), v);
    expect(t.takeException(), isNull, reason: 'typing "$v" in $key');
  }

  await t.tap(field(key));
  await set(a);
  await set('');
  await set(a);
  await set('${a}x');
  await set(a);
  await set('');
  await set('${a.substring(0, 1)}');
  await set(a);
  // Select all, delete, undo-like retype of the same text, Backspace.
  await t.sendKeyDownEvent(LogicalKeyboardKey.control);
  await t.sendKeyEvent(LogicalKeyboardKey.keyA);
  await t.sendKeyUpEvent(LogicalKeyboardKey.control);
  await t.sendKeyEvent(LogicalKeyboardKey.backspace);
  await t.pump(quick);
  expect(textOf(t, key), '');
  await set(a);
  expect(t.takeException(), isNull);
}

Future<void> tabStillWorks(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
  final before = FocusManager.instance.primaryFocus;
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  await t.pump();
  expect(FocusManager.instance.primaryFocus, isNot(same(before)));
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadAppFonts);

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    Future<void> on(WidgetTester t, Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    group('$platform: quick clear and retype, no pauses', () {
      testWidgets(
        'announcement',
        (t) => on(t, () async {
          await openLyrics(t, size: const Size(1366, 900));
          await t.tap(field('lyrics-add-announcement'));
          await settle(t);
          await hammer(t, 'lyrics-editor-title', a: 'Picnic');
          await hammer(t, 'lyrics-editor-words', a: 'Bring food');
          await hammer(t, 'lyrics-editor-detail', a: 'Hall');
          expect(
            find.textContaining('Bring food', findRichText: true),
            findsWidgets,
          );
          await tabStillWorks(t);
        }),
      );

      testWidgets(
        'song',
        (t) => on(t, () async {
          await openLyrics(t, size: const Size(1366, 900));
          await t.tap(field('lyrics-add-song'));
          await settle(t);
          await hammer(t, 'lyrics-editor-title', a: 'Grace');
          await hammer(t, 'lyrics-editor-words', a: 'Amazing grace');
          await tabStillWorks(t);
        }),
      );

      testWidgets(
        'Bible verses, pasted',
        (t) => on(t, () async {
          await openLyrics(t, size: const Size(1366, 900));
          await t.tap(field('lyrics-add-scripture'));
          await settle(t);
          await t.tap(find.text('Paste your own'));
          await settle(t);
          await hammer(t, 'lyrics-editor-title', a: 'Romans 8:28');
          await hammer(t, 'lyrics-editor-version', a: 'NIV');
          await hammer(t, 'lyrics-editor-words', a: 'All things work');
          await tabStillWorks(t);
        }),
      );

      testWidgets(
        'Bible verses, found in the KJV',
        (t) => on(t, () async {
          await openLyrics(t, size: const Size(1366, 900));
          await t.tap(field('lyrics-add-scripture'));
          await settle(t);
          await hammer(t, 'lyrics-editor-reference', a: 'John 3:16');
          await t.tap(field('lyrics-editor-find'));
          await t.pump(quick);
          await t.pump(const Duration(milliseconds: 50));
          await hammer(t, 'lyrics-editor-reference', a: 'Psalm 23');
          await tabStillWorks(t);
        }),
      );
    });
  }

  testWidgets('the stage takes Next, Previous, Next and show, clear, show', (
    t,
  ) async {
    Widget stage(Map<String, dynamic> data) => MaterialApp(
      home: SizedBox(
        width: 640,
        height: 360,
        child: LyricStage(data: {'bg': 'midnight', 'motion': false, ...data}),
      ),
    );
    const one = {'key': 's', 'text': 'First slide', 'title': ''};
    const two = {'key': 's', 'text': 'Second slide', 'title': ''};
    for (final seq in [
      [one, two, one, two, one], // Next, Previous, Next ...
      [
        one,
        {'black': true},
        one,
        {'black': true},
        one,
      ],
      [
        one,
        {'key': 's', 'text': '', 'title': ''},
        one,
      ],
    ]) {
      for (final data in seq) {
        await t.pumpWidget(stage(Map<String, dynamic>.from(data)));
        await t.pump(quick);
        expect(t.takeException(), isNull);
      }
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(LyricStage), findsOneWidget);
    }
  });
}
