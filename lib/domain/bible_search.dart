/// On-device search of a Bible translation, by reference or by words, as
/// the operator types. Pure Dart: no Flutter, so the index can be built in
/// an isolate. See "Scripture search" in docs/LYRICS-DESIGN.md.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';

// ---- Words: spelling, archaic and modern forms ---------------------------

/// Words as the King James text spells them, mapped to the modern word
/// they stand for, so that modern wording finds KJV text and the other way
/// round. Both the verses and the query go through [stemWord], so a pair
/// only has to be listed once. Anything not here is left alone (see the
/// design note for what this does not cover).
const archaicForms = <String, String>{
  // Pronouns.
  'thee': 'you', 'thou': 'you', 'ye': 'you', 'thy': 'your', 'thine': 'your',
  'yours': 'your', 'thyself': 'yourself', 'yourselves': 'yourself',
  'mine': 'my', 'which': 'who', 'whom': 'who',
  // Verbs: have, do, say, speak, be, will, shall, can, may, would…
  'hath': 'have', 'hast': 'have', 'has': 'have', 'had': 'have',
  'hadst': 'have', 'doth': 'do', 'dost': 'do', 'doeth': 'do', 'does': 'do',
  'doest': 'do', 'didst': 'do', 'did': 'do', 'saith': 'say', 'sayeth': 'say',
  'sayest': 'say', 'says': 'say', 'spake': 'speak', 'spoke': 'speak',
  'spoken': 'speak',
  'shalt': 'shall',
  'wilt': 'shall',
  'will': 'shall',
  'art': 'are',
  'wast': 'was', 'wert': 'were', 'canst': 'can', 'mayest': 'may',
  'wouldest': 'would', 'wouldst': 'would', 'shouldest': 'should',
  'shouldst': 'should', 'couldest': 'could', 'couldst': 'could',
  'goeth': 'go', 'goes': 'go', 'going': 'go', 'went': 'go', 'gone': 'go',
  // Small words.
  'unto': 'to', 'upon': 'on', 'ere': 'before', 'yea': 'yes', 'nay': 'no',
  'wherefore': 'therefore', 'hither': 'here', 'thither': 'there',
  'whither': 'where', 'oft': 'often', 'alway': 'always',
  'amongst': 'among', 'whilst': 'while', 'betwixt': 'between',
  'verily': 'truly', 'brethren': 'brother', 'wrought': 'work',
  'begat': 'beget', 'begotten': 'beget',
  'whosoever': 'whoever', 'whatsoever': 'whatever', 'whomsoever': 'whoever',
  'whensoever': 'whenever', 'wheresoever': 'wherever',
  'howsoever': 'however',
  // Irregular verbs, whose old and new forms are the same word.
  'gave': 'give', 'given': 'give', 'took': 'take', 'taken': 'take',
  'came': 'come', 'saw': 'see', 'seen': 'see', 'heard': 'hear',
  'knew': 'know', 'known': 'know', 'made': 'make', 'ran': 'run',
  'sat': 'sit', 'stood': 'stand', 'arose': 'arise', 'rose': 'rise',
  'fell': 'fall', 'fallen': 'fall', 'wrote': 'write', 'written': 'write',
  'brought': 'bring', 'sought': 'seek', 'taught': 'teach', 'told': 'tell',
  'sold': 'sell', 'kept': 'keep',
};

/// Words that end like a verb form (-est, -eth, -ed, -es) but are not one,
/// so they keep their ending.
const _keepEnding = {
  'honest',
  'harvest',
  'forest',
  'priest',
  'guest',
  'earnest',
  'interest',
  'request',
  'manifest',
  'tempest',
  'modest',
  'chest',
  'behest',
  'indeed',
  'hundred',
  'kindred',
  'sacred',
  'naked',
  'wicked',
  'beloved',
  'moses',
  'bless',
  'unless',
  'eleventh',
  'seventh',
  'tenth',
  'ninth',
};

/// The common words. They still count in a search (so "in the beginning"
/// works) but weigh a quarter as much as other words.
const stopWords = {
  'the',
  'a',
  'an',
  'and',
  'or',
  'of',
  'to',
  'in',
  'on',
  'at',
  'by',
  'for',
  'with',
  'from',
  'as',
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'it',
  'its',
  'i',
  'he',
  'she',
  'they',
  'we',
  'you',
  'his',
  'her',
  'their',
  'our',
  'my',
  'your',
  'him',
  'them',
  'me',
  'us',
  'that',
  'this',
  'these',
  'those',
  'not',
  'no',
  'but',
  'so',
  'if',
  'then',
  'than',
  'shall',
  'will',
  'have',
  'do',
  'who',
  'which',
  'unto',
  'upon',
  'thee',
  'thou',
  'thy',
  'ye',
  'hath',
  'all',
  'there',
  'what',
  'when',
  'up',
  'out',
  'into',
};

final _stemCache = <String, String>{};

/// The stop words as [stemWord] writes them.
final _stopStems = {for (final w in stopWords) stemWord(w)};

