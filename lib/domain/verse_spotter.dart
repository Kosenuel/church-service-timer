/// "Verse listening": the logic that turns what a speech recogniser heard
/// into passages for the Ready tray. It knows nothing about audio or any
/// speech engine: it is fed words and returns candidates. Nothing here
/// sends anything to a screen; the operator does that. See
/// docs/VERSE-LISTENING-DESIGN.md.
///
/// Two spotters share this file:
///  * [VerseSpotter] hears a spoken reference ("turn to john three sixteen").
///  * [VerseMatcher] and [QuoteSpotter] recognise a quoted verse from its
///    words (the KJV text), for when the preacher reads without naming it.
library;

import 'dart:math' as math;

import 'package:church_service_timer/domain/bible.dart';

// ---------------------------------------------------------------------------
// Spoken numbers.
//
// The branch fix/forgiving-bible-references is adding spoken-form parsing to
// parseBibleReference. When it lands, [parseSpokenNumber] and the run/split
// helpers below should be replaced by that code; they are kept in one place
// and are the only number-word handling in this file.
// ---------------------------------------------------------------------------

const _units = <String, int>{
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
};
const _teens = <String, int>{
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};
const _tens = <String, int>{
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fourty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};
const _ohs = {'oh', 'o', 'zero'};

/// Number words as a Nigerian-accented speaker (th said as t or d) may be
/// transcribed. Only applied inside reference spotting, never to quotes.
const _accentFixes = <String, String>{
  'tree': 'three',
  'tirty': 'thirty',
  'tirteen': 'thirteen',
  'tirdy': 'thirty',
  'tird': 'third',
  'fiftin': 'fifteen',
};

bool _isDigits(String s) => s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s);

bool _isNumberWord(String s) =>
    _units.containsKey(s) ||
    _teens.containsKey(s) ||
    _tens.containsKey(s) ||
    s == 'hundred' ||
    _isDigits(s);

/// The whole number [words] say, or null if they are not one number:
/// "sixteen", "twenty eight", "one hundred and nineteen", "one oh five",
/// "105".
int? parseSpokenNumber(List<String> words) {
  if (words.isEmpty) return null;
  if (words.length == 1 && _isDigits(words[0])) {
    return words[0].length > 3 ? null : int.parse(words[0]);
  }
  // "one oh five" is 105.
  if (words.length == 3 &&
      _units.containsKey(words[0]) &&
      _ohs.contains(words[1]) &&
      _units.containsKey(words[2])) {
    return _units[words[0]]! * 100 + _units[words[2]]!;
  }
  var i = 0;
  var hundreds = 0;
  if (_units.containsKey(words[0]) &&
      words.length > 1 &&
      words[1] == 'hundred') {
    hundreds = _units[words[0]]!;
    i = 2;
  } else if (words[0] == 'hundred') {
    hundreds = 1;
    i = 1;
  }
  if (hundreds > 0 && i < words.length && words[i] == 'and') i++;
  final rest = words.sublist(i);
  int? r;
  if (rest.isEmpty) {
    r = hundreds > 0 ? 0 : null;
  } else if (rest.length == 1) {
    r = _units[rest[0]] ?? _teens[rest[0]] ?? _tens[rest[0]];
  } else if (rest.length == 2 &&
      _tens.containsKey(rest[0]) &&
      _units.containsKey(rest[1])) {
    r = _tens[rest[0]]! + _units[rest[1]]!;
  }
  if (r == null) return null;
  return hundreds * 100 + r;
}

/// A chapter said the way people read the Psalms: "one nineteen" is 119.
/// Only used when the plain reading does not give a real chapter.
int? _impliedHundred(List<String> words) {
  if (words.length < 2 || words[0] != 'one') return null;
  final r = parseSpokenNumber(words.sublist(1));
  if (r == null || r < 10 || r > 99) return null;
  return 100 + r;
}

/// The end of the run of number words that starts at [from] (at most 8
/// words): "hundred and nineteen" keeps its "and", "one oh five" its "oh".
int _runEnd(List<String> w, int from) {
  var i = from;
  while (i < w.length && i - from < 8) {
    final t = w[i];
    if (_isNumberWord(t)) {
      i++;
    } else if (t == 'and' &&
        i > from &&
        w[i - 1] == 'hundred' &&
        i + 1 < w.length &&
        _isNumberWord(w[i + 1])) {
      i++;
    } else if (_ohs.contains(t) &&
        i > from &&
        _units.containsKey(w[i - 1]) &&
        i + 1 < w.length &&
        _units.containsKey(w[i + 1])) {
      i++;
    } else {
      break;
    }
  }
  return i;
}

// ---------------------------------------------------------------------------
// Book names as they are said, and as a recogniser mishears them.
// ---------------------------------------------------------------------------

class _Alias {
  final String book;

  /// How much a book on its own is worth: a name nobody says by accident
  /// (Habakkuk) is high; a word or name that turns up in any sermon
  /// (mark, job, numbers, john) is low; a mishearing that is itself an
  /// ordinary word (look, axe, sums) is lowest.
  final double weight;
  const _Alias(this.book, this.weight);
}

const _distinct = 0.62;
const _namey = 0.40;
const _mishear = 0.50;
const _wordy = 0.30;

/// Said names and the common ways they are transcribed. Keys are one to
/// three lower-case words.
final Map<String, _Alias> _aliases = _buildAliases();

