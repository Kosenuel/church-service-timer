import 'dart:convert';
import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

late BibleSearchIndex index;
late Duration buildTime;

enum Where { top, top5 }

/// A query and where the verse must be: first, or among the first five.
typedef Case = (String query, Where where, String reference);

const _t = Where.top;
const _f = Where.top5;

const cases = <Case>[
  // ---- References -------------------------------------------------------
  ('John 3:16', _t, 'John 3:16'),
  ('john 3 16', _t, 'John 3:16'),
  ('jn 3:16', _t, 'John 3:16'),
  ('John 3.16', _t, 'John 3:16'),
  ('john 3:16-18', _t, 'John 3:16-18'),
  ('joh 3', _t, 'John 3'),
  ('john 3', _t, 'John 3'),
  ('1cor13 4-7', _t, '1 Corinthians 13:4-7'),
  ('1 cor 13', _t, '1 Corinthians 13'),
  ('first corinthians 13:4', _t, '1 Corinthians 13:4'),
  ('psalm 23', _t, 'Psalm 23'),
  ('ps 23:1-3', _t, 'Psalm 23:1-3'),
  ('psalms 119:105', _t, 'Psalm 119:105'),
  ('rom 8:28', _t, 'Romans 8:28'),
  ('romans 8 28', _t, 'Romans 8:28'),
  ('gen 1:1', _t, 'Genesis 1:1'),
  ('genesis 1', _t, 'Genesis 1'),
  ('Gen 1:1-3', _t, 'Genesis 1:1-3'),
  ('rev 21:4', _t, 'Revelation 21:4'),
  ('2 tim 1:7', _t, '2 Timothy 1:7'),
  ('2tim 1:7', _t, '2 Timothy 1:7'),
  ('II Timothy 1:7', _t, '2 Timothy 1:7'),
  ('first john 4:8', _t, '1 John 4:8'),
  ('song of songs 2:1', _t, 'Song of Solomon 2:1'),
  ('jude 3', _t, 'Jude 1:3'),
  ('matt 5:3-12', _t, 'Matthew 5:3-12'),
  ('John 3:16–4:2', _t, 'John 3:16–4:2'),
  ('isa 40:31', _t, 'Isaiah 40:31'),
  ('jer 29:11', _t, 'Jeremiah 29:11'),
  ('phil 4:13', _t, 'Philippians 4:13'),
  ('prov 3:5-6', _t, 'Proverbs 3:5-6'),
  ('mt 28:19', _t, 'Matthew 28:19'),
  ('1 co 13', _t, '1 Corinthians 13'),
  ('3 john 4', _t, '3 John 1:4'),
  ('JOHN 3:16', _t, 'John 3:16'),
  ('  john   3 : 16  ', _t, 'John 3:16'),
  // A verse number still being typed also offers the longer ones.
  ('john 3:1', _t, 'John 3:1'),
  ('john 3:1', _f, 'John 3:10'),
  // ---- Famous verses by their words, as they are said today -------------
  ('for god so loved the world', _t, 'John 3:16'),
  ('god so loved', _t, 'John 3:16'),
  ('whoever believes in him should not perish', _t, 'John 3:16'),
  ('the lord is my shepherd', _f, 'Psalm 23:1'),
  ('the lord is my shepherd i shall not want', _f, 'Psalm 23:1'),
  ('shadow valley death', _t, 'Psalm 23:4'),
  ('valley of the shadow of death', _t, 'Psalm 23:4'),
  ('death shadow valley', _t, 'Psalm 23:4'),
  ('thy rod and thy staff they comfort me', _t, 'Psalm 23:4'),
  ('your rod and your staff comfort me', _t, 'Psalm 23:4'),
  ('he makes me lie down in green pastures', _t, 'Psalm 23:2'),
  ('goodness and mercy will follow me', _t, 'Psalm 23:6'),
  ('all things work together for good', _t, 'Romans 8:28'),
  ('work together for good', _t, 'Romans 8:28'),
  ('thoughts of peace and not of evil', _t, 'Jeremiah 29:11'),
  ('expected end', _t, 'Jeremiah 29:11'),
  ('i can do all things through christ', _t, 'Philippians 4:13'),
  (
    'i can do all things through christ who strengthens me',
    _t,
    'Philippians 4:13',
  ),
  ('strengthens me', _f, 'Philippians 4:13'),
  ('mount up with wings as eagles', _t, 'Isaiah 40:31'),
  ('wait upon the lord renew their strength', _t, 'Isaiah 40:31'),
  ('renew strength eagles', _t, 'Isaiah 40:31'),
  ('trust in the lord with all your heart', _t, 'Proverbs 3:5'),
  ('lean not unto thine own understanding', _t, 'Proverbs 3:5'),
  ('lean not on your own understanding', _f, 'Proverbs 3:5'),
  ('in all thy ways acknowledge him', _t, 'Proverbs 3:6'),
  ('go ye therefore and teach all nations', _t, 'Matthew 28:19'),
  ('baptizing them in the name of the father', _t, 'Matthew 28:19'),
  ('in the beginning', _t, 'Genesis 1:1'),
  ('in the beginning god created', _t, 'Genesis 1:1'),
  ('god created the heaven and the earth', _t, 'Genesis 1:1'),
  ('in the beginning was the word', _t, 'John 1:1'),
  ('let there be light', _t, 'Genesis 1:3'),
  ('the lord is my light and my salvation', _t, 'Psalm 27:1'),
  ('be still and know that i am god', _t, 'Psalm 46:10'),
  ('thy word is a lamp unto my feet', _t, 'Psalm 119:105'),
  ('your word is a lamp to my feet', _t, 'Psalm 119:105'),
  ('the wages of sin is death', _t, 'Romans 6:23'),
  ('for all have sinned', _t, 'Romans 3:23'),
  ('by grace are ye saved through faith', _t, 'Ephesians 2:8'),
  ('for by grace you are saved through faith', _t, 'Ephesians 2:8'),
  ('be strong and of a good courage', _f, 'Joshua 1:9'),
  ('fear not for i am with thee', _f, 'Isaiah 41:10'),
  ('fear thou not for i am with thee', _t, 'Isaiah 41:10'),
  ('do not fear for i am with you', _f, 'Isaiah 41:10'),
  ('charity suffereth long and is kind', _t, '1 Corinthians 13:4'),
  ('faith hope charity', _t, '1 Corinthians 13:13'),
  ('now faith is the substance of things hoped for', _t, 'Hebrews 11:1'),
  ('come unto me all ye that labour', _t, 'Matthew 11:28'),
  ('i am the way the truth and the life', _t, 'John 14:6'),
  ('peace i leave with you', _t, 'John 14:27'),
  ('a new commandment i give unto you', _t, 'John 13:34'),
  ('greater love hath no man than this', _t, 'John 15:13'),
  ('the word was made flesh', _t, 'John 1:14'),
  ('seek ye first the kingdom of god', _t, 'Matthew 6:33'),
  ('ask and it shall be given you', _t, 'Matthew 7:7'),
  ('ye are the light of the world', _t, 'Matthew 5:14'),
  ('let your light so shine', _t, 'Matthew 5:16'),
  ('thou shalt love the lord thy god with all thy heart', _f, 'Matthew 22:37'),
  ('the lord bless thee and keep thee', _t, 'Numbers 6:24'),
  ('for god hath not given us the spirit of fear', _t, '2 Timothy 1:7'),
  ('rejoice in the lord alway', _t, 'Philippians 4:4'),
  ('rejoice in the lord always', _t, 'Philippians 4:4'),
  ('careful for nothing', _t, 'Philippians 4:6'),
  ('the peace of god which passeth all understanding', _t, 'Philippians 4:7'),
  ('peace of god passes all understanding', _t, 'Philippians 4:7'),
  ('if we confess our sins', _t, '1 John 1:9'),
  ('god is love', _f, '1 John 4:8'),
  ('we love him because he first loved us', _t, '1 John 4:19'),
  ('behold i stand at the door and knock', _t, 'Revelation 3:20'),
  ('god shall wipe away all tears', _f, 'Revelation 21:4'),
  ('jesus wept', _t, 'John 11:35'),
  ('a soft answer turneth away wrath', _t, 'Proverbs 15:1'),
  ('a soft answer turns away wrath', _t, 'Proverbs 15:1'),
  ('train up a child in the way he should go', _t, 'Proverbs 22:6'),
  ('what doth the lord require of thee', _t, 'Micah 6:8'),
  ('what does the lord require of you', _t, 'Micah 6:8'),
  ('for unto us a child is born', _t, 'Isaiah 9:6'),
  ('for to us a child is born', _t, 'Isaiah 9:6'),
  ('with his stripes we are healed', _t, 'Isaiah 53:5'),
  ('all we like sheep have gone astray', _t, 'Isaiah 53:6'),
  ('create in me a clean heart', _t, 'Psalm 51:10'),
  ('this is the day which the lord hath made', _t, 'Psalm 118:24'),
  ('this is the day the lord has made', _t, 'Psalm 118:24'),
  ('i will lift up mine eyes unto the hills', _t, 'Psalm 121:1'),
  ('i lift up my eyes to the hills', _f, 'Psalm 121:1'),
  ('fearfully and wonderfully made', _t, 'Psalm 139:14'),
  ('taste and see that the lord is good', _t, 'Psalm 34:8'),
  ('delight thyself also in the lord', _t, 'Psalm 37:4'),
  ('god is our refuge and strength', _t, 'Psalm 46:1'),
  ('enter into his gates with thanksgiving', _t, 'Psalm 100:4'),
  ('bless the lord o my soul', _f, 'Psalm 103:1'),
  ('jesus christ the same yesterday today and for ever', _t, 'Hebrews 13:8'),
  ('faith without works is dead', _f, 'James 2:26'),
  ('cast all your care upon him', _t, '1 Peter 5:7'),
  ('as for me and my house we will serve the lord', _t, 'Joshua 24:15'),
  ('to every thing there is a season', _t, 'Ecclesiastes 3:1'),
  ('thy kingdom come thy will be done', _t, 'Matthew 6:10'),
  ('give us this day our daily bread', _t, 'Matthew 6:11'),
  ('our father which art in heaven', _t, 'Matthew 6:9'),
  ('our father who art in heaven', _t, 'Matthew 6:9'),
  ('blessed are the poor in spirit', _t, 'Matthew 5:3'),
  ('blessed are the meek', _t, 'Matthew 5:5'),
  ('blessed are the pure in heart', _t, 'Matthew 5:8'),
  ('blessed are the peacemakers', _t, 'Matthew 5:9'),
  ('father forgive them for they know not what they do', _t, 'Luke 23:34'),
  ('glory to god in the highest', _t, 'Luke 2:14'),
  ('it is finished', _f, 'John 19:30'),
  ('he is not here for he is risen', _t, 'Matthew 28:6'),
  ('ye must be born again', _t, 'John 3:7'),
  ('you must be born again', _t, 'John 3:7'),
  ('i am the good shepherd', _t, 'John 10:11'),
  ('i am the resurrection and the life', _t, 'John 11:25'),
  ('i am the vine ye are the branches', _t, 'John 15:5'),
  ('upon this rock i will build my church', _t, 'Matthew 16:18'),
  ('you shall receive power', _t, 'Acts 1:8'),
  (
    'believe on the lord jesus christ and thou shalt be saved',
    _t,
    'Acts 16:31',
  ),
  ('be not conformed to this world', _t, 'Romans 12:2'),
  ('do not be conformed to this world', _f, 'Romans 12:2'),
  ('there is therefore now no condemnation', _t, 'Romans 8:1'),
  ('if god be for us who can be against us', _t, 'Romans 8:31'),
  ('faith cometh by hearing', _t, 'Romans 10:17'),
  ('faith comes by hearing', _t, 'Romans 10:17'),
  ('i am crucified with christ', _t, 'Galatians 2:20'),
  ('whatsoever things are true', _t, 'Philippians 4:8'),
  ('whatever things are true', _t, 'Philippians 4:8'),
  ('all scripture is given by inspiration of god', _t, '2 Timothy 3:16'),
  ('pray without ceasing', _t, '1 Thessalonians 5:17'),
  ('with god all things are possible', _t, 'Matthew 19:26'),
  ('the joy of the lord is your strength', _t, 'Nehemiah 8:10'),
  ('my grace is sufficient for you', _t, '2 Corinthians 12:9'),
  ('for we walk by faith not by sight', _t, '2 Corinthians 5:7'),
  ('the lord will fight for you', _t, 'Exodus 14:14'),
  ('thou shalt have no other gods before me', _t, 'Exodus 20:3'),
  ('thou shalt not steal', _t, 'Exodus 20:15'),
  ('choose you this day whom ye will serve', _t, 'Joshua 24:15'),
  // ---- Word order, quoted phrases, partial words ------------------------
  ('world loved god so', _f, 'John 3:16'),
  ('"for god so loved"', _t, 'John 3:16'),
  ('"shadow of death"', _t, 'Psalm 23:4'),
  ('"in the beginning" god', _t, 'Genesis 1:1'),
  ('"love one another"', _f, 'John 13:34'),
  ('lie down in green pastures', _t, 'Psalm 23:2'),
  ('lord is my shep', _f, 'Psalm 23:1'),
  ('for god so lov', _t, 'John 3:16'),
  ('trust in the lord with all', _t, 'Proverbs 3:5'),
  // ---- Misspellings -----------------------------------------------------
  ('shadw of deth', _f, 'Psalm 23:4'),
  ('the lord is my sheperd', _f, 'Psalm 23:1'),
  ('for god so lovd the wrld', _t, 'John 3:16'),
  ('beleive on the lord jesus christ', _t, 'Acts 16:31'),
  ('in the begining', _t, 'Genesis 1:1'),
  ('i can do all things through chirst', _t, 'Philippians 4:13'),
  // ---- Named passages ---------------------------------------------------
  ("the lord's prayer", _t, 'Matthew 6:9-13'),
  ('lords prayer', _t, 'Matthew 6:9-13'),
  ('the beatitudes', _t, 'Matthew 5:3-12'),
  ('beatitudes', _t, 'Matthew 5:3-12'),
  ('ten commandments', _t, 'Exodus 20:1-17'),
  ('great commission', _t, 'Matthew 28:18-20'),
  ('the love chapter', _t, '1 Corinthians 13'),
  ('good samaritan', _t, 'Luke 10:25-37'),
  ('prodigal son', _t, 'Luke 15:11-32'),
  ('armour of god', _t, 'Ephesians 6:10-18'),
  ('fruit of the spirit', _t, 'Galatians 5:22-23'),
  // ---- A book first narrows to it ---------------------------------------
  ('rom faith', _t, 'Romans 10:17'),
  ('hebrews faith', _t, 'Hebrews 11:1'),
  ('john loved', _f, 'John 3:16'),
];