/// The key a word is searched under: lower case, archaic forms and
/// endings folded together (believeth, believes, believed and believe are
/// all "believ"). Applied to the verses and to the query alike, so the
/// folding only has to be consistent, not correct English.
String stemWord(String word) {
  final w = word.toLowerCase();
  final hit = _stemCache[w];
  if (hit != null) return hit;
  final s = _stem(archaicForms[w] ?? w);
  if (_stemCache.length < 60000) _stemCache[w] = s;
  return s;
}

String _undouble(String s) {
  if (s.length > 3 &&
      s.codeUnitAt(s.length - 1) == s.codeUnitAt(s.length - 2) &&
      !'lsfzaeiou'.contains(s[s.length - 1])) {
    return s.substring(0, s.length - 1);
  }
  return s;
}

String _stem(String w) {
  if (w.length <= 3 || _keepEnding.contains(w)) return w;
  var s = w;
  if (s.endsWith('ies') && s.length > 4) {
    return '${s.substring(0, s.length - 3)}y';
  }
  if (s.endsWith('ied') && s.length > 4) {
    return '${s.substring(0, s.length - 3)}y';
  }
  // A plural or "he loves" first, so the endings after it are the same
  // for "beginnings" as for "beginning" and "passes" as for "passeth".
  if (s.endsWith('s') &&
      !s.endsWith('ss') &&
      !s.endsWith('us') &&
      !s.endsWith('is')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.length <= 3) return s;
  if (s.endsWith('ing') && s.length > 5) {
    s = s.substring(0, s.length - 3);
  } else if ((s.endsWith('eth') || s.endsWith('est')) && s.length > 5) {
    s = s.substring(0, s.length - 3);
  } else if (s.endsWith('ed') && s.length > 4) {
    s = s.substring(0, s.length - 2);
  }
  if (s.endsWith('e') && s.length > 3) s = s.substring(0, s.length - 1);
  return _undouble(s);
}

final _wordPattern = RegExp(r"\p{L}+(?:['’]\p{L}+)*", unicode: true);

/// The words of [text] with where each starts and ends.
Iterable<RegExpMatch> wordsOf(String text) => _wordPattern.allMatches(text);

String _plain(String raw) => raw.toLowerCase().replaceAll(RegExp("['’]"), '');

// ---- Reading what was typed as a reference -------------------------------

/// What the box's text means as a reference. This is the one place the
/// search reads the reference parser: when the parser learns misspelt
/// books, spoken forms or candidate books, only [interpretReference]
/// changes.
class ReferenceReading {
  /// The complete reference, when the text is one.
  final BibleReference? reference;

  /// Books the text could be the start of, best first (typed "jo": Job,
  /// Joel, John, Jonah, Joshua).
  final List<String> books;

  /// What was typed after the book name ("3", "3:1"), for a book still
  /// being chosen.
  final String rest;

  /// A line saying how the text was understood, when it was not typed
  /// plainly ("Showing John 3:16").
  final String? note;

  /// Whether the verses were typed with a number still being typed:
  /// "John 3:1" also offers 10 to 19.
  final bool narrowing;
  const ReferenceReading({
    this.reference,
    this.books = const [],
    this.rest = '',
    this.note,
    this.narrowing = false,
  });

  bool get isReference => reference != null;
  bool get isBook => reference == null && books.isNotEmpty;
}

/// "John 3:16-18" for [r], as the reference parser reads it back.
String referenceText(BibleReference r) {
  final b = r.book;
  if (r.verse == null) {
    return r.endChapter == null
        ? '$b ${r.chapter}'
        : '$b ${r.chapter}-${r.endChapter}';
  }
  final start = '$b ${r.chapter}:${r.verse}';
  if (r.endChapter != null) return '$start-${r.endChapter}:${r.endVerse}';
  if (r.endVerse != null) return '$start-${r.endVerse}';
  return start;
}

String _bookKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Reads [input] as a reference or the start of a book's name.
ReferenceReading interpretReference(String input) {
  var q = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (q.isEmpty) return const ReferenceReading();
  // A separator typed and nothing after it yet: "John 3:" and "John 3:16-".
  final bare = q.replaceFirst(RegExp(r'[\s:.,\-–—]+$'), '');
  if (bare.isEmpty) return const ReferenceReading();
  final trailing = bare.length != q.length;
  q = bare;
  if (RegExp(r'\d').hasMatch(q)) {
    try {
      final r = parseBibleReference(q);
      // The last number is still being typed when it is a lone verse.
      return ReferenceReading(
        reference: r,
        narrowing: r.verse != null && r.endVerse == null && !trailing,
      );
    } on RuleError {
      // Fall through: it may be a book still being typed, "jo 3".
    }
  }
  final m = RegExp(
    r'^((?:[123]|i{1,3}|first|second|third|1st|2nd|3rd)?\s?[a-z][a-z .]*?)\s?(\d[\d:.,\- –]*)?$',
    caseSensitive: false,
  ).firstMatch(q);
  if (m == null) return const ReferenceReading();
  final typed = m.group(1)!.trim();
  final rest = (m.group(2) ?? '').trim();
  final found = <String>[];
  final exact = bibleBookOf(typed);
  if (exact != null) found.add(exact);
  final key = _bookKey(typed.replaceFirst(RegExp(r'^(1st|2nd|3rd)'), ''));
  final numbered = RegExp(
    r'^(?:([123])|(i{1,3})(?=\s)|(first)|(second)|(third)|(1st)|(2nd)|(3rd))\s?(?=[a-z])',
    caseSensitive: false,
  ).firstMatch(typed);
  int? part;
  var letters = key;
  if (numbered != null) {
    final p = numbered.group(0)!.trim().toLowerCase();
    part = switch (p) {
      '1' || 'i' || 'first' || '1st' => 1,
      '2' || 'ii' || 'second' || '2nd' => 2,
      _ => 3,
    };
    letters = _bookKey(typed.substring(numbered.end));
  }
  final byName = [...bibleBooks]
    ..sort(
      (a, b) => a
          .replaceFirst(RegExp(r'^\d '), '')
          .compareTo(b.replaceFirst(RegExp(r'^\d '), '')),
    );
  if (letters.length >= 2) {
    for (final b in byName) {
      final isNumbered = RegExp(r'^\d ').hasMatch(b);
      if (isNumbered != (part != null)) continue;
      if (isNumbered && !b.startsWith('$part ')) continue;
      final name = _bookKey(b.replaceFirst(RegExp(r'^\d '), ''));
      if (name.startsWith(letters) && !found.contains(b)) found.add(b);
    }
  }
  return ReferenceReading(books: found, rest: rest);
}

