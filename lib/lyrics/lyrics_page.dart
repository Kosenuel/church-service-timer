import 'dart:async';
import 'dart:math' as math;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/lyrics/lyric_backgrounds.dart';
import 'package:church_service_timer/lyrics/lyric_editors.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/screens/screens_entry.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a key does on the Lyrics page.
enum LyricsKey { next, previous, clear, black }

/// The Lyrics page's keys: → Space Page Down next, ← Page Up previous,
/// Esc clear, B black. They work only on the Lyrics page, so Live's own
/// meanings of Space, B and → (pause, next segment) never clash.
LyricsKey? lyricsKeyFor(LogicalKeyboardKey key, {required bool control}) {
  if (control) return null;
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.pageDown) {
    return LyricsKey.next;
  }
  if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
    return LyricsKey.previous;
  }
  if (key == LogicalKeyboardKey.escape) return LyricsKey.clear;
  if (key == LogicalKeyboardKey.keyB) return LyricsKey.black;
  return null;
}

/// The Lyrics page, its keys and the Lyrics button on Live.
extension LyricsPageViews on HomeState {
  /// The Lyrics page fills the window: on a wide screen its three columns
  /// each scroll on their own; on a narrow one the controls stay along
  /// the bottom.
  bool get lyricsFillsWindow => c.ready && page == lyricsPage;

  Widget lyricsPanel() => LyricsPanel(
    controller: c,
    locked: controlsLocked,
    keyHints: showKeyHints,
    desktop: c.port.isDesktop,
  );

  /// A key pressed on the Lyrics page: true when it changed the slides.
  /// Nothing while a field has the keyboard, a window is open on top, or
  /// the controls are locked.
  bool lyricsKey(KeyEvent event) {
    final action = lyricsKeyFor(
      event.logicalKey,
      control: HardwareKeyboard.instance.isControlPressed,
    );
    if (action == null ||
        typingInField ||
        controlsLocked ||
        !c.pairing.localControl ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final l = c.lyrics;
    switch (action) {
      case LyricsKey.next:
        l.next(selected: l.selectedId);
      case LyricsKey.previous:
        l.previous(selected: l.selectedId);
      case LyricsKey.clear:
        if (!l.showing) return false;
        l.clear();
      case LyricsKey.black:
        l.toggleBlack();
    }
    return true;
  }

  /// The Lyrics button under the display preview on Live, and while
  /// lyrics are on the screens, what they show with Clear lyrics.
  Widget lyricsButton() => OutlinedButton.icon(
    key: const ValueKey('live-lyrics-button'),
    onPressed: controlsLocked ? null : () => goToPage(lyricsPage),
    icon: const Icon(Icons.lyrics_outlined, size: 20),
    label: const Text('Slides'),
  );

  /// With [button] false the Lyrics button is placed by the caller, and
  /// only the line saying what is on the screens is added here.
  List<Widget> lyricsOnLive({bool button = true}) {
    // A desktop layout keeps its panes to the window; the button is in
    // the header there (see [lyricsHeaderButton]).
    if (!c.ready || liveFillsWindow) return const [];
    final l = c.lyrics;
    final colors = appColors(context);
    if (!button && !l.showing) return const [];
    return [
      const SizedBox(height: 12),
      Wrap(
        key: const ValueKey('live-lyrics'),
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (button) ...[lyricsButton(), screensButton()],
          if (l.showing) ...[
            Text(
              'On the screens: ${l.statusLine}',
              key: const ValueKey('live-lyrics-status'),
              style: TextStyle(color: colors.text),
            ),
            TextButton(
              key: const ValueKey('live-lyrics-clear'),
              onPressed: controlsLocked ? null : l.clear,
              child: const Text('Clear slide'),
            ),
          ],
        ],
      ),
    ];
  }
}

/// The Lyrics button in the header on Live in a desktop layout, whose
/// panes have no room for another row. Lit while lyrics are on the
/// screens.
extension LyricsHeaderButton on HomeState {
  Widget lyricsHeaderButton() {
    final l = c.lyrics;
    final on = l.showing;
    return IconButton(
      key: const ValueKey('live-lyrics-button'),
      tooltip: on ? 'Slides · on the screens: ${l.statusLine}' : 'Slides',
      isSelected: on,
      onPressed: controlsLocked ? null : () => goToPage(lyricsPage),
      icon: const Icon(Icons.lyrics_outlined),
      selectedIcon: const Icon(Icons.lyrics),
    );
  }
}