Map<String, _Alias> _buildAliases() {
  final m = <String, _Alias>{};
  void add(String book, double w, List<String> names) {
    for (final n in names) {
      m[n] = _Alias(book, w);
    }
  }

  // Distinct names, exactly as said, and spellings a recogniser may give.
  add('Genesis', _distinct, ['genesis', 'genesys', 'jenesis']);
  add('Exodus', _distinct, ['exodus']);
  add('Leviticus', _distinct, ['leviticus', 'levitikus']);
  add('Numbers', _namey, ['numbers']);
  add('Numbers', _wordy, ['number']);
  add('Deuteronomy', _distinct, [
    'deuteronomy',
    'deutronomy',
    'duteronomy',
    'dueteronomy',
  ]);
  add('Joshua', _distinct, ['joshua']);
  add('Judges', _namey, ['judges']);
  add('Judges', _wordy, ['judge']);
  add('Ruth', _namey, ['ruth']);
  add('Ruth', _wordy, ['roof', 'root', 'rut']);
  add('Samuel', _distinct, ['samuel', 'samuels']);
  add('Kings', _namey, ['kings']);
  add('Kings', _wordy, ['king']);
  add('Chronicles', _distinct, ['chronicles', 'chronicle', 'kronicles']);
  add('Ezra', _distinct, ['ezra', 'ezrah', 'esra']);
  add('Nehemiah', _distinct, ['nehemiah', 'nehemia', 'neemiah']);
  add('Esther', _namey, ['esther']);
  add('Job', _namey, ['job']);
  add('Job', _wordy, ['jobs', 'jobe']);
  add('Psalms', _distinct, ['psalms', 'psalm', 'psalmes', 'salms', 'salm']);
  add('Psalms', _wordy, ['sums', 'palms', 'sum', 'palm', 'sam', 'psalter']);
  add('Proverbs', _distinct, ['proverbs', 'proverb', 'provers']);
  add('Ecclesiastes', _distinct, [
    'ecclesiastes',
    'ecclesiasties',
    'eclesiastes',
    'ecclesiaste',
  ]);
  add('Song of Solomon', _distinct, [
    'song of solomon',
    'songs of solomon',
    'song of songs',
    'songs of songs',
    'song of solomons',
    'song solomon',
  ]);
  add('Isaiah', _distinct, ['isaiah', 'isaias', 'isiah', 'isaih']);
  add('Isaiah', _mishear, ['i say a', 'i say ah', 'is i a', 'i said ya']);
  add('Jeremiah', _distinct, ['jeremiah', 'jeremia']);
  add('Jeremiah', _wordy, ['jeremy']);
  add('Lamentations', _distinct, ['lamentations', 'lamentation']);
  add('Ezekiel', _distinct, ['ezekiel', 'ezekial', 'ezequiel', 'ezekeel']);
  add('Ezekiel', _mishear, ['is equal', 'is a kill', 'zekiel']);
  add('Daniel', _namey, ['daniel']);
  add('Hosea', _distinct, ['hosea', 'hoshea', 'hosia']);
  add('Hosea', _mishear, ['jose', 'hosier', 'hoze ya']);
  add('Joel', _namey, ['joel']);
  add('Joel', _wordy, ['jewel']);
  add('Amos', _namey, ['amos']);
  add('Amos', _wordy, ['almost', 'a moss', 'amas']);
  add('Obadiah', _distinct, ['obadiah', 'obadia', 'abadiah']);
  add('Jonah', _namey, ['jonah']);
  add('Micah', _distinct, ['micah', 'micha']);
  add('Micah', _mishear, ['mica', 'mika', 'my ca']);
  add('Nahum', _distinct, ['nahum']);
  add('Nahum', _mishear, ['nahoom', 'nay hum', 'na hum']);
  add('Habakkuk', _distinct, ['habakkuk', 'habakuk', 'habbakuk', 'habacuc']);
  add('Zephaniah', _distinct, ['zephaniah', 'zefaniah', 'zephania']);
  add('Haggai', _distinct, ['haggai', 'hagai']);
  add('Zechariah', _distinct, ['zechariah', 'zachariah', 'zacharia']);
  add('Malachi', _distinct, ['malachi', 'malaki', 'malakai']);
  add('Matthew', _namey, ['matthew', 'mathew']);
  add('Mark', _namey, ['mark']);
  add('Mark', _wordy, ['marks', 'mock', 'mart']);
  add('Luke', _namey, ['luke']);
  add('Luke', _wordy, ['look', 'luck', 'luc']);
  add('John', _namey, ['john']);
  add('Acts', _namey, ['acts']);
  add('Acts', _wordy, ['axe', 'ax', 'act']);
  add('Romans', _distinct, ['romans']);
  add('Romans', _wordy, ['romance', 'roman', 'ro mans']);
  add('Corinthians', _distinct, [
    'corinthians',
    'corinthian',
    'cornithians',
    'co rinthians',
  ]);
  add('Galatians', _distinct, ['galatians', 'galatian', 'gelatians']);
  add('Ephesians', _distinct, ['ephesians', 'ephesian', 'ephesus']);
  add('Ephesians', _mishear, ['efficient', 'efficients', 'e fishians']);
  add('Philippians', _distinct, ['philippians', 'philippian']);
  add('Philippians', _mishear, [
    'philipines',
    'philippines',
    'philipians',
    'phillipians',
    'filipians',
  ]);
  add('Colossians', _distinct, ['colossians', 'colossian', 'colosians']);
  add('Colossians', _mishear, ['collosians', 'collisions']);
  add('Thessalonians', _distinct, [
    'thessalonians',
    'thessalonian',
    'tessalonians',
    'salonians',
  ]);
  add('Timothy', _namey, ['timothy']);
  add('Timothy', _wordy, ['tim']);
  add('Titus', _distinct, ['titus']);
  add('Titus', _mishear, ['tight us', 'tidus', 'tight as']);
  add('Philemon', _distinct, ['philemon', 'filemon']);
  add('Hebrews', _distinct, ['hebrews', 'hebrew']);
  add('Hebrews', _mishear, ['he brews']);
  add('James', _namey, ['james']);
  add('Peter', _namey, ['peter']);
  add('Jude', _namey, ['jude']);
  add('Jude', _wordy, ['dude']);
  add('Revelation', _distinct, ['revelation', 'revelations']);
  return m;
}

/// Words that say which part of a numbered book ("first john").
const _partWords = <String, int>{
  'first': 1,
  '1st': 1,
  '1': 1,
  'one': 1,
  'second': 2,
  '2nd': 2,
  '2': 2,
  'two': 2,
  'third': 3,
  '3rd': 3,
  '3': 3,
  'three': 3,
  'tird': 3,
};

/// How many parts each numbered book has.
const _parts = <String, int>{
  'Samuel': 2,
  'Kings': 2,
  'Chronicles': 2,
  'Corinthians': 2,
  'Thessalonians': 2,
  'Timothy': 2,
  'Peter': 2,
  'John': 3,
};

const _oneChapterBooks = {'Obadiah', 'Philemon', '2 John', '3 John', 'Jude'};

