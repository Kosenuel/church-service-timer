import 'dart:async';
import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/lyrics/lyric_editors.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class DesktopPort extends FakePort {
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
  Map<String, dynamic>? textFile;
  @override
  Future<Map<String, dynamic>?> pickTextFile() async => textFile;
}

const amazing = '''Verse 1
Amazing grace! How sweet the sound
That saved a wretch like me!
I once was lost, but now am found;
Was blind, but now I see.

Verse 2
’Twas grace that taught my heart to fear,
And grace my fears relieved;
How precious did that grace appear
The hour I first believed.

Verse 3
Through many dangers, toils and snares,
I have already come;
’Tis grace hath brought me safe thus far,
And grace will lead me home.

Verse 4
The Lord has promised good to me,
His word my hope secures;
He will my shield and portion be,
As long as life endures.''';

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5),
  Segment('Praise & Worship', 20),
  Segment('Sermon', 40),
], DisplaySettings());

/// The app with three stored songs, on a computer or a phone, with a
/// service running when [running].
Future<AppController> openLyrics(
  WidgetTester t, {
  Size size = const Size(1366, 768),
  bool desktop = true,
  bool running = true,
  double textScale = 1,
  String finish = 'flat',
  String theme = 'royal_navy',
  Size? crop,
}) async {
  setScreen(t, size);
  final port = desktop ? DesktopPort() : FakePort();
  final c = AppController(port);
  await c.initialize(startTicker: false);
  for (final (id, title, words, by) in [
    ('amazing', 'Amazing Grace', amazing, 'John Newton'),
    (
      'holy',
      'Holy, Holy, Holy',
      'Verse 1\nHoly, holy, holy! Lord God Almighty!\nEarly in the morning our song shall rise to Thee.\n\nVerse 2\nHoly, holy, holy! All the saints adore Thee,\nCasting down their golden crowns around the glassy sea.',
      'Reginald Heber',
    ),
    (
      'well',
      'It Is Well with My Soul',
      'Verse 1\nWhen peace like a river attendeth my way,\nWhen sorrows like sea billows roll;\n\nChorus\nIt is well with my soul,\nIt is well, it is well with my soul.',
      'Horatio Spafford',
    ),
  ]) {
    await c.lyrics.save(
      LyricItem(id: id, kind: 'song', title: title, words: words, by: by),
    );
  }
  await c.lyrics.setLook(c.lyrics.look.copyWith(dim: 40));
  if (finish != 'flat' || theme != 'royal_navy') {
    await c.commit((draft, _) {
      draft.themeId = theme;
      draft.appearance = draft.appearance.copyWith(finish: finish);
    });
  }
  if (running) {
    await c.act('load', value: sunday());
    await c.act('start');
  }
  final app = MediaQuery(
    data: MediaQueryData.fromView(
      t.view,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: TimerApp(controller: c),
  );
  await t.pumpWidget(
    crop == null
        ? app
        // A corner of the window, for goldens of a finish: texture does not
        // compress, so the whole window would make a very large file.
        : Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: crop,
              child: RepaintBoundary(
                key: const ValueKey('crop'),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: app,
                  ),
                ),
              ),
            ),
          ),
  );
  await t.pump();
  // Live is checked at these sizes by its own tests (a text scale it was
  // never laid out for can cut a rundown block by a fraction of a pixel);
  // these tests look at the Lyrics page.
  t.takeException();
  final home = t.state<HomeState>(find.byType(Home));
  await home.goToPage(lyricsPage);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return c;
}

HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));

