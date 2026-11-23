/// Turns a written-out or spoken Bible reference into plain digits, so the
/// reference parser in `bible.dart` only has to read "john 3:16-18". Kept
/// apart because speech recognition will feed it later: it knows nothing
/// about which books exist.
library;

const _ones = <String, int>{
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
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

/// Words said before the reference that name nothing: "turn to", "open your
/// Bibles to", "the book of", "in".
final _leading = RegExp(
  r"^(?:(?:please|now|let us|lets|let's|turn|turning|go|flip|open|read|reading|with me|your bibles?|bible|to|in|from|the)\b\s*)+",
);

/// Words that say "from here to there" in a range.
const _rangeWords = {'to', 'through', 'thru', 'until', 'till', 'unto'};

/// "John chapter three verse sixteen" becomes "john 3 : 16" and
/// "first corinthians chapter thirteen verses four to seven" becomes
/// "first corinthians 13 : 4 - 7". Number words from zero to nine hundred
/// and ninety-nine are read ("one hundred and nineteen", "a hundred
/// nineteen", "twenty-three"), "chapter" and "the book of" and the other
/// filler are dropped, "verse", "vs" and "v" become a colon and
/// "to"/"through"/"until" become a dash. "and" between two numbers is kept
/// as "&", because only the parser knows whether the two are neighbours.
///
/// Digits, colons, dots, commas and dashes pass through, so input that is
/// already numeric comes back tidied: letters and digits are split apart
/// ("1cor13" is "1 cor 13"), spaces are collapsed and a chapter and verse
/// joined by a dot, a comma, a space or a "v" become "3:16".
String normaliseSpokenReference(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[–—−]'), '-');
  // "1st", "2nd" and "3rd" are words for the book's number: keep them whole.
  s = s
      .replaceAllMapped(
        RegExp(r'\b([123])\s*(?:st|nd|rd)\b'),
        (m) => const {'1': 'first', '2': 'second', '3': 'third'}[m[1]]!,
      )
      // "twenty-three": a dash between two words is a space.
      .replaceAllMapped(RegExp(r'(?<=[a-z])\s*-\s*(?=[a-z])'), (_) => ' ')
      // "Jn3:16", "1cor13", "john3v9".
      .replaceAllMapped(
        RegExp(r'(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])'),
        (_) => ' ',
      )
      .replaceAll(RegExp(r'\bbook of\b'), ' ')
      .replaceAll(RegExp(r'\bgospel (?:of|according to)\b'), ' ');
  s = s.replaceFirst(_leading, '').trim();
  final tokens = RegExp(
    r'[a-z]+|\d+|[^\sa-z\d]',
  ).allMatches(s).map((m) => m[0]!).toList();
  final out = <String>[];
  var i = 0;
  while (i < tokens.length) {
    final t = tokens[i];
    final number = _numberAt(tokens, i);
    if (number != null) {
      out.add('${number.$1}');
      i = number.$2;
      continue;
    }
    i++;
    switch (t) {
      case 'chapter' || 'chapters' || 'chap':
        break;
      case 'verse' || 'verses' || 'vs' || 'vss' || 'vv' || 'v' || 'colon':
        out.add(':');
      case 'and' || 'plus' || '&':
        out.add('&');
      case _ when _rangeWords.contains(t):
        out.add('-');
      default:
        out.add(t);
    }
  }
  var r = out.join(' ');
  r = r
      // "chapter three, verse sixteen" and "vs. 9".
      .replaceAll(RegExp(r'\s*[.,;]+\s*(?=:)|(?<=:)\s*[.,;]+'), '')
      .replaceAll(RegExp(r'\s*-\s*'), '-')
      .replaceAll(RegExp(r'\s*:\s*'), ':')
      .replaceAll(RegExp(r'\s*&\s*'), '&')
      // A dot or comma between two numbers is the chapter and verse.
      .replaceAll(RegExp(r'(?<=\d)\s*[.,]\s*(?=\d)'), ':')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return r;
}

/// The number the words at [i] say and where they end, or null.
(int, int)? _numberAt(List<String> t, int i) {
  final head = t[i];
  var j = i;
  int? lead;
  if (head == 'hundred') {
    lead = 1;
  } else if (head == 'a' && i + 1 < t.length && t[i + 1] == 'hundred') {
    lead = 1;
    j = i + 1;
  } else if (_ones.containsKey(head) &&
      (_ones[head]! >= 1 && _ones[head]! <= 9) &&
      i + 1 < t.length &&
      t[i + 1] == 'hundred') {
    lead = _ones[head];
    j = i + 1;
  }
  if (lead != null) {
    // t[j] is "hundred".
    var total = lead * 100;
    j++;
    if (j + 1 < t.length && t[j] == 'and' && _underHundred(t, j + 1) != null) {
      j++;
    }
    final rest = _underHundred(t, j);
    if (rest != null && rest.$1 > 0) {
      total += rest.$1;
      j = rest.$2;
    }
    return (total, j);
  }
  return _underHundred(t, i);
}

(int, int)? _underHundred(List<String> t, int i) {
  if (i >= t.length) return null;
  final word = t[i];
  final tens = _tens[word];
  if (tens != null) {
    if (i + 1 < t.length) {
      final one = _ones[t[i + 1]];
      if (one != null && one >= 1 && one <= 9) return (tens + one, i + 2);
    }
    return (tens, i + 1);
  }
  final one = _ones[word];
  return one == null ? null : (one, i + 1);
}