// ---------------------------------------------------------------------------
// Lead-ins and corrections.
// ---------------------------------------------------------------------------

/// Phrases that usually come just before a reference. A strong one all but
/// says "a reference follows"; a weak one is an ordinary word that often
/// does.
const _strongLeadIns = <String>[
  'turn with me to',
  'turn with me in your bibles to',
  'turn in your bibles to',
  'turn your bibles to',
  'turn to',
  'turn over to',
  'open your bibles to',
  'open your bible to',
  'open with me to',
  'open to',
  'let us read',
  'lets read',
  'let us turn to',
  'lets turn to',
  'read with me',
  'read from',
  'reading from',
  'our text is',
  'our text today is',
  'my text is',
  'the scripture is',
  'scripture reading is',
  'the book of',
  'in the book of',
  'as it says in',
  'it says in',
  'as it is written in',
  'we read in',
  'it is written in',
  'go to',
  'come with me to',
  'flip to',
  'look with me at',
  'look at',
  'let us go to',
  'lets go to',
  'take your bible and turn to',
  'with me to',
  'back to',
];
const _weakLeadIns = <String>['in', 'to', 'from', 'at', 'of', 'see'];

const _correctionWords = {
  'sorry',
  'rather',
  'actually',
  'correction',
  'oops',
  'no',
  'wait',
  'mean',
};

/// Markers that can introduce a bare replacement number ("john three,
/// sorry, four").
const _tailCorrections = {'sorry', 'oops', 'correction', 'rather', 'mean'};

const _verseMarkers = {'verse', 'verses', 'versus', 'vs', 'v'};
const _rangeWords = {'to', 'through', 'thru', 'until'};

// ---------------------------------------------------------------------------
// The spotter.
// ---------------------------------------------------------------------------

/// A passage the spotter thinks was named.
class VerseCandidate {
  final BibleReference reference;

  /// The reference as it would be shown: "John 3:16".
  final String label;

  /// The words that were heard, for "Heard: ..." in the tray.
  final String heardAs;

  /// 0 to 1. The tray shows anything the spotter emits; this orders them.
  final double confidence;

  /// The reference ran to the end of what has been heard so far and the
  /// speaker may be about to add a verse. A later, more complete candidate
  /// with [replaces] set will follow if so.
  final bool provisional;

  /// The speaker corrected themselves ("john three, sorry, john four").
  final bool correction;

  /// "from verse one": reading on from here.
  final bool openEnded;

  /// [key] of an earlier candidate this one completes or corrects; the tray
  /// should drop that one.
  final String? replaces;

  /// Other readings of the same words ("twenty three" is Psalm 23 or Psalm
  /// 20:3), most likely first.
  final List<BibleReference> alternatives;

  const VerseCandidate({
    required this.reference,
    required this.label,
    required this.heardAs,
    required this.confidence,
    this.provisional = false,
    this.correction = false,
    this.openEnded = false,
    this.replaces,
    this.alternatives = const [],
  });

  /// Identifies the passage, whatever the wording.
  String get key => referenceKey(reference);

  @override
  String toString() =>
      '$label (${confidence.toStringAsFixed(2)}${provisional ? ', provisional' : ''}) "$heardAs"';
}

String referenceKey(BibleReference r) =>
    '${r.book}|${r.chapter}|${r.verse ?? ''}|${r.endVerse ?? ''}';

/// "John 3:16", "Psalm 119:105-108", "Genesis 1".
String referenceLabel(BibleReference r) {
  final b = singularBook(r.book);
  if (r.verse == null) return '$b ${r.chapter}';
  final end = r.endVerse == null ? '' : '-${r.endVerse}';
  return '$b ${r.chapter}:${r.verse}$end';
}

class _Found {
  final int start, end;
  final BibleReference ref;
  final double confidence;
  final bool provisional, correction, openEnded;
  final int? replacesStart;
  final List<BibleReference> alts;
  const _Found({
    required this.start,
    required this.end,
    required this.ref,
    required this.confidence,
    this.provisional = false,
    this.correction = false,
    this.openEnded = false,
    this.replacesStart,
    this.alts = const [],
  });
}

class _Emitted {
  final int start;
  final String key;
  final DateTime at;
  final bool provisional;
  final BibleReference ref;
  _Emitted(this.start, this.key, this.at, this.provisional, this.ref);
}

/// Listens to recogniser output and says which references were spoken.
///
/// Feed it with [hear]: partial transcripts (each the whole current phrase,
/// replacing the last) and final ones (which are kept). Words are lower
/// case without punctuation, possibly wrong. [hear] returns only what is
/// new: a first sighting, a reference made more complete, a correction, or
/// a provisional one now settled.
class VerseSpotter {
  final Bible bible;

  /// Candidates below this are dropped. Lower it for a more eager spotter
  /// ("sensitivity"), raise it for a quieter one.
  final double minConfidence;

  /// The same passage heard again within this long is not reported again.
  final Duration dedupeWindow;

  /// Words kept for context (a reference can arrive across several
  /// transcripts).
  final int windowWords;

  final List<String> _committed = [];
  int _base = 0; // absolute index of _committed[0]
  final List<_Emitted> _emitted = [];

  VerseSpotter(
    this.bible, {
    this.minConfidence = 0.55,
    this.dedupeWindow = const Duration(seconds: 30),
    this.windowWords = 80,
  });

  /// Forget everything heard (a new service, or Listen switched off).
  void reset() {
    _committed.clear();
    _base = 0;
    _emitted.clear();
  }

