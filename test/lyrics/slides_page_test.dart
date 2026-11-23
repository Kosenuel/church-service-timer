import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/lyrics/slides_parts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'lyrics_page_test.dart' show openLyrics, settle, home;

// The tidied Slides page: one row of four buttons, a one-line status,
// Screens, Background and Look as rows that fold open, and Library tabs.
// See docs/LYRICS-DESIGN.md, "The Slides page".

ValueKey<String> k(String key) => ValueKey(key);

/// Psalm 23:1-3 as the Bible search saves it: one slide, named by its
/// reference, as the passage is.
LyricItem psalm() => LyricItem(
  id: 'psalm',
  kind: 'scripture',
  title: 'Psalm 23:1-3',
  version: 'KJV',
  verses: const [
    LyricVerse(23, 1, 'The LORD is my shepherd; I shall not want.'),
    LyricVerse(
      23,
      2,
      'He maketh me to lie down in green pastures: he leadeth me beside the still waters.',
    ),
    LyricVerse(
      23,
      3,
      'He restoreth my soul: he leadeth me in the paths of righteousness for his name’s sake.',
    ),
  ],
);

/// Whether [text] is drawn whole: as wide as it wants to be, not cut.
void expectWhole(WidgetTester t, Finder text, String reason) {
  for (final e in text.evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(
      p.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(p.size.width + .5),
      reason: '$reason: ${p.text.toPlainText()}',
    );
  }
}

/// The row whose header has the keyboard, by its key.
String? focusedRow() {
  final context = FocusManager.instance.primaryFocus?.context;
  final key = context?.findAncestorWidgetOfExactType<SlidesFold>()?.key;
  return key is ValueKey<String> ? key.value : null;
}

Future<void> openRow(WidgetTester t, String row) async {
  await t.ensureVisible(find.byKey(k('$row-header')));
  await t.tap(find.byKey(k('$row-header')));
  await settle(t);
}

