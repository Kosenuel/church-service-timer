/// Song words, Bible verses and announcements for the screens: the saved
/// library, how words become slides, and the look of the slides. See
/// docs/LYRICS-DESIGN.md.
library;

import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';

/// The kinds of thing the library keeps.
const lyricKinds = {'song', 'scripture', 'announcement'};

/// The most items the library keeps, and the longest words one may have,
/// so the saved state stays quick to save on every change.
const lyricLibraryLimit = 300;
const lyricWordsLimit = 12000;
const lyricTitleLimit = 80;

/// What one slide shows.
class LyricSlide {
  /// Its name on the operator's slide card: Verse 1, Chorus, Slide 3,
  /// John 3:16-17. Never shown on the screens.
  final String label;

  /// The words, one typed line to a line.
  final String text;

  /// Under the words of a Bible slide: "John 3:16 · KJV".
  final String reference;

  /// An announcement's title and its date, time or place line.
  final String title, detail;
  const LyricSlide({
    required this.label,
    this.text = '',
    this.reference = '',
    this.title = '',
    this.detail = '',
  });

  Json toJson() => {
    'label': label,
    'text': text,
    if (reference.isNotEmpty) 'reference': reference,
    if (title.isNotEmpty) 'title': title,
    if (detail.isNotEmpty) 'detail': detail,
  };

  /// What the operator's search and the slide cards read.
  String get plain =>
      [title, text, detail].where((s) => s.isNotEmpty).join('\n');
}

/// One verse of a looked-up reading: chapter, verse and its words.
class LyricVerse {
  final int chapter, verse;
  final String text;
  const LyricVerse(this.chapter, this.verse, this.text);
  Json toJson() => {'c': chapter, 'v': verse, 't': text};
  factory LyricVerse.fromJson(Json j) {
    final c = j['c'], v = j['v'], t = j['t'];
    require(
      c is int && v is int && c > 0 && v > 0 && t is String && t.length <= 2000,
      'A saved Bible verse is not valid.',
    );
    return LyricVerse(c, v, t);
  }
}

/// A song, a set of Bible verses or an announcement in the library.
class LyricItem {
  final String id, kind, title;

  /// A song's words as typed, pasted verse text, or an announcement's body.
  final String words;

  /// For songs: 0 keeps each block as typed, 2 or 4 splits blocks into
  /// slides of that many lines.
  final int linesPerSlide;

  /// A song's optional credit line, shown in the list only.
  final String by;

  /// For verses: the translation, `KJV` for looked-up verses, or what the
  /// operator typed for pasted text.
  final String version;

  /// For looked-up verses: the verses themselves, copied in so a saved
  /// reading never depends on a Bible file being there later.
  final List<LyricVerse> verses;

  /// An announcement's date, time or place line.
  final String detail;

  /// When it was last saved (wall ms). When it was last on the screens
  /// is ordering state, kept by [LyricsLibrary.lastUsed], not here.
  final int updated;

  LyricItem({
    required this.id,
    required this.kind,
    required this.title,
    this.words = '',
    this.linesPerSlide = 0,
    this.by = '',
    this.version = '',
    this.verses = const [],
    this.detail = '',
    this.updated = 0,
  });

  void validate() {
    require(
      lyricKinds.contains(kind),
      'Choose a song, verses or an announcement.',
    );
    require(id.isNotEmpty && id.length <= 40, 'A saved item has no id.');
    require(title.trim().isNotEmpty, switch (kind) {
      'scripture' => 'Enter the reference, such as John 3:16.',
      'announcement' => 'Enter a title.',
      _ => 'Enter the song title.',
    });
    require(
      title.runes.length <= lyricTitleLimit && !title.contains('\n'),
      'Keep the title to one line of $lyricTitleLimit characters.',
    );
    require(
      words.length <= lyricWordsLimit,
      'Keep the words within $lyricWordsLimit characters.',
    );
    require(
      {0, 2, 4}.contains(linesPerSlide),
      'Choose As typed, 2 or 4 lines.',
    );
    require(
      by.runes.length <= 80 && !by.contains('\n'),
      'Keep the credit to one short line.',
    );
    require(
      version.runes.length <= 24 && !version.contains('\n'),
      'Keep the translation name short.',
    );
    require(
      detail.runes.length <= 120 && !detail.contains('\n'),
      'Keep the date, time or place to one line.',
    );
    require(verses.length <= 200, 'Choose at most 200 verses at a time.');
    require(slides.isNotEmpty, switch (kind) {
      'scripture' => 'Find the verses or paste their words.',
      'announcement' => 'Enter the title or the words.',
      _ => 'Type or paste the words.',
    });
    require(slides.length <= 200, 'Keep it to at most 200 slides.');
  }