  /// Takes the next transcript. [isFinal] false means it is a partial one
  /// that the recogniser may still revise. [at] is when it was heard.
  List<VerseCandidate> hear(String text, {bool isFinal = false, DateTime? at}) {
    final now = at ?? DateTime.now();
    final words = _tokenise(text);
    final all = [..._committed, ...words];
    final found = _scan(all, isFinal: isFinal);
    final out = <VerseCandidate>[];
    for (final f in found) {
      if (f.confidence < minConfidence) continue;
      final abs = _base + f.start;
      final key = referenceKey(f.ref);
      String? replaces;
      if (f.replacesStart != null) {
        final prior = _emitted.where(
          (e) => e.start == _base + f.replacesStart!,
        );
        if (prior.isNotEmpty) replaces = prior.last.key;
      }
      final same = _emitted.where((e) => e.start == abs).toList();
      if (same.isNotEmpty) {
        final last = same.last;
        if (last.key == key) {
          // Seen at this very place. Only a provisional one that has now
          // settled is worth saying again.
          if (!(last.provisional && !f.provisional)) continue;
          replaces = key;
        } else {
          replaces ??= last.key;
        }
      } else {
        final dup = _emitted.any(
          (e) => e.key == key && now.difference(e.at) <= dedupeWindow,
        );
        if (dup && !f.correction) continue;
        // "john three" earlier, "john three sixteen" now with the words
        // shifted: the second completes the first.
        final earlier = _emitted.where(
          (e) =>
              e.ref.book == f.ref.book &&
              e.ref.chapter == f.ref.chapter &&
              e.ref.verse == null &&
              f.ref.verse != null &&
              now.difference(e.at) <= dedupeWindow,
        );
        if (earlier.isNotEmpty) replaces ??= earlier.last.key;
        if (dup) continue;
      }
      _emitted.add(_Emitted(abs, key, now, f.provisional, f.ref));
      out.add(
        VerseCandidate(
          reference: f.ref,
          label: referenceLabel(f.ref),
          heardAs: all.sublist(f.start, f.end).join(' '),
          confidence: f.confidence,
          provisional: f.provisional,
          correction: f.correction,
          openEnded: f.openEnded,
          replaces: replaces,
          alternatives: f.alts,
        ),
      );
    }
    if (isFinal) {
      _committed.addAll(words);
      if (_committed.length > windowWords) {
        final drop = _committed.length - windowWords;
        _committed.removeRange(0, drop);
        _base += drop;
      }
      _emitted.removeWhere(
        (e) => e.start < _base && now.difference(e.at) > dedupeWindow,
      );
    }
    return out;
  }

  static List<String> _tokenise(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
        .replaceAll("'", '');
    return [
      for (final t in cleaned.split(RegExp(r'\s+')))
        if (t.isNotEmpty) _accentFixes[t] ?? t,
    ];
  }

  // ---- scanning a window of words ----

  List<_Found> _scan(List<String> w, {required bool isFinal}) {
    final found = <_Found>[];
    var consumed = 0;
    _Found? last;
    for (var i = 0; i < w.length; i++) {
      if (i < consumed) continue;
      final m = _bookAt(w, i);
      if (m != null) {
        var f = _parseTail(w, m, isFinal);
        if (f != null) {
          // A correction: a marker word shortly after the last reference.
          if (last != null && i - last.end <= 5) {
            final gap = w.sublist(last.end, i);
            if (gap.any(_correctionWords.contains)) {
              f = _Found(
                start: f.start,
                end: f.end,
                ref: f.ref,
                // Saying it again straight after a correction word is
                // evidence in itself.
                confidence: math.min(0.99, f.confidence + 0.15),
                provisional: f.provisional,
                correction: true,
                openEnded: f.openEnded,
                replacesStart: last.start,
                alts: f.alts,
              );
            }
          }
          found.add(f);
          last = f;
          consumed = f.end;
          // "john three, sorry, four".
          final c = _tailCorrection(w, f, isFinal);
          if (c != null) {
            found.add(c);
            last = c;
            consumed = c.end;
          }
          continue;
        }
        continue;
      }
      // "verse sixteen" after a reference that named the chapter.
      final prior = last;
      if (prior != null &&
          i - prior.end <= 40 &&
          (_verseMarkers.contains(w[i]) || w[i] == 'from')) {
        final f = _followUpAt(w, i, prior, isFinal);
        if (f == null) continue;
        found.add(f);
        last = f;
        consumed = f.end;
        i = f.end - 1;
      }
    }
    return found;
  }

  /// A book at [i], with its numbered-part word if there is one.
  _BookHit? _bookAt(List<String> w, int i) {
    int? part;
    var s = i;
    if (_partWords.containsKey(w[i]) && i + 1 < w.length) {
      final n = _aliasAt(w, i + 1);
      if (n != null && _parts.containsKey(n.alias.book)) {
        part = _partWords[w[i]];
        return _hit(w, s, n, part);
      }
    }
    final a = _aliasAt(w, s);
    if (a == null) return null;
    return _hit(w, s, a, null);
  }

  _AliasAt? _aliasAt(List<String> w, int i) {
    for (var len = 3; len >= 1; len--) {
      if (i + len > w.length) continue;
      final a = _aliases[w.sublist(i, i + len).join(' ')];
      if (a != null) return _AliasAt(a, len);
    }
    return null;
  }

  _BookHit? _hit(List<String> w, int start, _AliasAt a, int? part) {
    final base = a.alias.book;
    final maxPart = _parts[base];
    String book;
    var weight = a.alias.weight;
    List<String> alt = const [];
    var end = start + a.len + (part == null ? 0 : 1);
    if (maxPart != null) {
      if (part == null) {
        if (base == 'John') {
          book = 'John';
        } else {
          // "kings" with no number: probably the first, less sure.
          book = '1 $base';
          weight *= 0.85;
          alt = [for (var p = 2; p <= maxPart; p++) '$p $base'];
        }
      } else {
        if (part > maxPart) return null;
        book = '$part $base';
        // A said number plus a book name is much better evidence.
        weight = math.max(weight, 0.55);
      }
    } else {
      if (part != null) return null;
      book = base;
    }
    if (!bibleBooks.contains(book)) return null;
    return _BookHit(
      start: start,
      bookEnd: end,
      book: book,
      weight: weight,
      altBooks: alt,
      leadIn: _leadIn(w, start),
    );
  }

  /// 0 for none, else how much the words before [start] say "a reference
  /// follows".
  double _leadIn(List<String> w, int start) {
    double at(int end) {
      for (final p in _strongLeadIns) {
        if (_endsAt(w, end, p)) return 0.25;
      }
      for (final p in _weakLeadIns) {
        if (_endsAt(w, end, p)) return 0.10;
      }
      return 0;
    }

    var score = at(start);
    // "turn to the book of ...", "let us read the gospel of ...".
    if (start >= 1 && w[start - 1] == 'the') {
      score = math.max(score, at(start - 1));
    }
    if (_endsAt(w, start, 'gospel of') || _endsAt(w, start, 'the gospel of')) {
      score = math.max(score, 0.25);
    }
    return score;
  }