// ---- Named passages ------------------------------------------------------

/// Passages people ask for by name, which no word of the verses says.
const namedPassages = <String, String>{
  "the lord's prayer": 'Matthew 6:9-13',
  'our father': 'Matthew 6:9-13',
  'the beatitudes': 'Matthew 5:3-12',
  'ten commandments': 'Exodus 20:1-17',
  'the great commission': 'Matthew 28:18-20',
  'the great commandment': 'Matthew 22:37-40',
  'the good samaritan': 'Luke 10:25-37',
  'the prodigal son': 'Luke 15:11-32',
  'the christmas story': 'Luke 2:1-20',
  'the nativity': 'Luke 2:1-20',
  'the love chapter': '1 Corinthians 13',
  'the shepherd psalm': 'Psalm 23',
  'the armour of god': 'Ephesians 6:10-18',
  'the armor of god': 'Ephesians 6:10-18',
  'the fruit of the spirit': 'Galatians 5:22-23',
  'the sermon on the mount': 'Matthew 5-7',
  'the golden rule': 'Matthew 7:12',
  'the creation': 'Genesis 1',
  'the resurrection': 'Matthew 28:1-10',
  'the lord is my shepherd': 'Psalm 23',
  'the road to emmaus': 'Luke 24:13-35',
  'the good shepherd': 'John 10:1-18',
  'the birth of jesus': 'Luke 2:1-20',
};

/// Verses most often asked for. Among words that fit equally well, these
/// come first, so "shadow of death" offers Psalm 23:4 before a verse of Job.
const popularVerses = [
  'Genesis 1:1',
  'Genesis 1:27',
  'Exodus 20:3',
  'Deuteronomy 31:6',
  'Joshua 1:9',
  'Psalm 23:1',
  'Psalm 23:4',
  'Psalm 27:1',
  'Psalm 34:8',
  'Psalm 37:4',
  'Psalm 46:1',
  'Psalm 51:10',
  'Psalm 91:1',
  'Psalm 100:4',
  'Psalm 118:24',
  'Psalm 119:105',
  'Psalm 121:1',
  'Psalm 139:14',
  'Proverbs 3:5',
  'Proverbs 3:6',
  'Proverbs 22:6',
  'Isaiah 9:6',
  'Isaiah 40:31',
  'Isaiah 41:10',
  'Isaiah 53:5',
  'Jeremiah 29:11',
  'Lamentations 3:22',
  'Micah 6:8',
  'Matthew 5:16',
  'Matthew 6:9',
  'Matthew 6:33',
  'Matthew 7:7',
  'Matthew 11:28',
  'Matthew 22:37',
  'Matthew 28:19',
  'Matthew 28:20',
  'Luke 2:11',
  'John 1:1',
  'John 1:14',
  'John 3:16',
  'John 8:32',
  'John 10:10',
  'John 13:34',
  'John 14:6',
  'John 14:27',
  'John 15:13',
  'Acts 1:8',
  'Romans 3:23',
  'Romans 5:8',
  'Romans 6:23',
  'Romans 8:28',
  'Romans 10:9',
  'Romans 12:2',
  '1 Corinthians 10:13',
  '1 Corinthians 13:4',
  '1 Corinthians 13:13',
  '2 Corinthians 5:17',
  '2 Corinthians 12:9',
  'Galatians 5:22',
  'Ephesians 2:8',
  'Ephesians 2:9',
  'Ephesians 6:11',
  'Philippians 4:6',
  'Philippians 4:7',
  'Philippians 4:13',
  'Colossians 3:23',
  '1 Thessalonians 5:16',
  '2 Timothy 1:7',
  'Hebrews 11:1',
  'Hebrews 12:1',
  'Hebrews 12:2',
  'Hebrews 13:8',
  'James 1:2',
  '1 Peter 5:7',
  '1 John 1:9',
  '1 John 4:8',
  '1 John 4:19',
  'Revelation 3:20',
  'Revelation 21:4',
];

