import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/home_widgets.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

/// One prepared passage in the Ready tray.
class ReadyPassage {
  /// Its place in the tray; the same through extending it.
  final int number;

  /// How many times it has been extended, so a screen that was showing it
  /// sees the words changed.
  final int revision;

  /// The book as the Bible file names it ("Psalms"), and the reference as
  /// it is shown ("Psalm 23:1-3").
  final String book, reference;

  /// The translation's code.
  final String version;
  final List<LyricVerse> verses;

  /// Where it came from: `search`, or `listening` for a suggestion made by
  /// the verse listener.
  final String source;

  /// What was heard, for a suggestion made from speech: "for God so loved
  /// the world".
  final String? heardAs;

  /// Whether it has been saved to the Library as it is now.
  final bool saved;
  const ReadyPassage({
    required this.number,
    required this.book,
    required this.reference,
    required this.version,
    required this.verses,
    this.revision = 0,
    this.source = 'search',
    this.heardAs,
    this.saved = false,
  });

  /// What the screens are given: a Bible verses item that is not in the
  /// Library, with the same slides as one that is.
  LyricItem get item => LyricItem(
    id: 'ready-$number-$revision',
    kind: 'scripture',
    title: reference,
    version: version,
    verses: verses,
  );

  /// The first words, for the tray's row.
  String get preview => verses.map((v) => v.text).join(' ');

  ReadyPassage copyWith({
    String? reference,
    List<LyricVerse>? verses,
    bool? saved,
    String? source,
    String? heardAs,
    bool extended = false,
  }) => ReadyPassage(
    number: number,
    revision: extended ? revision + 1 : revision,
    book: book,
    reference: reference ?? this.reference,
    version: version,
    verses: verses ?? this.verses,
    source: source ?? this.source,
    heardAs: heardAs ?? this.heardAs,
    saved: saved ?? this.saved,
  );
}

/// The Ready tray: passages prepared to go on the screens, one tap each.
/// Kept for the session with the app's controller, so it survives leaving
/// and coming back to the Slides page, and is not saved: a restart starts
/// with an empty tray.
///
/// Anything that finds passages adds them with [addReady]: today the Bible
/// search (`source: 'search'`), later the verse listener
/// (`source: 'listening'`, with what it [heardAs]).
class ReadyTray extends ChangeNotifier {
  static final _trays = Expando<ReadyTray>('ReadyTray');

  /// The tray of [app], made on first use.
  static ReadyTray of(AppController app) => _trays[app] ??= ReadyTray();

  /// How the Bible is read to extend a passage; tests replace it.
  static Future<Bible> Function(String code) bibleLoader = BibleLibrary.load;

  /// The most passages kept; adding more drops the oldest.
  static const limit = 12;

  final _items = <ReadyPassage>[];
  var _counter = 0;
  List<ReadyPassage> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  ReadyPassage? byNumber(int number) {
    for (final p in _items) {
      if (p.number == number) return p;
    }
    return null;
  }

  /// Puts [reading] in the tray, newest first; a passage already there is
  /// moved to the front instead of added twice. Returns the tray's entry.
  ReadyPassage addReady(
    BibleReading reading, {
    String source = 'search',
    String? heardAs,
  }) {
    for (final p in _items) {
      if (p.reference == reading.reference && p.version == reading.version) {
        _items
          ..remove(p)
          ..insert(0, p.copyWith(source: source, heardAs: heardAs));
        notifyListeners();
        return _items.first;
      }
    }
    final r = parseBibleReference(reading.reference);
    final entry = ReadyPassage(
      number: ++_counter,
      book: r.book,
      reference: reading.reference,
      version: reading.version,
      verses: reading.verses,
      source: source,
      heardAs: heardAs,
    );
    _items.insert(0, entry);
    while (_items.length > limit) {
      _items.removeLast();
    }
    notifyListeners();
    return entry;
  }