  bool _endsAt(List<String> w, int end, String phrase) {
    final p = phrase.split(' ');
    if (end < p.length) return false;
    for (var k = 0; k < p.length; k++) {
      if (w[end - p.length + k] != p[k]) return false;
    }
    return true;
  }

  int _chaptersOf(String book) => bible.text[bible.books.indexOf(book)].length;
  int _versesOf(String book, int chapter) =>
      bible.text[bible.books.indexOf(book)][chapter - 1].length;

  _Found? _parseTail(List<String> w, _BookHit m, bool isFinal) {
    final n = w.length;
    var j = m.bookEnd;
    var chapterWord = false;
    if (j < n && (w[j] == 'chapter' || w[j] == 'chapters')) {
      chapterWord = true;
      j++;
    }
    // The books and the alternatives for a numbered book without its number.
    final books = [m.book, ...m.altBooks];
    final runEnd = _runEnd(w, j);
    final book = m.book;
    final oneChapter = _oneChapterBooks.contains(book);

    int? chapter;
    int? verse, endVerse;
    var verseWord = false, openEnded = false;
    var alts = <BibleReference>[];
    var end = j;
    var penalty = 0.0;
    var ambiguous = false;

    bool isVerseMarkerAt(int k) =>
        k < n &&
        (_verseMarkers.contains(w[k]) ||
            (w[k] == 'from' && k + 1 < n && _verseMarkers.contains(w[k + 1])));

    if (runEnd == j) {
      // No number straight after the book. A one-chapter book can be
      // followed by "verse four".
      if (oneChapter && isVerseMarkerAt(j)) {
        chapter = 1;
      } else {
        return null;
      }
    } else if (isVerseMarkerAt(runEnd)) {
      // "chapter three verse sixteen".
      final c =
          parseSpokenNumber(w.sublist(j, runEnd)) ??
          _impliedHundred(w.sublist(j, runEnd));
      if (c == null) return null;
      chapter = c;
      end = runEnd;
    } else {
      // "john three sixteen", "psalm twenty three", "jude four".
      final run = w.sublist(j, runEnd);
      final option = _chooseSplit(book, run, chapterWord);
      if (option == null) return null;
      chapter = option.chapter;
      verse = option.verse;
      end = j + option.used;
      alts = option.alts;
      ambiguous = option.ambiguous;
      penalty += option.penalty;
      if (oneChapter && verse == null && chapter > 1) {
        // "jude four": verse four of the only chapter.
        verse = chapter;
        chapter = 1;
      }
    }
    if (chapter > _chaptersOf(book)) {
      // Wrong book of the possibilities? Try the others, else drop.
      var ok = false;
      for (final b in m.altBooks) {
        if (chapter <= _chaptersOf(b)) {
          ok = true;
          break;
        }
      }
      if (!ok) return null;
    }

    // Verse words.
    if (verse == null && isVerseMarkerAt(end)) {
      var k = end;
      if (w[k] == 'from') {
        openEnded = true;
        k++;
      }
      final markerWord = w[k];
      k++;
      final ve = _runEnd(w, k);
      if (ve > k) {
        final v = parseSpokenNumber(w.sublist(k, ve));
        if (v != null) {
          verse = v;
          verseWord = true;
          end = ve;
          // "verses four to seven", "verses four and five".
          if (end + 1 < n) {
            final rangeWord = w[end];
            final re = _runEnd(w, end + 1);
            final to = re > end + 1
                ? parseSpokenNumber(w.sublist(end + 1, re))
                : null;
            if (to != null &&
                (_rangeWords.contains(rangeWord) ||
                    (rangeWord == 'and' &&
                        markerWord == 'verses' &&
                        to == v + 1))) {
              endVerse = to;
              end = re;
            }
          }
        }
      }
    } else if (verse != null && end + 1 < n && _rangeWords.contains(w[end])) {
      // "john three sixteen to eighteen".
      final re = _runEnd(w, end + 1);
      final to = re > end + 1
          ? parseSpokenNumber(w.sublist(end + 1, re))
          : null;
      if (to != null) {
        endVerse = to;
        end = re;
      }
    }

    // Choose among the books by what actually exists.
    var useBook = book;
    if (chapter > _chaptersOf(book)) {
      useBook = books.firstWhere((b) => chapter! <= _chaptersOf(b));
    }
    // Check the verse against the real chapter.
    if (verse != null && verse > _versesOf(useBook, chapter)) {
      verse = null;
      endVerse = null;
      openEnded = false;
      penalty += 0.15;
    }
    if (verse != null && endVerse != null) {
      if (endVerse <= verse || endVerse > _versesOf(useBook, chapter)) {
        endVerse = null;
        penalty += 0.05;
      }
    }
    if (chapter < 1) return null;
    if (verse != null && verse < 1) return null;

    var conf = m.weight + m.leadIn - penalty;
    conf += verse != null ? 0.30 : 0.10;
    if (chapterWord) conf += 0.10;
    if (verseWord) conf += 0.05;
    if (ambiguous) conf -= 0.05;
    conf = conf.clamp(0.0, 0.99);

    final ref = BibleReference(
      useBook,
      chapter,
      verse: verse,
      endVerse: endVerse,
    );
    final alternatives = <BibleReference>[
      ...alts,
      for (final b in m.altBooks)
        if (b != useBook && chapter <= _chaptersOf(b))
          BibleReference(b, chapter, verse: verse, endVerse: endVerse),
    ];
    return _Found(
      start: m.start,
      end: end,
      ref: ref,
      confidence: conf,
      provisional: !isFinal && end == w.length,
      openEnded: openEnded,
      alts: alternatives,
    );
  }

