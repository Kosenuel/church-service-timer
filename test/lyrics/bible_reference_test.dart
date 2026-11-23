import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// The book the old, strict reader gave for [words]: a copy of the code
/// before spellings were forgiven, so "still resolves exactly as before" is
/// checked against what it really was.
String? legacyBookOf(String words) {
  var w = words.toLowerCase().replaceAll('.', ' ').trim();
  int? part;
  final prefix = RegExp(
    r'^(1|2|3|i{1,3}|first|second|third|1st|2nd|3rd)\s*',
  ).firstMatch(w);
  if (prefix != null) {
    part = switch (prefix.group(1)) {
      '1' || 'i' || 'first' || '1st' => 1,
      '2' || 'ii' || 'second' || '2nd' => 2,
      _ => 3,
    };
    final rest = w.substring(prefix.end).trim();
    if (rest.isEmpty) part = null;
    if (part != null) w = rest;
  }
  final key = w.replaceAll(RegExp(r'\s+'), '');
  String? base;
  for (final b in bibleBooks) {
    final name = b.replaceFirst(RegExp(r'^\d '), '');
    if (name.toLowerCase().replaceAll(' ', '') == key) base = name;
  }
  base ??= bibleBookAbbreviations[key];
  if (base == null && key.length >= 3) {
    final starts = {
      for (final b in bibleBooks)
        if (b
            .replaceFirst(RegExp(r'^\d '), '')
            .toLowerCase()
            .replaceAll(' ', '')
            .startsWith(key))
          b.replaceFirst(RegExp(r'^\d '), ''),
    };
    if (starts.length == 1) base = starts.single;
  }
  if (base == null) return null;
  const numbered = {
    'Samuel',
    'Kings',
    'Chronicles',
    'Corinthians',
    'Thessalonians',
    'Timothy',
    'Peter',
    'John',
  };
  if (numbered.contains(base)) {
    if (base == 'John' && part == null) return 'John';
    final name = '${part ?? 1} $base';
    return bibleBooks.contains(name) ? name : null;
  }
  return part == null ? base : null;
}

