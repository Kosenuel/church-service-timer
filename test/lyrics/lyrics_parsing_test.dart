import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, String)> slides(String words, {int lines = 0}) => [
  for (final s in parseSongSlides(words, linesPerSlide: lines))
    (s.label, s.text),
];

void main() {
  group('song words become slides', () {
    test('a blank line starts a new slide; headings name slides', () {
      expect(
        slides(
          'Verse 1\nAmazing grace\nHow sweet the sound\n\nChorus\nMy chains are gone\n\nNo heading here',
        ),
        [
          ('Verse 1', 'Amazing grace\nHow sweet the sound'),
          ('Chorus', 'My chains are gone'),
          ('Slide 3', 'No heading here'),
        ],
      );
    });

    test('every heading kind, in any case and dressing, is not shown', () {
      for (final (line, name) in [
        ('VERSE 2:', 'Verse 2'),
        ('[Chorus]', 'Chorus'),
        ('(Bridge)', 'Bridge'),
        ('Refrain.', 'Refrain'),
        ('Pre-chorus', 'Pre-chorus'),
        ('PreChorus', 'Pre-chorus'),
        ('pre chorus 2', 'Pre-chorus 2'),
        ('Intro', 'Intro'),
        ('Outro', 'Outro'),
        ('Tag', 'Tag'),
        ('Ending', 'Ending'),
      ]) {
        expect(slides('$line\nWords'), [(name, 'Words')], reason: line);
      }
      // Words that start like a heading are words.
      expect(slides('Verses of praise we sing'), [
        ('Slide 1', 'Verses of praise we sing'),
      ]);
      expect(slides('Chorus of angels'), [('Slide 1', 'Chorus of angels')]);
    });

    test('a heading mid-block, or on its own, starts and names a slide', () {
      expect(slides('Verse 1\nOne\nChorus\nTwo'), [
        ('Verse 1', 'One'),
        ('Chorus', 'Two'),
      ]);
      expect(slides('Chorus\n\nSing it\nAgain'), [
        ('Chorus', 'Sing it\nAgain'),
      ]);
    });

    test('Lines on a slide splits blocks and keeps their names', () {
      const words = 'Verse 1\na\nb\nc\nd\ne\n\nf\ng';
      expect(slides(words, lines: 2), [
        ('Verse 1', 'a\nb'),
        ('Verse 1', 'c\nd'),
        ('Verse 1', 'e'),
        ('Slide 4', 'f\ng'),
      ]);
      expect(slides(words, lines: 4), [
        ('Verse 1', 'a\nb\nc\nd'),
        ('Verse 1', 'e'),
        ('Slide 3', 'f\ng'),
      ]);
      expect(slides(words), [
        ('Verse 1', 'a\nb\nc\nd\ne'),
        ('Slide 2', 'f\ng'),
      ]);
    });

    test('odd whitespace and Windows line endings', () {
      const raw =
          '﻿Verse 1\r\n  Amazing  grace\t \r\n​how sweet\r\n \r\n\t\r\n\r\nChorus\rSing\r';
      expect(slides(raw), [
        ('Verse 1', 'Amazing grace\nhow sweet'),
        ('Chorus', 'Sing'),
      ]);
      expect(slides('   \n\n \t \n'), isEmpty);
    });
  });

  group('the library', () {
    LyricItem song(String id, String title, {int updated = 0}) => LyricItem(
      id: id,
      kind: 'song',
      title: title,
      words: 'Line one\nLine two',
      updated: updated,
    );

    test('saves, reads back and orders by last use', () {
      var lib = const LyricsLibrary()
          .saved(song('a', 'Amazing Grace', updated: 1))
          .saved(song('b', 'Be Thou My Vision', updated: 2))
          .usedAt('a', 50)
          .withLook(
            const LyricsLook(background: 'linen', dim: 40, toStage: true),
          );
      final back = LyricsLibrary.fromJson(lib.toJson());
      expect([for (final i in back.ordered) i.id], ['a', 'b']);
      expect(back.look.background, 'linen');
      expect(back.look.dim, 40);
      expect(back.look.toStage, isTrue);
      lib = back.without('a');
      expect(lib.items.single.id, 'b');
      expect(lib.lastUsed, isEmpty);
    });

    test('nothing saved reads as an empty library with the default look', () {
      final lib = LyricsLibrary.fromJson(null);
      expect(lib.isEmpty, isTrue);
      expect(lib.look.dim, 70);
      expect(lib.look.toSecond, isTrue);
      expect(lib.look.toWeb, isTrue);
      expect(
        lib.look.toStage,
        isFalse,
        reason: 'a speaker’s countdown is never covered by accident',
      );
      // Unknown or out-of-range values are the default.
      final odd = LyricsLook.fromJson({
        'dim': 300,
        'size': 'xl',
        'background': 'nowhere',
        'stage': 'yes',
      });
      expect(odd.dim, 70);
      expect(odd.size, 'm');
      expect(odd.background, 'mountain_dusk');
      expect(odd.toStage, isFalse);
    });

    test('a damaged item is left out, the rest load', () {
      final lib = LyricsLibrary.fromJson({
        'items': [
          {'id': 'x', 'kind': 'song', 'title': '', 'updated': 0},
          song('ok', 'Fine').toJson(),
          {'nonsense': true},
        ],
      });
      expect([for (final i in lib.items) i.id], ['ok']);
    });

    test('searching finds titles and words', () {
      final item = song('a', 'Amazing Grace');
      expect(item.matches('grace'), isTrue);
      expect(item.matches('LINE TWO'), isTrue);
      expect(item.matches('vision'), isFalse);
    });

    test('a saved state without lyrics loads, and with them round-trips', () {
      final fresh = AppState.fresh(const Stamp(0, 0, 'test'));
      final old = fresh.toJson();
      expect(
        old.containsKey('lyrics'),
        isFalse,
        reason: 'nothing written until used',
      );
      expect(AppState.fromJson(old).lyrics.isEmpty, isTrue);
      fresh.lyrics = fresh.lyrics.saved(song('a', 'Amazing Grace'));
      final again = AppState.fromJson(fresh.toJson());
      expect(again.lyrics.items.single.title, 'Amazing Grace');
    });
  });

  group('Bible references', () {
    late Bible kjv;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      kjv = await BibleLibrary.load();
    });

    test('the bundled text is the whole 1769 King James Version', () {
      expect(kjv.code, 'KJV');
      expect(kjv.books, bibleBooks);
      expect(kjv.text.expand((b) => b).expand((c) => c).length, 31102);
      expect(
        kjv.text[0][0][1],
        startsWith('And the earth was without form, and void;'),
      );
    });

    test('one verse, a range, a whole chapter and across chapters', () {
      final one = kjv.read('John 3:16');
      expect(one.reference, 'John 3:16');
      expect(one.verses.single.text, startsWith('For God so loved the world'));
      final range = kjv.read('john 3:16-18');
      expect(range.reference, 'John 3:16-18');
      expect([for (final v in range.verses) v.verse], [16, 17, 18]);
      final psalm = kjv.read('Psalm 23');
      expect(psalm.reference, 'Psalm 23');
      expect(psalm.verses, hasLength(6));
      expect(
        psalm.verses.first.text,
        'The LORD is my shepherd; I shall not want.',
      );
      final across = kjv.read('John 3:35–4:2');
      expect(across.reference, 'John 3:35–4:2');
      expect(across.verses, hasLength(4));
    });

    test('abbreviations and loose typing', () {
      for (final (input, reference) in [
        ('1 Cor 13:4-7', '1 Corinthians 13:4-7'),
        ('1co 13:4-7', '1 Corinthians 13:4-7'),
        ('First Corinthians 13:4', '1 Corinthians 13:4'),
        ('I Cor. 13:4', '1 Corinthians 13:4'),
        ('Ps 23:1-3', 'Psalm 23:1-3'),
        ('Psa. 23', 'Psalm 23'),
        ('Jn 3 16', 'John 3:16'),
        ('jhn 3.16', 'John 3:16'),
        ('1 John 4:8', '1 John 4:8'),
        ('Song of Songs 2:4', 'Song of Solomon 2:4'),
        ('Rev 21:4', 'Revelation 21:4'),
        ('Gen 1:1', 'Genesis 1:1'),
        ('Jude 3', 'Jude 1:3'),
        ('Phil 4 : 13', 'Philippians 4:13'),
        ('Deuter 6:5', 'Deuteronomy 6:5'),
      ]) {
        expect(kjv.read(input).reference, reference, reason: input);
      }
    });

    test('bad input says what to fix', () {
      void fails(String input, String message) => expect(
        () => kjv.read(input),
        throwsA(
          isA<RuleError>().having(
            (e) => e.toString(),
            'message',
            contains(message),
          ),
        ),
        reason: input,
      );
      fails('', 'Type a reference');
      fails('hello', 'such as John 3 or Psalm 23');
      fails('Hezekiah 3:1', 'is not a book of the Bible');
      fails('John 40', 'There is no chapter 40 in John: it has 21 chapters.');
      fails('John 3:99', 'John 3 has 36 verses, so there is no verse 99.');
      fails('John 3:18-16', 'must run forwards');
      fails('Psalm 1-150', 'Choose at most 200');
    });

    test('verses become slides with a reference line each', () {
      final r = kjv.read('1 Cor 13:4-7');
      final item = LyricItem(
        id: 'x',
        kind: 'scripture',
        title: r.reference,
        version: r.version,
        verses: r.verses,
      );
      final s = item.slides;
      expect(s, isNotEmpty);
      expect(s.first.reference, startsWith('1 Corinthians 13:4'));
      expect(s.first.reference, endsWith(' · KJV'));
      expect(
        s.first.text,
        contains('⁴'),
        reason: 'verse numbers on a slide of several',
      );
      expect(s.map((x) => x.text).join(' '), contains('endureth all things.'));
      for (final slide in s) {
        expect(slide.text.length, lessThanOrEqualTo(scriptureSlideChars * 1.5));
      }
      final single = LyricItem(
        id: 'y',
        kind: 'scripture',
        title: 'John 3:16',
        version: 'KJV',
        verses: kjv.read('John 3:16').verses,
      );
      expect(single.slides.single.reference, 'John 3:16 · KJV');
      expect(single.slides.single.text, isNot(contains('¹')));
    });

    test('pasted text from any translation keeps its own reference line', () {
      final item = LyricItem(
        id: 'p',
        kind: 'scripture',
        title: 'Romans 8:28',
        version: 'NLT',
        words: 'First part.\r\n\r\nSecond part.',
      );
      expect(
        [for (final s in item.slides) s.reference],
        ['Romans 8:28 · NLT', 'Romans 8:28 · NLT'],
      );
      expect(
        [for (final s in item.slides) s.text],
        ['First part.', 'Second part.'],
      );
    });
  });
}
