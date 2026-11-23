/// Bible text for verse slides: the bundled King James Version and, in a
/// later version, downloaded translations in the same file format, and
/// references such as "John 3:16-18", "Psalm 23" or "1 Cor 13:4-7".
library;

import 'package:church_service_timer/domain/domain.dart';

/// One translation, read from a `CSTBIBLE 1` file: a header line
/// `CSTBIBLE 1|<code>|<name>|<licence>`, then `#<book>` before each book,
/// `@` before each chapter and one verse per line.
class Bible {
  final String code, name, licence;

  /// Books in order; each is chapters, each chapter its verses.
  final List<String> books;
  final List<List<List<String>>> text;
  const Bible(this.code, this.name, this.licence, this.books, this.text);

  factory Bible.parse(String source) {
    final lines = source.split('\n');
    final head = lines.first.trim().split('|');
    require(
      head.length >= 3 && head[0] == 'CSTBIBLE 1',
      'This is not a Bible file this app can read.',
    );
    final books = <String>[];
    final text = <List<List<String>>>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        books.add(line.substring(1).trim());
        text.add([]);
      } else if (line == '@') {
        require(text.isNotEmpty, 'This Bible file is damaged.');
        text.last.add([]);
      } else {
        require(
          text.isNotEmpty && text.last.isNotEmpty,
          'This Bible file is damaged.',
        );
        text.last.last.add(line);
      }
    }
    require(books.isNotEmpty, 'This Bible file has no books.');
    return Bible(head[1], head[2], head.length > 3 ? head[3] : '', books, text);
  }

  /// The verses [reference] names, or a [RuleError] that says what to
  /// fix.
  BibleReading read(String reference) {
    final r = parseBibleReference(reference);
    final b = books.indexOf(r.book);
    require(b >= 0, '${r.book} is not in the $code.');
    final chapters = text[b];
    String chapterCount(int n) => n == 1 ? '1 chapter' : '$n chapters';
    require(
      r.chapter <= chapters.length,
      chapters.length == 1
          ? '${r.book} has only one chapter.'
          : 'There is no chapter ${r.chapter} in ${r.book}: it has ${chapterCount(chapters.length)}.',
    );
    final endChapter = r.endChapter ?? r.chapter;
    require(
      endChapter <= chapters.length,
      'There is no chapter $endChapter in ${r.book}: it has ${chapterCount(chapters.length)}.',
    );
    final first = r.verse ?? 1;
    require(
      first <= chapters[r.chapter - 1].length,
      '${r.book} ${r.chapter} has ${chapters[r.chapter - 1].length} verses, so there is no verse $first.',
    );
    final last =
        r.endVerse ??
        (r.verse == null || r.endChapter != null
            ? chapters[endChapter - 1].length
            : first);
    require(
      last <= chapters[endChapter - 1].length,
      '${r.book} $endChapter has ${chapters[endChapter - 1].length} verses, so there is no verse $last.',
    );
    final verses = <LyricVerse>[];
    for (var c = r.chapter; c <= endChapter; c++) {
      final from = c == r.chapter ? first : 1;
      final to = c == endChapter ? last : chapters[c - 1].length;
      for (var v = from; v <= to; v++) {
        verses.add(LyricVerse(c, v, chapters[c - 1][v - 1]));
      }
    }
    require(
      verses.isNotEmpty,
      'The verses must run forwards, such as John 3:16-18.',
    );
    require(
      verses.length <= 200,
      'That is ${verses.length} verses. Choose at most 200 at a time.',
    );
    // A whole chapter reads "Psalm 23"; a single-chapter book's verses
    // are still numbered with its chapter.
    final title = r.verse == null && r.endChapter == null
        ? '${singularBook(r.book)} ${r.chapter}'
        : verseRange(singularBook(r.book), verses);
    return BibleReading(title, code, verses);
  }
}

/// What a lookup found: its reference as it should be shown, the
/// translation and the verses.
class BibleReading {
  final String reference, version;
  final List<LyricVerse> verses;
  const BibleReading(this.reference, this.version, this.verses);
}

/// "Psalm 23", not "Psalms 23", for one psalm.
String singularBook(String book) => book == 'Psalms' ? 'Psalm' : book;

/// A reference, read: book, chapter, and the verses when given.
class BibleReference {
  final String book;
  final int chapter;
  final int? verse, endChapter, endVerse;
  const BibleReference(
    this.book,
    this.chapter, {
    this.verse,
    this.endChapter,
    this.endVerse,
  });
}

