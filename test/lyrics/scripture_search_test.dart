import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/ready_tray.dart';
import 'package:church_service_timer/lyrics/scripture_search.dart';
import 'package:church_service_timer/lyrics/scripture_search_ui.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';
import 'lyrics_page_test.dart' show openLyrics, settle, home;

late BibleSearchIndex index;

Future<void> type(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const ValueKey('lyrics-search')), text);
  await settle(t);
}

Future<void> ctrlEnter(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(t);
}

Future<AppController> open(
  WidgetTester t, {
  Size size = const Size(1366, 768),
  bool desktop = true,
  double textScale = 1,
}) async {
  ScriptureIndex.useForTest(index);
  ReadyTray.bibleLoader = (_) async => index.bible;
  return openLyrics(
    t,
    size: size,
    desktop: desktop,
    running: false,
    textScale: textScale,
  );
}

ReadyTray trayOf(AppController c) => ReadyTray.of(c);

class _Wire implements PairWire {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    final text = utf8.decode(
      gzip.decode(File('assets/bible/kjv.txt.gz').readAsBytesSync()),
    );
    index = BibleSearchIndex.build(Bible.parse(text));
  });

  group('excerpt', () {
    test('keeps the first match in view and moves the marks with it', () {
      final text =
          'Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ${'x ' * 30}shadow here';
      final at = text.indexOf('shadow');
      final e = excerptAround(text, [(at, at + 6)], 80);
      expect(e.text, startsWith('… '));
      expect(e.text.substring(e.spans.single.$1, e.spans.single.$2), 'shadow');
      expect(e.text.length, lessThan(text.length));
    });
    test('short text and an early match are left alone', () {
      final e = excerptAround('The LORD is my shepherd', [(4, 8)], 80);
      expect(e.text, 'The LORD is my shepherd');
      final long = 'The LORD ${'word ' * 60}';
      final f = excerptAround(long, [(4, 8)], 80);
      expect(f.text, long);
      expect(f.spans.single, (4, 8));
    });
  });

  test('which keys open the search', () {
    bool key(
      LogicalKeyboardKey k, {
      bool control = false,
      bool typing = false,
    }) => isScriptureSearchKey(k, control: control, typing: typing);
    expect(key(LogicalKeyboardKey.slash), isTrue);
    expect(
      key(LogicalKeyboardKey.slash, typing: true),
      isFalse,
      reason: 'a / is text in a field',
    );
    expect(key(LogicalKeyboardKey.keyF, control: true), isTrue);
    expect(key(LogicalKeyboardKey.keyF, control: true, typing: true), isTrue);
    expect(key(LogicalKeyboardKey.keyF), isFalse);
    expect(key(LogicalKeyboardKey.slash, control: true), isFalse);
  });

  testWidgets('a reference finds the verse; Enter puts it in Ready', (t) async {
    final c = await open(t);
    await type(t, 'john 3 16');
    expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
    expect(find.text('John 3:16'), findsWidgets);
    expect(find.textContaining('For God so loved the world'), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(trayOf(c).items.single.reference, 'John 3:16');
    expect(find.byKey(const ValueKey('ready-1')), findsOneWidget);
    // Nothing went to the screens.
    expect(c.lyrics.showing, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('Send puts the passage on the screens like a library slide', (
    t,
  ) async {
    final c = await open(t);
    await type(t, 'psalm 23:1-3');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    await t.tap(find.byKey(const ValueKey('ready-send-1')));
    await settle(t);
    final l = c.lyrics;
    expect(l.showing, isTrue);
    expect(l.item!.kind, 'scripture');
    expect(l.slide!.reference, 'Psalm 23:1-3 · KJV');
    expect(l.slide!.text, contains('The LORD is my shepherd'));
    // The very same field a library slide sends.
    final field = l.field(LyricTarget.second)!;
    expect(field['kind'], 'scripture');
    expect(field['reference'], 'Psalm 23:1-3 · KJV');
    expect(field['bg'], l.look.background);
    expect(field['dim'], l.look.dim);
    expect(l.field(LyricTarget.web), isNotNull);
    // And only to the groups showing slides: Room 1, not Stage.
    final phone = PairPeer('p', 'Pulpit', 'stage', _Wire());
    expect(
      c.decoratePairedSnapshot(phone, c.pairedSnapshot(false))['lyrics'],
      isNull,
      reason: 'Stage shows the timer',
    );
    expect(c.stageWindowSnapshot()['lyrics'], isA<Map>());
    // The library did not grow.
    expect(c.state.lyrics.items.where((i) => i.kind == 'scripture'), isEmpty);
    // The slide cards in the middle show what is on the screens.
    expect(find.byKey(const ValueKey('lyrics-slide-0')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Send follows the screen groups, Dim and Clear slide', (t) async {
    final c = await open(t);
    await t.runAsync(() async {
      await c.lyrics.setLook(c.lyrics.look.copyWith(dim: 25));
      // This computer in Stage (the timer); web screens stay in Room 1.
      await c.screens.move(thisScreenKey, 'stage');
    });
    await type(t, 'john 3:16');
    await ctrlEnter(t);
    final l = c.lyrics;
    expect(l.showing, isTrue);
    // A passage from Ready goes exactly where a Library slide goes.
    expect(c.stageWindowSnapshot().containsKey('lyrics'), isFalse);
    expect((c.webStageSnapshot()['lyrics'] as Map)['dim'], 25);
    await t.tap(find.byKey(const ValueKey('lyrics-clear')));
    await settle(t);
    expect(l.showing, isFalse);
    expect(l.field(LyricTarget.web), isNull);
    // Ready is still there to send again.
    expect(trayOf(c).items, hasLength(1));
  });

  testWidgets('Ctrl+Enter and a second tap send straight away', (t) async {
    final c = await open(t);
    await type(t, 'john 3:16');
    await ctrlEnter(t);
    expect(c.lyrics.slide!.text, contains('For God so loved'));
    c.lyrics.clear();
    await settle(t);
    await type(t, 'john 3:17');
    final hit = find.byKey(const ValueKey('search-hit-0'));
    await t.tap(hit);
    await t.pump(const Duration(milliseconds: 100));
    expect(c.lyrics.showing, isFalse, reason: 'one tap only prepares it');
    expect(trayOf(c).items.first.reference, 'John 3:17');
    await t.tap(hit);
    await settle(t);
    expect(c.lyrics.slide!.text, contains('For God sent not his Son'));
  });

  testWidgets('Up and Down move the highlight, Esc clears the box', (t) async {
    final c = await open(t);
    await type(t, 'psalm 23');
    final controller = _controllerOf(t);
    expect(controller.highlight, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.highlight, 3);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.highlight, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(trayOf(c).items.first.reference, 'Psalm 23:2');
    // Esc clears the box and does not touch what is on the screens.
    c.lyrics.show('amazing', 0);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('lyrics-search')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const ValueKey('scripture-results')), findsNothing);
    expect(
      c.lyrics.showing,
      isTrue,
      reason: 'Esc in the box is not Clear slide',
    );
    expect(find.byKey(const ValueKey('lyrics-item-amazing')), findsOneWidget);
  });

  testWidgets('b and space in the box are typing, not Black or Next', (
    t,
  ) async {
    final c = await open(t);
    c.lyrics.show('amazing', 0);
    await settle(t);
    await t.tap(find.byKey(const ValueKey('lyrics-search')));
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(c.lyrics.black, isFalse);
    expect(c.lyrics.index, 0);
    await t.enterText(find.byKey(const ValueKey('lyrics-search')), 'b ');
    await settle(t);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('lyrics-search')))
          .controller!
          .text,
      'b ',
    );
    expect(c.lyrics.black, isFalse);
    expect(c.lyrics.index, 0);
  });

  testWidgets('a second Esc hands the keys back to the slides', (t) async {
    final c = await open(t);
    c.lyrics.show('amazing', 0);
    await type(t, 'john 3');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(c.lyrics.showing, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(
      c.lyrics.showing,
      isTrue,
      reason: 'the second Esc only leaves the box',
    );
    final f = FocusManager.instance.primaryFocus?.context;
    expect(f?.findAncestorWidgetOfExactType<EditableText>(), isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(c.lyrics.index, 1, reason: 'the arrow keys work without a click');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(c.lyrics.showing, isFalse);
  });

  testWidgets('Tab reaches the box, results and the Ready buttons in order', (
    t,
  ) async {
    final c = await open(t);
    trayOf(c).addReady(index.bible.read('John 3:16'));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('lyrics-search')));
    final seen = <Key?>[];
    Key? buttonKey() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      return ctx?.findAncestorWidgetOfExactType<FilledButton>()?.key ??
          ctx?.findAncestorWidgetOfExactType<TextButton>()?.key ??
          ctx?.findAncestorWidgetOfExactType<IconButton>()?.key;
    }

    for (var i = 0; i < 30; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      seen.add(buttonKey());
    }
    for (final k in const [
      'ready-send-1',
      'ready-remove-1',
      'ready-next-1',
      'ready-chapter-1',
      'ready-save-1',
    ]) {
      expect(seen, contains(ValueKey(k)), reason: '$k reachable by Tab');
    }
    expect(
      seen.indexOf(const ValueKey('ready-send-1')),
      lessThan(seen.indexOf(const ValueKey('ready-save-1'))),
    );
    // And back with Shift+Tab.
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('a misspelt book is read, and says what is shown', (t) async {
    final c = await open(t);
    await type(t, 'jhon 3 16');
    expect(find.text('Showing John 3:16'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(trayOf(c).items.single.reference, 'John 3:16');
    await type(t, 'john chapter three verse sixteen');
    expect(find.text('Showing John 3:16'), findsNothing);
    expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
    await type(t, 'jo 3');
    for (final b in ['Job', 'Joel', 'John', 'Jonah', 'Joshua']) {
      expect(find.byKey(ValueKey('search-book-$b')), findsOneWidget);
    }
  });

  testWidgets('only common words show the phrase and a hint', (t) async {
    await open(t);
    await type(t, 'thou art');
    expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
    expect(find.textContaining('Add another word'), findsOneWidget);
    await type(t, 'the');
    expect(find.textContaining('add another word'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-hit-0')), findsNothing);
  });

  testWidgets('/ and Ctrl+F focus the box; Commands has it', (t) async {
    await open(t);
    bool inBox() {
      final f = FocusManager.instance.primaryFocus?.context;
      return f != null &&
              f.findAncestorWidgetOfExactType<EditableText>() != null ||
          f?.widget is EditableText;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    expect(inBox(), isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.slash);
    await settle(t);
    expect(inBox(), isTrue);
    // The / was a key, not text.
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('lyrics-search')))
          .controller!
          .text,
      isEmpty,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyF);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    expect(inBox(), isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    final entry = find.byKey(const ValueKey('command-search-bible'));
    await t.ensureVisible(entry);
    await t.pump();
    expect(entry, findsOneWidget);
    await t.tap(entry);
    await settle(t);
    expect(inBox(), isTrue);
  });

  testWidgets('the Commands entry from another page lands in the box', (
    t,
  ) async {
    await open(t);
    await home(t).goToPage(0);
    await settle(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    final entry = find.byKey(const ValueKey('command-search-bible'));
    await t.ensureVisible(entry);
    await t.pump();
    await t.tap(entry);
    await settle(t);
    expect(home(t).page, lyricsPage);
    final f = FocusManager.instance.primaryFocus?.context;
    expect(
      f?.findAncestorWidgetOfExactType<EditableText>() != null ||
          f?.widget is EditableText,
      isTrue,
    );
  });

  testWidgets('one box: Library first, then the Bible', (t) async {
    final c = await open(t);
    await type(t, 'grace');
    expect(
      find.byKey(const ValueKey('search-library-amazing')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('search-bible')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
    final library = t.getTopLeft(
      find.byKey(const ValueKey('search-library-amazing')),
    );
    final bible = t.getTopLeft(find.byKey(const ValueKey('search-hit-0')));
    expect(library.dy, lessThan(bible.dy));
    // A reference puts the Bible first.
    await type(t, 'john 3');
    expect(find.byKey(const ValueKey('search-library-amazing')), findsNothing);
    // Choosing a Library line selects it.
    await type(t, 'amazing');
    await t.tap(find.byKey(const ValueKey('search-library-amazing')));
    await settle(t);
    expect(c.lyrics.selectedId, 'amazing');
  });

  testWidgets('book candidates are chips; tapping one completes the box', (
    t,
  ) async {
    await open(t);
    await type(t, 'jo');
    for (final b in ['Job', 'Joel', 'John', 'Jonah', 'Joshua']) {
      expect(find.byKey(ValueKey('search-book-$b')), findsOneWidget);
    }
    await t.tap(find.byKey(const ValueKey('search-book-John')));
    await settle(t);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('lyrics-search')))
          .controller!
          .text,
      'John ',
    );
  });

  testWidgets('a bad reference says what is wrong', (t) async {
    await open(t);
    await type(t, 'john 40');
    expect(
      find.text('There is no chapter 40 in John: it has 21 chapters.'),
      findsOneWidget,
    );
  });

  group('Ready tray', () {
    testWidgets(
      'two passages, extend, save, remove, and it survives leaving the page',
      (t) async {
        final c = await open(t);
        final tray = trayOf(c);
        tray.addReady(index.bible.read('John 3:16'));
        tray.addReady(
          index.bible.read('Psalm 23:1-2'),
          source: 'listening',
          heardAs: 'the lord is my shepherd',
        );
        await settle(t);
        expect(tray.items.map((p) => p.reference), [
          'Psalm 23:1-2',
          'John 3:16',
        ]);
        expect(find.byKey(const ValueKey('ready-source-2')), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const ValueKey('ready-source-2'))).data,
          'Suggested while listening · heard as “the lord is my shepherd”',
        );
        expect(find.byKey(const ValueKey('ready-source-1')), findsNothing);

        // + next verse.
        await t.tap(find.byKey(const ValueKey('ready-next-1')));
        await settle(t);
        expect(tray.byNumber(1)!.reference, 'John 3:16-17');
        expect(tray.byNumber(2)!.reference, 'Psalm 23:1-2');
        await t.tap(find.byKey(const ValueKey('ready-next-2')));
        await settle(t);
        expect(tray.byNumber(2)!.reference, 'Psalm 23:1-3');
        // Whole chapter.
        await t.tap(find.byKey(const ValueKey('ready-chapter-2')));
        await settle(t);
        expect(tray.byNumber(2)!.reference, 'Psalm 23');
        expect(tray.byNumber(2)!.verses, hasLength(6));
        await t.tap(find.byKey(const ValueKey('ready-chapter-2')));
        await settle(t);
        expect(find.text('That is already the whole chapter.'), findsOneWidget);

        // Save to Library, once.
        await t.tap(find.byKey(const ValueKey('ready-save-2')));
        await settle(t);
        final saved = c.state.lyrics.items.where((i) => i.kind == 'scripture');
        expect(saved.single.title, 'Psalm 23');
        expect(saved.single.version, 'KJV');
        expect(saved.single.verses, hasLength(6));
        expect(find.text('In Library'), findsOneWidget);

        // Leaving the page and coming back keeps the tray.
        await home(t).goToPage(0);
        await settle(t);
        await home(t).goToPage(lyricsPage);
        await settle(t);
        expect(find.byKey(const ValueKey('ready-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('ready-2')), findsOneWidget);

        // Remove.
        await t.tap(find.byKey(const ValueKey('ready-remove-1')));
        await settle(t);
        expect(tray.items.map((p) => p.number), [2]);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'extending what is on the screens keeps the slide and adds the words',
      (t) async {
        final c = await open(t);
        final tray = trayOf(c);
        tray.addReady(index.bible.read('John 3:16'));
        tray.send(c, 1);
        await settle(t);
        expect(c.lyrics.slide!.reference, 'John 3:16 · KJV');
        await t.tap(find.byKey(const ValueKey('ready-next-1')));
        await settle(t);
        expect(c.lyrics.slide!.reference, 'John 3:16-17 · KJV');
        expect(c.lyrics.showing, isTrue);
        // Its key changes, so every screen sees new words.
        expect(
          c.lyrics.field(LyricTarget.second)!['key'],
          contains('ready-1-1'),
        );
      },
    );

    testWidgets(
      'a long passage splits into slides, and Next steps through them',
      (t) async {
        final c = await open(t);
        trayOf(c).addReady(index.bible.read('Psalm 23'));
        trayOf(c).send(c, 1);
        await settle(t);
        expect(c.lyrics.item!.slides.length, greaterThan(1));
        expect(c.lyrics.index, 0);
        c.lyrics.next(selected: c.lyrics.selectedId);
        expect(c.lyrics.index, 1);
        expect(
          c.lyrics.slide!.text,
          isNot(contains('The LORD is my shepherd')),
        );
      },
    );

    testWidgets('adding it twice moves it to the front', (t) async {
      final c = await open(t);
      final tray = trayOf(c);
      tray.addReady(index.bible.read('John 3:16'));
      tray.addReady(index.bible.read('Psalm 23:1'));
      tray.addReady(index.bible.read('John 3:16'));
      expect(tray.items.map((p) => p.reference), ['John 3:16', 'Psalm 23:1']);
      for (var i = 0; i < 20; i++) {
        tray.addReady(index.bible.read('Genesis 1:${i + 1}'));
      }
      expect(tray.items, hasLength(ReadyTray.limit));
      await settle(t);
    });

    testWidgets('the end of a book says so', (t) async {
      final c = await open(t);
      final tray = trayOf(c);
      tray.addReady(index.bible.read('Revelation 22:21'));
      expect(await tray.extend(c, 1), 'That is the end of Revelation.');
      tray.addReady(index.bible.read('Psalm 23:6'));
      expect(await tray.extend(c, 2), isNull);
      expect(tray.byNumber(2)!.reference, 'Psalm 23:6–24:1');
    });
  });

  testWidgets('the index builds in an isolate and can be used', (t) async {
    ScriptureIndex.resetForTest();
    BibleLibrary_reset();
    await t.runAsync(() async {
      final built = await ScriptureIndex.load();
      expect(built.verseCount, 31102);
      expect(built.search('john 3:16').hits.single.reference, 'John 3:16');
      // ignore: avoid_print
      print(
        'Index built in an isolate from the asset in '
        '${ScriptureIndex.lastBuild!.inMilliseconds} ms.',
      );
      expect(ScriptureIndex.lastBuild!.inSeconds, lessThan(30));
    });
    expect(ScriptureIndex.state.value, ScriptureIndexState.ready);
  });

  testWidgets('before the index is ready the box says it is preparing', (
    t,
  ) async {
    ScriptureIndex.resetForTest();
    ScriptureIndex.state.value = ScriptureIndexState.preparing;
    ReadyTray.bibleLoader = (_) async => index.bible;
    await openLyrics(t, running: false);
    await type(t, 'john 3');
    expect(find.text('Preparing search…'), findsOneWidget);
    // When it is ready the same text is answered without another keystroke.
    ScriptureIndex.useForTest(index);
    await settle(t);
    expect(find.text('Preparing search…'), findsNothing);
    expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
  });

  group('screens', () {
    final sizes = <(String, Size, bool, double)>[
      ('phone upright', const Size(360, 780), false, 1.0),
      ('phone upright text 1.6', const Size(360, 780), false, 1.6),
      ('phone sideways', const Size(780, 360), false, 1.0),
      ('1366 × 768', const Size(1366, 768), true, 1.0),
      ('1366 × 768 text 1.6', const Size(1366, 768), true, 1.6),
      ('1920 × 1080', const Size(1920, 1080), true, 1.0),
      ('1920 × 1080 text 1.6', const Size(1920, 1080), true, 1.6),
    ];
    for (final (name, size, desktop, scale) in sizes) {
      testWidgets('no overflow: $name', (t) async {
        final c = await open(t, size: size, desktop: desktop, textScale: scale);
        trayOf(c)
          ..addReady(index.bible.read('John 3:16-18'))
          ..addReady(
            index.bible.read('Psalm 23'),
            source: 'listening',
            heardAs: 'the lord is my shepherd i shall not want',
          );
        await settle(t);
        if (desktop) {
          await type(t, 'shadow valley death');
        } else {
          await t.tap(find.byKey(const ValueKey('scripture-search-launcher')));
          await settle(t);
          await t.enterText(
            find.byKey(const ValueKey('scripture-sheet-field')),
            'shadow valley death',
          );
          await settle(t);
        }
        expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        // And a chapter, with thirty rows.
        if (desktop) {
          await type(t, 'psalm 119');
        } else {
          await t.enterText(
            find.byKey(const ValueKey('scripture-sheet-field')),
            'psalm 119',
          );
          await settle(t);
        }
        expect(t.takeException(), isNull);
      });
    }
  });

  group('goldens', () {
    testWidgets('desktop: a word search with the match marked', (t) async {
      await open(t);
      await type(t, 'shadow valley death');
      expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/scripture-search-words-1366.png'),
      );
    });

    testWidgets('desktop: a reference with Ready holding two', (t) async {
      final c = await open(t);
      trayOf(c)
        ..addReady(index.bible.read('John 3:16'))
        ..addReady(
          index.bible.read('Psalm 23:1-3'),
          source: 'listening',
          heardAs: 'the lord is my shepherd',
        );
      await type(t, 'john 3');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/scripture-search-reference-1366.png'),
      );
    });

    testWidgets('desktop: Ready with two passages and nothing typed', (
      t,
    ) async {
      final c = await open(t);
      trayOf(c)
        ..addReady(index.bible.read('John 3:16-17'))
        ..addReady(
          index.bible.read('Psalm 23:1-3'),
          source: 'listening',
          heardAs: 'the lord is my shepherd',
        );
      trayOf(c).send(c, 2);
      await settle(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/scripture-ready-tray-1366.png'),
      );
    });

    testWidgets('desktop: nothing matches', (t) async {
      await open(t);
      await type(t, 'zqxjv wvkqz');
      expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/scripture-search-empty-1366.png'),
      );
    });

    testWidgets('phone: the page with Ready and the search field', (t) async {
      final c = await open(t, size: const Size(360, 780), desktop: false);
      trayOf(c)
        ..addReady(index.bible.read('John 3:16-17'))
        ..addReady(index.bible.read('Psalm 23:1-3'));
      await settle(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/scripture-ready-phone.png'),
      );
    });

    testWidgets('phone: the search sheet with results', (t) async {
      await open(t, size: const Size(360, 780), desktop: false);
      await t.tap(find.byKey(const ValueKey('scripture-search-launcher')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('scripture-sheet-field')),
        'shadow valley death',
      );
      await settle(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/scripture-search-words-phone.png'),
      );
    });

    testWidgets('phone: tapping a result closes the sheet and fills Ready', (
      t,
    ) async {
      final c = await open(t, size: const Size(360, 780), desktop: false);
      await t.tap(find.byKey(const ValueKey('scripture-search-launcher')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('scripture-sheet-field')),
        'john 3 16',
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('search-hit-0')));
      await settle(t);
      expect(find.byKey(const ValueKey('scripture-sheet-field')), findsNothing);
      expect(trayOf(c).items.single.reference, 'John 3:16');
      expect(find.byKey(const ValueKey('ready-1')), findsOneWidget);
      // And the play button sends it.
      await t.tap(find.byKey(const ValueKey('scripture-search-launcher')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('scripture-sheet-field')),
        'john 3 17',
      );
      await settle(t);
      await t.tap(find.byTooltip('Send now').first);
      await settle(t);
      expect(c.lyrics.slide!.text, contains('For God sent not his Son'));
    });
  });
}

// ignore: non_constant_identifier_names
void BibleLibrary_reset() {}

ScriptureSearchController _controllerOf(WidgetTester t) {
  final results = t.widget<ScriptureResults>(find.byType(ScriptureResults));
  return results.controller;
}