  /// The slides it makes, worked out each time, never saved.
  late final List<LyricSlide> slides = switch (kind) {
    'scripture' => scriptureSlides(this),
    'announcement' => [
      if (title.trim().isNotEmpty || words.trim().isNotEmpty)
        LyricSlide(
          label: 'Announcement',
          title: title.trim(),
          text: cleanLyricText(words).trim(),
          detail: detail.trim(),
        ),
    ],
    _ => parseSongSlides(words, linesPerSlide: linesPerSlide),
  };

  /// The line under its title in the list: "John Newton · 4 slides".
  String get summary {
    final count = slides.length == 1 ? '1 slide' : '${slides.length} slides';
    return switch (kind) {
      'scripture' => '${version.isEmpty ? 'Bible verses' : version} · $count',
      'announcement' => detail.isNotEmpty ? detail : 'Announcement',
      _ => by.isEmpty ? count : '$by · $count',
    };
  }

  /// Whether a search for [query] finds it, by its title or its words.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        by.toLowerCase().contains(q) ||
        words.toLowerCase().contains(q) ||
        verses.any((v) => v.text.toLowerCase().contains(q));
  }

  LyricItem copyWith({
    String? title,
    String? words,
    int? linesPerSlide,
    String? by,
    String? version,
    List<LyricVerse>? verses,
    String? detail,
    int? updated,
  }) => LyricItem(
    id: id,
    kind: kind,
    title: title ?? this.title,
    words: words ?? this.words,
    linesPerSlide: linesPerSlide ?? this.linesPerSlide,
    by: by ?? this.by,
    version: version ?? this.version,
    verses: verses ?? this.verses,
    detail: detail ?? this.detail,
    updated: updated ?? this.updated,
  );

  Json toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    if (words.isNotEmpty) 'words': words,
    if (linesPerSlide != 0) 'linesPerSlide': linesPerSlide,
    if (by.isNotEmpty) 'by': by,
    if (version.isNotEmpty) 'version': version,
    if (verses.isNotEmpty) 'verses': [for (final v in verses) v.toJson()],
    if (detail.isNotEmpty) 'detail': detail,
    'updated': updated,
  };

  factory LyricItem.fromJson(Json j) {
    final item = LyricItem(
      id: j['id'] as String,
      kind: j['kind'] as String,
      title: j['title'] as String,
      words: j['words'] as String? ?? '',
      linesPerSlide: j['linesPerSlide'] as int? ?? 0,
      by: j['by'] as String? ?? '',
      version: j['version'] as String? ?? '',
      verses: [
        for (final v in j['verses'] as List? ?? const [])
          LyricVerse.fromJson(Map<String, dynamic>.from(v as Map)),
      ],
      detail: j['detail'] as String? ?? '',
      updated: j['updated'] as int? ?? 0,
    );
    item.validate();
    return item;
  }
}

/// A new random id for a library item.
String newLyricId() {
  final r = math.Random.secure();
  return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
}

// ---- Words to slides -----------------------------------------------------

/// Lines as the operator meant them: one kind of line ending, ordinary
/// spaces, no invisible characters, each line trimmed.
String cleanLyricText(String raw) => raw
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp('[​‌‍⁠﻿]'), '')
    .replaceAll(RegExp('[\t  -   　]'), ' ')
    .split('\n')
    .map((l) => l.replaceAll(RegExp(' {2,}'), ' ').trim())
    .join('\n');

final _heading = RegExp(
  r'^[\[(]?\s*(verse|chorus|refrain|bridge|pre-?\s?chorus|intro|outro|tag|ending)\b\s*(\d{0,2})\s*[\])]?\s*[:.]?$',
  caseSensitive: false,
);

/// A heading line's name ("Verse 1", "Chorus", "Pre-chorus"), or null
/// when [line] is words to show.
String? lyricHeading(String line) {
  final m = _heading.firstMatch(line.trim());
  if (m == null) return null;
  var word = m.group(1)!.toLowerCase().replaceAll(RegExp(r'\s'), '');
  if (word.startsWith('pre')) word = 'pre-chorus';
  final name = '${word[0].toUpperCase()}${word.substring(1)}';
  final number = m.group(2)!;
  return number.isEmpty ? name : '$name $number';
}

