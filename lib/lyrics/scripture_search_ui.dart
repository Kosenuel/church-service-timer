import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/ready_tray.dart';
import 'package:church_service_timer/lyrics/scripture_search.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The part of [text] to show in about [maxChars] letters, starting a little
/// before the first matched word so the match stays in view, with the
/// matched stretches moved to match.
({String text, List<(int, int)> spans}) excerptAround(
  String text,
  List<(int, int)> spans,
  int maxChars,
) {
  if (text.length <= maxChars) return (text: text, spans: spans);
  var start = 0;
  if (spans.isNotEmpty && spans.first.$2 > maxChars - 6) {
    start = spans.first.$1 - maxChars ~/ 4;
    if (start < 0) start = 0;
    // Begin at a word.
    final space = text.indexOf(' ', start);
    if (start > 0 && space >= 0 && space < spans.first.$1) start = space + 1;
  }
  final lead = start > 0 ? '… ' : '';
  final shifted = <(int, int)>[
    for (final s in spans)
      if (s.$2 > start)
        (
          s.$1 < start ? 0 : s.$1 - start + lead.length,
          s.$2 - start + lead.length,
        ),
  ];
  return (text: '$lead${text.substring(start)}', spans: shifted);
}

/// Verse words with the matched words marked, on at most [maxLines] lines
/// with the first match kept in view.
class HighlightedVerse extends StatelessWidget {
  final String text;
  final List<(int, int)> spans;
  final int maxLines;
  const HighlightedVerse({
    super.key,
    required this.text,
    this.spans = const [],
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, space) {
        // About how many letters fit on the lines, so the excerpt starts
        // where the match shows without measuring the text.
        final perLine = space.maxWidth / (14 * scale * .52);
        final budget = (perLine * maxLines - 8).floor().clamp(30, 600);
        final e = excerptAround(text, spans, budget);
        final children = <InlineSpan>[];
        var at = 0;
        for (final s in e.spans) {
          if (s.$1 < at) continue;
          if (s.$1 > at)
            children.add(TextSpan(text: e.text.substring(at, s.$1)));
          children.add(
            TextSpan(
              text: e.text.substring(s.$1, s.$2),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.text,
                backgroundColor: colors.accent.withValues(alpha: .30),
              ),
            ),
          );
          at = s.$2;
        }
        if (at < e.text.length)
          children.add(TextSpan(text: e.text.substring(at)));
        return Text.rich(
          TextSpan(children: children),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.text, fontSize: 14, height: 1.3),
        );
      },
    );
  }
}