/// The 66 books, in order, as the bundled files name them.
const bibleBooks = [
  'Genesis',
  'Exodus',
  'Leviticus',
  'Numbers',
  'Deuteronomy',
  'Joshua',
  'Judges',
  'Ruth',
  '1 Samuel',
  '2 Samuel',
  '1 Kings',
  '2 Kings',
  '1 Chronicles',
  '2 Chronicles',
  'Ezra',
  'Nehemiah',
  'Esther',
  'Job',
  'Psalms',
  'Proverbs',
  'Ecclesiastes',
  'Song of Solomon',
  'Isaiah',
  'Jeremiah',
  'Lamentations',
  'Ezekiel',
  'Daniel',
  'Hosea',
  'Joel',
  'Amos',
  'Obadiah',
  'Jonah',
  'Micah',
  'Nahum',
  'Habakkuk',
  'Zephaniah',
  'Haggai',
  'Zechariah',
  'Malachi',
  'Matthew',
  'Mark',
  'Luke',
  'John',
  'Acts',
  'Romans',
  '1 Corinthians',
  '2 Corinthians',
  'Galatians',
  'Ephesians',
  'Philippians',
  'Colossians',
  '1 Thessalonians',
  '2 Thessalonians',
  '1 Timothy',
  '2 Timothy',
  'Titus',
  'Philemon',
  'Hebrews',
  'James',
  '1 Peter',
  '2 Peter',
  '1 John',
  '2 John',
  '3 John',
  'Jude',
  'Revelation',
];

/// Other names and common abbreviations, without spaces or full stops,
/// in lower case. A number before a book ("1", "i", "first") is read
/// separately.
const _bookNames = <String, String>{
  'gen': 'Genesis',
  'ge': 'Genesis',
  'gn': 'Genesis',
  'ex': 'Exodus',
  'exo': 'Exodus',
  'exod': 'Exodus',
  'lev': 'Leviticus',
  'le': 'Leviticus',
  'lv': 'Leviticus',
  'num': 'Numbers',
  'nu': 'Numbers',
  'nm': 'Numbers',
  'nb': 'Numbers',
  'deut': 'Deuteronomy',
  'de': 'Deuteronomy',
  'dt': 'Deuteronomy',
  'deu': 'Deuteronomy',
  'josh': 'Joshua',
  'jos': 'Joshua',
  'jsh': 'Joshua',
  'judg': 'Judges',
  'jdg': 'Judges',
  'jg': 'Judges',
  'jdgs': 'Judges',
  'rth': 'Ruth',
  'ru': 'Ruth',
  'sam': 'Samuel',
  'sa': 'Samuel',
  'sm': 'Samuel',
  'kgs': 'Kings',
  'ki': 'Kings',
  'kin': 'Kings',
  'chr': 'Chronicles',
  'chron': 'Chronicles',
  'ch': 'Chronicles',
  'ezr': 'Ezra',
  'neh': 'Nehemiah',
  'ne': 'Nehemiah',
  'est': 'Esther',
  'esth': 'Esther',
  'es': 'Esther',
  'jb': 'Job',
  'ps': 'Psalms',
  'psa': 'Psalms',
  'psalm': 'Psalms',
  'pss': 'Psalms',
  'psm': 'Psalms',
  'pslm': 'Psalms',
  'prov': 'Proverbs',
  'pro': 'Proverbs',
  'prv': 'Proverbs',
  'pr': 'Proverbs',
  'eccl': 'Ecclesiastes',
  'ecc': 'Ecclesiastes',
  'eccles': 'Ecclesiastes',
  'qoh': 'Ecclesiastes',
  'song': 'Song of Solomon',
  'songofsongs': 'Song of Solomon',
  'sos': 'Song of Solomon',
  'so': 'Song of Solomon',
  'canticles': 'Song of Solomon',
  'sg': 'Song of Solomon',
  'songofsol': 'Song of Solomon',
  'isa': 'Isaiah',
  'is': 'Isaiah',
  'jer': 'Jeremiah',
  'je': 'Jeremiah',
  'jr': 'Jeremiah',
  'lam': 'Lamentations',
  'la': 'Lamentations',
  'ezek': 'Ezekiel',
  'eze': 'Ezekiel',
  'ezk': 'Ezekiel',
  'dan': 'Daniel',
  'da': 'Daniel',
  'dn': 'Daniel',
  'hos': 'Hosea',
  'ho': 'Hosea',
  'joe': 'Joel',
  'jl': 'Joel',
  'am': 'Amos',
  'obad': 'Obadiah',
  'ob': 'Obadiah',
  'oba': 'Obadiah',
  'jon': 'Jonah',
  'jnh': 'Jonah',
  'mic': 'Micah',
  'mc': 'Micah',
  'nah': 'Nahum',
  'na': 'Nahum',
  'hab': 'Habakkuk',
  'hb': 'Habakkuk',
  'zeph': 'Zephaniah',
  'zep': 'Zephaniah',
  'zp': 'Zephaniah',
  'hag': 'Haggai',
  'hg': 'Haggai',
  'zech': 'Zechariah',
  'zec': 'Zechariah',
  'zc': 'Zechariah',
  'mal': 'Malachi',
  'ml': 'Malachi',
  'matt': 'Matthew',
  'mt': 'Matthew',
  'mat': 'Matthew',
  'mk': 'Mark',
  'mrk': 'Mark',
  'mar': 'Mark',
  'mr': 'Mark',
  'lk': 'Luke',
  'luk': 'Luke',
  'lu': 'Luke',
  'jn': 'John',
  'jhn': 'John',
  'joh': 'John',
  'ac': 'Acts',
  'act': 'Acts',
  'rom': 'Romans',
  'ro': 'Romans',
  'rm': 'Romans',
  'cor': 'Corinthians',
  'co': 'Corinthians',
  'gal': 'Galatians',
  'ga': 'Galatians',
  'eph': 'Ephesians',
  'ephes': 'Ephesians',
  'phil': 'Philippians',
  'php': 'Philippians',
  'pp': 'Philippians',
  'col': 'Colossians',
  'co.': 'Colossians',
  'thess': 'Thessalonians',
  'th': 'Thessalonians',
  'thes': 'Thessalonians',
  'tim': 'Timothy',
  'ti': 'Timothy',
  'tm': 'Timothy',
  'tit': 'Titus',
  'phm': 'Philemon',
  'philem': 'Philemon',
  'phlm': 'Philemon',
  'heb': 'Hebrews',
  'jas': 'James',
  'jm': 'James',
  'jam': 'James',
  'pet': 'Peter',
  'pe': 'Peter',
  'pt': 'Peter',
  'jud': 'Jude',
  'jd': 'Jude',
  'rev': 'Revelation',
  're': 'Revelation',
  'rv': 'Revelation',
  'revelations': 'Revelation',
};

