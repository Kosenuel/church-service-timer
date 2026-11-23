/// Bible text for verse slides: the bundled King James Version and, in a
/// later version, downloaded translations in the same file format, and
/// references such as "John 3:16-18", "Psalm 23" or "1 Cor 13:4-7".
library;

import 'package:church_service_timer/domain/bible_speech.dart';
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
    return BibleReading(title, code, verses, corrected: r.corrected);
  }
}

/// What a lookup found: its reference as it should be shown, the
/// translation and the verses.
class BibleReading {
  final String reference, version;
  final List<LyricVerse> verses;

  /// True when the book name was a misspelling that was put right.
  final bool corrected;
  const BibleReading(
    this.reference,
    this.version,
    this.verses, {
    this.corrected = false,
  });
}

/// "Psalm 23", not "Psalms 23", for one psalm.
String singularBook(String book) => book == 'Psalms' ? 'Psalm' : book;

/// A reference, read: book, chapter, and the verses when given.
class BibleReference {
  final String book;
  final int chapter;
  final int? verse, endChapter, endVerse;

  /// True when the book was not typed as a known name or abbreviation but
  /// worked out from a misspelling or a short start, so the screen can
  /// show what it understood.
  final bool corrected;
  const BibleReference(
    this.book,
    this.chapter, {
    this.verse,
    this.endChapter,
    this.endVerse,
    this.corrected = false,
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
const bibleBookAbbreviations = <String, String>{
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

String _baseName(String book) => book.replaceFirst(RegExp(r'^\d '), '');
String _squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');

/// A book written out in full or by an abbreviation, without its number,
/// or null. "Psalm", "song of songs", "jn".
String? _exactBase(String key) {
  for (final b in bibleBooks) {
    final name = _baseName(b);
    if (_squash(name) == key) return name;
  }
  return bibleBookAbbreviations[key];
}

final _partPrefix = RegExp(
  r'^(1st|2nd|3rd|first|second|third|1|2|3|iii|ii|i)(\s*)',
);

/// A leading "1", "II" or "first" and what follows it, or (null, all).
(int?, String) _splitPart(String w) {
  final prefix = _partPrefix.firstMatch(w);
  if (prefix == null) return (null, w);
  final rest = w.substring(prefix.end).trim();
  // "Is" (Isaiah) and "I" alone are not numbers.
  if (rest.isEmpty) return (null, w);
  final word = prefix.group(1)!;
  // "isa" and "iss" are not "I sa": a Roman numeral run straight into
  // letters counts only when what is left is not a book by itself.
  final glued = prefix.group(2)!.isEmpty && word.startsWith('i');
  if (glued && _exactBase(_squash(w)) != null) return (null, w);
  final part = switch (word) {
    '1' || 'i' || 'first' || '1st' => 1,
    '2' || 'ii' || 'second' || '2nd' => 2,
    _ => 3,
  };
  return (part, rest);
}

/// The full name of [base] as part [part] (null: not given), or null when
/// there is no such book. A bare numbered book is its first part, as it
/// always was ("Cor 13" is 1 Corinthians); bare John is the gospel.
String? _withPart(String base, int? part) {
  if (_numbered.contains(base)) {
    if (base == 'John' && part == null) return 'John';
    final name = '${part ?? 1} $base';
    return bibleBooks.contains(name) ? name : null;
  }
  return part == null ? base : null;
}

/// The book [words] names ("1 cor", "First Corinthians", "jn", "psalm"),
/// or null.
String? bibleBookOf(String words) {
  final w = words.toLowerCase().replaceAll('.', ' ').trim();
  final (part, rest) = _splitPart(w);
  final key = _squash(rest);
  var base = _exactBase(key);
  if (base == null && key.length >= 3) {
    // A clear start of a name: "deuter", "philip", "revel".
    final starts = {
      for (final b in bibleBooks)
        if (_squash(_baseName(b)).startsWith(key)) _baseName(b),
    };
    if (starts.length == 1) base = starts.single;
  }
  return base == null ? null : _withPart(base, part);
}

/// The books a misspelt or cut-short name could mean: one, when it is
/// clear, or several for the screen to offer. Empty when nothing is close.
/// Only the 66 names and the known abbreviations are compared, a number
/// before the name is respected ("1 jhon" is never the gospel of John) and
/// short names are never guessed at beyond a transposed pair of letters.
List<String> bibleBookGuesses(String words) {
  final w = words.toLowerCase().replaceAll('.', ' ').trim();
  final (part, rest) = _splitPart(w);
  var found = _guess(_squash(rest), part);
  if (found.isEmpty && part != null) {
    // "Isiah" is not "I siah".
    found = _guess(_squash(w), null);
  }
  return found;
}

List<String> _guess(String key, int? part) {
  if (key.length < 2) return const [];
  bool wanted(String base) => _withPart(base, part) != null;
  // A start shared by several books: "jo", "phi", "ma".
  final starts = <String>[
    for (final b in bibleBooks)
      if (_squash(_baseName(b)).startsWith(key) && wanted(_baseName(b)))
        _baseName(b),
  ];
  if (starts.isNotEmpty) {
    return _inOrder({for (final b in starts) _withPart(b, part)!});
  }
  if (key.length < 3) return const [];
  final limit = _allowed(key.length);
  var best = double.infinity;
  final byBase = <String, double>{};
  void consider(String base, String name, double extra) {
    if (!wanted(base)) return;
    var d = _distance(key, name);
    // A typed start of a long name: "phillip" for "philippians".
    if (key.length >= 5 && name.length > key.length) {
      final cut = _distance(key, name.substring(0, key.length));
      if (cut < d) d = cut;
    }
    d += extra;
    if (key.length == 3 && (name.length != 3 || d > 0.5 + extra)) return;
    if (d - extra > limit) return;
    if (d < (byBase[base] ?? double.infinity)) byBase[base] = d;
    if (d < best) best = d;
  }

  for (final b in bibleBooks) {
    final base = _baseName(b);
    if (b != base && !b.startsWith('1 ')) continue;
    consider(base, _squash(base), 0);
  }
  for (final e in bibleBookAbbreviations.entries) {
    if (e.key.length >= 4 || key.length == 3) {
      consider(e.value, e.key, 0.25);
    }
  }
  if (byBase.isEmpty) return const [];
  return _inOrder({
    for (final e in byBase.entries)
      if ((e.value - best).abs() < 0.01) _withPart(e.key, part)!,
  });
}

List<String> _inOrder(Set<String> names) => [
  for (final b in bibleBooks)
    if (names.contains(b)) b,
];

/// How many letters may be wrong in a name of [length] letters. A
/// transposed pair counts half, so "jhon" is nearer John than "jon" is.
double _allowed(int length) => length <= 3
    ? 0.5
    : length <= 6
    ? 1
    : length <= 12
    ? 2
    : 3;

/// Edit distance with swaps of neighbouring letters counted as half.
double _distance(String a, String b) {
  final d = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0.0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i.toDouble();
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j.toDouble();
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0.0 : 1.0;
      var v = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final t = d[i - 2][j - 2] + 0.5;
        if (t < v) v = t;
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

/// A book name that could be one of several, so the screen can offer them.
/// [rest] is what followed the book ("3:1"); with a chosen book put in
/// front it is a reference again.
class BibleBookChoice extends RuleError {
  final List<String> books;
  final String rest;
  BibleBookChoice(this.books, this.rest)
    : super('Which book? ${books.join(', ')}.');
}

/// Longest text taken for a reference; anything longer is not one.
const bibleReferenceLimit = 120;

final _translationTag = RegExp(
  r'\s*(?:\([^)]{1,30}\)|\b(?:king james(?: version)?|kjv|nkjv|niv|esv|nlt|asv|nasb|amp|msg|csb|web|nrsv|rsv|cev|gnt|erv|ylt|nirv|hcsb|tlb|lsb|bsb|net|ncv|nab|ceb))\s*$',
  caseSensitive: false,
);

/// Reads a reference such as "John 3:16", "John 3:16-18", "John 3:16–4:2",
/// "Psalm 23", "1 Cor 13:4-7", "Jn 3 16", "john chapter three verse sixteen"
/// or "Jhon 3 16". A trailing translation such as "KJV" is ignored. Throws a
/// [BibleBookChoice] when the book could be several, and any other
/// [RuleError] with a helpful message for anything else.
BibleReference parseBibleReference(String input) {
  var raw = input.trim();
  require(raw.isNotEmpty, 'Type a reference, such as John 3:16 or Psalm 23.');
  require(
    raw.length <= bibleReferenceLimit,
    'That is too long for a Bible reference. Try a book, chapter and verses, such as John 3:16-18.',
  );
  for (var i = 0; i < 2; i++) {
    final cut = raw.replaceFirst(_translationTag, '');
    raw = cut.replaceFirst(RegExp(r'[\s.,;:!?]+$'), '');
    if (raw.isEmpty) break;
  }
  require(raw.isNotEmpty, 'Type a reference, such as John 3:16 or Psalm 23.');
  var text = normaliseSpokenReference(raw);
  // "16 and 17" is the run 16-17; "16 and 19" is not one.
  text = text.replaceAllMapped(RegExp(r'(\d+)&(\d+)'), (m) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    require(
      b == a + 1,
      'Type one run of verses, such as John 3:16-19, not separate ones.',
    );
    return '$a-$b';
  });
  final m = RegExp(
    r'^((?:[123]|i{1,3}|first|second|third)?\s?[a-z][a-z .]*?)\s?(\d+)(?::(\d+)|\s(\d+))?(?:-(\d+)(?::(\d+))?)?$',
    caseSensitive: false,
  ).firstMatch(text);
  require(
    m != null,
    'Try a book and chapter, such as John 3 or Psalm 23, or add verses: John 3:16-18.',
  );
  final found = m!;
  final words = found.group(1)!;
  var corrected = false;
  var book = bibleBookOf(words);
  if (book == null) {
    final guesses = bibleBookGuesses(words);
    if (guesses.length == 1) {
      book = guesses.single;
      corrected = true;
    } else if (guesses.length > 1) {
      throw BibleBookChoice(guesses, text.substring(words.length).trim());
    }
  }
  require(
    book != null,
    '"${words.trim()}" is not a book of the Bible this app knows. Try the full name, such as 1 Corinthians.',
  );
  final chapter = int.parse(found.group(2)!);
  final verseText = found.group(3) ?? found.group(4);
  final verse = verseText == null ? null : int.parse(verseText);
  int? endChapter, endVerse;
  if (found.group(5) != null) {
    if (found.group(6) != null) {
      endChapter = int.parse(found.group(5)!);
      endVerse = int.parse(found.group(6)!);
    } else if (verse == null) {
      endChapter = int.parse(found.group(5)!);
    } else {
      endVerse = int.parse(found.group(5)!);
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
    return BibleReference(book!, 1, verse: chapter, corrected: corrected);
  }
  return BibleReference(
    book!,
    chapter,
    verse: verse,
    endChapter: endChapter,
    endVerse: endVerse,
    corrected: corrected,
  );
}