void main() {
  late Bible kjv;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    kjv = await BibleLibrary.load();
  });

  String shown(String input) => kjv.read(input).reference;

  List<String> choices(String input) {
    try {
      parseBibleReference(input);
    } on BibleBookChoice catch (e) {
      return e.books;
    }
    fail('"$input" did not offer choices');
  }

  group('what already worked still does', () {
    for (final (input, expected) in [
      ('John 3:9', 'John 3:9'),
      ('John 3 9', 'John 3:9'),
      ('Joh3: 9', 'John 3:9'),
      ('jn 3.9', 'John 3:9'),
      ('1cor13 4-7', '1 Corinthians 13:4-7'),
      ('1 corinthians 13:4 - 7', '1 Corinthians 13:4-7'),
      ('psalm23', 'Psalm 23'),
      ('Ps 23 1', 'Psalm 23:1'),
      ('2 Tim 3 16', '2 Timothy 3:16'),
      ('rev 22 21', 'Revelation 22:21'),
      ('Jn3:16-18', 'John 3:16-18'),
      ('Gen 1', 'Genesis 1'),
      ('gen1:1', 'Genesis 1:1'),
      ('Song of Solomon 2:1', 'Song of Solomon 2:1'),
      ('John 3:16', 'John 3:16'),
      ('John 3:35–4:2', 'John 3:35–4:2'),
      ('Phil 4 : 13', 'Philippians 4:13'),
      ('Deuter 6:5', 'Deuteronomy 6:5'),
      ('Jude 3', 'Jude 1:3'),
      ('I Cor. 13:4', '1 Corinthians 13:4'),
      ('Song of Songs 2:4', 'Song of Solomon 2:4'),
    ]) {
      test('"$input"', () => expect(shown(input), expected));
    }
  });

  group('misspelt books', () {
    for (final (input, expected) in [
      ('Jhon 3 16', 'John 3:16'),
      ('Jonh 3:16', 'John 3:16'),
      ('Genisis 1:1', 'Genesis 1:1'),
      ('Revelations 22:21', 'Revelation 22:21'),
      ('Phillipians 4:13', 'Philippians 4:13'),
      ('Psalms 23', 'Psalm 23'),
      ('Psalm 23', 'Psalm 23'),
      ('Pslam 23', 'Psalm 23'),
      ('Eccl 3:1', 'Ecclesiastes 3:1'),
      ('Ecclesiates 3:1', 'Ecclesiastes 3:1'),
      ('Isiah 53:5', 'Isaiah 53:5'),
      ('Mathew 5:3', 'Matthew 5:3'),
      ('Collosians 3:2', 'Colossians 3:2'),
      ('Thesalonians 5:16', '1 Thessalonians 5:16'),
      ('2 Thesalonians 3:3', '2 Thessalonians 3:3'),
      ('Phillippians 4:13', 'Philippians 4:13'),
      ('Habbakuk 2:4', 'Habakkuk 2:4'),
      ('Zecharia 4:6', 'Zechariah 4:6'),
      ('Nehemia 8:10', 'Nehemiah 8:10'),
      ('Deutronomy 6:5', 'Deuteronomy 6:5'),
      ('Leviticas 19:18', 'Leviticus 19:18'),
      ('Proverb 3:5', 'Proverbs 3:5'),
      ('Corinthian 13:4', '1 Corinthians 13:4'),
      ('2 Corinthian 5:17', '2 Corinthians 5:17'),
      ('1st Corinthians 13:4', '1 Corinthians 13:4'),
      ('First John 4:8', '1 John 4:8'),
      ('II Timothy 3:16', '2 Timothy 3:16'),
      ('2nd Peter 1:3', '2 Peter 1:3'),
      ('I Kings 3:9', '1 Kings 3:9'),
      ('III John 4', '3 John 1:4'),
      ('1 Jhon 4:8', '1 John 4:8'),
      ('2 Jhon 6', '2 John 1:6'),
      ('1 Timthy 6:12', '1 Timothy 6:12'),
      ('Jeramiah 29:11', 'Jeremiah 29:11'),
      ('Ephesions 2:8', 'Ephesians 2:8'),
      ('Galations 5:22', 'Galatians 5:22'),
      ('Hebrew 11:1', 'Hebrews 11:1'),
      ('Romons 8:28', 'Romans 8:28'),
      ('Lamentation 3:22', 'Lamentations 3:22'),
      ('Philipians 4:13', 'Philippians 4:13'),
      ('Ezekial 37:1', 'Ezekiel 37:1'),
      ('Danial 6:10', 'Daniel 6:10'),
      ('Malachai 3:10', 'Malachi 3:10'),
      ('Joshuah 1:9', 'Joshua 1:9'),
      ('Exodous 20:3', 'Exodus 20:3'),
      ('Numbres 6:24', 'Numbers 6:24'),
      ('Titas 2:11', 'Titus 2:11'),
      ('Mathhew 5:3', 'Matthew 5:3'),
      ('Johm 3:16', 'John 3:16'),
      ('Jams 1:2', 'James 1:2'),
    ]) {
      test('"$input"', () {
        expect(shown(input), expected);
      });
    }

    test('a corrected spelling is marked, a correct one is not', () {
      expect(parseBibleReference('Jhon 3:16').corrected, isTrue);
      expect(parseBibleReference('Isiah 53:5').corrected, isTrue);
      expect(parseBibleReference('John 3:16').corrected, isFalse);
      expect(parseBibleReference('jn 3 16').corrected, isFalse);
      expect(parseBibleReference('Deuter 6:5').corrected, isFalse);
      expect(kjv.read('Jhon 3:16').corrected, isTrue);
      expect(kjv.read('John 3:16').corrected, isFalse);
    });

    test('a number in front is kept, never dropped', () {
      expect(parseBibleReference('1 Jhon 4:8').book, '1 John');
      expect(parseBibleReference('Jhon 4:8').book, 'John');
      expect(parseBibleReference('2 Pter 1:3').book, '2 Peter');
      expect(
        () => parseBibleReference('2 Isiah 53'),
        throwsA(isA<RuleError>()),
        reason: 'there is no 2 Isaiah',
      );
    });
  });

  group('books that could be several are offered, not guessed', () {
    for (final (input, books) in [
      ('Jo 3:1', ['Job', 'Joel', 'John', 'Jonah', 'Joshua']),
      ('Phi 4:13', ['Philippians', 'Philemon']),
      ('Ju 3', ['Judges', 'Jude']),
      ('Ma 3:1', ['Mark', 'Matthew', 'Malachi']),
      ('Ez 3:1', ['Ezra', 'Ezekiel']),
      ('1 Jo 3:1', ['1 John']),
    ]) {
      test('"$input"', () {
        if (books.length == 1) {
          expect(parseBibleReference(input).book, books.single);
        } else {
          expect(choices(input).toSet(), books.toSet());
        }
      });
    }

    test('the choice carries what followed the book', () {
      try {
        parseBibleReference('Jo 3 16-18');
        fail('should offer choices');
      } on BibleBookChoice catch (e) {
        expect(e.rest, '3 16-18');
        expect(
          shown('John ${e.rest}'),
          'John 3:16-18',
          reason: 'a chosen book and the rest is a reference again',
        );
      }
    });

    test('established abbreviations are kept as they were', () {
      expect(parseBibleReference('Phil 4:13').book, 'Philippians');
      expect(parseBibleReference('Jon 1:1').book, 'Jonah');
      expect(parseBibleReference('Jos 1:9').book, 'Joshua');
      expect(parseBibleReference('Jud 3').book, 'Jude');
      expect(parseBibleReference('Mar 1:1').book, 'Mark');
      expect(parseBibleReference('Cor 13:4').book, '1 Corinthians');
    });
  });

  group('verse markers', () {
    for (final (input, expected) in [
      ('john3v9', 'John 3:9'),
      ('john 3v9', 'John 3:9'),
      ('John 3 v 9', 'John 3:9'),
      ('John 3 v9', 'John 3:9'),
      ('John 3 vs 9', 'John 3:9'),
      ('John 3 vs. 9', 'John 3:9'),
      ('John 3 verse 9', 'John 3:9'),
      ('John 3 verses 16 to 18', 'John 3:16-18'),
      ('John 3v9-11', 'John 3:9-11'),
      ('John 3, 16', 'John 3:16'),
      ('John 3,16', 'John 3:16'),
      ('John 3 . 16', 'John 3:16'),
      ('John 3 : 16', 'John 3:16'),
      ('john chapter 3 verse 16', 'John 3:16'),
    ]) {
      test('"$input"', () => expect(shown(input), expected));
    }
  });

  group('spoken and written out', () {
    for (final (input, expected) in [
      ('john chapter 3 verse 16', 'John 3:16'),
      ('John chapter three verse sixteen', 'John 3:16'),
      (
        'first corinthians chapter thirteen verses four to seven',
        '1 Corinthians 13:4-7',
      ),
      ('psalm twenty three', 'Psalm 23'),
      ('john three sixteen', 'John 3:16'),
      ('romans eight twenty-eight', 'Romans 8:28'),
      ('genesis one one', 'Genesis 1:1'),
      ('John 3 16 to 18', 'John 3:16-18'),
      ('John 3:16 through 18', 'John 3:16-18'),
      ('John 3 16 and 17', 'John 3:16-17'),
      ('psalm one hundred and nineteen', 'Psalm 119'),
      ('psalm a hundred nineteen', 'Psalm 119'),
      (
        'psalm one hundred nineteen verse one hundred seventy six',
        'Psalm 119:176',
      ),
      ('psalm one hundred and nineteen verses one to eight', 'Psalm 119:1-8'),
      ('psalm one hundred fifty', 'Psalm 150'),
      ('psalm one hundred and fifty verse six', 'Psalm 150:6'),
      ('the book of John chapter three', 'John 3'),
      ('turn to John 3 verse 16', 'John 3:16'),
      ('in john chapter three verse sixteen', 'John 3:16'),
      (
        'turn to the book of Romans chapter eight verse twenty eight',
        'Romans 8:28',
      ),
      ('second timothy chapter three verse sixteen', '2 Timothy 3:16'),
      ('first john chapter four verse eight', '1 John 4:8'),
      ('one john four eight', '1 John 4:8'),
      ('genesis chapter one through three', 'Genesis 1:1–3:24'),
      ('genesis one verse one to three', 'Genesis 1:1-3'),
      ('Jhon three sixteen', 'John 3:16'),
      ('isiah fifty three five', 'Isaiah 53:5'),
      ('john three sixteen and seventeen', 'John 3:16-17'),
      ('matthew five three through twelve', 'Matthew 5:3-12'),
      ('psalm twenty three verse one', 'Psalm 23:1'),
      ('revelation twenty-two twenty-one', 'Revelation 22:21'),
      ('john chapter three verse sixteen through eighteen', 'John 3:16-18'),
    ]) {
      test('"$input"', () => expect(shown(input), expected));
    }

    test('verses that are not neighbours are not turned into a run', () {
      expect(
        () => parseBibleReference('John 3 16 and 19'),
        throwsA(
          isA<RuleError>().having(
            (e) => e.message,
            'message',
            contains('one run of verses'),
          ),
        ),
      );
    });
  });

  group('harmless noise', () {
    for (final (input, expected) in [
      ('  John   3:16  ', 'John 3:16'),
      ('John 3:16.', 'John 3:16'),
      ('John 3:16!', 'John 3:16'),
      ('John 3:16,', 'John 3:16'),
      ('John 3:16 KJV', 'John 3:16'),
      ('John 3:16 (KJV)', 'John 3:16'),
      ('John 3:16 (NIV)', 'John 3:16'),
      ('John 3:16 NKJV.', 'John 3:16'),
      ('John 3:16 King James Version', 'John 3:16'),
      ('John 3:16-18 esv', 'John 3:16-18'),
      ('John 3:16–18', 'John 3:16-18'),
      ('John 3:16—18', 'John 3:16-18'),
      ('John 3:16 – 18', 'John 3:16-18'),
      ('John 3:16 - 4:2', 'John 3:16–4:2'),
      ('John 3:35 – 4:2', 'John 3:35–4:2'),
      ('JOHN 3:16', 'John 3:16'),
      ('\tJohn 3:16\n', 'John 3:16'),
      ('Psalm 23 (KJV)', 'Psalm 23'),
      ('1 Corinthians 13:4-7 (KJV)', '1 Corinthians 13:4-7'),
      ('Psalm 120-122', 'Psalm 120:1–122:9'),
      ('John 3-4', 'John 3:1–4:54'),
    ]) {
      test('"$input"', () => expect(shown(input), expected));
    }
  });

  group('every book written correctly', () {
    for (final book in bibleBooks) {
      final plain = book.replaceFirst(RegExp(r'^\d '), '');
      test(book, () {
        for (final variant in {
          book,
          book.toLowerCase(),
          book.toUpperCase(),
          book.replaceAll(' ', ''),
        }) {
          final r = parseBibleReference('$variant 1');
          // A one-chapter book's number is a verse.
          expect(r.book, book, reason: variant);
          expect(r.corrected, isFalse, reason: variant);
        }
        expect(plain, isNotEmpty);
      });
    }
  });

  group('each of the 66 books with one slip still finds its book', () {
    /// Swaps two neighbouring letters in the middle, or drops a letter
    /// when the two are the same.
    String slip(String name, int variant) {
      final letters = name.split('');
      var i = letters.length ~/ 2;
      if (variant == 1) {
        letters.removeAt(i);
        return letters.join();
      }
      if (i >= letters.length - 1) i = letters.length - 2;
      while (i > 0 && letters[i] == letters[i + 1]) {
        i--;
      }
      final t = letters[i];
      letters[i] = letters[i + 1];
      letters[i + 1] = t;
      return letters.join();
    }

    for (final book in bibleBooks) {
      final number = RegExp(r'^\d').hasMatch(book) ? book[0] : '';
      final plain = book.replaceFirst(RegExp(r'^\d '), '');
      // A letter dropped from a name of three or four letters ("Ams",
      // "Jon") is too short to tell from other books and real
      // abbreviations, so only a swap is tried on those.
      for (final variant in plain.length <= 5 ? [0] : [0, 1]) {
        final typed = slip(plain.replaceAll(' ', ''), variant);
        if (typed.toLowerCase() == plain.toLowerCase()) continue;
        test('$book as "$number $typed"', () {
          final input = '$number $typed 1:1'.trim();
          try {
            final r = parseBibleReference(input);
            expect(r.book, book, reason: input);
          } on BibleBookChoice catch (e) {
            expect(e.books, contains(book), reason: input);
          }
        });
      }
    }
  });

  group('what is not a reference is refused with a message', () {
    void fails(String input, String message) => expect(
      () => parseBibleReference(input),
      throwsA(
        isA<RuleError>().having((e) => e.message, 'message', contains(message)),
      ),
      reason: input,
    );

    test('no reference, no chapter, no book', () {
      fails('', 'Type a reference');
      fails('   ', 'Type a reference');
      fails('John', 'Try a book and chapter');
      fails('3:16', 'Try a book and chapter');
      fails('3', 'Try a book and chapter');
      fails('hello', 'Try a book and chapter');
    });

    test('a word that is no book', () {
      fails('Hello 3:16', 'is not a book of the Bible');
      fails('Hezekiah 3:1', 'is not a book of the Bible');
      fails('Jesus 3:16', 'is not a book of the Bible');
      fails('Maccabees 1:1', 'is not a book of the Bible');
      fails('Tobit 2:2', 'is not a book of the Bible');
      fails('xyz 4', 'is not a book of the Bible');
      fails('j 3:16', 'is not a book of the Bible');
    });

    test('zero, backwards and out of range', () {
      fails('John 0', 'start at 1');
      fails('John 3:0', 'start at 1');
      fails('John 3:18-16', 'must run forwards');
      fails('Psalm 122-120', 'must run forwards');
    });

    test('junk and very long input', () {
      fails('!!!', 'Type a reference');
      fails('???? 3', 'Try a book and chapter');
      fails('John 3:16 and then some', 'Try a book and chapter');
      fails('a' * 5000, 'too long');
      fails('John 3:16 ' * 50, 'too long');
      fails('${'word ' * 30}3:16', 'too long');
    });

    test('out of range names the limit', () {
      void range(String input, String message) => expect(
        () => kjv.read(input),
        throwsA(
          isA<RuleError>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
        reason: input,
      );
      range('John 3:99', 'John 3 has 36 verses, so there is no verse 99.');
      range('John 30', 'There is no chapter 30 in John: it has 21 chapters.');
      range('John 30:1', 'There is no chapter 30 in John: it has 21 chapters.');
      range('John 1-30', 'There is no chapter 30 in John: it has 21 chapters.');
      range('Jhon 3:99', 'John 3 has 36 verses');
      range('Psalm 151', 'it has 150 chapters');
      range('Psalm 119:177', 'Psalms 119 has 176 verses');
      range('Psalm 1-150', 'Choose at most 200');
      range('Jude 2:1', 'Jude has only one chapter.');
      range('John 3:16-40', 'John 3 has 36 verses, so there is no verse 40.');
    });
  });

  group('known names and abbreviations resolve exactly as before', () {
    test('every full name, with and without its number', () {
      for (final b in bibleBooks) {
        // The old reader took the "I" of "Isaiah" for a Roman one, so the
        // full name itself failed; every other name is read as before.
        expect(
          bibleBookOf(b),
          b == 'Isaiah' ? 'Isaiah' : legacyBookOf(b),
          reason: b,
        );
        expect(bibleBookOf(b.toLowerCase()), b);
      }
    });

    test('every abbreviation, plain and numbered', () {
      final differences = <String>[];
      var checked = 0;
      for (final key in bibleBookAbbreviations.keys) {
        for (final prefix in [
          '',
          '1 ',
          '2 ',
          '3 ',
          '1',
          'I ',
          'II ',
          'III ',
          'first ',
          'second ',
          'third ',
          '1st ',
          '2nd ',
        ]) {
          final typed = '$prefix$key';
          checked++;
          if (bibleBookOf(typed) != legacyBookOf(typed)) {
            differences.add(
              '$typed: ${legacyBookOf(typed)} -> ${bibleBookOf(typed)}',
            );
          }
        }
      }
      expect(checked, greaterThan(1000));
      // The old reader took the "i" of "is" and "isa" for a Roman one, so
      // Isaiah's own abbreviations did not work; "1st" and "2nd" glued to a
      // name were also misread. Everything else is unchanged.
      final unexpected = differences.where((d) {
        final typed = d.split(':').first;
        final isIsaiah = typed == 'is' || typed == 'isa';
        final ordinal = RegExp(r'^[12](st|nd) ').hasMatch(typed);
        return !isIsaiah && !ordinal;
      });
      expect(unexpected, isEmpty);
      expect(bibleBookOf('is'), 'Isaiah');
      expect(bibleBookOf('isa'), 'Isaiah');
      expect(bibleBookOf('Isa.'), 'Isaiah');
    });

    test('every full name with a chapter reads as before', () {
      for (final b in bibleBooks) {
        for (final tail in ['1', '1:1', '1 1', '1:1-2', '1-2']) {
          final input = '$b $tail';
          final r = parseBibleReference(input);
          expect(r.book, b, reason: input);
          expect(r.corrected, isFalse, reason: input);
        }
      }
    });

    test('the clear start of a name still works', () {
      expect(bibleBookOf('deuter'), 'Deuteronomy');
      expect(bibleBookOf('philip'), 'Philippians');
      expect(bibleBookOf('revel'), 'Revelation');
      expect(bibleBookOf('Hezekiah'), isNull);
    });
  });
}