/// The text field's keys for the results: Up and Down move the highlight,
/// Enter adds it to Ready, Ctrl+Enter sends it, Esc clears the box.
class ScriptureSearchKeys extends StatelessWidget {
  final ScriptureSearchController controller;
  final VoidCallback onClear;
  final void Function(SearchEntry entry, {required bool send}) onChoose;
  final Widget child;
  const ScriptureSearchKeys({
    super.key,
    required this.controller,
    required this.onClear,
    required this.onChoose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (node, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape) {
        if (!controller.active) return KeyEventResult.ignored;
        onClear();
        return KeyEventResult.handled;
      }
      if (!controller.active) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowDown) {
        controller.move(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        controller.move(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        final entry = controller.current;
        if (entry != null && event is KeyDownEvent) {
          onChoose(entry, send: HardwareKeyboard.instance.isControlPressed);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

/// The results of the box: Library items and Bible passages, grouped.
class ScriptureResults extends StatelessWidget {
  final ScriptureSearchController controller;
  final AppController app;
  final bool enabled;

  /// A Library line was chosen (tapped, or Enter), or sent (double tap,
  /// Ctrl+Enter).
  final void Function(LyricItem item, {required bool send}) onLibrary;

  /// A Bible line was added to Ready, or sent.
  final void Function(SearchHit hit, {required bool send}) onBible;

  /// A book was chosen from the candidates.
  final ValueChanged<String> onBook;
  const ScriptureResults({
    super.key,
    required this.controller,
    required this.app,
    required this.onLibrary,
    required this.onBible,
    required this.onBook,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        ScriptureIndex.state,
        ReadyTray.of(app),
      ]),
      builder: (context, _) {
        final colors = appColors(context);
        final r = controller.result;
        final entries = controller.entries;
        final lib = controller.libraryHits;
        final hits = r?.hits ?? const <SearchHit>[];
        final bibleStart = controller.bibleFirst ? 0 : lib.length;
        final libStart = controller.bibleFirst ? hits.length : 0;
        final highlightedBible =
            controller.highlight >= bibleStart &&
                controller.highlight < bibleStart + hits.length
            ? controller.highlight - bibleStart + 1
            : null;
        Widget libraryGroup() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupLabel('Library', trailing: '${controller.libraryTotal}'),
            for (var i = 0; i < lib.length; i++)
              _LibraryRow(
                key: ValueKey('search-library-${lib[i].id}'),
                item: lib[i],
                highlighted: controller.highlight == libStart + i,
                onTap: () {
                  controller.highlightAt(libStart + i);
                  onLibrary(lib[i], send: false);
                },
                onSend: () => onLibrary(lib[i], send: true),
              ),
            if (controller.moreLibrary)
              TextButton(
                key: const ValueKey('search-library-more'),
                onPressed: controller.showAllLibrary,
                child: Text(
                  'Show all ${controller.libraryTotal} in the Library',
                ),
              ),
          ],
        );
        Widget bibleGroup() {
          final waiting = controller.preparing && r == null;
          return Column(
            key: const ValueKey('search-bible'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GroupLabel(
                'Bible',
                trailing: r == null || r.total == 0
                    ? null
                    : highlightedBible != null
                    ? '$highlightedBible of ${r.total}'
                    : '${r.total} found',
              ),
              if (waiting)
                Padding(
                  key: const ValueKey('search-preparing'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Preparing search…',
                          style: TextStyle(color: colors.muted),
                        ),
                      ),
                    ],
                  ),
                )
              else if (controller.failed && r == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'The Bible could not be opened for searching.',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              if (r != null && r.books.isNotEmpty && !r.byReference)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final b in r.books)
                        ActionChip(
                          key: ValueKey('search-book-$b'),
                          visualDensity: VisualDensity.compact,
                          label: Text(b),
                          onPressed: () => onBook(b),
                        ),
                    ],
                  ),
                ),
              if (r?.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    r!.note!,
                    key: const ValueKey('search-note'),
                    style: TextStyle(
                      color: r.problem ? colors.error : colors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              for (var i = 0; i < hits.length; i++)
                _BibleRow(
                  key: ValueKey('search-hit-$i'),
                  hit: hits[i],
                  app: app,
                  highlighted: controller.highlight == bibleStart + i,
                  onTap: () {
                    controller.highlightAt(bibleStart + i);
                    onBible(hits[i], send: false);
                  },
                  onSend: () => onBible(hits[i], send: true),
                  enabled: enabled,
                ),
              if (controller.hasMore)
                TextButton(
                  key: const ValueKey('search-more'),
                  onPressed: controller.showMore,
                  child: const Text('Show more'),
                ),
              if (r != null &&
                  hits.isEmpty &&
                  (r.books.isEmpty || r.byReference) &&
                  r.note == null)
                _Empty(query: controller.query, anyLibrary: lib.isNotEmpty),
              if (r != null &&
                  hits.isEmpty &&
                  r.books.isNotEmpty &&
                  !r.byReference)
                Text(
                  'Add a chapter and verse, such as ${r.books.first} 3 or ${r.books.first} 3:16.',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
            ],
          );
        }

        return Column(
          key: const ValueKey('scripture-results'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.bibleFirst) ...[
              bibleGroup(),
              if (lib.isNotEmpty) ...[
                const SizedBox(height: 12),
                libraryGroup(),
              ],
            ] else ...[
              if (lib.isNotEmpty) ...[
                libraryGroup(),
                const SizedBox(height: 12),
              ],
              bibleGroup(),
            ],
            if (entries.isEmpty &&
                r == null &&
                !controller.preparing &&
                lib.isEmpty)
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const _GroupLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(text.toUpperCase(), style: sectionLabelStyle(context)),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(fontSize: 12, color: appColors(context).muted),
          ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  final String query;
  final bool anyLibrary;
  const _Empty({required this.query, required this.anyLibrary});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Padding(
      key: const ValueKey('search-empty'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            anyLibrary
                ? 'No verses match “${query.trim()}”.'
                : 'Nothing matches “${query.trim()}”.',
            style: TextStyle(color: colors.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Try fewer words, or a reference such as John 3:16 or Psalm 23.',
            style: TextStyle(color: colors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final LyricItem item;
  final bool highlighted;
  final VoidCallback onTap, onSend;
  const _LibraryRow({
    super.key,
    required this.item,
    required this.highlighted,
    required this.onTap,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: highlighted
            ? colors.accent.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Icon(
                  switch (item.kind) {
                    'scripture' => Icons.menu_book_outlined,
                    'announcement' => Icons.campaign_outlined,
                    _ => Icons.music_note_outlined,
                  },
                  size: 18,
                  color: colors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One Bible result: the reference in the accent colour, the words with
/// the match marked, and a button that sends it straight away.
class _BibleRow extends StatefulWidget {
  final SearchHit hit;
  final AppController app;
  final bool highlighted, enabled;
  final VoidCallback onTap, onSend;
  const _BibleRow({
    super.key,
    required this.hit,
    required this.app,
    required this.highlighted,
    required this.enabled,
    required this.onTap,
    required this.onSend,
  });

  @override
  State<_BibleRow> createState() => _BibleRowState();
}

class _BibleRowState extends State<_BibleRow> {
  Timer? _armed;

  /// A second tap soon after the first sends it, without making the first
  /// wait to see whether a second is coming.
  void _tap() {
    if (_armed != null) {
      _armed!.cancel();
      _armed = null;
      widget.onSend();
      return;
    }
    _armed = Timer(const Duration(milliseconds: 450), () => _armed = null);
    widget.onTap();
  }

  @override
  void dispose() {
    _armed?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final hit = widget.hit;
    final inReady = ReadyTray.of(
      widget.app,
    ).items.any((p) => p.reference == hit.reference);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: widget.highlighted
            ? colors.accent.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.enabled ? _tap : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: widget.highlighted
                      ? colors.accent
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              hit.reference,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (hit.verses > 1)
                            Text(
                              '  ${hit.verses} verses',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.muted,
                              ),
                            ),
                          if (inReady)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                'In Ready',
                                key: ValueKey(
                                  'search-inready-${hit.reference}',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      HighlightedVerse(text: hit.text, spans: hit.spans),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Send now',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.play_arrow_rounded, color: colors.accent),
                  onPressed: widget.enabled ? widget.onSend : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// On a phone: the field that opens the full-height search.
class ScriptureSearchLauncher extends StatelessWidget {
  final String query;
  final VoidCallback onTap;
  const ScriptureSearchLauncher({
    super.key,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return OutlinedButton(
      key: const ValueKey('scripture-search-launcher'),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              query.trim().isEmpty
                  ? 'Search the Bible and songs'
                  : query.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: query.trim().isEmpty ? colors.muted : colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-height search on a phone: the box at the top, the results
/// below. Tapping a verse puts it in Ready and closes the sheet; its play
/// button sends it.
Future<void> showScriptureSearchSheet({
  required BuildContext context,
  required ScriptureSearchController controller,
  required AppController app,
  required List<LyricItem> Function(String) library,
  required void Function(LyricItem item, {required bool send}) onLibrary,
  required bool enabled,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheet) => _SearchSheet(
    controller: controller,
    app: app,
    library: library,
    onLibrary: onLibrary,
    enabled: enabled,
  ),
);

class _SearchSheet extends StatefulWidget {
  final ScriptureSearchController controller;
  final AppController app;
  final List<LyricItem> Function(String) library;
  final void Function(LyricItem item, {required bool send}) onLibrary;
  final bool enabled;
  const _SearchSheet({
    required this.controller,
    required this.app,
    required this.library,
    required this.onLibrary,
    required this.enabled,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final _text = TextEditingController(text: widget.controller.query);
  final _field = FocusNode();

  ScriptureSearchController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.prepare();
    if (_text.text.isNotEmpty)
      c.setQuery(_text.text, widget.library(_text.text));
  }

  @override
  void dispose() {
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  void _set(String v) => c.setQuery(v, widget.library(v));

  void _choose(SearchEntry e, {required bool send}) {
    if (e.isBible) {
      c.addToReady(e.hit!, send: send);
    } else {
      widget.onLibrary(e.item!, send: send);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ScriptureSearchKeys(
                controller: c,
                onClear: () {
                  _text.clear();
                  c.clear();
                },
                onChoose: _choose,
                child: TextField(
                  key: const ValueKey('scripture-sheet-field'),
                  controller: _text,
                  focusNode: _field,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _set,
                  onSubmitted: (_) {
                    final e = c.current;
                    if (e != null) _choose(e, send: false);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'John 3:16, psalm 23, or words from a verse',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _text.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear the search',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _text.clear();
                              c.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: c,
                builder: (context, _) => c.active
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          ScriptureResults(
                            controller: c,
                            app: widget.app,
                            enabled: widget.enabled,
                            onLibrary: (item, {required send}) {
                              widget.onLibrary(item, send: send);
                              Navigator.of(context).pop();
                            },
                            onBible: (hit, {required send}) {
                              c.addToReady(hit, send: send);
                              Navigator.of(context).pop();
                            },
                            onBook: (b) {
                              _text.text = '$b ';
                              _text.selection = TextSelection.collapsed(
                                offset: _text.text.length,
                              );
                              _set(_text.text);
                              _field.requestFocus();
                            },
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Type a reference, such as John 3:16 or Psalm 23, or any words from a verse. Tap a verse to put it in Ready.',
                          style: TextStyle(color: colors.muted),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