/// What the reference parser now reads: misspelt books, "v" for verse and
/// spoken numbers. Each must come out as the same passage the Add Bible
/// verses editor reads.
const forgiving = <(String, String)>[
  ('jerimiah 29 11', 'Jeremiah 29:11'),
  ('jeramiah 29:11', 'Jeremiah 29:11'),
  ('Jhon 3 16', 'John 3:16'),
  ('jhn 3:16', 'John 3:16'),
  ('galations 5:22', 'Galatians 5:22'),
  ('phillipians 4:13', 'Philippians 4:13'),
  ('ephesions 2:8', 'Ephesians 2:8'),
  ('revelations 21:4', 'Revelation 21:4'),
  ('mathew 5:3', 'Matthew 5:3'),
  ('duteronomy 6:4', 'Deuteronomy 6:4'),
  ('isiah 53:5', 'Isaiah 53:5'),
  ('hebrew 11:1', 'Hebrews 11:1'),
  ('proverb 3:5', 'Proverbs 3:5'),
  ('romens 8:28', 'Romans 8:28'),
  ('genisis 1:1', 'Genesis 1:1'),
  ('joshuah 1:9', 'Joshua 1:9'),
  ('1 corinthans 13', '1 Corinthians 13'),
  ('john 3 v 9', 'John 3:9'),
  ('john 3 v. 16', 'John 3:16'),
  ('john 3 verse 16', 'John 3:16'),
  ('psalm 23 v 1-3', 'Psalm 23:1-3'),
  ('romans 8 vs 28', 'Romans 8:28'),
  ('john chapter three verse sixteen', 'John 3:16'),
  ('romans eight twenty-eight', 'Romans 8:28'),
  ('romans eight twenty eight', 'Romans 8:28'),
  ('psalm twenty three', 'Psalm 23'),
  (
    'first corinthians chapter thirteen verses four to seven',
    '1 Corinthians 13:4-7',
  ),
  ('turn to genesis chapter one verse one', 'Genesis 1:1'),
  ('open your bibles to john chapter three verse sixteen', 'John 3:16'),
  (
    'psalm one hundred and nineteen verse one hundred and five',
    'Psalm 119:105',
  ),
  ('matthew twenty eight nineteen', 'Matthew 28:19'),
  ('philippians four thirteen', 'Philippians 4:13'),
  ('isaiah forty thirty one', 'Isaiah 40:31'),
  ('revelation twenty one four', 'Revelation 21:4'),
  ('john three sixteen', 'John 3:16'),
  ('second timothy chapter one verse seven', '2 Timothy 1:7'),
  ('john 3:16 kjv', 'John 3:16'),
  ('John 3:16 (KJV)', 'John 3:16'),
  ('jn 3 16', 'John 3:16'),
  ('1 jhn 4:8', '1 John 4:8'),
];