void main() {
  setUpAll(loadAppFonts);
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await BibleLibrary.load();
  });

  group('the four buttons', () {
    testWidgets('stay on one row at one height at every size and text scale', (
      t,
    ) async {
      for (final (size, desktop) in const [
        (Size(360, 780), false),
        (Size(780, 360), false),
        (Size(1024, 768), true),
        (Size(1366, 768), true),
        (Size(1920, 1080), true),
      ]) {
        for (final scale in [1.0, 1.6]) {
          final c = await openLyrics(
            t,
            size: size,
            desktop: desktop,
            textScale: scale,
          );
          c.lyrics.selectedId = 'amazing';
          c.lyrics.show('amazing', 1);
          await settle(t);
          final why = '$size ×$scale';
          expect(t.takeException(), isNull, reason: why);
          final rects = [
            for (final b in ['previous', 'next', 'clear', 'black'])
              t.getRect(find.byKey(k('lyrics-$b'))),
          ];
          for (final r in rects) {
            expect(r.top, moreOrLessEquals(rects.first.top), reason: why);
            expect(r.height, moreOrLessEquals(rects.first.height), reason: why);
          }
          // Left to right, and Next the widest.
          for (var i = 1; i < rects.length; i++) {
            expect(rects[i].left, greaterThan(rects[i - 1].right), reason: why);
          }
          for (final i in [0, 2, 3]) {
            expect(rects[1].width, greaterThan(rects[i].width), reason: why);
          }
          await t.pumpWidget(const SizedBox());
        }
      }
    });

    testWidgets('show their keys on a computer, under the words', (t) async {
      await openLyrics(t);
      final row = find.byKey(k('lyrics-transport'));
      for (final word in ['Previous', 'Next', 'Clear', 'Black']) {
        expect(
          find.descendant(of: row, matching: find.text(word)),
          findsOneWidget,
        );
      }
      for (final key in ['or Space', 'Esc', 'B']) {
        expect(
          find.descendant(of: row, matching: find.text(key)),
          findsOneWidget,
          reason: key,
        );
      }
      // The keys go before the words get small: none on a narrow phone
      // with large text, and still one row (checked above).
      await t.pumpWidget(const SizedBox());
      await openLyrics(
        t,
        size: const Size(360, 780),
        desktop: false,
        textScale: 1.6,
      );
      expect(
        find.descendant(
          of: find.byKey(k('lyrics-transport')),
          matching: find.text('Esc'),
        ),
        findsNothing,
      );
    });

    testWidgets('Black shows as on while the screens are black', (t) async {
      final c = await openLyrics(t);
      c.lyrics.show('amazing', 0);
      await settle(t);
      await t.tap(find.byKey(k('lyrics-black')));
      await settle(t);
      expect(c.lyrics.black, isTrue);
      final black = t.widget<ButtonStyleButton>(find.byKey(k('lyrics-black')));
      expect(
        black.style?.backgroundColor?.resolve({}),
        Colors.black,
        reason: 'black, as the screens are',
      );
      final handle = t.ensureSemantics();
      expect(
        t.getSemantics(find.byKey(k('lyrics-black'))),
        isSemantics(isToggled: true, hasToggledState: true),
      );
      handle.dispose();
    });
  });

  group('the status line', () {
    testWidgets('is one line and names a Bible passage once', (t) async {
      final c = await openLyrics(t, size: const Size(360, 780), desktop: false);
      await c.lyrics.save(psalm());
      c.lyrics.show('psalm', 0);
      await settle(t);
      final status = find.byKey(k('lyrics-status'));
      // It used to read "Psalm 23:1-3 · Psalm 23:1-3 · on full screen…".
      expect(c.lyrics.statusLine, 'Psalm 23:1-3');
      expect(t.widget<Text>(status).data, 'Psalm 23:1-3');
      expect(t.widget<Text>(status).maxLines, 1);
      expect(t.widget<Text>(status).softWrap, isFalse);

      c.lyrics.show('amazing', 1);
      await settle(t);
      expect(t.widget<Text>(status).data, 'Amazing Grace · Verse 2 · 2 of 4');
      c.lyrics.toggleBlack();
      await settle(t);
      expect(t.widget<Text>(status).data, 'Black on the screens');
      c.lyrics.toggleBlack();
      await c.lyrics.setLook(
        c.lyrics.look.copyWith(toSecond: false, toWeb: false, toStage: false),
      );
      await settle(t);
      expect(
        t.widget<Text>(status).data,
        'Amazing Grace · Verse 2 · 2 of 4 · on no screen',
      );
      expect(t.takeException(), isNull);
    });

    test('a slide named like its item is not named twice', () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      String line(LyricItem item, [int i = 0]) {
        c.lyrics.showTransient(item, i);
        return c.lyrics.statusLine;
      }

      expect(line(psalm()), 'Psalm 23:1-3');
      expect(
        line(
          LyricItem(
            id: 'p',
            kind: 'scripture',
            title: 'Psalm 23',
            words: 'The Lord is my shepherd.\n\nHe restoreth my soul.',
          ),
          1,
        ),
        'Psalm 23 (2)',
      );
      expect(
        line(
          LyricItem(
            id: 'a',
            kind: 'announcement',
            title: 'Harvest lunch',
            words: 'All welcome',
          ),
        ),
        'Harvest lunch · Announcement',
      );
      expect(
        line(LyricItem(id: 's', kind: 'song', title: 'Holy', words: 'Holy')),
        'Holy · Slide 1',
      );
      c.dispose();
    });
  });

  // Tall, so every row and its controls are built without scrolling.
  const tall = Size(1366, 1700);

  group('rows that fold open', () {
    testWidgets('Background and Look start closed, open in place, and are '
        'remembered on this device only', (t) async {
      final c = await openLyrics(t, size: tall, running: false);
      for (final row in ['lyrics-background-row', 'lyrics-look']) {
        expect(find.byKey(k('$row-header')), findsOneWidget);
        expect(find.byKey(k('$row-body')), findsNothing, reason: row);
      }
      // Closed, each says what is chosen.
      expect(find.text('Mountain dusk'), findsOneWidget);
      expect(find.byKey(k('lyrics-bg-swatch')), findsOneWidget);
      expect(
        find.text('Dim 40% · Medium · Centre · Gentle · Countdown'),
        findsOneWidget,
      );

      await openRow(t, 'lyrics-background-row');
      await openRow(t, 'lyrics-look');
      expect(find.byKey(k('lyrics-background-row-body')), findsOneWidget);
      expect(find.byKey(k('lyrics-look-body')), findsOneWidget);
      expect(c.state.slidesOpen, {'background', 'look'});
      expect(t.takeException(), isNull);

      // Kept with this device's saved state, read back after a restart.
      expect(AppState.fromJson(c.state.toJson()).slidesOpen, {
        'background',
        'look',
      });
      // Leaving the page and coming back finds them as they were.
      await home(t).goToPage(0);
      await settle(t);
      await home(t).goToPage(lyricsPage);
      await settle(t);
      expect(find.byKey(k('lyrics-background-row-body')), findsOneWidget);
      expect(find.byKey(k('lyrics-look-body')), findsOneWidget);

      // Not in a backup, and restoring one leaves them alone.
      final backup = exportBackup(c.state, c.now);
      expect(backup, isNot(contains('slidesOpen')));
      expect(backup, isNot(contains('slidesTab')));
      expect(await c.restoreBackup(importBackup(backup, c.now)), isTrue);
      expect(c.state.slidesOpen, {'background', 'look'});

      await openRow(t, 'lyrics-look');
      expect(find.byKey(k('lyrics-look-body')), findsNothing);
      expect(c.state.slidesOpen, {'background'});
    });

    test(
      'saved data from before the rows, or odd values, read as closed',
      () async {
        final c = AppController(FakePort());
        await c.initialize(startTicker: false);
        final before = c.state.toJson()
          ..remove('slidesOpen')
          ..remove('slidesTab');
        c.dispose();
        final fresh = AppState.fromJson(before);
        expect(fresh.slidesOpen, isEmpty);
        expect(fresh.slidesTab, 'all');
        final json = fresh.toJson()
          ..['slidesOpen'] = ['look', 'nonsense', 3, null]
          ..['slidesTab'] = 'videos';
        final odd = AppState.fromJson(json);
        expect(odd.slidesOpen, {'look'});
        expect(odd.slidesTab, 'all');
        final kept = AppState.fromJson(
          fresh.toJson()..['slidesTab'] = 'announcement',
        );
        expect(kept.slidesTab, 'announcement');
      },
    );

    testWidgets('the Look row sums up the look as it is, and keeps every '
        'control', (t) async {
      final c = await openLyrics(t, size: tall, running: false);
      await c.lyrics.setLook(
        c.lyrics.look.copyWith(
          dim: 50,
          size: 'l',
          align: 'left',
          motion: 'still',
          chip: false,
        ),
      );
      await settle(t);
      expect(find.text('Dim 50% · Large · Left · Still'), findsOneWidget);
      await openRow(t, 'lyrics-look');
      for (final control in [
        'lyrics-dim',
        'lyrics-size',
        'lyrics-align',
        'lyrics-motion',
        'lyrics-chip-toggle',
      ]) {
        expect(find.byKey(k(control)), findsOneWidget, reason: control);
      }
      await t.tap(find.byKey(k('lyrics-chip-toggle')));
      await settle(t);
      expect(c.lyrics.look.chip, isTrue);
      await t.tap(find.text('S'));
      await settle(t);
      expect(c.lyrics.look.size, 's');
      expect(
        find.text('Dim 50% · Small · Left · Still · Countdown'),
        findsOneWidget,
      );
      // Linen is never dimmed, and the row says so.
      await c.lyrics.setLook(c.lyrics.look.copyWith(background: 'linen'));
      await settle(t);
      expect(
        find.text('Not dimmed · Small · Left · Still · Countdown'),
        findsOneWidget,
      );
      expect(
        lyricLookSummary(const LyricsLook()),
        'Dim 70% · Medium · Centre · Gentle · Countdown',
      );
    });

    testWidgets('the background picker keeps its groups as chips, and the row '
        'names what is chosen', (t) async {
      final c = await openLyrics(t, size: tall, running: false);
      await openRow(t, 'lyrics-background-row');
      for (final g in ['designs', 'nature', 'people', 'yours']) {
        expect(find.byKey(k('lyrics-bg-group-$g')), findsOneWidget);
      }
      // The current background's group shows first.
      for (final id in lyricDrawnBackgrounds.keys) {
        expect(find.byKey(k('lyrics-bg-$id')), findsOneWidget, reason: id);
      }
      await t.tap(find.byKey(k('lyrics-bg-group-nature')));
      await settle(t);
      expect(find.byKey(k('lyrics-bg-aurora')), findsNothing);
      await t.ensureVisible(find.byKey(k('lyrics-bg-photo:candle')));
      await t.tap(find.byKey(k('lyrics-bg-photo:candle')));
      await settle(t);
      expect(c.lyrics.look.background, 'photo:candle');
      expect(
        find.descendant(
          of: find.byKey(k('lyrics-background-row-header')),
          matching: find.text('Candle'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(k('lyrics-bg-group-people')));
      await settle(t);
      expect(find.byKey(k('lyrics-bg-photo:worship-crowd-hands')), findsOne);
      await t.tap(find.byKey(k('lyrics-bg-group-yours')));
      await settle(t);
      expect(find.byKey(k('lyrics-bg-own')), findsOneWidget);
      expect(find.byKey(k('lyrics-photo-credits')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Screens is one row; Change opens the same choices', (t) async {
      final c = await openLyrics(t, size: tall, running: false);
      final header = find.byKey(k('lyrics-screens-row-header'));
      expect(
        find.descendant(
          of: header,
          matching: find.text('Second screen · Web screens'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(k('lyrics-send-stage')), findsNothing);
      expect(find.byKey(k('lyrics-send-note')), findsNothing);
      await openRow(t, 'lyrics-screens-row');
      await t.tap(find.byKey(k('lyrics-send-stage')));
      await settle(t);
      expect(c.lyrics.look.toStage, isTrue);
      expect(
        find.descendant(
          of: header,
          matching: find.text('Second screen · Web screens · Stage screens'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(k('lyrics-send-note')), findsOneWidget);
      await c.lyrics.setLook(
        c.lyrics.look.copyWith(toSecond: false, toWeb: false, toStage: false),
      );
      await settle(t);
      expect(
        find.descendant(of: header, matching: find.text('None chosen')),
        findsOneWidget,
      );
    });

    testWidgets('Tab reaches the rows, Enter and Space open and close them, '
        'and a screen reader hears which', (t) async {
      final handle = t.ensureSemantics();
      final c = await openLyrics(t, size: tall);
      await t.tap(find.byKey(k('lyrics-item-amazing')));
      await settle(t);
      c.lyrics.show('amazing', 1);
      await settle(t);
      expect(
        t.getSemantics(find.byKey(k('lyrics-look-header'))),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
      );
      // Tab, as a person would, until the Look row has the keyboard.
      for (var i = 0; i < 80 && focusedRow() != 'lyrics-look'; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
      }
      expect(focusedRow(), 'lyrics-look');
      expect(slidesFoldHasFocus(), isTrue);

      // Space opens it, and does not move the slides on.
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await settle(t);
      expect(find.byKey(k('lyrics-look-body')), findsOneWidget);
      expect(c.lyrics.index, 1, reason: 'Space opened the row');
      expect(
        t.getSemantics(find.byKey(k('lyrics-look-header'))),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );
      // Enter closes it.
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(t);
      expect(find.byKey(k('lyrics-look-body')), findsNothing);
      expect(c.lyrics.index, 1);
      // The arrows, Esc and B still work with the row focused.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(t);
      expect(c.lyrics.index, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await settle(t);
      expect(c.lyrics.black, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(c.lyrics.showing, isFalse);
      // So does / for the search box, and typing there is only typing.
      await t.sendKeyEvent(LogicalKeyboardKey.slash);
      await settle(t);
      expect(focusedRow(), isNull);
      for (final key in [
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await t.sendKeyEvent(key);
        await settle(t);
      }
      expect(c.lyrics.black, isFalse);
      expect(c.lyrics.showing, isFalse);
      handle.dispose();
    });
  });

  group('Library tabs', () {
    testWidgets('full names; a remembered tab; an empty state for each; '
        'search covers every kind', (t) async {
      final c = await openLyrics(t, running: false);
      final tabs = find.byKey(k('lyrics-tabs'));
      for (final name in ['Songs', 'Bible verses', 'Announcements', 'All']) {
        expect(
          find.descendant(of: tabs, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expectWhole(
        t,
        find.descendant(of: tabs, matching: find.byType(RichText)),
        '1366',
      );
      // All, to begin with: nothing is hidden from an existing library.
      for (final id in ['amazing', 'holy', 'well']) {
        expect(find.byKey(k('lyrics-item-$id')), findsOneWidget);
      }
      await t.tap(find.byKey(k('lyrics-tab-scripture')));
      await settle(t);
      expect(find.byKey(k('lyrics-item-amazing')), findsNothing);
      expect(find.textContaining('No Bible verses saved yet'), findsOneWidget);
      expect(c.state.slidesTab, 'scripture');
      await t.tap(find.byKey(k('lyrics-tab-announcement')));
      await settle(t);
      expect(find.textContaining('No announcements yet'), findsOneWidget);
      await t.tap(find.byKey(k('lyrics-tab-song')));
      await settle(t);
      expect(find.byKey(k('lyrics-item-holy')), findsOneWidget);
      await c.lyrics.save(psalm());
      await settle(t);
      expect(find.byKey(k('lyrics-item-psalm')), findsNothing);
      await t.tap(find.byKey(k('lyrics-tab-scripture')));
      await settle(t);
      expect(find.byKey(k('lyrics-item-psalm')), findsOneWidget);
      expect(find.byKey(k('lyrics-item-holy')), findsNothing);

      // A search finds songs from the Bible verses tab.
      await t.enterText(find.byKey(k('lyrics-search')), 'grace');
      await settle(t);
      expect(find.byKey(k('search-library-amazing')), findsOneWidget);
      expect(find.byKey(k('lyrics-tabs')), findsNothing);
      await t.enterText(find.byKey(k('lyrics-search')), '');
      await settle(t);

      // The tab comes back with the page, and stays on this device.
      await home(t).goToPage(0);
      await settle(t);
      await home(t).goToPage(lyricsPage);
      await settle(t);
      expect(find.byKey(k('lyrics-item-psalm')), findsOneWidget);
      expect(find.byKey(k('lyrics-item-amazing')), findsNothing);
      expect(AppState.fromJson(c.state.toJson()).slidesTab, 'scripture');
      expect(exportBackup(c.state, c.now), isNot(contains('slidesTab')));
    });

    testWidgets('an empty library says how to start on every tab', (t) async {
      final c = await openLyrics(t, running: false);
      for (final id in ['amazing', 'holy', 'well']) {
        await c.lyrics.delete(id);
      }
      await settle(t);
      for (final (tab, words) in [
        ('all', 'Nothing stored yet'),
        ('song', 'No songs yet'),
        ('scripture', 'No Bible verses saved yet'),
        ('announcement', 'No announcements yet'),
      ]) {
        await t.tap(find.byKey(k('lyrics-tab-$tab')));
        await settle(t);
        expect(
          find.descendant(
            of: find.byKey(k('lyrics-library-empty')),
            matching: find.textContaining(words),
          ),
          findsOneWidget,
          reason: tab,
        );
      }
    });

    testWidgets('tabs and the Add row fit a phone with large text, and on a '
        'phone the sheet searches every kind', (t) async {
      final c = await openLyrics(
        t,
        size: const Size(360, 780),
        desktop: false,
        textScale: 1.6,
        running: false,
      );
      await t.tap(find.byKey(k('lyrics-picker')));
      await settle(t);
      expect(t.takeException(), isNull);
      final tabs = find.byKey(k('lyrics-tabs'));
      expect(tabs, findsOneWidget);
      // They scroll sideways rather than squeeze or cut a name.
      expectWhole(
        t,
        find.descendant(of: tabs, matching: find.byType(RichText)),
        'phone ×1.6',
      );
      await t.ensureVisible(find.byKey(k('lyrics-tab-song')));
      await settle(t);
      await t.tap(find.byKey(k('lyrics-tab-song')));
      await settle(t);
      expect(c.state.slidesTab, 'song');
      final add = find.byKey(k('lyrics-add-row'));
      await t.ensureVisible(add);
      expectWhole(
        t,
        find.descendant(of: add, matching: find.byType(RichText)),
        'Add row',
      );
      for (final b in [
        'lyrics-add-song',
        'lyrics-add-scripture',
        'lyrics-add-announcement',
      ]) {
        expect(find.byKey(k(b)), findsOneWidget);
      }
      // Searching in the sheet finds an announcement from the Songs tab.
      await c.lyrics.save(
        LyricItem(
          id: 'harvest',
          kind: 'announcement',
          title: 'Harvest lunch',
          words: 'All welcome',
        ),
      );
      await settle(t);
      expect(find.byKey(k('lyrics-item-harvest')), findsNothing);
      await t.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byKey(k('lyrics-search')),
        ),
        'harvest',
      );
      await settle(t);
      expect(find.byKey(k('lyrics-item-harvest')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Add row has the full words on a computer', (t) async {
      for (final size in const [Size(1366, 768), Size(1920, 1080)]) {
        await openLyrics(t, size: size, running: false);
        final add = find.byKey(k('lyrics-add-row'));
        for (final words in ['+ Song', '+ Bible verses', '+ Announcement']) {
          expect(
            find.descendant(of: add, matching: find.text(words)),
            findsOneWidget,
            reason: '$size $words',
          );
        }
        expectWhole(
          t,
          find.descendant(of: add, matching: find.byType(RichText)),
          '$size',
        );
        // One row.
        final song = t.getRect(find.byKey(k('lyrics-add-song')));
        final notice = t.getRect(find.byKey(k('lyrics-add-announcement')));
        expect(notice.top, moreOrLessEquals(song.top));
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  testWidgets('a repeat mark shows as written on the cards, the preview, '
      'the stage screens and web screens', (t) async {
    final c = await openLyrics(t, running: false);
    await c.lyrics.save(
      LyricItem(
        id: 'work',
        kind: 'song',
        title: 'God Will Work It Out',
        words: 'Chorus\nGod will work it out _(x2)_\nOne thing I know',
      ),
    );
    await settle(t);
    await t.tap(find.byKey(k('lyrics-item-work')));
    await settle(t);
    final card = find.byKey(k('lyrics-slide-0'));
    expect(
      find.descendant(
        of: card,
        matching: find.text('God will work it out (x2)\nOne thing I know'),
      ),
      findsOneWidget,
    );
    await t.tap(card);
    await settle(t);
    const shown = 'God will work it out (x2)\nOne thing I know';
    final preview = t.widget<LyricStage>(
      find.descendant(
        of: find.byKey(k('lyrics-preview')),
        matching: find.byType(LyricStage),
      ),
    );
    expect(preview.data['text'], shown);
    for (final target in LyricTarget.values) {
      expect(
        c.lyrics.field(target, always: true)!['text'],
        shown,
        reason: '$target',
      );
    }
    expect(c.stageWindowSnapshot()['lyrics']['text'], shown);
    expect(webLyrics(c.lyrics.field(LyricTarget.web)!)['text'], shown);
    // The words themselves keep what was typed.
    expect(c.state.lyrics.byId('work')!.words, contains('_(x2)_'));
  });

  testWidgets('the keys are one quiet line under the slides', (t) async {
    await openLyrics(t);
    await t.tap(find.byKey(k('lyrics-item-amazing')));
    await settle(t);
    final tip = find.byKey(k('lyrics-tip'));
    final slides = t.getRect(find.byKey(k('lyrics-slides')));
    expect(t.getRect(tip).top, greaterThan(slides.bottom));
    expect(t.getSize(tip).height, lessThan(26));
    expect(find.byType(SlidesKeysLine), findsOneWidget);
  });
}