// ---- The index -----------------------------------------------------------

/// One verse or passage in a result.
class SearchHit {
  /// The reference as it is shown ("John 3:16", "Psalm 23", "John 3:16–4:2").
  final String reference;

  /// The passage in the form [parseBibleReference] reads back.
  final BibleReference passage;

  /// Its words: a verse's text, or the verses joined for a passage.
  final String text;

  /// Matched stretches of [text] to highlight, as [start, end) pairs.
  final List<(int, int)> spans;

  /// How many verses it covers: 1 for a verse.
  final int verses;

  /// Why it is here: 0 the reference, 1 a named passage, 2 an exact
  /// phrase, 3 all words near each other, 4 all words, 5 and 6 the same
  /// with a misspelt word, 7 most of the words.
  final int tier;
  const SearchHit({
    required this.reference,
    required this.passage,
    required this.text,
    this.spans = const [],
    this.verses = 1,
    this.tier = 0,
  });
}

/// What a search found.
class SearchResult {
  final String query;

  /// The best hits, at most the limit asked for.
  final List<SearchHit> hits;

  /// How many there are in all.
  final int total;

  /// Books the text could be the start of.
  final List<String> books;

  /// A line to show above the hits ("Showing John 3:16"), or a problem
  /// ("There is no chapter 40 in John: it has 21 chapters.").
  final String? note;
  final bool problem;

  /// Whether the text was read as a reference.
  final bool byReference;
  const SearchResult(
    this.query, {
    this.hits = const [],
    this.total = 0,
    this.books = const [],
    this.note,
    this.problem = false,
    this.byReference = false,
  });

  bool get isEmpty => hits.isEmpty && books.isEmpty;
}

class _Token {
  final String raw, stem;
  var prefix = false;
  bool fuzzy = false;
  bool phrase;
  late Uint8List mask;
  final ids = <int>[];
  var found = false;
  var weight = 1.0;
  _Token(this.raw, this.stem, {this.phrase = false});
}

/// The words of one translation, ready to search: every word of every
/// verse as a small number, and for each word the verses that have it.
/// Keeps its [Bible] so results can be read in full. The same code
/// searches any translation in the `CSTBIBLE` format.
class BibleSearchIndex {
  final Bible bible;
  final int verseCount;

  /// Per verse: its book (index into [bible.books]), chapter and number.
  final Uint8List _book;
  final Uint8List _chapter;
  final Uint8List _number;

  /// Where each chapter starts, by book.
  final List<Int32List> _chapterStart;

  /// Each verse's words, as stem numbers: [_tokenStart] gives the range.
  final Int32List _tokenStart, _tokens;

  /// Per stem number: the verses that have it, in canonical order.
  final Int32List _postStart, _postings;
  final Map<String, int> _stemId;

  /// The words as the text spells them (lower case, sorted), each with
  /// its stem number, for typing the start of a word and for typos.
  final List<String> _forms;
  final Int32List _formStem;
  final List<double> _idf;

  /// 1 for the verses in [popularVerses].
  final Uint8List _popular;

  BibleSearchIndex._(
    this.bible,
    this.verseCount,
    this._book,
    this._chapter,
    this._number,
    this._chapterStart,
    this._tokenStart,
    this._tokens,
    this._postStart,
    this._postings,
    this._stemId,
    this._forms,
    this._formStem,
    this._idf,
    this._popular,
  );

  /// The translation's code, such as KJV.
  String get code => bible.code;

  /// Bytes the index holds beyond the Bible text itself, worked out from
  /// the sizes of its tables.
  int get approxBytes =>
      _book.lengthInBytes * 3 +
      _tokenStart.lengthInBytes +
      _tokens.lengthInBytes +
      _postStart.lengthInBytes +
      _postings.lengthInBytes +
      _formStem.lengthInBytes +
      _idf.length * 8 +
      // Strings of the word lists: about 2 bytes a letter plus overhead.
      (_forms.fold<int>(0, (n, w) => n + 2 * w.length + 24)) +
      _stemId.length * 56;

  int get wordCount => _stemId.length;
  int get tokenCount => _tokens.length;

