import 'dart:async';
import 'dart:math' as math;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/lyrics/lyrics_page.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/home_widgets.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

/// Adds or edits a song, a set of Bible verses or an announcement, with
/// the slides it makes beside it. Pops with the saved item.
class LyricEditorPage extends StatefulWidget {
  final AppController controller;
  final LyricItem? item;
  final String kind;
  const LyricEditorPage({
    super.key,
    required this.controller,
    this.item,
    this.kind = 'song',
  });

  @override
  State<LyricEditorPage> createState() => _LyricEditorPageState();
}

class _LyricEditorPageState extends State<LyricEditorPage> {
  AppController get c => widget.controller;
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _words = TextEditingController(text: widget.item?.words ?? '');
  late final _by = TextEditingController(text: widget.item?.by ?? '');
  late final _detail = TextEditingController(text: widget.item?.detail ?? '');
  late final _version = TextEditingController(
    text: widget.item?.verses.isEmpty ?? true ? widget.item?.version ?? '' : '',
  );
  late int _lines = widget.item?.linesPerSlide ?? 0;

  /// For verses: looked up in the KJV, or pasted from any translation.
  late bool _pasted =
      widget.kind == 'scripture' &&
      widget.item != null &&
      widget.item!.verses.isEmpty;
  late BibleReading? _reading =
      widget.item == null || widget.item!.verses.isEmpty
      ? null
      : BibleReading(
          widget.item!.title,
          widget.item!.version,
          widget.item!.verses,
        );
  String? _problem;

  /// The books a typed name could be, and what followed the name, for the
  /// choices under the field.
  List<String> _choices = const [];
  String _choicesRest = '';

  /// The reference as understood, shown when a spelling was put right.
  String? _understood;
  bool _saving = false;

  String get kind => widget.kind;

  @override
  void dispose() {
    for (final t in [_title, _words, _by, _detail, _version]) {
      t.dispose();
    }
    super.dispose();
  }

  LyricItem get _draft => LyricItem(
    id: widget.item?.id ?? newLyricId(),
    kind: kind,
    title: kind == 'scripture' && !_pasted
        ? (_reading?.reference ?? _title.text.trim())
        : _title.text.trim(),
    words: kind == 'scripture' && !_pasted ? '' : _words.text,
    linesPerSlide: kind == 'song' ? _lines : 0,
    by: kind == 'song' ? _by.text.trim() : '',
    version: kind != 'scripture'
        ? ''
        : _pasted
        ? _version.text.trim()
        : (_reading?.version ?? 'KJV'),
    verses: kind == 'scripture' && !_pasted
        ? _reading?.verses ?? const []
        : const [],
    detail: kind == 'announcement' ? _detail.text.trim() : '',
    updated: widget.item?.updated ?? 0,
  );

  String get _name => switch (kind) {
    'scripture' => 'Bible verses',
    'announcement' => 'announcement',
    _ => 'song',
  };

  Future<void> _find() async {
    setState(() {
      _problem = null;
      _choices = const [];
      _understood = null;
    });
    try {
      final bible = await BibleLibrary.load();
      final reading = bible.read(_title.text);
      setState(() {
        _reading = reading;
        _title.text = reading.reference;
        _understood = reading.corrected ? reading.reference : null;
      });
    } on BibleBookChoice catch (e) {
      setState(() {
        _reading = null;
        _choices = e.books;
        _choicesRest = e.rest;
      });
    } on RuleError catch (e) {
      setState(() {
        _reading = null;
        _problem = e.message;
      });
    }
  }

  /// A tapped book: the same reference with that book in front.
  void _choose(String book) {
    _title.text = '$book $_choicesRest';
    _find();
  }

  Future<void> _open() async {
    try {
      final file = await c.port.pickTextFile();
      if (file == null || !mounted) return;
      final content = '${file['content'] ?? ''}';
      if (content.length > lyricWordsLimit) {
        setState(
          () => _problem =
              'That file is too long for one song. Keep it within $lyricWordsLimit characters.',
        );
        return;
      }
      setState(() {
        _words.text = cleanLyricText(content).trim();
        if (_title.text.trim().isEmpty) {
          _title.text = '${file['name'] ?? ''}'
              .replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '')
              .trim();
        }
        _problem = null;
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _problem = e is RuleError
              ? e.message
              : 'The file could not be opened.',
        );
    }
  }