  /// Splits a run of number words after a book into chapter and verse using
  /// what the book really has.
  _Split? _chooseSplit(String book, List<String> run, bool chapterWord) {
    final chapters = _chaptersOf(book);
    final oneChapter = _oneChapterBooks.contains(book);
    final options = <_Split>[];

    // All of it as one chapter: "psalm twenty three".
    final whole = parseSpokenNumber(run);
    if (whole != null && whole >= 1 && whole <= chapters) {
      options.add(_Split(whole, null, run.length));
    } else if (whole != null && oneChapter && whole >= 1) {
      // "jude four": a verse number.
      final inChapter = _versesOf(book, 1);
      if (whole <= inChapter) options.add(_Split(whole, null, run.length));
    }
    // A digit string such as "316".
    if (run.length == 1 && _isDigits(run[0]) && run[0].length >= 3) {
      final d = run[0];
      for (var k = 1; k < d.length; k++) {
        final c = int.parse(d.substring(0, k));
        final v = int.parse(d.substring(k));
        if (c >= 1 && c <= chapters && v >= 1 && v <= _versesOf(book, c)) {
          options.add(_Split(c, v, 1));
        }
      }
    }
    // Chapter then verse.
    {
      for (var s = 1; s < run.length; s++) {
        final a = run.sublist(0, s);
        final b = run.sublist(s);
        final c = parseSpokenNumber(a);
        final v = parseSpokenNumber(b);
        if (c != null && v != null) {
          if (c >= 1 && c <= chapters && v >= 1 && v <= _versesOf(book, c)) {
            options.add(_Split(c, v, run.length));
          }
        }
      }
      // "psalm one nineteen one oh five".
      for (var s = 2; s < run.length; s++) {
        final c = _impliedHundred(run.sublist(0, s));
        final v = parseSpokenNumber(run.sublist(s));
        if (c != null &&
            v != null &&
            c <= chapters &&
            v >= 1 &&
            v <= _versesOf(book, c)) {
          options.add(_Split(c, v, run.length, penalty: 0.05));
        }
      }
    }
    // "psalm one nineteen" (or "one fifty").
    if (options.isEmpty) {
      final c = _impliedHundred(run);
      if (c != null && c <= chapters) {
        options.add(_Split(c, null, run.length, penalty: 0.05));
      }
    }
    // A run longer than the reference ("john three sixteen eighty people"):
    // use the front of it. A chapter alone from a run that went on with
    // number words ("three sixty five") means the verse was misheard, so it
    // is marked down; a number that goes on ("two hundred") is not cut.
    if (options.isEmpty) {
      for (var len = run.length - 1; len >= 1; len--) {
        if (run[len] == 'hundred' || run[len] == 'and') continue;
        final r = _chooseSplitExact(book, run.sublist(0, len));
        if (r != null) {
          return _Split(
            r.chapter,
            r.verse,
            len,
            penalty: r.verse == null ? 0.15 : 0,
          );
        }
      }
    }
    // Nothing fits the book: the chapter alone if it exists, else nothing.
    if (options.isEmpty) {
      for (var s = run.length - 1; s >= 1; s--) {
        if (run[s] == 'hundred' || run[s] == 'and') continue;
        final c = parseSpokenNumber(run.sublist(0, s));
        if (c != null && c >= 1 && c <= chapters) {
          return _Split(c, null, s, penalty: 0.15);
        }
      }
      return null;
    }
    // Prefer chapter and verse over a chapter alone only when the whole run
    // cannot be one number; a number that is a chapter reads as the chapter.
    final first = options.first;
    final others = [
      for (final o in options.skip(1))
        BibleReference(book, o.chapter, verse: o.verse),
    ];
    final result = _Split(
      first.chapter,
      first.verse,
      first.used,
      penalty: first.penalty,
      alts: others,
      ambiguous: options.length > 1,
    );
    return result;
  }

  _Split? _chooseSplitExact(String book, List<String> run) {
    final chapters = _chaptersOf(book);
    final whole = parseSpokenNumber(run);
    if (whole != null && whole >= 1 && whole <= chapters) {
      return _Split(whole, null, run.length);
    }
    for (var s = 1; s < run.length; s++) {
      final c = parseSpokenNumber(run.sublist(0, s));
      final v = parseSpokenNumber(run.sublist(s));
      if (c != null &&
          v != null &&
          c >= 1 &&
          c <= chapters &&
          v >= 1 &&
          v <= _versesOf(book, c)) {
        return _Split(c, v, run.length);
      }
    }
    return null;
  }

  /// "john three, sorry, four": a replacement number straight after a
  /// reference.
  _Found? _tailCorrection(List<String> w, _Found f, bool isFinal) {
    var k = f.end;
    var sawMarker = false;
    while (k < w.length && k - f.end < 3) {
      if (_tailCorrections.contains(w[k])) {
        sawMarker = true;
        k++;
        if (k < w.length && w[k] == 'i') k++;
      } else if (w[k] == 'i' && k + 1 < w.length && w[k + 1] == 'mean') {
        sawMarker = true;
        k += 2;
      } else if (w[k] == 'make' && k + 1 < w.length && w[k + 1] == 'that') {
        sawMarker = true;
        k += 2;
      } else {
        break;
      }
    }
    if (!sawMarker || k >= w.length) return null;
    var isVerse = false;
    if (w[k] == 'verse') {
      isVerse = true;
      k++;
    } else if (w[k] == 'chapter') {
      k++;
    }
    final re = _runEnd(w, k);
    if (re == k) return null;
    final v = parseSpokenNumber(w.sublist(k, re));
    if (v == null || v < 1) return null;
    final base = f.ref;
    BibleReference ref;
    if (isVerse || base.verse != null) {
      if (v > _versesOf(base.book, base.chapter)) return null;
      ref = BibleReference(base.book, base.chapter, verse: v);
    } else {
      if (v > _chaptersOf(base.book)) return null;
      ref = BibleReference(base.book, v);
    }
    return _Found(
      start: f.end,
      end: re,
      ref: ref,
      confidence: math.min(0.95, f.confidence),
      provisional: !isFinal && re == w.length,
      correction: true,
      replacesStart: f.start,
    );
  }