/// The slides a song's [words] make. A blank line starts a new slide; a
/// heading line (Verse 1, Chorus, Bridge…) names the slide and is not
/// shown; with [linesPerSlide] 2 or 4 a block is split into slides of
/// that many lines, each keeping the block's name.
List<LyricSlide> parseSongSlides(String words, {int linesPerSlide = 0}) {
  final slides = <LyricSlide>[];
  String? pending;
  var block = <String>[];
  void flush() {
    if (block.isEmpty) return;
    final size = linesPerSlide > 0 ? linesPerSlide : block.length;
    for (var i = 0; i < block.length; i += size) {
      final lines = block.sublist(i, math.min(block.length, i + size));
      slides.add(
        LyricSlide(
          label: pending ?? 'Slide ${slides.length + 1}',
          text: lines.join('\n'),
        ),
      );
    }
    block = [];
    pending = null;
  }

  for (final line in cleanLyricText(words).split('\n')) {
    if (line.isEmpty) {
      flush();
      continue;
    }
    final heading = lyricHeading(line);
    if (heading != null) {
      flush();
      pending = heading;
      continue;
    }
    block.add(line);
  }
  flush();
  return slides;
}

// ---- Bible verses to slides ------------------------------------------------

/// About how many characters of verse go on one slide: large enough to
/// read from the back of a room on a 16:9 screen.
const scriptureSlideChars = 280;

const _superscripts = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// A verse number as small raised digits: ¹⁶.
String superscriptNumber(int n) =>
    n.toString().split('').map((d) => _superscripts[int.parse(d)]).join();

/// "John 3:16", "John 3:16-18" or "John 3:16–4:2" for a run of verses.
String verseRange(String book, List<LyricVerse> verses) {
  if (verses.isEmpty) return book;
  final a = verses.first, b = verses.last;
  if (a.chapter == b.chapter && a.verse == b.verse) {
    return '$book ${a.chapter}:${a.verse}';
  }
  if (a.chapter == b.chapter) return '$book ${a.chapter}:${a.verse}-${b.verse}';
  return '$book ${a.chapter}:${a.verse}–${b.chapter}:${b.verse}';
}

/// Splits one very long verse or paragraph at sentence or clause ends
/// into parts of about [limit] characters.
List<String> splitLongText(String text, int limit) {
  if (text.length <= limit * 1.4) return [text];
  final pieces = RegExp(
    r'[^.;:!?,]+[.;:!?,]*\s*',
  ).allMatches(text).map((m) => m[0]!);
  final parts = <String>[];
  var current = '';
  for (final piece in pieces) {
    if (current.isNotEmpty && current.length + piece.length > limit) {
      parts.add(current.trim());
      current = '';
    }
    current += piece;
  }
  if (current.trim().isNotEmpty) parts.add(current.trim());
  return parts;
}

/// The slides a set of verses makes: looked-up verses grouped by length,
/// or pasted text split at blank lines and by length.
List<LyricSlide> scriptureSlides(LyricItem item) {
  final book = item.title.trim();
  final suffix = item.version.isEmpty ? '' : ' · ${item.version}';
  if (item.verses.isEmpty) {
    // Pasted text, from any translation, with its own reference line.
    final parts = [
      for (final para in cleanLyricText(item.words).split(RegExp(r'\n\s*\n')))
        if (para.trim().isNotEmpty)
          ...splitLongText(
            para.trim().replaceAll('\n', ' '),
            scriptureSlideChars,
          ),
    ];
    return [
      for (var i = 0; i < parts.length; i++)
        LyricSlide(
          label: parts.length == 1 ? book : '$book (${i + 1})',
          text: parts[i],
          reference: '$book$suffix',
        ),
    ];
  }
  // The book's name, without the chapter and verses the title carries.
  final name = bookOfReference(book);
  final groups = <List<LyricVerse>>[];
  var current = <LyricVerse>[];
  var length = 0;
  for (final v in item.verses) {
    if (current.isNotEmpty &&
        (length + v.text.length > scriptureSlideChars ||
            v.chapter != current.last.chapter)) {
      groups.add(current);
      current = [];
      length = 0;
    }
    current.add(v);
    length += v.text.length + 4;
  }
  if (current.isNotEmpty) groups.add(current);
  final slides = <LyricSlide>[];
  for (final group in groups) {
    final range = verseRange(name, group);
    if (group.length == 1) {
      final parts = splitLongText(group.single.text, scriptureSlideChars);
      for (var i = 0; i < parts.length; i++) {
        slides.add(
          LyricSlide(
            label: parts.length == 1 ? range : '$range (${i + 1})',
            text: parts[i],
            reference: '$range$suffix',
          ),
        );
      }
      continue;
    }
    slides.add(
      LyricSlide(
        label: range,
        text: [
          for (final v in group) '${superscriptNumber(v.verse)} ${v.text}',
        ].join(' '),
        reference: '$range$suffix',
      ),
    );
  }
  return slides;
}