  Future<void> _save() async {
    final item = _draft;
    try {
      item.validate();
    } on RuleError catch (e) {
      setState(() => _problem = e.message);
      return;
    }
    setState(() => _saving = true);
    final ok = await c.lyrics.save(item);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(item);
    } else {
      setState(() => _problem = c.error ?? 'It could not be saved. Try again.');
    }
  }

  Future<void> _delete() async {
    final item = widget.item!;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete “${item.title}”?'),
            content: Text(
              'This removes the $_name from the library. It cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-action'),
                style: destructiveFilled(),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    if (await c.lyrics.delete(item.id) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item == null
        ? switch (kind) {
            'scripture' => 'Add Bible verses',
            'announcement' => 'Add an announcement',
            _ => 'Add a song',
          }
        : switch (kind) {
            'scripture' => 'Edit Bible verses',
            'announcement' => 'Edit announcement',
            _ => 'Edit song',
          };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.item != null)
            IconButton(
              key: const ValueKey('lyrics-editor-delete'),
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, space) {
            final wide = space.maxWidth >= 840;
            // Words sit on cards, so the finish shows and they stay legible.
            final form = AppPanel(child: _form());
            final preview = AppPanel(child: _preview());
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: form),
                            const SizedBox(width: 20),
                            Expanded(child: preview),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [form, const SizedBox(height: 20), preview],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _form() {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final save = FilledButton.icon(
      key: const ValueKey('lyrics-editor-save'),
      onPressed: _saving ? null : _save,
      icon: const Icon(Icons.check, size: 20),
      label: Text(switch (kind) {
        'scripture' => 'Save verses',
        'announcement' => 'Save announcement',
        _ => 'Save song',
      }),
    );
    final problem = _problem == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _problem!,
              key: const ValueKey('lyrics-editor-problem'),
              style: TextStyle(color: colors.error),
            ),
          );
    if (kind == 'scripture') return _scriptureForm(save, problem, muted);
    if (kind == 'announcement') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('lyrics-editor-title'),
            controller: _title,
            maxLength: lyricTitleLimit,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Title',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('lyrics-editor-words'),
            controller: _words,
            minLines: 4,
            maxLines: 10,
            maxLength: 600,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Words',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('lyrics-editor-detail'),
            controller: _detail,
            maxLength: 120,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Date, time or place (optional)',
              hintText: 'Sunday 30 November · 12:30 · Church hall',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The title shows large in gold, the words under it. Centre or Left and the background follow the screen look.',
            style: muted,
          ),
          problem,
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: save),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('lyrics-editor-title'),
          controller: _title,
          maxLength: lyricTitleLimit,
          decoration: const InputDecoration(
            labelText: 'Song title',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('lyrics-editor-by'),
          controller: _by,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Written by (optional, shown in the list only)',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('lyrics-editor-words'),
          controller: _words,
          minLines: 10,
          maxLines: 18,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(height: 1.5),
          decoration: const InputDecoration(
            labelText: 'Words',
            alignLabelWithHint: true,
            hintText:
                'Verse 1\nAmazing grace! How sweet the sound\nThat saved a wretch like me!\n\nChorus\n…',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Lines on a slide', style: TextStyle(color: colors.muted)),
            SegmentedButton<int>(
              key: const ValueKey('lyrics-editor-lines'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 0, label: Text('As typed')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {_lines},
              onSelectionChanged: (v) => setState(() => _lines = v.single),
            ),
            OutlinedButton.icon(
              key: const ValueKey('lyrics-editor-open'),
              onPressed: _open,
              icon: const Icon(Icons.file_open_outlined, size: 20),
              label: const Text('Open a text file'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Type or paste the words. A blank line starts a new slide. A line such as Verse 1, Chorus, Bridge, Refrain, Pre-chorus, Intro, Outro, Tag or Ending names the slide and is not shown.',
          style: muted,
        ),
        problem,
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft, child: save),
      ],
    );
  }

  Widget _scriptureForm(Widget save, Widget problem, TextStyle muted) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        key: const ValueKey('lyrics-editor-source'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('Find in the KJV')),
          ButtonSegment(value: true, label: Text('Paste your own')),
        ],
        selected: {_pasted},
        onSelectionChanged: (v) => setState(() {
          _pasted = v.single;
          _problem = null;
        }),
      ),
      const SizedBox(height: 16),
      if (!_pasted) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('lyrics-editor-reference'),
                controller: _title,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _find(),
                onChanged: (_) {
                  if (_choices.isNotEmpty || _understood != null) {
                    setState(() {
                      _choices = const [];
                      _understood = null;
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  hintText: 'John 3:16-18, Psalm 23, 1 Cor 13:4-7',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton.tonal(
                key: const ValueKey('lyrics-editor-find'),
                onPressed: _find,
                child: const Text('Find'),
              ),
            ),
          ],
        ),
        if (_choices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            key: const ValueKey('lyrics-editor-choices'),
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Did you mean:', style: muted),
              for (final book in _choices)
                ActionChip(
                  key: ValueKey('lyrics-editor-choice-$book'),
                  label: Text(book),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _choose(book),
                ),
            ],
          ),
        ],
        if (_understood != null) ...[
          const SizedBox(height: 8),
          Text(
            'Showing $_understood',
            key: const ValueKey('lyrics-editor-understood'),
            style: muted,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'From the King James Version (1769), which comes with the app. Other translations are under copyright and cannot be included; use Paste your own for them.',
          style: muted,
        ),
      ] else ...[
        TextField(
          key: const ValueKey('lyrics-editor-title'),
          controller: _title,
          maxLength: lyricTitleLimit,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Reference',
            hintText: 'Romans 8:28',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('lyrics-editor-version'),
          controller: _version,
          maxLength: 24,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Translation (optional)',
            hintText: 'NIV, NLT, ESV…',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('lyrics-editor-words'),
          controller: _words,
          minLines: 6,
          maxLines: 14,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Verse text',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Paste the verses from any translation your church has the right to show. A blank line starts a new slide; long text is split by length. The reference and translation show under the words.',
          style: muted,
        ),
      ],
      problem,
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerLeft, child: save),
    ],
  );

  Widget _preview() {
    final colors = appColors(context);
    final item = _draft;
    final slides = item.slides;
    final look = c.lyrics.look;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('THE SLIDES THIS MAKES', style: sectionLabelStyle(context)),
        const SizedBox(height: 10),
        if (slides.isEmpty)
          Text(
            kind == 'scripture' && !_pasted
                ? 'Type a reference and press Find.'
                : 'The slides appear here as you type.',
            style: TextStyle(color: colors.muted),
          )
        else ...[
          // The first slide as the screens will show it.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LyricStage(
                key: const ValueKey('lyrics-editor-preview'),
                data: {
                  'key': 'editor',
                  'kind': kind,
                  ...slides.first.toJson(),
                  'bg': look.background.startsWith('custom:')
                      ? 'midnight'
                      : look.background,
                  'dim': look.dim,
                  'size': look.size,
                  'align': look.align,
                  'motion': false,
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, space) {
              final count = math.max(1, (space.maxWidth / 170).floor());
              final width = (space.maxWidth - 8 * (count - 1)) / count;
              return Wrap(
                key: const ValueKey('lyrics-editor-slides'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < slides.length; i++)
                    SizedBox(
                      width: width,
                      child: LyricSlideCard(slide: slides[i], number: i + 1),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            slides.length == 1 ? '1 slide' : '${slides.length} slides',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
        ],
      ],
    );
  }
}

/// Where the bundled photos come from, each public domain or CC0.
Future<void> showLyricPhotoCredits(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Photo credits'),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<List<Json>>(
        future: lyricPhotoCredits(),
        builder: (context, snap) {
          final credits = snap.data ?? const [];
          return ListView(
            shrinkWrap: true,
            children: [
              for (final c in credits)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c['title']}'),
                  subtitle: Text(
                    '${c['author']} · ${c['license']}\n${c['source']}',
                  ),
                  isThreeLine: true,
                ),
              const Text(
                'From Wikimedia Commons. None needs credit to be shown on screen; they are listed here with thanks.',
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