/// The operator's Lyrics panel: Stored songs, the slides, and what is on
/// the screens now with the controls and the look.
class LyricsPanel extends StatefulWidget {
  final AppController controller;
  final bool locked, keyHints, desktop;
  const LyricsPanel({
    super.key,
    required this.controller,
    this.locked = false,
    this.keyHints = false,
    this.desktop = false,
  });

  /// From this width the panel has three columns.
  static const wideWidth = 1100.0;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  AppController get c => widget.controller;
  final _search = TextEditingController();

  /// The Dim slider while it is being dragged, saved when let go.
  double? _dimming;

  /// Holds the keyboard on the page, so the arrow keys and Space change
  /// slides instead of moving between buttons or pressing one; the slides
  /// themselves change in [LyricsPageViews.lyricsKey].
  final _focus = FocusNode(debugLabel: 'Slides panel');

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    final focus = FocusManager.instance.primaryFocus?.context;
    final typing =
        focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null);
    return !typing &&
            lyricsKeyFor(
                  event.logicalKey,
                  control: HardwareKeyboard.instance.isControlPressed,
                ) !=
                null
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// After a click on a slide or a song, the keys work again, even if the
  /// search box had the keyboard.
  void _takeKeys() {
    if (!_focus.hasPrimaryFocus) _focus.requestFocus();
  }

  LyricItem? get selected {
    final l = c.lyrics;
    return l.library.byId(l.selectedId) ?? l.item;
  }

  bool get enabled => !widget.locked && c.pairing.localControl && !c.corrupt;

  void _select(LyricItem item) {
    _takeKeys();
    setState(() => c.lyrics.selectedId = item.id);
  }

  Future<void> _edit([LyricItem? item, String kind = 'song']) async {
    final saved = await Navigator.of(context).push<LyricItem>(
      MaterialPageRoute(
        builder: (_) => LyricEditorPage(
          controller: c,
          item: item,
          kind: item?.kind ?? kind,
        ),
      ),
    );
    if (saved != null && mounted)
      setState(() => c.lyrics.selectedId = saved.id);
  }

  Future<void> _delete(LyricItem item) async {
    final what = switch (item.kind) {
      'scripture' => 'these verses',
      'announcement' => 'this announcement',
      _ => 'this song',
    };
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete “${item.title}”?'),
            content: Text(
              'This removes $what from the library. It cannot be undone.',
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
    if (ok) await c.lyrics.delete(item.id);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _keys,
    child: AnimatedBuilder(
      animation: Listenable.merge([c, c.liveClock]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, space) => space.maxWidth >= LyricsPanel.wideWidth
            ? _wide(space)
            : _narrow(space),
      ),
    ),
  );

  // ---- Layouts ---------------------------------------------------------------

  Widget _column(String name, List<Widget> children, {Key? key}) => AppPanel(
    key: key,
    padding: EdgeInsets.zero,
    child: ListView(
      key: ValueKey('lyrics-column-$name'),
      padding: const EdgeInsets.all(16),
      children: children,
    ),
  );

  Widget _wide(BoxConstraints space) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: _column('stored', [_label('Library'), ..._stored()]),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 100,
          child: _column('slides', [
            _slidesHeader(),
            const SizedBox(height: 10),
            _slides(columns: null),
            _tip(),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 115,
          child: _column('screens', [
            _label('On the screens now'),
            _preview(),
            _status(),
            _controls(),
            ..._look(),
          ]),
        ),
      ],
    ),
  );

  Widget _narrow(BoxConstraints space) {
    final columns = space.maxWidth >= 700 ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('lyrics-column-narrow'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              // Cards in the finish's material, as Live and Settings have
              // on a phone: words always sit on a panel.
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        // Sideways on a phone, a preview the whole width
                        // would push the slides off the screen.
                        constraints: BoxConstraints(
                          maxWidth: math.max(
                            240,
                            MediaQuery.sizeOf(context).height * .9,
                          ),
                        ),
                        child: _preview(),
                      ),
                    ),
                    _status(),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _picker(),
                    const SizedBox(height: 12),
                    _slides(columns: columns),
                    _tip(),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppPanel(
                child: ExpansionTile(
                  key: const ValueKey('lyrics-look'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  title: Text(
                    'Screens and look',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    _sendToSummary(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: _look(),
                ),
              ),
            ],
          ),
        ),
        _bar(),
      ],
    );
  }

  // ---- Stored songs ------------------------------------------------------------

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text.toUpperCase(), style: sectionLabelStyle(context)),
  );

  List<LyricItem> get _found => [
    for (final i in c.lyrics.library.ordered)
      if (i.matches(_search.text)) i,
  ];

  List<Widget> _stored({VoidCallback? picked}) {
    final colors = appColors(context);
    final found = _found;
    final current = selected;
    return [
      TextField(
        key: const ValueKey('lyrics-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search the library',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear the search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(_search.clear),
                ),
        ),
      ),
      const SizedBox(height: 10),
      if (c.lyrics.library.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nothing stored yet. Add a song, Bible verses or an announcement; they stay here for every service.',
            style: TextStyle(color: colors.muted),
          ),
        )
      else if (found.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nothing matches “${_search.text.trim()}”.',
            style: TextStyle(color: colors.muted),
          ),
        ),
      for (final item in found)
        _storedRow(item, item.id == current?.id, picked: picked),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(
        key: const ValueKey('lyrics-add-song'),
        onPressed: enabled ? () => _edit() : null,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add a song'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('lyrics-add-scripture'),
        onPressed: enabled ? () => _edit(null, 'scripture') : null,
        icon: const Icon(Icons.menu_book_outlined, size: 20),
        label: const Text('Add Bible verses'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('lyrics-add-announcement'),
        onPressed: enabled ? () => _edit(null, 'announcement') : null,
        icon: const Icon(Icons.campaign_outlined, size: 20),
        label: const Text('Add an announcement'),
      ),
    ];
  }

  Widget _storedRow(LyricItem item, bool chosen, {VoidCallback? picked}) {
    final colors = appColors(context);
    final live = c.lyrics.item?.id == item.id && c.lyrics.slide != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        // A tint over whatever the panel is made of, so it reads on a
        // finish as on the plain card.
        color: chosen
            ? colors.accent.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('lyrics-item-${item.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _select(item);
            picked?.call();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: chosen ? colors.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
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
                        live
                            ? 'On the screens · ${item.summary}'
                            : item.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: live ? colors.accent : colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('lyrics-item-menu-${item.id}'),
                  tooltip: 'Edit or delete',
                  enabled: enabled,
                  onSelected: (v) {
                    if (v == 'edit') unawaited(_edit(item));
                    if (v == 'delete') unawaited(_delete(item));
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete…')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// On a narrow screen: the chosen item, and a button that opens Stored
  /// songs in a sheet.
  Widget _picker() {
    final item = selected;
    final colors = appColors(context);
    return OutlinedButton(
      key: const ValueKey('lyrics-picker'),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheet).bottom,
            ),
            child: StatefulBuilder(
              builder: (sheet, update) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheet).height * .85,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _label('Library'),
                    ...(() {
                      // The sheet keeps its own search in step with the page.
                      return _stored(picked: () => Navigator.pop(sheet));
                    })(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ).then((_) => mounted ? setState(() {}) : null),
      child: Row(
        children: [
          Icon(Icons.library_music_outlined, size: 20, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.title ?? 'Library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  item == null
                      ? 'Choose a song, verses or an announcement'
                      : 'Library · change',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.expand_more, color: colors.muted),
        ],
      ),
    );
  }

  // ---- Slides ------------------------------------------------------------------

  Widget _slidesHeader() {
    final item = selected;
    return Row(
      children: [
        Expanded(
          child: Text(
            (item?.title ?? 'Slides').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sectionLabelStyle(context),
          ),
        ),
        if (item != null)
          TextButton.icon(
            key: const ValueKey('lyrics-edit-selected'),
            onPressed: enabled ? () => _edit(item) : null,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
      ],
    );
  }

  Widget _slides({required int? columns}) {
    final item = selected;
    final colors = appColors(context);
    if (item == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          c.lyrics.library.isEmpty
              ? 'Add a song to see its slides here.'
              : 'Choose something from the library to see its slides.',
          style: TextStyle(color: colors.muted),
        ),
      );
    }
    final l = c.lyrics;
    final live = l.item?.id == item.id ? l.index : null;
    final next = live == null ? 0 : live + 1;
    return LayoutBuilder(
      builder: (context, space) {
        final count = columns ?? math.max(1, (space.maxWidth / 170).floor());
        const gap = 8.0;
        final width = (space.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          key: const ValueKey('lyrics-slides'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < item.slides.length; i++)
              SizedBox(
                width: width,
                child: LyricSlideCard(
                  key: ValueKey('lyrics-slide-$i'),
                  slide: item.slides[i],
                  number: i + 1,
                  live: i == live,
                  next: i == next && !(l.black && live == null),
                  onTap: enabled
                      ? () {
                          _takeKeys();
                          l.show(item.id, i);
                        }
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tip() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      widget.desktop
          ? 'Click a slide to show it. Right arrow or Space next, Left arrow previous, Esc clear slide, B black. The dashed slide is next.'
          : 'Tap a slide to show it. The dashed slide is next.',
      key: const ValueKey('lyrics-tip'),
      style: TextStyle(fontSize: 12, color: appColors(context).muted),
    ),
  );

  // ---- On the screens now ------------------------------------------------------------

  Widget _preview() {
    final l = c.lyrics;
    // What a ticked screen shows: the slide, or the screen as it is
    // without lyrics.
    final field = l.previewField();
    return Semantics(
      key: const ValueKey('lyrics-preview'),
      label: 'On the screens now',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: Colors.black,
            child: ExcludeSemantics(
              child: field != null
                  ? LyricStage(data: field)
                  : StageSurface(
                      data: c.stageWindowSnapshot()..remove('lyrics'),
                      stale: false,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// The groups showing slides, as words: "Room 1 and Stage".
  String _targets() {
    final names = [for (final g in c.screens.slideGroups) g.name];
    if (names.isEmpty) return 'no screens';
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  String _sendToSummary() => c.screens.slideGroups.isEmpty
      ? 'No screens are showing slides'
      : 'Showing slides: ${_targets()}';

  /// Which groups show slides, in place of the old Send to boxes: what a
  /// group shows is set in the Screens panel. With none, it says so and
  /// offers one tap to fix it, or a slide would seem to do nothing.
  List<Widget> _groupsLine() {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final groups = c.screens.slideGroups;
    final fix = c.screens.setup.groupOf(thisScreenKey);
    final cues = [
      for (final g in groups)
        if (g.cues) g.name,
    ];
    return [
      if (groups.isEmpty) ...[
        Text(
          'No screens are showing slides.',
          key: const ValueKey('lyrics-no-groups'),
          style: TextStyle(color: colors.warning, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonal(
              key: const ValueKey('lyrics-fix-groups'),
              onPressed: enabled
                  ? () => unawaited(c.screens.setShow(fix.id, 'slides'))
                  : null,
              child: Text('Show slides in ${fix.name}'),
            ),
            TextButton(
              key: const ValueKey('lyrics-open-screens'),
              onPressed: () => openScreensPanel(context, c),
              child: const Text('Screens'),
            ),
          ],
        ),
      ] else
        Wrap(
          key: const ValueKey('lyrics-groups'),
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              [
                for (final g in groups)
                  '${g.name}${g.show == 'monitor' ? ' (with the timer)' : ''}',
              ].join(' · '),
              style: TextStyle(color: colors.text),
            ),
            TextButton(
              key: const ValueKey('lyrics-open-screens'),
              onPressed: () => openScreensPanel(context, c),
              child: const Text('Screens'),
            ),
          ],
        ),
      const SizedBox(height: 4),
      Text(
        [
          'What each group of screens shows is set in Screens.',
          if (cues.isNotEmpty)
            'Cues show over the slide on ${cues.join(', ')}.'
          else if (groups.isNotEmpty)
            'Cues never cover the slide: no group showing slides has Shows cues on.',
          'The LED sign never shows slides.',
        ].join(' '),
        key: const ValueKey('lyrics-send-note'),
        style: muted,
      ),
    ];
  }

  Widget _status() {
    final l = c.lyrics, colors = appColors(context);
    final on = l.showing;
    final text = l.black
        ? 'Black on ${_targets()}'
        : on
        ? '${l.statusLine} · on ${_targets()}'
        : c.state.session.active
        ? 'Showing the countdown'
        : 'No slide on the screens';
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? colors.error : colors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('lyrics-status'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (c.screens.slideGroups.isNotEmpty) return row;
    // Where the operator looks while clicking slides: with no group
    // showing slides a click would seem to do nothing, so say so here.
    final fix = c.screens.setup.groupOf(thisScreenKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Container(
          key: const ValueKey('lyrics-no-groups-top'),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.warning.withValues(alpha: .5)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'No screens are showing slides.',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                key: const ValueKey('lyrics-fix-groups-top'),
                onPressed: enabled
                    ? () => unawaited(c.screens.setShow(fix.id, 'slides'))
                    : null,
                child: Text('Show slides in ${fix.name}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _keyed(String text, String key) => widget.keyHints
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            // Roboto has no arrows; the key is drawn as one.
            switch (key) {
              '→' => const _ArrowHint(Icons.arrow_forward),
              '←' => const _ArrowHint(Icons.arrow_back),
              _ => KeyHint(key),
            },
          ],
        )
      : Text(text, overflow: TextOverflow.ellipsis);

  void _previous() => c.lyrics.previous(selected: c.lyrics.selectedId);
  void _next() => c.lyrics.next(selected: c.lyrics.selectedId);

  Widget _controls() {
    final l = c.lyrics;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          key: const ValueKey('lyrics-previous'),
          onPressed: enabled ? _previous : null,
          child: _keyed('Previous', '←'),
        ),
        FilledButton(
          key: const ValueKey('lyrics-next'),
          onPressed: enabled ? _next : null,
          child: _keyed('Next', '→'),
        ),
        OutlinedButton(
          key: const ValueKey('lyrics-clear'),
          onPressed: enabled && l.showing ? l.clear : null,
          child: _keyed('Clear slide', 'Esc'),
        ),
        l.black
            ? FilledButton(
                key: const ValueKey('lyrics-black'),
                onPressed: enabled ? l.toggleBlack : null,
                child: _keyed('Black', 'B'),
              )
            : OutlinedButton(
                key: const ValueKey('lyrics-black'),
                onPressed: enabled ? l.toggleBlack : null,
                child: _keyed('Black', 'B'),
              ),
      ],
    );
  }

  /// On a narrow screen, the four controls along the bottom, under the
  /// thumb.
  Widget _bar() {
    final l = c.lyrics, colors = appColors(context);
    Widget cell(Widget child, {int flex = 1}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: child,
      ),
    );
    const pad = EdgeInsets.symmetric(horizontal: 4, vertical: 12);
    Text word(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    final finish = finishLook(context).active;
    final bar = Material(
      color: finish ? Colors.transparent : colors.surface,
      child: Container(
        decoration: finish
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          key: const ValueKey('lyrics-bar'),
          children: [
            cell(
              OutlinedButton(
                key: const ValueKey('lyrics-previous'),
                style: OutlinedButton.styleFrom(padding: pad),
                onPressed: enabled ? _previous : null,
                child: const Icon(
                  Icons.chevron_left,
                  semanticLabel: 'Previous',
                ),
              ),
            ),
            cell(
              FilledButton(
                key: const ValueKey('lyrics-next'),
                style: FilledButton.styleFrom(padding: pad),
                onPressed: enabled ? _next : null,
                child: word('Next'),
              ),
              flex: 2,
            ),
            cell(
              OutlinedButton(
                key: const ValueKey('lyrics-clear'),
                style: OutlinedButton.styleFrom(padding: pad),
                onPressed: enabled && l.showing ? l.clear : null,
                child: word('Clear'),
              ),
            ),
            cell(
              l.black
                  ? FilledButton(
                      key: const ValueKey('lyrics-black'),
                      style: FilledButton.styleFrom(padding: pad),
                      onPressed: enabled ? l.toggleBlack : null,
                      child: word('Black'),
                    )
                  : OutlinedButton(
                      key: const ValueKey('lyrics-black'),
                      style: OutlinedButton.styleFrom(padding: pad),
                      onPressed: enabled ? l.toggleBlack : null,
                      child: word('Black'),
                    ),
            ),
          ],
        ),
      ),
    );
    // On a finish the bar is a plate of the material across the window.
    return finish ? FinishPane(strip: true, child: bar) : bar;
  }

  // ---- Send to and the look ------------------------------------------------------------

  void _setLook(LyricsLook next) => unawaited(c.lyrics.setLook(next));

  List<Widget> _look() {
    final l = c.lyrics, look = l.look, colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final second = c.secondScreen;
    // This computer's group shows slides, but its window is closed.
    final secondShut =
        widget.desktop &&
        second != null &&
        showsSlides(c.screens.groupOf(thisScreenKey).show) &&
        !second.host.open;
    final custom = look.background.startsWith('custom:');
    final dim = _dimming ?? look.dim.toDouble();
    return [
      const SizedBox(height: 16),
      _label('Showing slides'),
      ..._groupsLine(),
      if (secondShut)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('The second screen is not showing.', style: muted),
              if (second.target case final target?)
                TextButton(
                  key: const ValueKey('lyrics-show-second'),
                  onPressed: enabled ? () => second.show(target) : null,
                  child: const Text('Show on second screen'),
                ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      _label('Background'),
      LayoutBuilder(
        builder: (context, space) {
          final count = math.max(3, (space.maxWidth / 96).floor());
          const gap = 8.0;
          final width = (space.maxWidth - gap * (count - 1)) / count;
          Widget tile(String id, String name) => SizedBox(
            width: width,
            child: LyricBackgroundTile(
              key: ValueKey('lyrics-bg-$id'),
              id: id,
              name: name,
              selected: look.background == id,
              onTap: enabled
                  ? () => _setLook(look.copyWith(background: id))
                  : null,
            ),
          );
          // Grouped, so 35 backgrounds stay easy to scan.
          Widget group(String name, List<Widget> tiles) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Wrap(spacing: gap, runSpacing: gap, children: tiles),
              ],
            ),
          );
          return Column(
            key: const ValueKey('lyrics-backgrounds'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              group('Designs', [
                for (final e in lyricDrawnBackgrounds.entries)
                  tile(e.key, e.value),
              ]),
              group('Nature', [
                for (final p in lyricPhotos)
                  if (p.kind == 'nature') tile('photo:${p.id}', p.title),
              ]),
              group('People', [
                for (final p in lyricPhotos)
                  if (p.kind == 'people') tile('photo:${p.id}', p.title),
              ]),
              group('Your picture', [
                if (custom && l.pictureBytes != null)
                  tile(look.background, 'Your picture'),
                SizedBox(
                  width: width,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: OutlinedButton(
                      key: const ValueKey('lyrics-bg-own'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: enabled ? _pickPicture : null,
                      child: const FittedBox(child: Text('+ Your picture')),
                    ),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
      const SizedBox(height: 6),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            custom
                ? 'Your picture shows on the second screen, full screen and web screens. Stage screens show Midnight instead.'
                : 'Photos are public domain or CC0, from Wikimedia Commons.',
            key: const ValueKey('lyrics-bg-note'),
            style: muted,
          ),
          TextButton(
            key: const ValueKey('lyrics-photo-credits'),
            onPressed: () => showLyricPhotoCredits(context),
            child: const Text('Photo credits'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _label('Dim'),
      Row(
        children: [
          Expanded(
            child: Slider(
              key: const ValueKey('lyrics-dim'),
              value: look.darkInk ? 0 : dim,
              min: 0,
              max: 90,
              divisions: 18,
              label: '${dim.round()}%',
              onChanged: enabled && !look.darkInk
                  ? (v) => setState(() => _dimming = v)
                  : null,
              onChangeEnd: enabled && !look.darkInk
                  ? (v) {
                      _dimming = null;
                      _setLook(look.copyWith(dim: v.round()));
                    }
                  : null,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              look.darkInk ? '—' : '${dim.round()}%',
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      if (look.darkInk)
        Text('Linen has dark words and is never dimmed.', style: muted),
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _segments('size', 'Text', look.size, const {
            's': 'S',
            'm': 'M',
            'l': 'L',
          }, (v) => look.copyWith(size: v)),
          _segments('align', null, look.align, const {
            'center': 'Centre',
            'left': 'Left',
          }, (v) => look.copyWith(align: v)),
          _segments('motion', 'Motion', look.motion, const {
            'still': 'Still',
            'gentle': 'Gentle',
          }, (v) => look.copyWith(motion: v)),
          FilterChip(
            key: const ValueKey('lyrics-chip-toggle'),
            label: const Text('Countdown in the corner'),
            selected: look.chip,
            onSelected: enabled
                ? (v) => _setLook(look.copyWith(chip: v))
                : null,
          ),
        ],
      ),
      if (look.chip)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'A small countdown stays on the slide while a service runs.',
            style: muted,
          ),
        ),
    ];
  }

  Widget _segments(
    String key,
    String? name,
    String value,
    Map<String, String> options,
    LyricsLook Function(String v) change,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (name != null) ...[
        Text(name, style: TextStyle(color: appColors(context).muted)),
        const SizedBox(width: 8),
      ],
      SegmentedButton<String>(
        key: ValueKey('lyrics-$key'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final e in options.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {value},
        onSelectionChanged: enabled ? (v) => _setLook(change(v.single)) : null,
      ),
    ],
  );

  Future<void> _pickPicture() async {
    try {
      await c.lyrics.pickPicture();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is RuleError ? e.message : 'The picture could not be used.',
            ),
          ),
        );
      }
    }
  }
}

/// A slide on the operator's grid: its name, number and words, ringed
/// while it is on the screens and dashed when it is next.
class LyricSlideCard extends StatelessWidget {
  final LyricSlide slide;
  final int number;
  final bool live, next;
  final VoidCallback? onTap;
  const LyricSlideCard({
    super.key,
    required this.slide,
    required this.number,
    this.live = false,
    this.next = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final live = colors.error;
    final border = this.live
        ? live
        : next
        ? colors.accent
        : colors.border;
    final words = [
      if (slide.title.isNotEmpty) slide.title,
      if (slide.text.isNotEmpty) slide.text,
      if (slide.detail.isNotEmpty) slide.detail,
    ].join('\n');
    return Semantics(
      selected: this.live,
      button: true,
      label:
          '${slide.label}, slide $number${this.live
              ? ', on the screens'
              : next
              ? ', next'
              : ''}',
      child: CustomPaint(
        foregroundPainter: next && !this.live ? _DashedBorder(border) : null,
        child: Material(
          color: colors.input,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: next && !this.live
                ? BorderSide.none
                : BorderSide(color: border, width: this.live ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              slide.label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: .8,
                                fontWeight: FontWeight.w700,
                                color: colors.muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (this.live)
                            Container(
                              key: const ValueKey('lyrics-on-screens-badge'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: live,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                'On screens',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: readable(live),
                                ),
                              ),
                            )
                          else ...[
                            const Spacer(),
                            Text(
                              '$number',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      words.replaceAll(RegExp('[⁰¹²³⁴⁵⁶⁷⁸⁹]+ '), ''),
                      maxLines: 7,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  final Color color;
  _DashedBorder(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.75),
          const Radius.circular(10),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// A background in the picker: a small still copy with its name.
class LyricBackgroundTile extends StatelessWidget {
  final String id, name;
  final bool selected;
  final VoidCallback? onTap;
  const LyricBackgroundTile({
    super.key,
    required this.id,
    required this.name,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$name background',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? colors.accent : colors.border,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(child: _thumb()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: const Color(0x8c000000),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    if (id.startsWith('photo:')) {
      final photo = lyricPhotoById(id.substring(6));
      if (photo != null) {
        return Image.asset(
          photo.thumbnail,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      }
    }
    if (id.startsWith('custom:') && LyricPictureSource.bytes != null) {
      return Image.memory(
        LyricPictureSource.bytes!,
        fit: BoxFit.cover,
        cacheWidth: 240,
      );
    }
    return CustomPaint(painter: LyricBackgroundPainter(id));
  }
}

class _ArrowHint extends StatelessWidget {
  final IconData icon;
  const _ArrowHint(this.icon);
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(
      icon,
      size: 14,
      color: DefaultTextStyle.of(context).style.color?.withValues(alpha: .62),
    ),
  );
}