/// "John" from "John 3:16-18"; "1 Corinthians" from "1 Corinthians 13".
String bookOfReference(String reference) => reference
    .replaceFirst(RegExp(r'\s+\d+([:.]\d+)?([-–]\d+([:.]\d+)?)?$'), '')
    .trim();

// ---- The look of the slides -------------------------------------------------

/// The drawn backgrounds, in the order the picker shows them, with the
/// ink that reads on each: light words on dark, dark words on Linen.
const lyricDrawnBackgrounds = <String, String>{
  'black': 'Black',
  'midnight': 'Midnight',
  'aurora': 'Aurora',
  'sunrise': 'Sunrise',
  'mountain_dusk': 'Mountain dusk',
  'starry_night': 'Starry night',
  'candlelight': 'Candlelight',
  'ocean': 'Ocean',
  'forest_mist': 'Forest mist',
  'stained_glass': 'Stained glass',
  'royal_velvet': 'Royal velvet',
  'linen': 'Linen',
};

/// Backgrounds whose words are dark, and which are never dimmed.
const lyricDarkInkBackgrounds = {'linen'};

/// What a paired stage screen shows in place of Your picture, which is
/// not sent to them in phase 1.
const lyricPictureStandIn = 'midnight';

/// Whether [id] names a background this version can draw: a drawn one,
/// `photo:<id>` or `custom:<name>`.
bool lyricBackgroundKnown(String id, Set<String> photos) =>
    lyricDrawnBackgrounds.containsKey(id) ||
    (id.startsWith('photo:') && photos.contains(id.substring(6))) ||
    (id.startsWith('custom:') && id.length > 7);

/// How the slides look and where they go. Saved, and in backups.
class LyricsLook {
  final String background, size, align, motion;
  final int dim;
  final bool chip, toSecond, toWeb, toStage;
  const LyricsLook({
    this.background = 'mountain_dusk',
    this.dim = 70,
    this.size = 'm',
    this.align = 'center',
    this.chip = true,
    this.motion = 'gentle',
    this.toSecond = true,
    this.toWeb = true,
    this.toStage = false,
  });

  bool get darkInk => lyricDarkInkBackgrounds.contains(background);
  bool get moving => motion == 'gentle';

  LyricsLook copyWith({
    String? background,
    int? dim,
    String? size,
    String? align,
    bool? chip,
    String? motion,
    bool? toSecond,
    bool? toWeb,
    bool? toStage,
  }) => LyricsLook(
    background: background ?? this.background,
    dim: dim ?? this.dim,
    size: size ?? this.size,
    align: align ?? this.align,
    chip: chip ?? this.chip,
    motion: motion ?? this.motion,
    toSecond: toSecond ?? this.toSecond,
    toWeb: toWeb ?? this.toWeb,
    toStage: toStage ?? this.toStage,
  );

  Json toJson() => {
    'background': background,
    'dim': dim,
    'size': size,
    'align': align,
    'chip': chip,
    'motion': motion,
    'second': toSecond,
    'web': toWeb,
    'stage': toStage,
  };