/// Settles what can settle; slide backgrounds keep moving.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadAppFonts);
  // The finish photographs, decoded before any shot draws them.
  setUpAll(FinishTextures.instance.loadAll);

  testWidgets('Slides sits after Programs in the navigation', (t) async {
    await openLyrics(
      t,
      size: const Size(390, 844),
      desktop: false,
      running: false,
    );
    final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      [for (final d in bar.destinations) (d as NavigationDestination).label],
      ['Live', 'Programs', 'Slides', 'Reports', 'Settings'],
    );
    expect(bar.selectedIndex, 2);
    expect(home(t).page, lyricsPage);
  });

  testWidgets('desktop at 1366 × 768: a song chosen and a slide live', (
    t,
  ) async {
    final c = await openLyrics(t);
    await t.tap(find.byKey(const ValueKey('lyrics-item-amazing')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('lyrics-slide-1')));
    await settle(t);
    expect(c.lyrics.statusLine, 'Amazing Grace · Verse 2');
    expect(
      find.byKey(const ValueKey('lyrics-on-screens-badge')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/lyrics-page-1366.png'),
    );
  });

  testWidgets('phone upright: a song chosen and a slide live', (t) async {
    final c = await openLyrics(t, size: const Size(360, 780), desktop: false);
    c.lyrics.selectedId = 'amazing';
    c.lyrics.show('amazing', 0);
    await settle(t);
    expect(find.byKey(const ValueKey('lyrics-bar')), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/lyrics-page-phone.png'),
    );
  });

  testWidgets('nothing overflows at any usual size or at text scale 1.6', (
    t,
  ) async {
    for (final (size, desktop) in const [
      (Size(360, 780), false),
      (Size(780, 360), false),
      (Size(1366, 768), true),
      (Size(1920, 1080), true),
      (Size(1024, 768), true),
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
        expect(t.takeException(), isNull, reason: '$size ×$scale');
        // Every part of the look scrolls into view and fits.
        final look = find.byKey(const ValueKey('lyrics-look'));
        if (look.evaluate().isNotEmpty) {
          await t.ensureVisible(look);
          await t.tap(look);
          await settle(t);
          expect(t.takeException(), isNull, reason: '$size ×$scale look');
        }
        await t.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('the background picker and the look, at full HD', (t) async {
    final c = await openLyrics(t, size: const Size(1920, 1080));
    c.lyrics.selectedId = 'amazing';
    c.lyrics.show('amazing', 0);
    await settle(t);
    // Scrolled as a person would, inside the column only.
    await t.drag(
      find.byKey(const ValueKey('lyrics-column-screens')),
      const Offset(0, -700),
    );
    await settle(t);
    // Let the photo thumbnails decode.
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await settle(t);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/lyrics-backgrounds-1920.png'),
    );
  });

  testWidgets('one click or key per slide; keys only on the Lyrics page', (
    t,
  ) async {
    final c = await openLyrics(t);
    await t.tap(find.byKey(const ValueKey('lyrics-item-amazing')));
    await settle(t);
    final revision = c.state.session.revision;
    expect(c.lyrics.showing, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(c.lyrics.index, 0, reason: '→ starts the chosen song');
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(t);
    expect(c.lyrics.index, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await settle(t);
    expect(c.lyrics.index, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(t);
    expect(c.lyrics.index, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await settle(t);
    expect(c.lyrics.black, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await settle(t);
    expect(c.lyrics.black, isFalse);
    expect(c.lyrics.index, 1, reason: 'Black off brings the slide back');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(t);
    expect(c.lyrics.showing, isFalse);
    // None of it touched the service: Space did not pause, → did not move on.
    expect(c.state.session.paused, isFalse);
    expect(c.state.session.index, 0);
    expect(c.state.session.revision, revision);
    expect(find.byType(SnackBar), findsNothing);

    // Typing in the search box is typing.
    await t.tap(find.byKey(const ValueKey('lyrics-search')));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(t);
    expect(c.lyrics.showing, isFalse);
    FocusManager.instance.primaryFocus?.unfocus();

    // On Live the same keys are Live's: → asks about the next segment.
    await home(t).goToPage(0);
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    expect(c.lyrics.showing, isFalse, reason: 'no slide from Live');
    expect(find.byKey(const ValueKey('clicker-confirm')), findsOneWidget);
  });

  testWidgets('clicking a slide shows it; Clear and Black', (t) async {
    final c = await openLyrics(t);
    await t.tap(find.byKey(const ValueKey('lyrics-item-well')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('lyrics-slide-1')));
    await settle(t);
    expect(c.lyrics.statusLine, 'It Is Well with My Soul · Chorus');
    expect(find.byKey(const ValueKey('lyric-stage')), findsWidgets);
    await t.tap(find.byKey(const ValueKey('lyrics-black')));
    await settle(t);
    expect(c.lyrics.black, isTrue);
    await t.tap(find.byKey(const ValueKey('lyrics-clear')));
    await settle(t);
    expect(c.lyrics.showing, isFalse);
  });

  testWidgets('the Slides button on Live opens the page and shows what is on', (
    t,
  ) async {
    final c = await openLyrics(t, size: const Size(390, 844), desktop: false);
    await home(t).goToPage(0);
    await settle(t);
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('live-lyrics-button')),
      300,
    );
    c.lyrics.show('amazing', 3);
    await settle(t);
    expect(
      find.text('On the screens: Amazing Grace · Verse 4'),
      findsOneWidget,
    );
    await expectLater(
      find.byKey(const ValueKey('live-lyrics')),
      matchesGoldenFile('../goldens/lyrics-live-button.png'),
    );
    await t.tap(find.byKey(const ValueKey('live-lyrics-clear')));
    await settle(t);
    expect(c.lyrics.showing, isFalse);
    await t.tap(find.byKey(const ValueKey('live-lyrics-button')));
    await settle(t);
    expect(home(t).page, lyricsPage);
  });

  testWidgets('Live in a desktop layout has the Slides button in the header', (
    t,
  ) async {
    final c = await openLyrics(t, size: const Size(1920, 1080));
    await home(t).goToPage(0);
    await settle(t);
    c.lyrics.show('amazing', 1);
    await settle(t);
    // A desktop layout keeps its panes to the window: the button is in
    // the header, lit while lyrics are on the screens.
    final button = t.widget<IconButton>(
      find.byKey(const ValueKey('live-lyrics-button')),
    );
    expect(button.isSelected, isTrue);
    expect(button.tooltip, 'Slides · on the screens: Amazing Grace · Verse 2');
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/lyrics-live-button-1920.png'),
    );
  });

  testWidgets('add a song: words, headings, lines on a slide, a text file', (
    t,
  ) async {
    final c = await openLyrics(t, size: const Size(1366, 900), running: false);
    (c.port as DesktopPort).textFile = {
      'name': 'Be Thou My Vision.txt',
      'content':
          'Verse 1\r\nBe Thou my vision, O Lord of my heart;\r\nNaught be all else to me, save that Thou art.\r\nThou my best thought, by day or by night,\r\nWaking or sleeping, Thy presence my light.\r\n\r\nVerse 2\r\nBe Thou my wisdom, and Thou my true word;\r\nI ever with Thee and Thou with me, Lord.\r\nThou my great Father, I Thy true son;\r\nThou in me dwelling, and I with Thee one.\r\n\r\nHigh King of heaven, my victory won,\r\nMay I reach heaven’s joys, O bright heaven’s Sun!',
    };
    await t.tap(find.byKey(const ValueKey('lyrics-add-song')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('lyrics-editor-open')));
    await settle(t);
    expect(
      find.text('Be Thou My Vision'),
      findsOneWidget,
      reason: 'the file name becomes the title',
    );
    expect(find.text('VERSE 2'), findsOneWidget);
    expect(find.text('3 slides'), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/lyrics-add-song.png'),
    );
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('lyrics-editor-lines')),
        matching: find.text('2'),
      ),
    );
    await settle(t);
    expect(find.text('5 slides'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('lyrics-editor-save')));
    await settle(t);
    final saved = c.state.lyrics.items.firstWhere(
      (i) => i.title == 'Be Thou My Vision',
    );
    expect(saved.linesPerSlide, 2);
    expect(c.lyrics.selectedId, saved.id);
  });

  testWidgets('a song with no words says what to do', (t) async {
    await openLyrics(t, running: false);
    await t.tap(find.byKey(const ValueKey('lyrics-add-song')));
    await settle(t);
    await t.enterText(
      find.byKey(const ValueKey('lyrics-editor-title')),
      'Nothing yet',
    );
    await t.tap(find.byKey(const ValueKey('lyrics-editor-save')));
    await settle(t);
    expect(find.text('Type or paste the words.'), findsOneWidget);
  });

  testWidgets('delete asks first', (t) async {
    final c = await openLyrics(t, running: false);
    await t.tap(find.byKey(const ValueKey('lyrics-item-menu-holy')));
    await settle(t);
    await t.tap(find.text('Delete…'));
    await settle(t);
    expect(find.text('Delete “Holy, Holy, Holy”?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(c.state.lyrics.byId('holy'), isNotNull);
    await t.tap(find.byKey(const ValueKey('lyrics-item-menu-holy')));
    await settle(t);
    await t.tap(find.text('Delete…'));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('confirm-action')));
    await settle(t);
    expect(c.state.lyrics.byId('holy'), isNull);
  });

  testWidgets(
    'Bible verses from a reference, with a helpful message for a bad one',
    (t) async {
      final c = await openLyrics(
        t,
        size: const Size(1366, 900),
        running: false,
      );
      await t.tap(find.byKey(const ValueKey('lyrics-add-scripture')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('lyrics-editor-reference')),
        'John 40',
      );
      await t.tap(find.byKey(const ValueKey('lyrics-editor-find')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await settle(t);
      expect(
        find.text('There is no chapter 40 in John: it has 21 chapters.'),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const ValueKey('lyrics-editor-reference')),
        '1 cor 13:4-7',
      );
      await t.tap(find.byKey(const ValueKey('lyrics-editor-find')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await settle(t);
      expect(find.textContaining('1 Corinthians 13:4'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('lyrics-editor-save')));
      await settle(t);
      final item = c.state.lyrics.items.firstWhere(
        (i) => i.kind == 'scripture',
      );
      expect(item.title, '1 Corinthians 13:4-7');
      expect(item.version, 'KJV');
      expect(item.verses, hasLength(4));
    },
  );

  testWidgets('an announcement is saved like a song', (t) async {
    final c = await openLyrics(t, size: const Size(1366, 900), running: false);
    await t.tap(find.byKey(const ValueKey('lyrics-add-announcement')));
    await settle(t);
    await t.enterText(
      find.byKey(const ValueKey('lyrics-editor-title')),
      'Harvest lunch',
    );
    await t.enterText(
      find.byKey(const ValueKey('lyrics-editor-words')),
      'Tea, coffee and cake in the hall. Everyone is welcome.',
    );
    await t.enterText(
      find.byKey(const ValueKey('lyrics-editor-detail')),
      'Sunday 30 November · 12:30',
    );
    await settle(t);
    await t.tap(find.byKey(const ValueKey('lyrics-editor-save')));
    await settle(t);
    final item = c.state.lyrics.items.firstWhere(
      (i) => i.kind == 'announcement',
    );
    expect(item.slides.single.title, 'Harvest lunch');
    expect(item.slides.single.detail, 'Sunday 30 November · 12:30');
    expect(jsonEncode(c.state.toJson()), contains('Harvest lunch'));
  });

  group('Slides in a finish', () {
    final finishes = [...finishIds.where((f) => f != 'flat')];

    Future<void> checkPage(WidgetTester t, {required int panels}) async {
      expect(t.takeException(), isNull);
      // Cards of the finish's material, not loose words on the wall.
      expect(find.byType(FinishSurface), findsAtLeastNWidgets(panels));
      expect(finishLook(t.element(find.byType(LyricsPanel))).active, isTrue);
    }

    for (final finish in finishes) {
      testWidgets('$finish: three columns on a computer', (t) async {
        await openLyrics(t, finish: finish, running: false);
        await checkPage(t, panels: 3);
        expect(find.text('LIBRARY'), findsOneWidget);
      });
    }

    for (final (name, size, scale) in [
      ('a phone upright', const Size(360, 780), 1.0),
      ('a phone upright, large text', const Size(360, 780), 1.6),
      ('a phone sideways', const Size(780, 360), 1.0),
      ('a tablet', const Size(800, 1100), 1.0),
    ]) {
      for (final finish in ['glass', 'console', 'walnut', 'papery']) {
        testWidgets('$finish: one column on $name', (t) async {
          await openLyrics(
            t,
            size: size,
            desktop: false,
            textScale: scale,
            finish: finish == 'papery' ? 'flat' : finish,
            theme: finish == 'papery' ? 'paper_ink' : 'royal_navy',
          );
          // The rest of the cards are below the fold and built on scroll.
          await checkPage(t, panels: 1);
          // The controls along the bottom are a plate of the material too.
          expect(find.byKey(const ValueKey('lyrics-bar')), findsOneWidget);
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('lyrics-look')),
            300,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('lyrics-column-narrow')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await t.tap(find.byKey(const ValueKey('lyrics-look')));
          await settle(t);
          expect(t.takeException(), isNull);
        });
      }
    }

    for (final finish in ['brick', 'oak', 'papery']) {
      testWidgets('$finish: the editors sit on cards and fit', (t) async {
        for (final size in [const Size(1366, 768), const Size(360, 780)]) {
          await openLyrics(
            t,
            size: size,
            desktop: size.width > 800,
            finish: finish == 'papery' ? 'flat' : finish,
            theme: finish == 'papery' ? 'paper_ink' : 'royal_navy',
            running: false,
            textScale: size.width > 800 ? 1 : 1.6,
          );
          final c = t.widget<TimerApp>(find.byType(TimerApp)).controller;
          unawaited(
            Navigator.of(t.element(find.byType(LyricsPanel))).push(
              MaterialPageRoute<void>(
                builder: (_) => LyricEditorPage(controller: c),
              ),
            ),
          );
          await settle(t);
          expect(t.takeException(), isNull);
          expect(find.byType(FinishSurface), findsAtLeastNWidgets(2));
          expect(
            find.byKey(const ValueKey('lyrics-editor-save')),
            findsOneWidget,
          );
          await t.pageBack();
          await settle(t);
        }
      });
    }

    testWidgets('the slides themselves stay as they are in a finish', (
      t,
    ) async {
      final c = await openLyrics(t, finish: 'walnut');
      c.lyrics.show('amazing', 0);
      await settle(t);
      final stage = find.byKey(const ValueKey('lyric-stage'));
      expect(stage, findsWidgets);
      expect(
        find.descendant(of: stage.first, matching: find.byType(FinishSurface)),
        findsNothing,
        reason: 'the slide is drawn as the screens show it',
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('the page in Walnut', (t) async {
      final c = await openLyrics(
        t,
        finish: 'walnut',
        running: false,
        crop: const Size(1100, 620),
      );
      c.lyrics.show('amazing', 0);
      await settle(t);
      await expectLater(
        find.byKey(const ValueKey('crop')),
        matchesGoldenFile('../goldens/finish/lyrics-walnut-1366.png'),
      );
    });
  });
}