  void remove(int number) {
    _items.removeWhere((p) => p.number == number);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  void _replace(ReadyPassage next) {
    final i = _items.indexWhere((p) => p.number == next.number);
    if (i >= 0) _items[i] = next;
    notifyListeners();
  }

  /// Puts the passage's first slide on the screens, through the same
  /// show method a library slide uses.
  void send(AppController app, int number) {
    final p = byNumber(number);
    if (p == null) return;
    app.lyrics.selectedId = null;
    app.lyrics.showTransient(p.item, 0);
  }

  /// Adds the verse after the last one (the next chapter's first at a
  /// chapter's end), or with [wholeChapter] fills the chapter (or every
  /// chapter) the passage touches. Returns what to tell the operator
  /// when it cannot, else null. A passage showing on the screens keeps
  /// its slide and gains the words.
  Future<String?> extend(
    AppController app,
    int number, {
    bool wholeChapter = false,
  }) async {
    final p = byNumber(number);
    if (p == null) return null;
    final Bible bible;
    try {
      bible = await bibleLoader(p.version);
    } on RuleError catch (e) {
      return e.message;
    }
    final b = bible.books.indexOf(p.book);
    if (b < 0) return 'The ${p.version} does not have ${p.book}.';
    final chapters = bible.text[b];
    final first = p.verses.first, last = p.verses.last;
    var endChapter = last.chapter, endVerse = last.verse;
    var startChapter = first.chapter, startVerse = first.verse;
    String? whole;
    if (wholeChapter) {
      startVerse = 1;
      endVerse = chapters[endChapter - 1].length;
      if (startVerse == first.verse &&
          endVerse == last.verse &&
          p.verses.length ==
              _count(
                chapters,
                startChapter,
                startVerse,
                endChapter,
                endVerse,
              )) {
        return 'That is already the whole chapter.';
      }
      whole = startChapter == endChapter
          ? '${singularBook(p.book)} $startChapter'
          : '${singularBook(p.book)} $startChapter-$endChapter';
    } else if (endVerse < chapters[endChapter - 1].length) {
      endVerse++;
    } else if (endChapter < chapters.length) {
      endChapter++;
      endVerse = 1;
    } else {
      return 'That is the end of ${singularBook(p.book)}.';
    }
    final BibleReading reading;
    try {
      reading = bible.read(
        whole ??
            referenceText(
              BibleReference(
                p.book,
                startChapter,
                verse: startVerse,
                endChapter: endChapter == startChapter ? null : endChapter,
                endVerse: endVerse == startVerse && endChapter == startChapter
                    ? null
                    : endVerse,
              ),
            ),
      );
    } on RuleError catch (e) {
      return e.message;
    }
    final current = byNumber(number);
    if (current == null) return null;
    final next = current.copyWith(
      reference: reading.reference,
      verses: reading.verses,
      saved: false,
      extended: true,
    );
    final showing = app.lyrics.item?.id == current.item.id;
    final at = app.lyrics.index ?? 0;
    _replace(next);
    if (showing) app.lyrics.showTransient(next.item, at);
    return null;
  }

  static int _count(
    List<List<String>> chapters,
    int c1,
    int v1,
    int c2,
    int v2,
  ) {
    var n = 0;
    for (var c = c1; c <= c2; c++) {
      final from = c == c1 ? v1 : 1;
      final to = c == c2 ? v2 : chapters[c - 1].length;
      n += to - from + 1;
    }
    return n;
  }

  /// Saves the passage to the Library as Bible verses, once: a reading
  /// already there is not saved again. Returns what to tell the operator.
  Future<String> saveToLibrary(AppController app, int number) async {
    final p = byNumber(number);
    if (p == null) return 'That passage is no longer in Ready.';
    final already = app.state.lyrics.items.any(
      (i) =>
          i.kind == 'scripture' &&
          i.title == p.reference &&
          i.version == p.version,
    );
    if (already) {
      _replace(p.copyWith(saved: true));
      return '${p.reference} is already in the Library.';
    }
    final saved = await app.lyrics.save(
      LyricItem(
        id: newLyricId(),
        kind: 'scripture',
        title: p.reference,
        version: p.version,
        verses: p.verses,
      ),
    );
    if (!saved) return app.error ?? 'It could not be saved.';
    final now = byNumber(number);
    if (now != null) _replace(now.copyWith(saved: true));
    return 'Saved ${p.reference} to the Library.';
  }
}

/// The Ready tray on the Slides page: each passage with Send, a way to
/// take in the next verse or the whole chapter, Save to Library and
/// remove.
class ReadyTrayPanel extends StatelessWidget {
  final AppController controller;