  /// Builds the index of [bible]. Takes a few hundred milliseconds for a
  /// whole Bible: run it away from the screen's thread.
  factory BibleSearchIndex.build(Bible bible) {
    var n = 0;
    for (final b in bible.text) {
      for (final c in b) {
        n += c.length;
      }
    }
    final book = Uint8List(n), chapter = Uint8List(n), number = Uint8List(n);
    final chapterStart = <Int32List>[];
    final tokenStart = Int32List(n + 1);
    var tokens = Int32List(n * 30 + 1024);
    var t = 0;
    final stemId = <String, int>{};
    final formStem = <String, int>{};
    var v = 0;
    for (var b = 0; b < bible.text.length; b++) {
      final starts = Int32List(bible.text[b].length);
      for (var c = 0; c < bible.text[b].length; c++) {
        starts[c] = v;
        final verses = bible.text[b][c];
        for (var i = 0; i < verses.length; i++) {
          book[v] = b;
          chapter[v] = math.min(255, c + 1);
          number[v] = math.min(255, i + 1);
          tokenStart[v] = t;
          for (final m in wordsOf(verses[i])) {
            final form = _plain(m[0]!);
            final stem = stemWord(form);
            final id = stemId.putIfAbsent(stem, () => stemId.length);
            formStem[form] = id;
            if (t == tokens.length) {
              final grown = Int32List(tokens.length * 2)..setAll(0, tokens);
              tokens = grown;
            }
            tokens[t++] = id;
          }
          v++;
        }
      }
      chapterStart.add(starts);
    }
    tokenStart[n] = t;
    final stems = stemId.length;
    // Verses per stem, each verse once.
    final counts = Int32List(stems + 1);
    final seen = Int32List(stems)..fillRange(0, stems, -1);
    for (var i = 0; i < n; i++) {
      for (var j = tokenStart[i]; j < tokenStart[i + 1]; j++) {
        final s = tokens[j];
        if (seen[s] != i) {
          seen[s] = i;
          counts[s + 1]++;
        }
      }
    }
    for (var s = 0; s < stems; s++) {
      counts[s + 1] += counts[s];
    }
    final postings = Int32List(counts[stems]);
    final fill = Int32List.fromList(counts.sublist(0, stems));
    seen.fillRange(0, stems, -1);
    for (var i = 0; i < n; i++) {
      for (var j = tokenStart[i]; j < tokenStart[i + 1]; j++) {
        final s = tokens[j];
        if (seen[s] != i) {
          seen[s] = i;
          postings[fill[s]++] = i;
        }
      }
    }
    final forms = formStem.keys.toList()..sort();
    final formIds = Int32List(forms.length);
    for (var i = 0; i < forms.length; i++) {
      formIds[i] = formStem[forms[i]]!;
    }
    final idf = List<double>.generate(stems, (s) {
      final df = counts[s + 1] - counts[s];
      return math.log(1 + n / df);
    });
    final popular = Uint8List(n);
    for (final ref in popularVerses) {
      final r = parseBibleReference(ref);
      final b = bible.books.indexOf(r.book);
      if (b < 0 || r.chapter > chapterStart[b].length) continue;
      final id = chapterStart[b][r.chapter - 1] + r.verse! - 1;
      if (id < n) popular[id] = 1;
    }
    return BibleSearchIndex._(
      bible,
      n,
      book,
      chapter,
      number,
      chapterStart,
      tokenStart,
      Int32List.sublistView(tokens, 0, t),
      counts,
      postings,
      stemId,
      forms,
      formIds,
      idf,
      popular,
    );
  }

  // ---- Verses ------------------------------------------------------------

  int _verseId(int book, int chapter, int verse) =>
      _chapterStart[book][chapter - 1] + verse - 1;

  String _verseText(int id) =>
      bible.text[_book[id]][_chapter[id] - 1][_number[id] - 1];

  /// The verse's reference, "John 3:16".
  String verseReference(int id) =>
      '${singularBook(bible.books[_book[id]])} ${_chapter[id]}:${_number[id]}';

  SearchHit _verseHit(
    int id,
    int tier,
    List<_Token> tokens, {
    bool highlight = true,
  }) {
    final text = _verseText(id);
    return SearchHit(
      reference: verseReference(id),
      passage: BibleReference(
        bible.books[_book[id]],
        _chapter[id],
        verse: _number[id],
      ),
      text: text,
      spans: highlight && tokens.isNotEmpty
          ? _highlight(text, tokens)
          : const [],
      tier: tier,
    );
  }

  /// The hit for a reference that may be a verse, a run of verses or a
  /// chapter, or the problem in it.
  ({SearchHit? hit, String? problem}) _passage(BibleReference r, int tier) {
    try {
      final reading = bible.read(referenceText(r));
      final verses = reading.verses;
      return (
        hit: SearchHit(
          reference: reading.reference,
          passage: r,
          text: verses.length == 1
              ? verses.single.text
              : verses.map((v) => v.text).join(' '),
          verses: verses.length,
          tier: tier,
        ),
        problem: null,
      );
    } on RuleError catch (e) {
      return (hit: null, problem: e.message);
    }
  }

  // ---- Searching ---------------------------------------------------------

  /// Everything the box can ask: a reference, the start of a book's name,
  /// a named passage, or words. [limit] is how many hits to return.
  SearchResult search(String query, {int limit = 30}) {
    final q = query.length > 300 ? query.substring(0, 300) : query;
    final trimmed = q.trim();
    if (trimmed.isEmpty) return SearchResult(query);
    final reading = interpretReference(trimmed);
    if (reading.isReference) return _byReference(query, reading, limit);
    final named = _named(trimmed);
    final words = _byWords(query, trimmed, limit, reading);
    if (named.isEmpty) return words;
    return SearchResult(
      query,
      hits: [...named, ...words.hits].take(limit).toList(),
      total: named.length + words.total,
      books: reading.books,
      note: words.note,
      problem: words.problem,
    );
  }

  List<SearchHit> _named(String q) {
    String plain(String t) => t
        .toLowerCase()
        .replaceAll(RegExp(r"['’]"), '')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^the '), '');
    final key = plain(q);
    if (key.length < 4) return const [];
    final out = <SearchHit>[];
    final shown = <String>{};
    for (final e in namedPassages.entries) {
      final name = plain(e.key);
      if (name == key || (key.length >= 5 && name.startsWith(key))) {
        if (!shown.add(e.value)) continue;
        final hit = _passage(parseBibleReference(e.value), 1).hit;
        if (hit != null) out.add(hit);
      }
    }
    return out;
  }