  /// "verse sixteen" or "from verse one" after a reference that has a
  /// chapter.
  _Found? _followUpAt(List<String> w, int i, _Found last, bool isFinal) {
    var k = i;
    var open = false;
    if (w[k] == 'from') {
      open = true;
      k++;
      if (k >= w.length || !_verseMarkers.contains(w[k])) return null;
    }
    final marker = w[k];
    // A bare "v" or "vs" is too easy to hear by accident.
    if (marker == 'v' || marker == 'vs') return null;
    k++;
    final ve = _runEnd(w, k);
    if (ve == k) return null;
    final v = parseSpokenNumber(w.sublist(k, ve));
    if (v == null || v < 1) return null;
    final base = last.ref;
    if (v > _versesOf(base.book, base.chapter)) return null;
    var end = ve;
    int? endVerse;
    if (end + 1 < w.length && _rangeWords.contains(w[end])) {
      final re = _runEnd(w, end + 1);
      final to = re > end + 1
          ? parseSpokenNumber(w.sublist(end + 1, re))
          : null;
      if (to != null && to > v && to <= _versesOf(base.book, base.chapter)) {
        endVerse = to;
        end = re;
      }
    }
    final ref = BibleReference(
      base.book,
      base.chapter,
      verse: v,
      endVerse: endVerse,
    );
    return _Found(
      start: i,
      end: end,
      ref: ref,
      confidence: 0.60,
      provisional: !isFinal && end == w.length,
      openEnded: open,
      replacesStart: base.verse == null ? last.start : null,
    );
  }
}

class _AliasAt {
  final _Alias alias;
  final int len;
  const _AliasAt(this.alias, this.len);
}

class _BookHit {
  final int start, bookEnd;
  final String book;
  final double weight;
  final List<String> altBooks;
  final double leadIn;
  const _BookHit({
    required this.start,
    required this.bookEnd,
    required this.book,
    required this.weight,
    required this.altBooks,
    required this.leadIn,
  });
}

class _Split {
  final int chapter;
  final int? verse;
  final int used;
  final double penalty;
  final List<BibleReference> alts;
  final bool ambiguous;
  const _Split(
    this.chapter,
    this.verse,
    this.used, {
    this.penalty = 0,
    this.alts = const [],
    this.ambiguous = false,
  });
  _Split withUsed(int u) => _Split(
    chapter,
    verse,
    u,
    penalty: penalty,
    alts: alts,
    ambiguous: ambiguous,
  );
}

// ---------------------------------------------------------------------------
// Quoted verses.
// ---------------------------------------------------------------------------

/// Words that a modern speaker says for the KJV's. Applied to both the
/// verse and what was heard, so either side may use either form.
const _archaic = <String, String>{
  'thee': 'you',
  'thou': 'you',
  'ye': 'you',
  'thy': 'your',
  'thine': 'your',
  'hath': 'has',
  'hast': 'have',
  'doth': 'does',
  'dost': 'do',
  'saith': 'says',
  'unto': 'to',
  'shalt': 'shall',
  'wilt': 'will',
  'art': 'are',
  'wherefore': 'therefore',
  'verily': 'truly',
  'whosoever': 'whoever',
  'whatsoever': 'whatever',
  'begotten': 'only',
  'ought': 'should',
};

/// A rough stem that makes "loveth", "loves", "loved" and "loving" one word.
String _canon(String w) {
  w = _archaic[w] ?? w;
  for (final s in const ['eth', 'est', 'ing', 'ed', 'es', 's', 'e']) {
    if (w.length - s.length >= 3 && w.endsWith(s)) {
      return w.substring(0, w.length - s.length);
    }
  }
  return w;
}

List<String> quoteWords(String text) => [
  for (final t
      in text
          .toLowerCase()
          .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
          .split(RegExp(r'\s+')))
    if (t.isNotEmpty) t,
];

/// One possible verse for a quotation.
class VerseMatch {
  final int bookIndex, chapter, verse;
  final String label;

  /// 0 to 1: how well the words heard fit this verse, counting dropped,
  /// wrong and extra words against it.
  final double score;

  /// How much of the heard words' weight the verse accounts for. A long
  /// match has more than a short one.
  final double evidence;

  /// The share of everything heard (by weight) that this verse accounts
  /// for. Low when the match is a few words in the middle of other talk.
  final double coverage;
  const VerseMatch(
    this.bookIndex,
    this.chapter,
    this.verse,
    this.label,
    this.score,
    this.evidence,
    this.coverage,
  );

  double get rank => score * evidence;

  @override
  String toString() =>
      '$label score ${score.toStringAsFixed(2)} evidence ${evidence.toStringAsFixed(1)} coverage ${coverage.toStringAsFixed(2)}';
}

class MatchResult {
  /// Best first. May be empty.
  final List<VerseMatch> top;

  /// Set only when the best is good enough and clearly ahead of the next.
  final VerseMatch? proposal;
  const MatchResult(this.top, this.proposal);
}

/// Finds the KJV verse a run of recognised words is quoting.
class VerseMatcher {
  final Bible bible;

  /// A proposal needs at least this much matched weight (about eight
  /// ordinary words, fewer if they are rare ones). Chosen on a tuning seed
  /// (see docs/VERSE-LISTENING-DESIGN.md).
  final double minEvidence;

  /// ... and at least this score ...
  final double minScore;

  /// ... and the verse must account for at least this share of the words
  /// heard, so a few words of a verse inside other talk ("the love of god
  /// is greater than anything") do not count ...
  final double minCoverage;

  /// ... and a rank at least this many times the runner-up's.
  final double lead;

  final List<_Verse> _verses = [];
  final Map<String, int> _vocab = {};
  final List<int> _df = [];
  final List<List<int>> _postings = [];
  late final List<double> _idf;
  late final double _unknownWeight;
  late final int _commonCut;

  VerseMatcher(
    this.bible, {
    this.minEvidence = 16,
    this.minScore = 0.55,
    this.minCoverage = 0.4,
    this.lead = 1.25,
  }) {
    for (var b = 0; b < bible.text.length; b++) {
      for (var c = 0; c < bible.text[b].length; c++) {
        for (var v = 0; v < bible.text[b][c].length; v++) {
          final ids = <int>[];
          for (final w in quoteWords(bible.text[b][c][v])) {
            final k = _canon(w);
            final id = _vocab.putIfAbsent(k, () {
              _df.add(0);
              _postings.add([]);
              return _vocab.length;
            });
            ids.add(id);
          }
          final n = _verses.length;
          for (final id in ids.toSet()) {
            _df[id]++;
            _postings[id].add(n);
          }
          _verses.add(_Verse(b, c + 1, v + 1, ids));
        }
      }
    }
    final total = _verses.length;
    _idf = [for (final d in _df) math.log(total / d)];
    _unknownWeight = 3.0;
    _commonCut = (total * 0.02).round();
  }