  /// Reads a saved look; anything missing or unknown is the default.
  factory LyricsLook.fromJson(Json? j) {
    const d = LyricsLook();
    if (j == null) return d;
    T pick<T>(String key, T fallback, bool Function(T v) ok) {
      final v = j[key];
      return v is T && ok(v) ? v : fallback;
    }

    return LyricsLook(
      background: pick<String>(
        'background',
        d.background,
        (v) =>
            v.length <= 80 &&
            (lyricDrawnBackgrounds.containsKey(v) ||
                v.startsWith('photo:') ||
                v.startsWith('custom:')),
      ),
      dim: pick<int>('dim', d.dim, (v) => v >= 0 && v <= 90),
      size: pick<String>(
        'size',
        d.size,
        (v) => const {'s', 'm', 'l'}.contains(v),
      ),
      align: pick<String>(
        'align',
        d.align,
        (v) => const {'center', 'left'}.contains(v),
      ),
      chip: pick<bool>('chip', d.chip, (_) => true),
      motion: pick<String>(
        'motion',
        d.motion,
        (v) => const {'gentle', 'still'}.contains(v),
      ),
      toSecond: pick<bool>('second', d.toSecond, (_) => true),
      toWeb: pick<bool>('web', d.toWeb, (_) => true),
      toStage: pick<bool>('stage', d.toStage, (_) => true),
    );
  }
}

/// The library and the look, saved as `lyrics` in the app's state.
///
/// Items hold only what each thing is, under an id that never changes,
/// so a program segment can later refer to items by id. Ordering is
/// kept apart, in [lastUsed]; what is selected or showing is not saved.
class LyricsLibrary {
  final List<LyricItem> items;
  final LyricsLook look;

  /// Item id to when it was last put on the screens (wall ms).
  final Map<String, int> lastUsed;
  const LyricsLibrary({
    this.items = const [],
    this.look = const LyricsLook(),
    this.lastUsed = const {},
  });

  bool get isEmpty => items.isEmpty;

  /// Stored songs as the list shows them: most recently used first, then
  /// most recently saved.
  List<LyricItem> get ordered => [...items]
    ..sort((a, b) {
      final used = (lastUsed[b.id] ?? 0).compareTo(lastUsed[a.id] ?? 0);
      return used != 0 ? used : b.updated.compareTo(a.updated);
    });

  LyricItem? byId(String? id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  LyricsLibrary _with({
    List<LyricItem>? items,
    LyricsLook? look,
    Map<String, int>? lastUsed,
  }) => LyricsLibrary(
    items: items ?? this.items,
    look: look ?? this.look,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  /// With [item] saved: replacing the one with its id, or added.
  LyricsLibrary saved(LyricItem item) {
    item.validate();
    final at = items.indexWhere((i) => i.id == item.id);
    require(
      at >= 0 || items.length < lyricLibraryLimit,
      'The library can hold $lyricLibraryLimit items. Delete some first.',
    );
    return _with(items: at < 0 ? [...items, item] : ([...items]..[at] = item));
  }

  LyricsLibrary without(String id) => _with(
    items: [
      for (final i in items)
        if (i.id != id) i,
    ],
    lastUsed: {...lastUsed}..remove(id),
  );

  LyricsLibrary withLook(LyricsLook next) => _with(look: next);

  LyricsLibrary usedAt(String id, int wall) =>
      _with(lastUsed: {...lastUsed, id: wall});

  Json toJson() => {
    'items': [for (final i in items) i.toJson()],
    'look': look.toJson(),
    if (lastUsed.isNotEmpty) 'lastUsed': lastUsed,
  };

  /// The look for a backup: Your picture stays on this device, so a
  /// restored look that named it shows Midnight.
  Json toBackupJson() {
    final j = toJson();
    if (look.background.startsWith('custom:')) {
      j['look'] = look.copyWith(background: lyricPictureStandIn).toJson();
    }
    return j;
  }

  /// Reads the saved library. Missing (saved data from before lyrics) is
  /// an empty library with the default look. An item that cannot be read
  /// is left out rather than losing the rest.
  factory LyricsLibrary.fromJson(Object? raw) {
    if (raw is! Map) return const LyricsLibrary();
    final j = Map<String, dynamic>.from(raw);
    final items = <LyricItem>[];
    final ids = <String>{};
    for (final e in j['items'] as List? ?? const []) {
      try {
        final item = LyricItem.fromJson(Map<String, dynamic>.from(e as Map));
        if (ids.add(item.id) && items.length < lyricLibraryLimit)
          items.add(item);
      } catch (_) {
        // Left out; the rest of the library still loads.
      }
    }
    final used = j['lastUsed'];
    return LyricsLibrary(
      items: items,
      look: LyricsLook.fromJson(
        j['look'] is Map ? Map<String, dynamic>.from(j['look'] as Map) : null,
      ),
      lastUsed: {
        if (used is Map)
          for (final e in used.entries)
            if (e.key is String && e.value is int && ids.contains(e.key))
              e.key as String: e.value as int,
      },
    );
  }
}