  SearchResult _byReference(String query, ReferenceReading reading, int limit) {
    final r = reading.reference!;
    final whole = _passage(r, 0);
    if (whole.hit == null) {
      return SearchResult(
        query,
        note: whole.problem,
        problem: true,
        byReference: true,
      );
    }
    final hits = <SearchHit>[];
    var total = 1;
    if (r.verse == null) {
      // A chapter: the whole chapter first, then each of its verses.
      hits.add(whole.hit!);
      final first = _verseId(bible.books.indexOf(r.book), r.chapter, 1);
      final lastChapter = r.endChapter ?? r.chapter;
      final b = bible.books.indexOf(r.book);
      final end = _verseId(
        b,
        lastChapter,
        bible.text[b][lastChapter - 1].length,
      );
      total = 1 + end - first + 1;
      for (var id = first; id <= end && hits.length < limit; id++) {
        hits.add(_verseHit(id, 0, const []));
      }
    } else if (r.endVerse == null && r.endChapter == null) {
      // A verse, or the start of its number: "John 3:1" also offers 10 to 19.
      final b = bible.books.indexOf(r.book);
      final count = bible.text[b][r.chapter - 1].length;
      final typed = '${r.verse}';
      final ids = <int>[
        for (var n = 1; n <= count; n++)
          if (n == r.verse || (reading.narrowing && '$n'.startsWith(typed)))
            _verseId(b, r.chapter, n),
      ];
      total = ids.length;
      for (final id in ids.take(limit)) {
        hits.add(_verseHit(id, 0, const []));
      }
    } else {
      hits.add(whole.hit!);
    }
    return SearchResult(
      query,
      hits: hits,
      total: total,
      note: reading.note,
      byReference: true,
    );
  }