  /// Whether the controls are live (not locked, not paired away).
  final bool enabled;

  /// Draws the heading and the rows without a card around them, for use
  /// inside another card.
  final bool bare;
  const ReadyTrayPanel({
    super.key,
    required this.controller,
    this.enabled = true,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final tray = ReadyTray.of(controller);
    return ListenableBuilder(
      listenable: Listenable.merge([tray, controller]),
      builder: (context, _) {
        final colors = appColors(context);
        final body = Column(
          key: const ValueKey('ready-tray'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tray.isEmpty ? 'READY' : 'READY · ${tray.items.length}',
                      style: sectionLabelStyle(context),
                    ),
                  ),
                  if (tray.items.length > 1)
                    TextButton(
                      key: const ValueKey('ready-clear-all'),
                      onPressed: tray.clear,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
            ),
            if (tray.isEmpty)
              Text(
                'Passages you find wait here, ready to send.',
                key: const ValueKey('ready-empty'),
                style: TextStyle(color: colors.muted, fontSize: 13),
              )
            else
              for (final p in tray.items)
                ReadyRow(
                  key: ValueKey('ready-${p.number}'),
                  tray: tray,
                  passage: p,
                  controller: controller,
                  enabled: enabled,
                ),
          ],
        );
        return bare ? body : AppPanel(child: body);
      },
    );
  }
}

/// One passage in the tray.
class ReadyRow extends StatelessWidget {
  final ReadyTray tray;
  final ReadyPassage passage;
  final AppController controller;
  final bool enabled;
  const ReadyRow({
    super.key,
    required this.tray,
    required this.passage,
    required this.controller,
    required this.enabled,
  });

  Future<void> _extend(BuildContext context, {bool whole = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final problem = await tray.extend(
      controller,
      passage.number,
      wholeChapter: whole,
    );
    if (problem != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await tray.saveToLibrary(controller, passage.number);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final l = controller.lyrics;
    final live = l.item?.id == passage.item.id && l.slide != null;
    final from = switch (passage.source) {
      'search' => null,
      'listening' => 'Suggested while listening',
      final other => 'From $other',
    };
    final small = TextStyle(fontSize: 12, color: colors.muted);
    final compact = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
      decoration: BoxDecoration(
        color: live ? colors.accent.withValues(alpha: .14) : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: live ? colors.accent : colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  passage.reference,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton(
                key: ValueKey('ready-send-${passage.number}'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: enabled
                    ? () => tray.send(controller, passage.number)
                    : null,
                child: const Text('Send'),
              ),
              IconButton(
                key: ValueKey('ready-remove-${passage.number}'),
                tooltip: 'Remove from Ready',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => tray.remove(passage.number),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              passage.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.text, fontSize: 13),
            ),
          ),
          if (passage.heardAs != null || from != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text(
                [
                  ?from,
                  if (passage.heardAs != null) 'heard as “${passage.heardAs}”',
                ].join(' · '),
                key: ValueKey('ready-source-${passage.number}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          Wrap(
            children: [
              TextButton(
                key: ValueKey('ready-next-${passage.number}'),
                style: compact,
                onPressed: enabled ? () => _extend(context) : null,
                child: const Text('+ next verse'),
              ),
              TextButton(
                key: ValueKey('ready-chapter-${passage.number}'),
                style: compact,
                onPressed: enabled ? () => _extend(context, whole: true) : null,
                child: const Text('Whole chapter'),
              ),
              TextButton(
                key: ValueKey('ready-save-${passage.number}'),
                style: compact,
                onPressed: enabled && !passage.saved
                    ? () => _save(context)
                    : null,
                child: Text(passage.saved ? 'In Library' : 'Save to Library'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