/// Inputs both the editor and the search must read the same way, including
/// the ones that are wrong or could be several books.
const agreeing = <String>[
  'John 3:16',
  'john 3 16',
  'jerimiah 29 11',
  'Jhon 3 16',
  'john 3 v 9',
  'john chapter three verse sixteen',
  'romans eight twenty-eight',
  'psalm 23',
  'psalm 23:1-3',
  '1cor13 4-7',
  'isaiah 40:31',
  'jude 3',
  'john 3:16-4:2',
  'john 40',
  'john 3:99',
  'jo 3',
  'phi 4:13',
  'ma 5:3',
  'john 3:16 kjv',
  'psalm 119:105',
  'first corinthians chapter thirteen verses four to seven',
  'obadiah 1:3',
  'revelation 22:21',
];

/// Text that must find nothing sensible, and must not crash.
const nothing = [
  '',
  ' ',
  '   \n ',
  'a',
  'z',
  '!!!',
  '???',
  '...',
  '12345',
  '3:16',
  '"',
  '""',
  'xyzzy',
  'zzzzzzzz',
  'qwertyuiop asdfghjkl',
  'xyzzy qwxz',
  'the',
  'αγάπη',
  '愛',
  'مرحبا',
  '🙏',
  '🙏🙏🙏',
  '<script>alert(1)</script>',
];