  /// The tokens of a words search, reading quotes as phrases.
  List<_Token> _tokensOf(String text, {required bool typing}) {
    final out = <_Token>[];
    var inQuote = false;
    var last = 0;
    final parts = <(String, bool)>[];
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"' || ch == '“' || ch == '”') {
        parts.add((text.substring(last, i), inQuote));
        inQuote = !inQuote;
        last = i + 1;
      }
    }
    parts.add((text.substring(last), inQuote));
    for (final (part, quoted) in parts) {
      for (final m in wordsOf(part)) {
        if (out.length >= 12) break;
        final raw = _plain(m[0]!);
        out.add(_Token(raw, stemWord(raw), phrase: quoted));
      }
    }
    if (out.isNotEmpty && typing && out.last.raw.length >= 2) {
      out.last.prefix = true;
    }
    return out;
  }

  /// The verses of one book, when the words start with its name:
  /// "rom faith". Returns the book, and how many words it used.
  (int, int)? _leadingBook(String trimmed) {
    final words = trimmed.split(RegExp(r'\s+'));
    for (var n = math.min(3, words.length - 1); n >= 1; n--) {
      final name = words.take(n).join(' ');
      if (RegExp(r'\d').hasMatch(name.replaceFirst(RegExp(r'^[123]\s?'), ''))) {
        continue;
      }
      final letters = name.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length < 3) continue;
      final b = bibleBookOf(name);
      if (b == null) continue;
      // The whole name, or a short form of it that is not also a word the
      // verses use: "the" starts Thessalonians but is not a book.
      final whole =
          _bookKey(name) == _bookKey(b) ||
          _bookKey(name) == _bookKey(b.replaceFirst(RegExp(r'^\d '), ''));
      if (!whole && words.length >= 2 && n == 1 && _isWord(name)) continue;
      if (!whole && _isWord(name)) continue;
      return (bible.books.indexOf(b), n);
    }
    return null;
  }

  /// Whether [word] is in common use in the verses (in a hundred or more).
  bool _isWord(String word) {
    final id = _stemId[stemWord(word)];
    return id != null && _postStart[id + 1] - _postStart[id] >= 100;
  }

  SearchResult _byWords(
    String query,
    String trimmed,
    int limit,
    ReferenceReading reading,
  ) {
    final typing = !RegExp(r'\s$').hasMatch(query) && !query.endsWith('"');
    var text = trimmed;
    int? onlyBook;
    final lead = _leadingBook(trimmed);
    if (lead != null) {
      onlyBook = lead.$1;
      text = trimmed.split(RegExp(r'\s+')).skip(lead.$2).join(' ');
    }
    var result = _wordSearch(query, text, typing, limit, onlyBook, reading);
    if (result.hits.isEmpty && onlyBook != null) {
      // "mark my words": Mark was a word, not a book.
      result = _wordSearch(query, trimmed, typing, limit, null, reading);
    }
    return result;
  }

  SearchResult _wordSearch(
    String query,
    String text,
    bool typing,
    int limit,
    int? onlyBook,
    ReferenceReading reading,
  ) {
    final tokens = _tokensOf(text, typing: typing);
    final none = SearchResult(query, books: reading.books);
    if (tokens.isEmpty) return none;
    // A single letter or two is a book's start or nothing: too many verses.
    if (tokens.length == 1 &&
        tokens.first.raw.length < 3 &&
        !tokens.first.phrase) {
      return none;
    }
    final stems = _stemId.length;
    final missing = <String>[];
    for (final tok in tokens) {
      tok.mask = Uint8List(stems);
      _resolve(tok);
      if (!tok.found) missing.add(tok.raw);
    }
    final used = [
      for (final t in tokens)
        if (t.found) t,
    ];
    final hasReal = used.any((t) => !_stopStems.contains(t.stem));
    // A word nothing matches is set aside when real words match.
    if (used.isEmpty || !hasReal) return none;
    final k = used.length;
    final marks = Uint16List(verseCount);
    for (var i = 0; i < k; i++) {
      final tok = used[i];
      final bit = 1 << i;
      for (final s in tok.ids) {
        for (var p = _postStart[s]; p < _postStart[s + 1]; p++) {
          marks[_postings[p]] |= bit;
        }
      }
    }
    final full = (1 << k) - 1;
    final strict = <int>[];
    final partial = <int>[];
    final lo = onlyBook == null ? 0 : _chapterStart[onlyBook].first;
    final hi = onlyBook == null
        ? verseCount
        : (onlyBook + 1 < _chapterStart.length
              ? _chapterStart[onlyBook + 1].first
              : verseCount);
    for (var v = lo; v < hi; v++) {
      final m = marks[v];
      if (m == full) {
        strict.add(v);
      } else if (k >= 3 && m != 0 && _popcount(m) == k - 1) {
        partial.add(v);
      }
    }
    final quoted = used.any((t) => t.phrase);
    final fuzzyAny = used.any((t) => t.fuzzy);
    final keys = <int>[];
    for (final v in strict) {
      final r = _rank(v, used);
      if (quoted && !r.phrase) continue;
      keys.add(
        _key(_tierOf(r, fuzzyAny), r.score * (_popular[v] == 1 ? 1.5 : 1), v),
      );
    }
    // Most of the words only when the whole set finds little.
    if (keys.length < 5 && !quoted) {
      for (final v in partial) {
        final r = _rank(v, used, partial: true);
        keys.add(_key(7, r.score, v));
      }
    }
    keys.sort();
    final hits = <SearchHit>[];
    for (final key in keys.take(limit)) {
      final v = key & 0xfffff;
      hits.add(_verseHit(v, key >> 40, used));
    }
    String? note;
    if (missing.isNotEmpty) {
      note = missing.length == 1
          ? 'No verse has “${missing.first}”; showing the rest of your words.'
          : 'No verse has “${missing.join('”, “')}”; showing the rest of your words.';
    }
    return SearchResult(
      query,
      hits: hits,
      total: keys.length,
      books: reading.books,
      note: hits.isEmpty ? null : note,
    );
  }

  static int _popcount(int x) {
    var n = 0;
    while (x != 0) {
      n += x & 1;
      x >>= 1;
    }
    return n;
  }

  static int _key(int tier, double score, int verse) {
    final inv = 65535 - math.min<int>(65535, (score * 200).round());
    return (tier << 40) | (inv << 20) | verse;
  }

  int _tierOf(_Rank r, bool fuzzy) {
    if (fuzzy) return r.phrase || r.near ? 5 : 6;
    if (r.phrase) return 2;
    if (r.near) return 3;
    return 4;
  }

  /// Fills [tok]'s mask with every stem it may mean: the word itself, the
  /// start of a word being typed, or, for a word that is nowhere, the
  /// words a typo or two away.
  void _resolve(_Token tok) {
    // 2 marks the word itself, 1 a longer word it starts or a near miss.
    void add(int s, [int how = 1]) {
      if (tok.mask[s] == 0) tok.ids.add(s);
      if (tok.mask[s] < how) tok.mask[s] = how;
    }

    final exact = _stemId[tok.stem];
    if (exact != null) {
      add(exact, 2);
      tok.found = true;
    }
    if (tok.prefix) {
      var lo = _lowerBound(tok.raw);
      while (lo < _forms.length && _forms[lo].startsWith(tok.raw)) {
        add(_formStem[lo]);
        tok.found = true;
        lo++;
      }
    }
    if (tok.found) {
      tok.weight = exact != null ? 1.0 : .8;
      return;
    }
    final allowed = tok.raw.length >= 8
        ? 2
        : tok.raw.length >= 4
        ? 1
        : 0;
    if (allowed == 0) return;
    var best = allowed + 1;
    final near = <int>[];
    for (var i = 0; i < _forms.length; i++) {
      final f = _forms[i];
      if ((f.length - tok.raw.length).abs() > allowed) continue;
      // Two slips in a long word leave its first letter alone.
      if (allowed == 2 && f.codeUnitAt(0) != tok.raw.codeUnitAt(0)) continue;
      final d = allowed == 1
          ? _oneAway(tok.raw, f)
          : _distance(tok.raw, f, allowed);
      if (d > allowed) continue;
      if (d < best) {
        best = d;
        near.clear();
      }
      if (d == best) near.add(_formStem[i]);
    }
    near.forEach(add);
    if (near.isNotEmpty) {
      tok.found = true;
      tok.fuzzy = true;
      tok.weight = .6;
    }
  }

  int _lowerBound(String prefix) {
    var lo = 0, hi = _forms.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_forms[mid].compareTo(prefix) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 0 when equal, 1 when one letter added, dropped, changed or swapped
  /// makes them equal, 2 otherwise: no memory used.
  static int _oneAway(String a, String b) {
    final n = a.length, m = b.length;
    if ((n - m).abs() > 1) return 2;
    var i = 0;
    while (i < n && i < m && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    if (i == n && i == m) return 0;
    if (n == m) {
      // Changed letter, or two letters swapped.
      if (a.substring(i + 1) == b.substring(i + 1)) return 1;
      if (i + 1 < n &&
          a.codeUnitAt(i) == b.codeUnitAt(i + 1) &&
          a.codeUnitAt(i + 1) == b.codeUnitAt(i) &&
          a.substring(i + 2) == b.substring(i + 2)) {
        return 1;
      }
      return 2;
    }
    final longer = n > m ? a : b, shorter = n > m ? b : a;
    return longer.substring(i + 1) == shorter.substring(i) ? 1 : 2;
  }

  /// Edits between [a] and [b] (a swap of two letters counts once), or
  /// more than [max] when it is further.
  static int _distance(String a, String b, int max) {
    final n = a.length, m = b.length;
    if ((n - m).abs() > max) return max + 1;
    var prev2 = List<int>.filled(m + 1, 0);
    var prev = List<int>.generate(m + 1, (j) => j);
    for (var i = 1; i <= n; i++) {
      final cur = List<int>.filled(m + 1, 0);
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var d = math.min(
          math.min(prev[j] + 1, cur[j - 1] + 1),
          prev[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          d = math.min(d, prev2[j - 2] + 1);
        }
        cur[j] = d;
        if (d < rowMin) rowMin = d;
      }
      if (rowMin > max) return max + 1;
      prev2 = prev;
      prev = cur;
    }
    return prev[m];
  }

  /// How well verse [v] fits the words: all in a row (a phrase), close
  /// together, or anywhere, and a score for ordering within that.
  _Rank _rank(int v, List<_Token> tokens, {bool partial = false}) {
    final from = _tokenStart[v], to = _tokenStart[v + 1];
    final n = tokens.length;
    var phrase = false;
    var phraseAt = -1;
    if (!partial) {
      // Words in a row, in the order typed.
      for (var i = from; i + n <= to && !phrase; i++) {
        var ok = true;
        for (var k = 0; k < n; k++) {
          if (tokens[k].mask[_tokens[i + k]] == 0) {
            ok = false;
            break;
          }
        }
        phrase = ok;
        if (ok) phraseAt = i;
      }
    }
    // The shortest stretch holding every word.
    var near = false;
    if (!partial && !phrase) {
      final seenAt = List<int>.filled(n, -1);
      var span = 1 << 30;
      for (var i = from; i < to; i++) {
        final s = _tokens[i];
        for (var k = 0; k < n; k++) {
          if (tokens[k].mask[s] != 0) seenAt[k] = i;
        }
        if (seenAt.every((p) => p >= 0)) {
          final lowest = seenAt.reduce(math.min);
          span = math.min(span, i - lowest + 1);
        }
      }
      near = span <= math.max(2 * n + 3, 8);
    }
    var score = 0.0;
    for (final t in tokens) {
      var best = 0.0;
      for (var i = from; i < to; i++) {
        final how = t.mask[_tokens[i]];
        if (how != 0) {
          final w = how == 2 ? 1.0 : (t.fuzzy ? .6 : .8);
          best = math.max(best, _idf[_tokens[i]] * w);
          if (how == 2) break;
        }
      }
      score += _stopStems.contains(t.stem) ? best * .25 : best;
    }
    // A shorter verse says more about the words than a long one, and a
    // verse that opens with the phrase is the one people mean.
    score *= 1 + 6 / (to - from + 10);
    if (phraseAt == from) score *= 1.35;
    return _Rank(phrase, near, score);
  }

  List<(int, int)> _highlight(String text, List<_Token> tokens) {
    final spans = <(int, int)>[];
    for (final m in wordsOf(text)) {
      final form = _plain(m[0]!);
      final id = _stemId[stemWord(form)];
      var hit = false;
      for (final t in tokens) {
        if ((id != null && t.mask[id] != 0) ||
            (t.prefix && form.startsWith(t.raw))) {
          hit = true;
          break;
        }
      }
      if (hit) spans.add((m.start, m.end));
    }
    return spans;
  }

  /// Every verse of the chapter [chapter] of [book], as hits (for
  /// extending a passage).
  List<LyricVerse> chapterVerses(String book, int chapter) {
    final b = bible.books.indexOf(book);
    if (b < 0 || chapter < 1 || chapter > bible.text[b].length) return const [];
    final verses = bible.text[b][chapter - 1];
    return [
      for (var i = 0; i < verses.length; i++)
        LyricVerse(chapter, i + 1, verses[i]),
    ];
  }
}

class _Rank {
  final bool phrase, near;
  final double score;
  const _Rank(this.phrase, this.near, this.score);
}