  int get verseCount => _verses.length;

  String _label(_Verse v) =>
      '${singularBook(bible.books[v.book])} ${v.chapter}:${v.verse}';

  /// The verses [words] most resemble.
  MatchResult match(List<String> words, {int keep = 5}) {
    final q = <int>[]; // vocabulary id, or -1 for a word the KJV never uses
    final qw = <double>[];
    for (final w in words) {
      final id = _vocab[_canon(w)];
      q.add(id ?? -1);
      qw.add(id == null ? _unknownWeight : _idf[id]);
    }
    if (q.where((e) => e >= 0).length < 3) return const MatchResult([], null);
    // Candidate verses: those sharing rare words with the query.
    final score = <int, double>{};
    for (final id in q.toSet()) {
      if (id < 0 || _df[id] > _commonCut) continue;
      for (final v in _postings[id]) {
        score.update(v, (s) => s + _idf[id], ifAbsent: () => _idf[id]);
      }
    }
    if (score.isEmpty) return const MatchResult([], null);
    final cands = score.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final matches = <VerseMatch>[];
    final heardWeight = qw.fold<double>(0, (a, b) => a + b);
    for (final e in cands.take(40)) {
      final m = _align(q, qw, _verses[e.key], heardWeight);
      if (m != null) matches.add(m);
    }
    matches.sort((a, b) => b.rank.compareTo(a.rank));
    final top = matches.take(keep).toList();
    VerseMatch? proposal;
    if (top.isNotEmpty) {
      final a = top.first;
      final b = top.length > 1 ? top[1].rank : 0.0;
      if (a.evidence >= minEvidence &&
          a.score >= minScore &&
          a.coverage >= minCoverage &&
          a.rank >= lead * b) {
        proposal = a;
      }
    }
    return MatchResult(top, proposal);
  }

  /// Weighted longest common subsequence of the query and the verse, scored
  /// over the stretch of each that the match covers.
  VerseMatch? _align(
    List<int> q,
    List<double> qw,
    _Verse v,
    double heardWeight,
  ) {
    final n = q.length, m = v.words.length;
    // dp[i][j]: best matched weight using q[0..i) and v[0..j).
    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        var best = math.max(dp[i - 1][j], dp[i][j - 1]);
        if (q[i - 1] >= 0 && q[i - 1] == v.words[j - 1]) {
          best = math.max(best, dp[i - 1][j - 1] + qw[i - 1]);
        }
        dp[i][j] = best;
      }
    }
    final matched = dp[n][m];
    if (matched <= 0) return null;
    // Walk back to find the first and last matched positions and the
    // weight of the words the match skipped in between.
    // End at the earliest place the full match is reached, so words that
    // merely repeat later in the verse ("dedicated it ... dedicate it")
    // do not stretch the span.
    var j = 1;
    while (j < m && dp[n][j] != matched) {
      j++;
    }
    var i = 1;
    while (i < n && dp[i][j] != matched) {
      i++;
    }
    var lastQ = -1, lastV = -1, firstQ = n, firstV = m;
    while (i > 0 && j > 0) {
      if (q[i - 1] >= 0 &&
          q[i - 1] == v.words[j - 1] &&
          dp[i][j] == dp[i - 1][j - 1] + qw[i - 1]) {
        if (lastQ < 0) {
          lastQ = i - 1;
          lastV = j - 1;
        }
        firstQ = i - 1;
        firstV = j - 1;
        i--;
        j--;
      } else if (dp[i - 1][j] >= dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    if (lastQ < 0) return null;
    var skippedQ = 0.0;
    for (var k = firstQ; k <= lastQ; k++) {
      skippedQ += qw[k];
    }
    skippedQ -= matched;
    var skippedV = 0.0;
    for (var k = firstV; k <= lastV; k++) {
      final id = v.words[k];
      skippedV += _idf[id];
    }
    skippedV -= matched;
    if (skippedQ < 0) skippedQ = 0;
    if (skippedV < 0) skippedV = 0;
    final fit = matched / (matched + skippedQ + skippedV);
    return VerseMatch(
      v.book,
      v.chapter,
      v.verse,
      _label(v),
      fit,
      matched,
      matched / heardWeight,
    );
  }
}

class _Verse {
  final int book, chapter, verse;
  final List<int> words;
  const _Verse(this.book, this.chapter, this.verse, this.words);
}

/// A quoted verse the listener thinks it heard.
class QuoteCandidate {
  final VerseMatch match;
  final String heardAs;
  const QuoteCandidate(this.match, this.heardAs);
  @override
  String toString() => '${match.label} "$heardAs"';
}

/// Feeds a [VerseMatcher] a rolling window of recognised words and reports
/// each quoted verse once.
class QuoteSpotter {
  final VerseMatcher matcher;

  /// The newest words to match against.
  final int windowWords;

  /// Fewer words than this is too little to go on.
  final int minWords;
  final Duration dedupeWindow;

  final List<String> _committed = [];
  final Map<String, DateTime> _seen = {};

  QuoteSpotter(
    this.matcher, {
    this.windowWords = 24,
    this.minWords = 6,
    this.dedupeWindow = const Duration(seconds: 60),
  });

  void reset() {
    _committed.clear();
    _seen.clear();
  }

  /// A partial or final transcript. Returns a candidate the first time a
  /// verse is proposed within [dedupeWindow].
  QuoteCandidate? hear(String text, {bool isFinal = false, DateTime? at}) {
    final now = at ?? DateTime.now();
    final words = quoteWords(text);
    final all = [..._committed, ...words];
    if (isFinal) {
      _committed.addAll(words);
      if (_committed.length > windowWords * 2) {
        _committed.removeRange(0, _committed.length - windowWords * 2);
      }
    }
    if (all.length < minWords) return null;
    final window = all.length > windowWords
        ? all.sublist(all.length - windowWords)
        : all;
    final r = matcher.match(window);
    final p = r.proposal;
    if (p == null) return null;
    final key = p.label;
    final seen = _seen[key];
    if (seen != null && now.difference(seen) <= dedupeWindow) return null;
    _seen[key] = now;
    return QuoteCandidate(p, window.join(' '));
  }
}