void main() {
  setUpAll(() {
    final sw = Stopwatch()..start();
    final text = utf8.decode(
      gzip.decode(File('assets/bible/kjv.txt.gz').readAsBytesSync()),
    );
    final bible = Bible.parse(text);
    final parsed = sw.elapsed;
    sw.reset();
    index = BibleSearchIndex.build(bible);
    buildTime = sw.elapsed;
    // ignore: avoid_print
    print(
      'KJV parsed in ${parsed.inMilliseconds} ms; index built in '
      '${buildTime.inMilliseconds} ms (${index.wordCount} word keys, '
      '${index.tokenCount} words, about '
      '${(index.approxBytes / 1048576).toStringAsFixed(1)} MB held).',
    );
  });

  test('the table has at least 120 searches', () {
    expect(cases.length + nothing.length, greaterThanOrEqualTo(120));
  });

  group('searches find the verse', () {
    for (final (query, where, reference) in cases) {
      test('“$query” → $reference (${where.name})', () {
        final r = index.search(query);
        final refs = [for (final h in r.hits) h.reference];
        if (where == Where.top) {
          expect(refs, isNotEmpty, reason: 'nothing found');
          expect(refs.first, reference, reason: 'got ${refs.take(5)}');
        } else {
          expect(
            refs.take(5),
            contains(reference),
            reason: 'got ${refs.take(5)}',
          );
        }
      });
    }
  });

  group('searches that find nothing', () {
    for (final q in nothing) {
      test('“$q”', () {
        final r = index.search(q);
        expect(r.hits, isEmpty);
        expect(r.problem, isFalse);
      });
    }
    test('very long input is cut, not slow or fatal', () {
      final sw = Stopwatch()..start();
      final r = index.search('love ' * 500);
      expect(r.hits.length, lessThanOrEqualTo(30));
      expect(sw.elapsedMilliseconds, lessThan(1500));
      index.search('x' * 5000);
      index.search('"' * 400);
      index.search('1:' * 300);
    });
    test('odd punctuation and a bare book never throw', () {
      for (final q in [
        'john 0',
        'john 0:0',
        'john 3:0',
        'john 3:99',
        'john 3:16-2',
        '::::',
        'john :3',
        '1 ',
        '- - -',
        'psalm 151',
        'obadiah 2',
        '(lord)',
        "'lord'",
      ]) {
        expect(() => index.search(q), returnsNormally, reason: q);
      }
    });
  });

  group('what the reference parser now reads', () {
    for (final (query, reference) in forgiving) {
      test('“$query” → $reference', () {
        final r = index.search(query);
        expect(r.byReference, isTrue, reason: '${r.note} ${r.books}');
        expect(r.hits.first.reference, reference);
      });
    }
    test('a corrected spelling says what is shown', () {
      expect(index.search('Jhon 3 16').note, 'Showing John 3:16');
      expect(index.search('jerimiah 29 11').note, 'Showing Jeremiah 29:11');
      expect(index.search('John 3 16').note, isNull);
      expect(index.search('john chapter three verse sixteen').note, isNull);
    });
    test('a book that could be several offers them, in one list', () {
      expect(index.search('jo 3').books, [
        'Job',
        'Joel',
        'John',
        'Jonah',
        'Joshua',
      ]);
      expect(index.search('jo').books, [
        'Job',
        'Joel',
        'John',
        'Jonah',
        'Joshua',
      ]);
      expect(
        index.search('phi 4:13').books,
        containsAll(['Philemon', 'Philippians']),
      );
      expect(index.search('1 jo').books, ['1 John']);
      expect(index.search('jhon').books, contains('John'));
      expect(index.search('jo 3').hits, isEmpty);
    });
    test('the editor and the search read the same input the same way', () {
      for (final input in agreeing) {
        String? editor, editorProblem;
        List<String>? editorBooks;
        try {
          editor = index.bible.read(input).reference;
        } on BibleBookChoice catch (e) {
          editorBooks = e.books;
        } on RuleError catch (e) {
          editorProblem = e.message;
        }
        final r = index.search(input);
        if (editor != null) {
          expect(r.hits.first.passage.book, isNotEmpty, reason: input);
          // A chapter's first hit is the chapter; a verse's own hit is it.
          final first = r.hits.first.reference;
          final narrowed = r.hits.map((h) => h.reference);
          expect(narrowed, contains(editor), reason: '$input: $first');
          expect(r.problem, isFalse, reason: input);
        } else if (editorBooks != null) {
          expect(r.books.toSet(), editorBooks.toSet(), reason: input);
          expect(r.hits, isEmpty, reason: input);
        } else {
          expect(r.problem, isTrue, reason: input);
          expect(r.note, editorProblem, reason: input);
        }
      }
    });
    test('only common words: the exact phrase, or a hint', () {
      final r = index.search('thou art');
      expect(r.hits, isNotEmpty);
      expect(r.hits.every((h) => h.tier == 2), isTrue);
      expect(r.note, contains('Add another word'));
      expect(index.search('in the').hits, isNotEmpty);
      final one = index.search('the');
      expect(one.hits, isEmpty);
      expect(one.note, contains('add another word'));
      expect(index.search('"thou art"').hits, isNotEmpty);
    });
  });

  group('references', () {
    test('Isaiah is a book, not a Roman numeral I and a book called saiah', () {
      expect(parseBibleReference('Isaiah 40:31').book, 'Isaiah');
      expect(parseBibleReference('isa 40').book, 'Isaiah');
      expect(parseBibleReference('Is 40').book, 'Isaiah');
      expect(
        index.bible.read('Isaiah 40:31').verses.single.text,
        startsWith('But they that wait upon the LORD'),
      );
      // Roman numerals before a book still count.
      expect(parseBibleReference('I Cor 13').book, '1 Corinthians');
      expect(parseBibleReference('II Kings 2').book, '2 Kings');
      expect(parseBibleReference('III John 4').book, '3 John');
      expect(index.search('isaiah 53').hits.first.reference, 'Isaiah 53');
      expect(index.search('isaiah faith').hits.first.passage.book, 'Isaiah');
    });

    test('a chapter lists its verses after the whole chapter', () {
      final r = index.search('john 3');
      expect(r.byReference, isTrue);
      expect(r.hits.first.reference, 'John 3');
      expect(r.hits.first.verses, 36);
      expect(r.total, 37);
      expect(r.hits[1].reference, 'John 3:1');
      expect(r.hits[16].reference, 'John 3:16');
    });
    test('a verse number narrows as it is typed', () {
      expect(
        [for (final h in index.search('john 3:1').hits) h.reference],
        ['John 3:1', for (var v = 10; v <= 19; v++) 'John 3:$v'],
      );
      expect(
        [for (final h in index.search('john 3:16').hits) h.reference],
        ['John 3:16'],
      );
      expect(
        [for (final h in index.search('john 3:4').hits) h.reference],
        ['John 3:4'],
      );
    });
    test('a range is one passage', () {
      final r = index.search('john 3:16-18');
      expect(r.hits, hasLength(1));
      expect(r.hits.single.verses, 3);
      expect(r.hits.single.text, startsWith('For God so loved'));
    });
    test('a cross-chapter range', () {
      final r = index.search('john 3:35-4:2');
      expect(r.hits.single.reference, 'John 3:35–4:2');
      expect(r.hits.single.verses, 4);
    });
    test('a bad reference says what is wrong', () {
      var r = index.search('john 40');
      expect(r.problem, isTrue);
      expect(r.note, 'There is no chapter 40 in John: it has 21 chapters.');
      expect(r.hits, isEmpty);
      r = index.search('john 3:99');
      expect(r.note, contains('John 3 has 36 verses'));
    });
    test('a trailing separator is still a reference being typed', () {
      expect(index.search('john 3:').hits.first.reference, 'John 3');
      expect(index.search('john 3:16-').hits.first.reference, 'John 3:16');
    });
    test('a partial book name offers the books', () {
      expect(index.search('jo').books, [
        'Job',
        'Joel',
        'John',
        'Jonah',
        'Joshua',
      ]);
      expect(index.search('jo').hits, isEmpty);
      expect(index.search('ph').books, ['Philemon', 'Philippians']);
      expect(index.search('1 jo').books, ['1 John']);
      expect(index.search('2 co').books, ['2 Corinthians']);
      expect(index.search('rev').books.first, 'Revelation');
      expect(index.search('john').books.first, 'John');
      expect(index.search('jud').books, containsAll(['Jude', 'Judges']));
    });
    test('a partial book and a number still offers the books', () {
      final r = index.search('jo 3');
      expect(r.books, contains('John'));
      expect(r.hits, isEmpty);
    });
    test('the reading adapter keeps what it was given', () {
      final r = interpretReference('1cor13 4-7');
      expect(r.reference!.book, '1 Corinthians');
      expect(referenceText(r.reference!), '1 Corinthians 13:4-7');
      expect(interpretReference('lord is my shepherd').isReference, isFalse);
      expect(interpretReference('').isReference, isFalse);
    });
  });

  group('words', () {
    test('a misspelt word still finds its verses', () {
      final r = index.search('rightous');
      expect(r.hits, isNotEmpty);
      expect(r.hits.first.tier, 5);
      expect(r.hits.first.text.toLowerCase(), contains('righteous'));
      expect(r.hits.first.spans, isNotEmpty);
    });
    test('the, and other words that begin a book, are not read as books', () {
      final r = index.search('the lord shall');
      expect(r.total, greaterThan(1000));
      expect(index.search('song of joy').hits, isNotEmpty);
    });

    test('every hit has all the words, in the tiers the order promises', () {
      final r = index.search('shadow valley death');
      expect(r.hits.first.reference, 'Psalm 23:4');
      expect(r.hits.first.tier, 3, reason: 'all words near each other');
      final tiers = [for (final h in r.hits) h.tier];
      expect(tiers, orderedEquals([...tiers]..sort()));
    });
    test('an adjacent phrase ranks above the same words apart', () {
      final r = index.search('love thy neighbour');
      expect(r.hits.first.tier, 2);
      final apart = index.search('neighbour love');
      expect(apart.hits, isNotEmpty);
    });
    test('quotes demand the phrase', () {
      final r = index.search('"neighbour love"');
      for (final h in r.hits) {
        expect(h.text.toLowerCase(), contains('neighbour'));
      }
      expect(
        index.search('"love neighbour"').hits,
        isEmpty,
        reason: 'those two words are never next to each other in that order',
      );
    });
    test('the last word is a prefix while typing, whole after a space', () {
      expect(index.search('god so lov').hits.first.reference, 'John 3:16');
      // After a space “lov” is a whole word, which only means love.
      expect(index.search('god so lov ').hits.first.reference, 'John 3:16');
    });
    test('a word nothing has is set aside and said', () {
      final r = index.search('shepherd xyzzy');
      expect(r.hits, isNotEmpty);
      expect(r.note, contains('xyzzy'));
    });
    test('most of the words, only when few verses have all', () {
      final r = index.search(
        'i can do all things through christ who strengthens me',
      );
      expect(r.hits.first.reference, 'Philippians 4:13');
    });
    test('ties are broken by the order of the books', () {
      // Verses of Numbers 7 are word for word the same.
      final r = index.search('"one golden spoon of ten shekels"');
      final refs = [for (final h in r.hits) h.passage];
      expect(refs.length, greaterThanOrEqualTo(10));
      final order = [for (final p in refs) p.chapter * 1000 + p.verse!];
      expect(order, orderedEquals([...order]..sort()));
      expect(refs.every((p) => p.book == 'Numbers'), isTrue);
    });
    test('limit and total', () {
      final r = index.search('lord', limit: 10);
      expect(r.hits, hasLength(10));
      expect(r.total, greaterThan(1000));
    });
    test('book first narrows, and a book that was a word falls back', () {
      final r = index.search('rom faith');
      expect(r.hits.every((h) => h.passage.book == 'Romans'), isTrue);
      final back = index.search('mark my words');
      expect(back.hits, isNotEmpty);
    });
    test('named passages come first', () {
      final r = index.search('beatitudes');
      expect(r.hits.first.tier, 1);
      expect(r.hits.first.verses, 10);
    });
  });

  group('highlighting', () {
    test('spans cover the matched words, in archaic or modern form', () {
      final hit = index.search('shadow valley death').hits.first;
      final marked = [
        for (final (a, b) in hit.spans) hit.text.substring(a, b).toLowerCase(),
      ];
      expect(marked, ['valley', 'shadow', 'death']);
      final modern = index.search('he who believes').hits.first;
      final words = [
        for (final (a, b) in modern.spans)
          modern.text.substring(a, b).toLowerCase(),
      ];
      expect(words, isNotEmpty);
    });
    test('a word being typed is marked by its start', () {
      final hit = index.search('god so lov').hits.first;
      final marked = [for (final (a, b) in hit.spans) hit.text.substring(a, b)];
      expect(marked, containsAll(['God', 'so', 'loved']));
    });
    test('spans never run past the text', () {
      for (final q in ['lord', 'and the', 'love thy neighbour', 'peace']) {
        for (final h in index.search(q).hits) {
          for (final (a, b) in h.spans) {
            expect(a, lessThan(b));
            expect(b, lessThanOrEqualTo(h.text.length));
          }
        }
      }
    });
  });

  group('archaic and modern forms', () {
    String top(String q) => index.search(q).hits.first.reference;
    final same = <(String, String)>[
      ('thus saith the lord', 'thus says the lord'),
      ('come unto me', 'come to me'),
      ('he hath said', 'he has said'),
      ('thou art my son', 'you are my son'),
      ('God spake all these words', 'God spoke all these words'),
      ('whosoever believeth', 'whoever believes'),
      (
        'he that doeth the will of my father',
        'he who does the will of my father',
      ),
      ('thy kingdom come', 'your kingdom come'),
    ];
    for (final (a, b) in same) {
      test('“$a” and “$b” find the same first verse', () {
        expect(index.search(a).hits, isNotEmpty);
        expect(top(a), top(b));
      });
    }

    final stems = <List<String>>[
      ['believeth', 'believes', 'believed', 'believe', 'believing'],
      ['loveth', 'loves', 'loved', 'love', 'lovest', 'loving'],
      ['cometh', 'comes', 'come', 'coming', 'came'],
      ['saith', 'says', 'say', 'sayeth', 'sayest'],
      ['hath', 'has', 'have', 'hast'],
      ['doth', 'does', 'do', 'dost', 'doeth'],
      ['thee', 'thou', 'you', 'ye'],
      ['thy', 'thine', 'your'],
      ['unto', 'to'],
      ['shalt', 'shall', 'will', 'wilt'],
      ['spake', 'speak', 'speaketh', 'spoke', 'spoken'],
      ['maketh', 'makes', 'make', 'made'],
      ['wherefore', 'therefore'],
      ['whatsoever', 'whatever'],
      ['yea', 'yes'],
      ['alway', 'always'],
      ['mine', 'my'],
      ['beginning', 'beginnings'],
    ];
    for (final group in stems) {
      test('${group.join(', ')} are one word', () {
        expect(
          {for (final w in group) stemWord(w)},
          hasLength(1),
          reason: '${[for (final w in group) stemWord(w)]}',
        );
      });
    }
    test('words that only look like verb endings keep them', () {
      for (final w in [
        'honest',
        'harvest',
        'forest',
        'priest',
        'earnest',
        'this',
        'jesus',
        'grace',
        'death',
      ]) {
        expect(stemWord(w), isNot(isEmpty));
      }
      expect(stemWord('honest'), isNot(stemWord('hon')));
      expect(stemWord('jesus'), 'jesus');
      expect(stemWord('this'), 'this');
      expect(stemWord('grace'), 'grac');
      expect(stemWord('LORD'), 'lord');
    });
    test('words that are different stay different', () {
      expect(stemWord('god'), isNot(stemWord('good')));
      expect(stemWord('heaven'), isNot(stemWord('heavy')));
      expect(stemWord('love'), isNot(stemWord('lord')));
      expect(stemWord('faith'), isNot(stemWord('faithful')));
    });
    test('the table is small and written out', () {
      expect(archaicForms.length, lessThan(200));
      for (final e in archaicForms.entries) {
        expect(e.key, e.key.toLowerCase());
        expect(e.value, e.value.toLowerCase());
        expect(e.key, isNot(e.value));
      }
    });
  });

  group('speed', () {
    test('a query takes a few milliseconds', () {
      final queries = [for (final c in cases) c.$1];
      // Warm up, then time each query alone.
      for (final q in queries.take(20)) {
        index.search(q);
      }
      final times = <int>[];
      for (var round = 0; round < 3; round++) {
        for (final q in queries) {
          final sw = Stopwatch()..start();
          index.search(q);
          times.add(sw.elapsedMicroseconds);
        }
      }
      times.sort();
      final p50 = times[times.length ~/ 2] / 1000;
      final p95 = times[(times.length * .95).floor()] / 1000;
      final worst = times.last / 1000;
      final mean = times.fold<int>(0, (a, b) => a + b) / times.length / 1000;
      // ignore: avoid_print
      print(
        'Query latency over ${times.length} searches (this machine, '
        'unoptimised test VM, other jobs running): mean '
        '${mean.toStringAsFixed(1)} ms, median ${p50.toStringAsFixed(1)} ms, '
        '95th percentile ${p95.toStringAsFixed(1)} ms, worst '
        '${worst.toStringAsFixed(1)} ms. Index build ${buildTime.inMilliseconds} ms.',
      );
      // Generous bounds: other agents are running tests on this machine.
      expect(p50, lessThan(60));
      expect(p95, lessThan(250));
      expect(buildTime.inSeconds, lessThan(20));
    });

    test('typing one letter at a time stays quick', () {
      const text = 'for god so loved the world';
      final times = <int>[];
      for (var i = 1; i <= text.length; i++) {
        final sw = Stopwatch()..start();
        index.search(text.substring(0, i));
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      // ignore: avoid_print
      print(
        'Typing “$text”: worst keystroke ${times.last / 1000} ms, '
        'median ${times[times.length ~/ 2] / 1000} ms.',
      );
      expect(times.last / 1000, lessThan(400));
    });
  });

  test('the index knows its size', () {
    expect(index.verseCount, 31102);
    expect(index.approxBytes, greaterThan(1 << 20));
    expect(index.approxBytes, lessThan(40 << 20));
  });
}
