import 'dart:math';

import 'package:church_service_timer/domain/bible.dart';
import 'package:church_service_timer/domain/verse_spotter.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// One thing the preacher says (as final transcripts, one after another)
/// and the labels the spotter should report, in order.
class Case {
  final List<String> said;
  final List<String> want;
  const Case(this.said, this.want);
}

Case c(String said, [List<String> want = const []]) => Case([said], want);

String spell(int n) {
  const small = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  if (n < 20) return small[n];
  if (n < 100) {
    return n % 10 == 0 ? tens[n ~/ 10] : '${tens[n ~/ 10]} ${small[n % 10]}';
  }
  final h = '${small[n ~/ 100]} hundred';
  return n % 100 == 0 ? h : '$h and ${spell(n % 100)}';
}

void main() {
  late Bible kjv;
  late VerseMatcher matcher;
  var buildMs = 0;
  final t0 = DateTime(2026, 1, 4, 10);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    kjv = await BibleLibrary.load();
    final sw = Stopwatch()..start();
    matcher = VerseMatcher(kjv);
    buildMs = sw.elapsedMilliseconds;
  });

  /// Everything the spotter reports for [said], one final at a time, five
  /// seconds apart.
  List<String> labels(List<String> said, {double min = 0.55}) {
    final s = VerseSpotter(kjv, minConfidence: min);
    final out = <String>[];
    for (var i = 0; i < said.length; i++) {
      for (final cand in s.hear(
        said[i],
        isFinal: true,
        at: t0.add(Duration(seconds: 5 * i)),
      )) {
        out.add(cand.label);
      }
    }
    return out;
  }

  group('spoken references', () {
    final cases = <Case>[
      // The plain forms.
      c('turn with me to john three sixteen', ['John 3:16']),
      c('romans eight twenty eight', ['Romans 8:28']),
      c('john chapter three verse sixteen', ['John 3:16']),
      c('psalm twenty three', ['Psalm 23']),
      c('psalms twenty three', ['Psalm 23']),
      c('psalm one hundred and nineteen verse one oh five', ['Psalm 119:105']),
      c('psalm one hundred and nineteen verse one hundred and five', [
        'Psalm 119:105',
      ]),
      c('psalm one nineteen one oh five', ['Psalm 119:105']),
      c('psalm one nineteen', ['Psalm 119']),
      c('psalm one fifty', ['Psalm 150']),
      c('psalm one hundred and fifty', ['Psalm 150']),
      c('let us read first john four eight', ['1 John 4:8']),
      c('second corinthians five seventeen', ['2 Corinthians 5:17']),
      c('turn to genesis chapter one verses one to three', ['Genesis 1:1-3']),
      c('turn to john chapter three verses four to seven', ['John 3:4-7']),
      c('turn to john chapter three verses sixteen and seventeen', [
        'John 3:16-17',
      ]),
      c('john three sixteen to eighteen', ['John 3:16-18']),
      c('john three sixteen through eighteen', ['John 3:16-18']),
      c('turn to john chapter three from verse one', ['John 3:1']),
      c('matthew five three', ['Matthew 5:3']),
      c('first corinthians thirteen four', ['1 Corinthians 13:4']),
      c('hebrews eleven one', ['Hebrews 11:1']),
      c('turn to isaiah fifty three five', ['Isaiah 53:5']),
      c('jeremiah twenty nine eleven', ['Jeremiah 29:11']),
      c('philippians four thirteen', ['Philippians 4:13']),
      c('revelation twenty one four', ['Revelation 21:4']),
      c('genesis one one', ['Genesis 1:1']),
      c('turn to john one one', ['John 1:1']),
      c('exodus twenty', ['Exodus 20']),
      c('second timothy three sixteen', ['2 Timothy 3:16']),
      c('first peter two nine', ['1 Peter 2:9']),
      c('second peter three nine', ['2 Peter 3:9']),
      c('second kings six seventeen', ['2 Kings 6:17']),
      c('first samuel seventeen forty five', ['1 Samuel 17:45']),
      c('second samuel twenty two', ['2 Samuel 22']),
      c('first chronicles four ten', ['1 Chronicles 4:10']),
      c('second chronicles seven fourteen', ['2 Chronicles 7:14']),
      c('first thessalonians five seventeen', ['1 Thessalonians 5:17']),
      c('second thessalonians three three', ['2 Thessalonians 3:3']),
      c('first timothy six ten', ['1 Timothy 6:10']),
      c('song of solomon two four', ['Song of Solomon 2:4']),
      c('song of songs eight six', ['Song of Solomon 8:6']),
      c('acts two thirty eight', ['Acts 2:38']),
      c('turn to the book of acts chapter one', ['Acts 1']),
      c('galatians five twenty two', ['Galatians 5:22']),
      c('ephesians two eight', ['Ephesians 2:8']),
      c('colossians three twenty three', ['Colossians 3:23']),
      c('proverbs three five', ['Proverbs 3:5']),
      c('proverbs eighteen ten', ['Proverbs 18:10']),
      c('ecclesiastes three one', ['Ecclesiastes 3:1']),
      c('lamentations three twenty two', ['Lamentations 3:22']),
      c('daniel three seventeen', ['Daniel 3:17']),
      c('turn to joshua one nine', ['Joshua 1:9']),
      c('deuteronomy six four', ['Deuteronomy 6:4']),
      c('leviticus nineteen eighteen', ['Leviticus 19:18']),
      c('malachi three ten', ['Malachi 3:10']),
      c('zechariah four six', ['Zechariah 4:6']),
      c('nehemiah eight ten', ['Nehemiah 8:10']),
      c('esther four fourteen', ['Esther 4:14']),
      c('turn to ezra seven ten', ['Ezra 7:10']),
      c('turn to james one five', ['James 1:5']),
      c('luke fifteen eleven', ['Luke 15:11']),
      c('luke twenty four forty six', ['Luke 24:46']),
      c('turn to ruth one sixteen', ['Ruth 1:16']),
      c('turn to jonah two nine', ['Jonah 2:9']),
      c('turn to habakkuk two four', ['Habakkuk 2:4']),
      c('turn to ezekiel thirty seven', ['Ezekiel 37']),
      c('turn to nahum one seven', ['Nahum 1:7']),
      c('turn to haggai two nine', ['Haggai 2:9']),
      c('turn to zephaniah three seventeen', ['Zephaniah 3:17']),
      c('turn to obadiah chapter one verse five', ['Obadiah 1:5']),
      c('turn to philemon verse six', ['Philemon 1:6']),
      c('turn to jude verse twenty four', ['Jude 1:24']),
      c('turn to jude three', ['Jude 1:3']),
      c('third john four', ['3 John 1:4']),
      c('second john chapter one verse six', ['2 John 1:6']),

      // Digits, in case the engine writes them.
      c('john 3 16', ['John 3:16']),
      c('turn to psalm 119 105', ['Psalm 119:105']),
      c('romans 8 28', ['Romans 8:28']),
      c('turn to john 316', ['John 3:16']),
      c('1 corinthians 13 4', ['1 Corinthians 13:4']),
      c('2 timothy 3 16', ['2 Timothy 3:16']),
      c('john three 16', ['John 3:16']),

      // Accent: th said as t.
      c('turn to john tree sixteen', ['John 3:16']),
      c('turn to genesis tirty one', ['Genesis 31']),
      c('turn to first corinthians tirteen four', ['1 Corinthians 13:4']),
      c('turn to tird john four', ['3 John 1:4']),

      // Lead-ins.
      c('as it says in john three sixteen', ['John 3:16']),
      c('let us read in the book of john chapter three', ['John 3']),
      c('open your bibles to romans twelve one', ['Romans 12:1']),
      c('our text today is psalm ninety one', ['Psalm 91']),
      c('we read in luke chapter two', ['Luke 2']),
      c('turn with me to the book of isaiah chapter fifty three', [
        'Isaiah 53',
      ]),
      c('the book of john chapter fourteen verse six', ['John 14:6']),
      c('take your bible and turn to second corinthians twelve nine', [
        '2 Corinthians 12:9',
      ]),
      c('good morning church please turn to ephesians six ten', [
        'Ephesians 6:10',
      ]),
      c('amen amen turn to matthew twenty eight nineteen', ['Matthew 28:19']),

      // Said badly: books the recogniser mishears.
      c('turn to romance eight twenty eight', ['Romans 8:28']),
      c('axe two thirty eight', ['Acts 2:38']),
      c('turn to look chapter two', ['Luke 2']),
      c('turn to palms twenty three', ['Psalm 23']),
      c('turn to sums twenty three', ['Psalm 23']),
      c('the book of revelations twenty one', ['Revelation 21']),
      c('revelations twenty one four', ['Revelation 21:4']),
      c('first king eight twenty seven', ['1 Kings 8:27']),
      c('turn to first kings eight', ['1 Kings 8']),
      c('turn to hosea three one', ['Hosea 3:1']),
      c('jose three one', ['Hosea 3:1']),
      c('turn to amos five twenty four', ['Amos 5:24']),
      c('almost five twenty four', ['Amos 5:24']),
      c('turn to micah six eight', ['Micah 6:8']),
      c('mica six eight', ['Micah 6:8']),
      c('turn to jude verse four', ['Jude 1:4']),
      c('turn to dude verse four', ['Jude 1:4']),
      c('philipines four thirteen', ['Philippians 4:13']),
      c('turn to philippines four six', ['Philippians 4:6']),
      c('efficient two eight', ['Ephesians 2:8']),
      c('turn to efficients six ten', ['Ephesians 6:10']),
      c('tight us two eleven', ['Titus 2:11']),
      c('turn to roof one sixteen', ['Ruth 1:16']),
      c('he brews eleven one', ['Hebrews 11:1']),
      c('turn to hebrew eleven six', ['Hebrews 11:6']),
      c('is equal thirty seven one', ['Ezekiel 37:1']),
      c('turn to i say a fifty three five', ['Isaiah 53:5']),
      c('turn to colosians three one', ['Colossians 3:1']),
      c('turn to habakuk three seventeen', ['Habakkuk 3:17']),
      c('turn to mark chapter four', ['Mark 4']),
      c('turn to marks four thirty five', ['Mark 4:35']),
      c('turn to the book of numbers thirteen', ['Numbers 13']),
      c('turn to the book of job chapter thirty eight verse four', [
        'Job 38:4',
      ]),
      c('turn to judges sixteen', ['Judges 16']),
      c('turn to deutronomy six', ['Deuteronomy 6']),
      c('turn to corinthians thirteen four', ['1 Corinthians 13:4']),

      // Things the preacher says that are not references.
      c('i have three children and sixteen cousins'),
      c('mark my words'),
      c('the job of a pastor'),
      c('numbers do not lie'),
      c('john went to the market'),
      c('john is three years old'),
      c('john three times'),
      c('we had numbers one'),
      c('he acts like he knows'),
      c('acts of kindness'),
      c('luke warm christians'),
      c('look at those three'),
      c('it is almost five'),
      c('he marked three of them'),
      c('the judges of the land'),
      c('on the job three days'),
      c('give me five minutes'),
      c('ruth is my aunt'),
      c('three sixteen is a famous verse'),
      c('chapter three verse sixteen'),
      c('verse sixteen says'),
      c('the first john went home'),
      c('sixteen people came to church'),
      c('john'),
      c('turn to john'),
      c('turn to romans and read'),
      c('i was born in nineteen eighty'),
      c('mark three sixty'),
      c('john thirty'),
      c('romans seventeen'),
      c('genesis sixty'),
      c('psalm two hundred'),
      c('jude four hundred'),
      c('turn to john three sixty', ['John 3']),
      c('look three'),
      c('sums three'),
      c('a hundred and nineteen people'),
      c('the kings of the earth'),

      // Impossible chapters or verses.
      c('turn to john three sixty five', ['John 3']),
      c('turn to genesis fifty one', ['Genesis 50:1']),
      c('turn to john twenty five', ['John 20:5']),
      c('turn to ruth five two'),

      // Several references in a row.
      c('turn to john three sixteen and then romans five eight', [
        'John 3:16',
        'Romans 5:8',
      ]),
      c('genesis one one and john one one', ['Genesis 1:1', 'John 1:1']),
      c('turn to first john one nine then second timothy two fifteen', [
        '1 John 1:9',
        '2 Timothy 2:15',
      ]),

      // Corrections.
      c('turn to john three sorry john four', ['John 3', 'John 4']),
      c('turn to genesis one no genesis two', ['Genesis 1', 'Genesis 2']),
      c('turn to john three sixteen sorry john three seventeen', [
        'John 3:16',
        'John 3:17',
      ]),
      c('turn to romans eight twenty eight sorry twenty nine', [
        'Romans 8:28',
        'Romans 8:29',
      ]),
      c('turn to romans eight sorry nine', ['Romans 8', 'Romans 9']),
      c('turn to john three sixteen i mean verse seventeen', [
        'John 3:16',
        'John 3:17',
      ]),

      // Verse said later.
      c('turn to john chapter three and in verse sixteen', [
        'John 3',
        'John 3:16',
      ]),
      c('turn to psalm twenty three and look at verse four', [
        'Psalm 23',
        'Psalm 23:4',
      ]),
      c('turn to john three sixteen and verse seventeen', [
        'John 3:16',
        'John 3:17',
      ]),
    ];

    for (var i = 0; i < cases.length; i++) {
      final k = cases[i];
      test('${i + 1}: "${k.said.join(' | ')}" -> ${k.want}', () {
        expect(labels(k.said), k.want);
      });
    }

    test('there are at least 150 hand-written cases', () {
      expect(cases.length, greaterThanOrEqualTo(150));
    });
  });

  group('every chapter and verse can be said and heard', () {
    // Each book, a spread of chapters and verses, said in words after a
    // lead-in. The reading is right when it is the one said, or when it is
    // one of the alternatives the spotter offers (for "twenty three":
    // chapter 23 or 20:3).
    final sayName = <String, String>{
      for (final b in bibleBooks)
        b: b
            .toLowerCase()
            .replaceFirst('1 ', 'first ')
            .replaceFirst('2 ', 'second ')
            .replaceFirst('3 ', 'third '),
    };
    test('round trip over all 66 books', () {
      var total = 0, exact = 0, viaAlternative = 0;
      final misses = <String>[];
      for (var b = 0; b < kjv.books.length; b++) {
        final book = kjv.books[b];
        final chapters = kjv.text[b].length;
        final picks = {
          1,
          chapters,
          (chapters / 2).ceil(),
          (chapters / 3).ceil(),
        };
        for (final ch in picks) {
          final verses = kjv.text[b][ch - 1].length;
          for (final v in {1, verses, (verses / 2).ceil()}) {
            final said = 'turn to ${sayName[book]} ${spell(ch)} ${spell(v)}';
            final s = VerseSpotter(kjv);
            final got = s.hear(said, isFinal: true, at: t0);
            total++;
            final wantC = chapters == 1 ? 1 : ch;
            bool same(BibleReference r) =>
                r.book == book && r.chapter == wantC && r.verse == v;
            if (got.isNotEmpty && same(got.first.reference)) {
              exact++;
            } else if (got.isNotEmpty && got.first.alternatives.any(same)) {
              viaAlternative++;
            } else {
              misses.add('$said -> $got');
            }
          }
        }
      }
      // ignore: avoid_print
      print(
        'round trip: $total said, $exact heard exactly, '
        '$viaAlternative offered as an alternative, ${misses.length} missed',
      );
      if (misses.isNotEmpty) {
        // ignore: avoid_print
        print(misses.take(10).join('\n'));
      }
      expect(misses, isEmpty);
      expect(exact / total, greaterThan(0.97));
    });
  });

  group('streaming', () {
    List<VerseCandidate> feed(
      VerseSpotter s,
      List<(String, bool)> steps, {
      int gap = 1,
    }) {
      final out = <VerseCandidate>[];
      for (var i = 0; i < steps.length; i++) {
        out.addAll(
          s.hear(
            steps[i].$1,
            isFinal: steps[i].$2,
            at: t0.add(Duration(seconds: gap * i)),
          ),
        );
      }
      return out;
    }

    test('a reference arriving word by word across partials', () {
      final s = VerseSpotter(kjv);
      final got = feed(s, [
        ('turn', false),
        ('turn to', false),
        ('turn to john', false),
        ('turn to john three', false),
        ('turn to john three sixteen', false),
        ('turn to john three sixteen', true),
      ]);
      expect(
        [for (final g in got) g.label],
        ['John 3', 'John 3:16', 'John 3:16'],
      );
      expect(got[0].provisional, isTrue);
      // The verse completes the chapter the tray already shows.
      expect(got[1].replaces, 'John|3||');
      expect(got[1].provisional, isTrue);
      // The final transcript settles it.
      expect(got[2].provisional, isFalse);
      expect(got[2].replaces, got[2].key);
    });

    test('a reference split across two final transcripts', () {
      final s = VerseSpotter(kjv);
      final got = feed(s, [
        ('turn with me to john', true),
        ('three sixteen', true),
      ]);
      expect([for (final g in got) g.label], ['John 3:16']);
      expect(got.single.heardAs, 'john three sixteen');
    });

    test('a chapter heard first is replaced by the verse that follows', () {
      final s = VerseSpotter(kjv);
      final got = feed(s, [('romans eight', true), ('twenty eight', true)]);
      expect([for (final g in got) g.label], ['Romans 8', 'Romans 8:28']);
      expect(got[1].replaces, got[0].key);
    });

    test('a revised partial moves to the new reading', () {
      final s = VerseSpotter(kjv);
      final got = feed(s, [
        ('turn to john three sixteen', false),
        ('turn to john three seventeen', false),
      ]);
      expect([for (final g in got) g.label], ['John 3:16', 'John 3:17']);
      expect(got[1].replaces, got[0].key);
    });

    test('the same reference heard again soon is reported once', () {
      final s = VerseSpotter(kjv);
      final a = s.hear('turn to john three sixteen', isFinal: true, at: t0);
      final b = s.hear(
        'as i said john three sixteen',
        isFinal: true,
        at: t0.add(const Duration(seconds: 12)),
      );
      expect(a, hasLength(1));
      expect(b, isEmpty);
    });

    test('and again once the window has passed', () {
      final s = VerseSpotter(kjv);
      s.hear('turn to john three sixteen', isFinal: true, at: t0);
      final b = s.hear(
        'remember john three sixteen',
        isFinal: true,
        at: t0.add(const Duration(seconds: 45)),
      );
      expect(b.map((e) => e.label), ['John 3:16']);
    });

    test('a different reference is never held back by the window', () {
      final s = VerseSpotter(kjv);
      s.hear('turn to john three sixteen', isFinal: true, at: t0);
      final b = s.hear(
        'turn to romans eight twenty eight',
        isFinal: true,
        at: t0.add(const Duration(seconds: 2)),
      );
      expect(b.map((e) => e.label), ['Romans 8:28']);
    });

    test('rescanning the same words reports nothing new', () {
      final s = VerseSpotter(kjv);
      s.hear('turn to john three sixteen', isFinal: true, at: t0);
      for (var i = 1; i < 5; i++) {
        expect(
          s.hear(
            'and he said',
            isFinal: false,
            at: t0.add(Duration(seconds: i)),
          ),
          isEmpty,
        );
      }
    });

    test('a correction says which candidate it replaces', () {
      final s = VerseSpotter(kjv);
      final got = s.hear(
        'turn to john three sorry john four',
        isFinal: true,
        at: t0,
      );
      expect(got.map((e) => e.label), ['John 3', 'John 4']);
      expect(got[1].correction, isTrue);
      expect(got[1].replaces, got[0].key);
    });

    test('reset forgets what was heard', () {
      final s = VerseSpotter(kjv);
      s.hear('turn to john three sixteen', isFinal: true, at: t0);
      s.reset();
      final b = s.hear(
        'turn to john three sixteen',
        isFinal: true,
        at: t0.add(const Duration(seconds: 1)),
      );
      expect(b, hasLength(1));
    });

    test('old words fall out of the window without breaking it', () {
      final s = VerseSpotter(kjv, windowWords: 20);
      for (var i = 0; i < 50; i++) {
        s.hear('praise the lord church we are blessed', isFinal: true, at: t0);
      }
      final b = s.hear('turn to john three sixteen', isFinal: true, at: t0);
      expect(b.map((e) => e.label), ['John 3:16']);
    });
  });

  group('confidence', () {
    VerseCandidate one(String said, {bool isFinal = true}) {
      final got = VerseSpotter(
        kjv,
        minConfidence: 0,
      ).hear(said, isFinal: isFinal, at: t0);
      expect(got, isNotEmpty, reason: said);
      return got.first;
    }

    test('a verse beats a chapter alone', () {
      expect(
        one('turn to john three sixteen').confidence,
        greaterThan(one('turn to john three').confidence),
      );
    });

    test('a lead-in beats none', () {
      expect(
        one('turn to john three sixteen').confidence,
        greaterThan(one('john three sixteen').confidence),
      );
    });

    test('a distinct book beats an ordinary word', () {
      expect(
        one('habakkuk two four').confidence,
        greaterThan(one('mark two four').confidence),
      );
      expect(
        one('mark two four').confidence,
        greaterThan(one('look two four').confidence),
      );
    });

    test(
      'a verse that does not exist is marked down and cut to the chapter',
      () {
        final bad = one('turn to john three sixty five');
        expect(bad.label, 'John 3');
        expect(bad.confidence, lessThan(one('turn to john three').confidence));
      },
    );

    test('a chapter that does not exist is dropped even at zero threshold', () {
      final got = VerseSpotter(
        kjv,
        minConfidence: 0,
      ).hear('turn to romans seventeen', isFinal: true, at: t0);
      expect(got, isEmpty);
    });

    test('the threshold is the sensitivity setting', () {
      expect(labels(['john three'], min: 0.45), ['John 3']);
      expect(labels(['john three'], min: 0.55), isEmpty);
      expect(labels(['john three'], min: 0.9), isEmpty);
      expect(labels(['turn to john three sixteen'], min: 0.97), isEmpty);
    });

    test(
      '"twenty three" is the chapter, with the verse offered as the other reading',
      () {
        final p = one('turn to psalm twenty three');
        expect(p.label, 'Psalm 23');
        expect(
          [for (final a in p.alternatives) referenceLabel(a)],
          ['Psalm 20:3'],
        );
      },
    );

    test('a numbered book with no number offers the others', () {
      final p = one('turn to corinthians thirteen four');
      expect(p.label, '1 Corinthians 13:4');
      expect(
        [for (final a in p.alternatives) referenceLabel(a)],
        ['2 Corinthians 13:4'],
      );
    });

    test('a numbered book with its number is surer than without', () {
      expect(
        one('first corinthians thirteen four').confidence,
        greaterThan(one('corinthians thirteen four').confidence),
      );
    });

    test('heard-as is the words as heard', () {
      expect(
        one('please turn to romance eight twenty eight now').heardAs,
        'romance eight twenty eight',
      );
      expect(
        one('turn to the first john four eight').heardAs,
        'first john four eight',
      );
    });

    test('from verse says the reading goes on', () {
      expect(one('john chapter three from verse one').openEnded, isTrue);
      expect(one('john chapter three verse one').openEnded, isFalse);
    });
  });

  group('spoken numbers', () {
    test('the words people use', () {
      const cases = <String, int>{
        'one': 1,
        'sixteen': 16,
        'twenty': 20,
        'twenty eight': 28,
        'ninety nine': 99,
        'one hundred': 100,
        'one hundred and five': 105,
        'one hundred five': 105,
        'one hundred and nineteen': 119,
        'a': -1,
        'hundred and fifty': 150,
        'one oh five': 105,
        'one zero five': 105,
        '12': 12,
        '119': 119,
      };
      cases.forEach((said, n) {
        expect(
          parseSpokenNumber(said.split(' ')),
          n == -1 ? null : n,
          reason: said,
        );
      });
    });
    test('and what is not one number', () {
      for (final said in [
        'three sixteen',
        'eight twenty eight',
        'twenty twenty',
        'sixteen four',
        '',
        'one two',
      ]) {
        expect(
          parseSpokenNumber(said.isEmpty ? [] : said.split(' ')),
          isNull,
          reason: said,
        );
      }
    });
    test('spell and parse agree for 1 to 176', () {
      for (var n = 1; n <= 176; n++) {
        expect(parseSpokenNumber(spell(n).split(' ')), n, reason: spell(n));
      }
    });
  });

  group('quoted verses', () {
    // Synthetic test set: real verses, spoken the way a recogniser may
    // return them (words dropped, replaced, added, modern words for archaic
    // ones), and sentences that are not Scripture.
    final vocab = <String>[];
    final archaicToModern = <String, List<String>>{
      'thee': ['you'],
      'thou': ['you'],
      'thy': ['your'],
      'thine': ['your'],
      'ye': ['you'],
      'hath': ['has'],
      'unto': ['to'],
      'doth': ['does'],
      'saith': ['says', 'said'],
      'shalt': ['shall', 'will'],
      'wilt': ['will'],
      'art': ['are'],
      'verily': ['truly'],
      'wherefore': ['therefore', 'so'],
      'behold': ['look', 'see'],
      'whosoever': ['whoever', 'anyone'],
      'begotten': ['one and only'],
      'lo': ['look'],
      'whom': ['who'],
      'beloved': ['dear'],
      'cometh': ['comes'],
      'saw': ['saw'],
    };
    late List<(int, int, int, List<String>)> pool;

    setUpAll(() {
      final seen = <String>{};
      pool = [];
      for (var b = 0; b < kjv.text.length; b++) {
        for (var ch = 0; ch < kjv.text[b].length; ch++) {
          for (var v = 0; v < kjv.text[b][ch].length; v++) {
            final w = quoteWords(kjv.text[b][ch][v]);
            for (final x in w) {
              if (seen.add(x)) vocab.add(x);
            }
            if (w.length >= 8) pool.add((b, ch + 1, v + 1, w));
          }
        }
      }
    });

    String label(int b, int c, int v) => '${singularBook(kjv.books[b])} $c:$v';

    List<String> corrupt(
      List<String> words,
      double rate,
      Random r, {
      bool modern = false,
    }) {
      final out = <String>[];
      for (final w in words) {
        var x = w;
        if (modern && archaicToModern.containsKey(x) && r.nextDouble() < 0.6) {
          final options = archaicToModern[x]!;
          x = options[r.nextInt(options.length)];
        }
        if (r.nextDouble() < rate) {
          switch (r.nextInt(3)) {
            case 0: // dropped
              continue;
            case 1: // heard as another word
              out.add(vocab[r.nextInt(vocab.length)]);
              continue;
            default: // an extra word, then this one
              out.add(vocab[r.nextInt(vocab.length)]);
          }
        }
        out.add(x);
      }
      return out;
    }

    // What the preacher might say that is not a quotation, including
    // sermon talk made of the same kind of words.
    final negatives = <String>[
      'good morning church we are glad to see you all this morning',
      'please remember the youth meeting after the service in the main hall',
      'the choir will now come forward and lead us in worship',
      'we thank god for the safe journey of our brothers from lagos',
      'if you are a visitor today please stand so that we can welcome you',
      'the offering baskets will be passed around during the next song',
      'i want you to turn to your neighbour and say god is good',
      'last week we talked about faith and this week we will talk about patience',
      'god is faithful and he will bring you through this season of your life',
      'the lord has been good to this church and to every family in it',
      'i remember when i was a young man and my father took me to the village church',
      'the number of people who gave their lives to christ last year was more than two hundred',
      'brothers and sisters the time is short and we must tell the world about jesus',
      'when you pray do not pray like the people who want to be seen by men',
      'my friend told me that he lost his job and his house in the same month',
      'let us bow our heads and thank god for the food that we are about to eat',
      'the prophet was a man like us and he prayed and the rain stopped for three years',
      'we are the children of god and we must live like it every day of the week',
      'the pastor will be travelling to abuja on monday for the conference',
      'jesus is the same yesterday today and forever and i believe that with all my heart',
      'the wedding of our sister will hold next saturday at the church hall',
      'if god be for us who can be against us is a question we should ask ourselves daily',
      'the devil is a liar and he wants to steal your joy this year',
      'all of us have sinned and come short and that is why we need the cross',
      'please keep the children quiet during the sermon and use the nursery if you need to',
      'god did not call you to be afraid he called you to be strong and to trust him',
      'the generator will be serviced this week so the lights may go off during the day',
      'thank you for coming to the youth night and we hope to see you again next month',
      'we will take the offering now and the ushers will come to the front',
      'some people think that heaven is a place where you float on clouds but i do not',
      'let me tell you a story about a man who walked ten miles to church every sunday',
      'i love to see the young people praising god with all their strength',
      'our theme for this year is rise and shine and we will study it every sunday',
      'the car park will be closed next sunday for the building work to be done',
      'we pray for the sick in our church and for those who cannot be here today',
      'the love of god is greater than anything we can think of or imagine',
      'the morning service begins at eight and the second service begins at ten thirty',
      'i would like to thank the choir the ushers and everyone who worked this week',
      'there was a woman in our village who prayed every day for her son to return',
      'the grace of the lord jesus christ be with all of you as you go home',
      'sometimes god says wait and sometimes he says go and we must listen carefully',
      'the church anniversary will be celebrated in november with a special thanksgiving service',
      'pray for our nation and for the leaders that god will give them wisdom',
      'we serve a mighty god who answers prayer and does wonders in our time',
      'in the market this week i met an old friend who had not been to church in years',
    ];
    final openers = [
      'brothers and sisters',
      'church i want to say that',
      'let me remind you that',
      'the thing about this season is that',
      'my dear friends',
      'as we begin this week',
    ];
    final bodies = [
      'the lord is good and he is working in the lives of his people',
      'we must not give up on praying for our families and our children',
      'it is time to come together and serve one another in love',
      'the children of this church will perform a short drama after the service',
      'every one of us has a part to play in the work of the kingdom',
      'i saw a man who gave everything he had to follow the call of god',
      'the young man went to the city to look for work but found the church',
      'the people of god must walk in love and truth and forgive one another',
      'the sound system needs a new cable and we will fix it this week',
      'the love of god is greater than anything we can think of or imagine',
    ];

    List<String> allNegatives() {
      // Every opener before every body, then each standalone sentence on its
      // own and after each opener, so that sentences built from the same
      // sermon words are well covered.
      return [
        for (final o in openers)
          for (final b in bodies) '$o $b',
        for (final n in negatives) ...[n, for (final o in openers) '$o $n'],
      ];
    }

    ({int correct, int wrong, int abstain, int total}) evaluate(
      int seed,
      double rate,
      bool modern,
      int n,
      VerseMatcher m, {
      bool preamble = false,
    }) {
      final r = Random(seed);
      var correct = 0, wrong = 0, abstain = 0;
      for (var i = 0; i < n; i++) {
        final p = pool[r.nextInt(pool.length)];
        final len = min(p.$4.length, 12 + r.nextInt(13));
        final start = r.nextInt(p.$4.length - len + 1);
        var heard = corrupt(
          p.$4.sublist(start, start + len),
          rate,
          r,
          modern: modern,
        );
        if (preamble) {
          // The preacher talks for a few words before the quote starts.
          final talk = quoteWords(negatives[r.nextInt(negatives.length)]);
          heard = [...talk.take(6 + r.nextInt(6)), ...heard];
          if (heard.length > 24) heard = heard.sublist(heard.length - 24);
        }
        final res = m.match(heard);
        final got = res.proposal;
        if (got == null) {
          abstain++;
        } else if (got.label == label(p.$1, p.$2, p.$3)) {
          correct++;
        } else {
          wrong++;
        }
      }
      return (correct: correct, wrong: wrong, abstain: abstain, total: n);
    }

    int falsePositives(VerseMatcher m) {
      var fp = 0;
      for (final s in allNegatives()) {
        if (m.match(quoteWords(s)).proposal != null) fp++;
      }
      return fp;
    }

    test('the matcher indexes the whole Bible', () {
      expect(matcher.verseCount, 31102);
    });

    test('a clean verse is found, and a verse quoted in part', () {
      final j = matcher.match(
        quoteWords(
          'for god so loved the world that he gave his only begotten son',
        ),
      );
      expect(j.proposal?.label, 'John 3:16');
      final p = matcher.match(
        quoteWords('the lord is my shepherd i shall not want'),
      );
      expect(p.proposal?.label, 'Psalm 23:1');
    });

    test('a verse quoted in modern words and with errors is found', () {
      final r = matcher.match(
        quoteWords(
          'for god so loved the world that he gave his one and only son that whoever believes',
        ),
      );
      expect(r.proposal?.label, 'John 3:16');
      final r2 = matcher.match(
        quoteWords('i can do all things through christ who strengthens me'),
      );
      expect(r2.proposal?.label, 'Philippians 4:13');
    });

    test('common sayings that are not quotations propose nothing', () {
      for (final s in [
        'good morning church we are glad to see you all',
        'please turn to your neighbour and say hello',
        'the lord is good',
        'god bless you all',
      ]) {
        expect(matcher.match(quoteWords(s)).proposal, isNull, reason: s);
      }
    });

    test('too few words propose nothing', () {
      expect(matcher.match(quoteWords('in the beginning')).proposal, isNull);
      expect(matcher.match([]).proposal, isNull);
    });

    test('a verse that appears twice word for word is not proposed', () {
      // "the grace of our lord jesus christ be with you" ends many letters;
      // the matcher must not pick one at random.
      final r = matcher.match(
        quoteWords('the grace of our lord jesus christ be with you amen'),
      );
      expect(r.proposal, isNull);
      expect(r.top.length, greaterThan(1));
    });

    test('the quote spotter reports each verse once, from a rolling window', () {
      final q = QuoteSpotter(matcher);
      final words =
          'and the bible says for god so loved the world that he gave his only begotten son that whosoever believeth in him should not perish'
              .split(' ');
      final found = <String>[];
      var said = <String>[];
      for (var i = 0; i < words.length; i++) {
        said.add(words[i]);
        final c = q.hear(
          said.join(' '),
          isFinal: false,
          at: t0.add(Duration(milliseconds: 400 * i)),
        );
        if (c != null) found.add(c.match.label);
      }
      expect(found.toSet(), {'John 3:16'});
      expect(found.length, 1);
    });

    test('measured on corrupted verses and non-Scripture sentences', () {
      final lines = <String>[];
      for (final modern in [false, true]) {
        for (final rate in [0.0, 0.10, 0.20, 0.30]) {
          final e = evaluate(4242, rate, modern, 600, matcher);
          final recall = e.correct / e.total;
          lines.add(
            '${modern ? 'modern words ' : 'KJV words    '} errors ${(rate * 100).round().toString().padLeft(2)}%: '
            'right ${(recall * 100).toStringAsFixed(1)}%  '
            'wrong ${e.wrong}  abstained ${e.abstain}  '
            'precision ${(e.correct / max(1, e.correct + e.wrong) * 100).toStringAsFixed(1)}%',
          );
          if (rate <= 0.10)
            expect(recall, greaterThan(0.80), reason: lines.last);
          if (rate <= 0.20)
            expect(recall, greaterThan(0.60), reason: lines.last);
          expect(e.wrong / e.total, lessThan(0.03), reason: lines.last);
        }
      }
      final e = evaluate(4242, 0.2, true, 600, matcher, preamble: true);
      lines.add(
        'modern words, 20% errors, 6-11 words of other talk first: '
        'right ${(e.correct / e.total * 100).toStringAsFixed(1)}%  '
        'wrong ${e.wrong}  abstained ${e.abstain}',
      );
      expect(e.wrong / e.total, lessThan(0.03));
      final fp = falsePositives(matcher);
      lines.add(
        'non-Scripture sentences: $fp of ${allNegatives().length} proposed a verse',
      );
      // ignore: avoid_print
      print(lines.join('\n'));
      expect(fp, lessThanOrEqualTo(3));
    });

    test('query time over the whole Bible', () {
      final r = Random(5);
      final times = <int>[];
      for (var i = 0; i < 300; i++) {
        final p = pool[r.nextInt(pool.length)];
        final len = min(p.$4.length, 20);
        final heard = corrupt(p.$4.sublist(0, len), 0.2, r);
        final sw = Stopwatch()..start();
        matcher.match(heard);
        sw.stop();
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      final mean = times.reduce((a, b) => a + b) / times.length / 1000;
      final p95 = times[(times.length * 0.95).floor()] / 1000;
      final worst = times.last / 1000;
      // ignore: avoid_print
      print(
        'query over ${matcher.verseCount} verses, 20-word window: '
        'mean ${mean.toStringAsFixed(1)} ms, p95 ${p95.toStringAsFixed(1)} ms, '
        'worst ${worst.toStringAsFixed(1)} ms (flutter test, JIT); '
        'building the index took $buildMs ms',
      );
      // Loose: other agents' tests share this machine.
      expect(p95, lessThan(250));
    });
  });
}