/// Books that come in numbered parts.
const _numbered = {
  'Samuel',
  'Kings',
  'Chronicles',
  'Corinthians',
  'Thessalonians',
  'Timothy',
  'Peter',
  'John',
};

/// The book [words] names ("1 cor", "First Corinthians", "jn", "psalm"),
/// or null.
String? bibleBookOf(String words) {
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
    // "Is" (Isaiah) and "I" alone are not numbers.
    if (rest.isEmpty) part = null;
    if (part != null) w = rest;
  }
  final key = w.replaceAll(RegExp(r'\s+'), '').replaceAll('of', 'of');
  String? base;
  for (final b in bibleBooks) {
    final name = b.replaceFirst(RegExp(r'^\d '), '');
    if (name.toLowerCase().replaceAll(' ', '') == key) base = name;
  }
  base ??= _bookNames[key];
  if (base == null && key.length >= 3) {
    // A clear start of a name: "deuter", "philip", "revel".
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
  if (_numbered.contains(base)) {
    // John alone is the gospel; 1, 2 and 3 John are the letters.
    if (base == 'John' && part == null) return 'John';
    final n = part ?? 1;
    final name = '$n $base';
    return bibleBooks.contains(name) ? name : null;
  }
  return part == null ? base : null;
}

/// Reads a reference such as "John 3:16", "John 3:16-18", "John 3:16–4:2",
/// "Psalm 23", "1 Cor 13:4-7" or "Jn 3 16". Throws a [RuleError] with a
/// helpful message for anything else.
BibleReference parseBibleReference(String input) {
  final text = input
      .trim()
      .replaceAll(RegExp('[–—−]'), '-')
      .replaceAll(RegExp(r'\s*-\s*'), '-')
      .replaceAll(RegExp(r'(?<=\d)\s*[:.]\s*(?=\d)'), ':')
      .replaceAll(RegExp(r'\s+'), ' ');
  require(text.isNotEmpty, 'Type a reference, such as John 3:16 or Psalm 23.');
  final m = RegExp(
    r'^((?:[123]|i{1,3}|first|second|third|1st|2nd|3rd)?\s?[a-z][a-z .]*?)\s?(\d+)(?:[: ](\d+))?(?:-(\d+)(?::(\d+))?)?$',
    caseSensitive: false,
  ).firstMatch(text);
  require(
    m != null,
    'Try a book and chapter, such as John 3 or Psalm 23, or add verses: John 3:16-18.',
  );
  final book = bibleBookOf(m!.group(1)!);
  require(
    book != null,
    '"${m.group(1)!.trim()}" is not a book of the Bible this app knows. Try the full name, such as 1 Corinthians.',
  );
  final chapter = int.parse(m.group(2)!);
  final verse = m.group(3) == null ? null : int.parse(m.group(3)!);
  int? endChapter, endVerse;
  if (m.group(4) != null) {
    if (m.group(5) != null) {
      endChapter = int.parse(m.group(4)!);
      endVerse = int.parse(m.group(5)!);
    } else if (verse == null) {
      endChapter = int.parse(m.group(4)!);
    } else {
      endVerse = int.parse(m.group(4)!);
    }
  }
  require(chapter > 0 && (verse ?? 1) > 0, 'Chapters and verses start at 1.');
  require(
    endChapter == null || endChapter >= chapter,
    'The chapters must run forwards, such as Psalm 120-122.',
  );
  require(
    endVerse == null ||
        endChapter != null ||
        verse == null ||
        endVerse >= verse,
    'The verses must run forwards, such as John 3:16-18.',
  );
  // A one-chapter book's verse can be written without its chapter:
  // "Jude 3" is Jude 1:3.
  if (verse == null &&
      endChapter == null &&
      const {
        'Obadiah',
        'Philemon',
        '2 John',
        '3 John',
        'Jude',
      }.contains(book)) {
    return BibleReference(book!, 1, verse: chapter);
  }
  return BibleReference(
    book!,
    chapter,
    verse: verse,
    endChapter: endChapter,
    endVerse: endVerse,
  );
}
