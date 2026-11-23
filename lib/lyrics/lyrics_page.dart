import 'dart:async';
import 'dart:math' as math;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/lyrics/lyric_backgrounds.dart';
import 'package:church_service_timer/lyrics/lyric_editors.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/lyrics/ready_tray.dart';
import 'package:church_service_timer/lyrics/scripture_search.dart';
import 'package:church_service_timer/lyrics/scripture_search_ui.dart';
import 'package:church_service_timer/lyrics/slides_parts.dart';
import 'package:church_service_timer/main.dart';
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
    // `/` or Ctrl+F: the search box (Ctrl+F also from inside it).
    if (!controlsLocked &&
        isScriptureSearchKey(
          event.logicalKey,
          control: HardwareKeyboard.instance.isControlPressed,
          typing: typingInField,
        ) &&
        ModalRoute.of(context)?.isCurrent == true) {
      ScriptureSearchFocus.request();
      return true;
    }
    final action = lyricsKeyFor(
      event.logicalKey,
      control: HardwareKeyboard.instance.isControlPressed,
    );
    if (action == null ||
        typingInField ||
        // Space opens and closes a row that folds open, as Enter does.
        (event.logicalKey == LogicalKeyboardKey.space &&
            slidesFoldHasFocus()) ||
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
          if (button) lyricsButton(),
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

class _LyricsPanelState extends State<LyricsPanel>
    with SingleTickerProviderStateMixin {
  AppController get c => widget.controller;
  final _search = TextEditingController();

  /// The Library's tabs, in the order they show.
  static const _tabs = ['song', 'scripture', 'announcement', 'all'];
  static const _tabNames = {
    'song': 'Songs',
    'scripture': 'Bible verses',
    'announcement': 'Announcements',
    'all': 'All',
  };

  /// Which Library tab shows and which rows are open. Read from this
  /// device's saved state when the page opens and saved on each change,
  /// but used from here, so a tap shows at once even while a save is
  /// under way.
  late final TabController _tab = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: math.max(0, _tabs.indexOf(c.state.slidesTab)),
  )..addListener(_tabChanged);
  late final Set<String> _open = {...c.state.slidesOpen};

  /// The Screens row's choices, open until closed again; not remembered.
  bool _screensOpen = false;

  /// The background group shown in the picker; at first the current
  /// background's.
  String? _bgGroup;

  /// The box also searches the Bible; see scripture_search.dart.
  late final _bible = ScriptureSearchController(c);

  /// The Dim slider while it is being dragged, saved when let go.
  double? _dimming;

  /// Holds the keyboard on the page, so the arrow keys and Space change
  /// slides instead of moving between buttons or pressing one; the slides
  /// themselves change in [LyricsPageViews.lyricsKey].
  final _focus = FocusNode(debugLabel: 'Slides panel');

  @override
  void initState() {
    super.initState();
    _bible.prepare();
  }

  String get _kind => _tabs[_tab.index];

  void _tabChanged() {
    if (_tab.indexIsChanging) return;
    setState(() {});
    final kind = _kind;
    unawaited(_remember((d) => d.slidesTab = kind));
  }

  void _toggle(String row) {
    setState(() => _open.contains(row) ? _open.remove(row) : _open.add(row));
    final open = {..._open};
    unawaited(_remember((d) => d.slidesOpen = open));
  }

  /// Saves a choice kept on this device only, after any save already under
  /// way, as [LyricsController] does, so a quick tap is not lost.
  Future<void> _remember(void Function(AppState draft) change) async {
    for (var i = 0; i < 50 && c.busy; i++) {
      await (c.pendingWrite ??
          Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await c.commit((draft, _) => change(draft));
  }

  @override
  void dispose() {
    _tab.dispose();
    _bible.dispose();
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
    if (event.logicalKey == LogicalKeyboardKey.space && slidesFoldHasFocus()) {
      return KeyEventResult.ignored;
    }
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
      animation: Listenable.merge([c, c.liveClock, ReadyTray.of(c)]),
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

  /// The Library: the search box, the tabs and the list scroll; the Add
  /// row stays along the bottom of the card.
  Widget _libraryColumn() => AppPanel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('lyrics-column-stored'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            children: [_label('Library'), ..._stored()],
          ),
        ),
        const SlidesHairline(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: _addRow(),
        ),
      ],
    ),
  );

  Widget _wide(BoxConstraints space) {
    _bible.openSheet = null;
    return _wideLayout(space);
  }

  Widget _wideLayout(BoxConstraints space) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          // Wider while searching, so verses read on a few lines; wide
          // enough for the four tabs and the Add row by their full names.
          width: _bible.active ? 400 : 328,
          child: _libraryColumn(),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 100,
          child: _column('slides', [
            ReadyTrayPanel(controller: c, enabled: enabled, bare: true),
            const SizedBox(height: 20),
            _slidesHeader(),
            const SizedBox(height: 12),
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
            const SlidesHairline(),
            const SizedBox(height: 12),
            _controls(),
            const SizedBox(height: 12),
            ..._rows(),
          ]),
        ),
      ],
    ),
  );

  Widget _narrow(BoxConstraints space) {
    final columns = space.maxWidth >= 700 ? 3 : 2;
    _bible.openSheet = _openSearch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('lyrics-column-narrow'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              ScriptureSearchLauncher(query: _bible.query, onTap: _openSearch),
              const SizedBox(height: 12),
              if (!ReadyTray.of(c).isEmpty) ...[
                ReadyTrayPanel(controller: c, enabled: enabled),
                const SizedBox(height: 12),
              ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _rows(first: true),
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

  /// What the list shows: the tab's kind, or, while searching, whatever
  /// matches whatever its kind, so a search never misses a thing because
  /// another tab was open.
  List<LyricItem> get _found {
    final searching = _search.text.trim().isNotEmpty;
    return [
      for (final i in c.lyrics.library.ordered)
        if (searching
            ? i.matches(_search.text)
            : _kind == 'all' || i.kind == _kind)
          i,
    ];
  }

  List<LyricItem> _libraryFor(String q) => [
    for (final i in c.lyrics.library.ordered)
      if (i.matches(q)) i,
  ];

  /// Library or Bible line chosen in the search results.
  void _chooseLibrary(LyricItem item, {required bool send}) {
    _select(item);
    if (send && enabled) c.lyrics.show(item.id, 0);
  }

  void _chooseBible(SearchHit hit, {required bool send}) {
    _bible.addToReady(hit, send: send);
    // After sending, the arrow keys and Esc work on the slides again.
    if (send) _takeKeys();
  }

  void _chooseEntry(SearchEntry e, {required bool send}) => e.isBible
      ? _chooseBible(e.hit!, send: send)
      : _chooseLibrary(e.item!, send: send);

  void _clearSearch() => setState(() {
    _search.clear();
    _bible.clear();
  });

  Future<void> _openSearch() => showScriptureSearchSheet(
    context: context,
    controller: _bible,
    app: c,
    library: _libraryFor,
    onLibrary: _chooseLibrary,
    enabled: enabled,
  ).then((_) => mounted ? setState(() {}) : null);

  List<Widget> _stored({VoidCallback? picked}) {
    final colors = appColors(context);
    final found = _found;
    final current = selected;
    // The wide column's box searches the Library and the Bible together;
    // the phone's sheet picker keeps a Library-only box.
    final both = picked == null;
    final field = ScriptureSearchKeys(
      key: const ValueKey('lyrics-search-keys'),
      controller: _bible,
      onClear: _clearSearch,
      onRelease: _takeKeys,
      onChoose: _chooseEntry,
      child: TextField(
        key: const ValueKey('lyrics-search'),
        controller: _search,
        focusNode: both ? _bible.focus : null,
        onChanged: (v) {
          if (both) _bible.setQuery(v, _libraryFor(v));
          setState(() {});
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: both ? 'Search songs, Bible' : 'Search the library',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear the search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clearSearch,
                ),
        ),
      ),
    );
    if (both && _search.text.trim().isNotEmpty) {
      return [
        field,
        const SizedBox(height: 10),
        ScriptureResults(
          controller: _bible,
          app: c,
          enabled: enabled,
          onLibrary: _chooseLibrary,
          onBible: _chooseBible,
          onBook: (b) {
            _search.text = '$b ';
            _search.selection = TextSelection.collapsed(
              offset: _search.text.length,
            );
            _bible.setQuery(_search.text, _libraryFor(_search.text));
            _bible.focus.requestFocus();
            setState(() {});
          },
        ),
      ];
    }
    final searching = _search.text.trim().isNotEmpty;
    return [
      field,
      if (!searching) _libraryTabs() else const SizedBox(height: 10),
      if (found.isEmpty)
        Padding(
          key: const ValueKey('lyrics-library-empty'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            searching
                ? 'Nothing matches “${_search.text.trim()}”.'
                : _emptyTab(),
            style: TextStyle(color: colors.muted),
          ),
        ),
      for (final item in found)
        _storedRow(item, item.id == current?.id, picked: picked),
    ];
  }

  /// What an empty tab says: what goes there and how to add one.
  String _emptyTab() {
    if (c.lyrics.library.isEmpty) {
      return switch (_kind) {
        'song' =>
          'No songs yet. Add one with + Song; it stays here for every service.',
        'scripture' =>
          'No Bible verses saved yet. Search the Bible above, or add a passage with + Bible verses.',
        'announcement' => 'No announcements yet. Add one with + Announcement.',
        _ =>
          'Nothing stored yet. Add a song, Bible verses or an announcement; they stay here for every service.',
      };
    }
    return switch (_kind) {
      'song' => 'No songs yet. Add one with + Song.',
      'scripture' =>
        'No Bible verses saved yet. Search the Bible above, or add a passage with + Bible verses.',
      _ => 'No announcements yet. Add one with + Announcement.',
    };
  }

  /// Songs, Bible verses, Announcements and All, by their full names.
  /// Where they do not all fit (a phone, large text) the row scrolls
  /// sideways and keeps the chosen tab in view.
  Widget _libraryTabs() {
    final colors = appColors(context);
    const style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontFamily: appFontFamily,
    );
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, space) {
        var words = 0.0;
        for (final t in _tabs) {
          final p = TextPainter(
            text: TextSpan(text: _tabNames[t], style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          words += p.width + 1;
          p.dispose();
        }
        // The space left over, shared out round the names so the tabs
        // fill the row; too little, and the row scrolls instead.
        final share = (space.maxWidth - words) / (_tabs.length * 2);
        final pad = share >= 5 ? math.min(share.floorToDouble(), 16.0) : 10.0;
        return _tabBar(colors, pad);
      },
    );
  }

  Widget _tabBar(AppPalette colors, double pad) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: TabBar(
          key: const ValueKey('lyrics-tabs'),
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerHeight: 0,
          labelPadding: EdgeInsets.symmetric(horizontal: pad),
          padding: EdgeInsets.zero,
          labelColor: colors.text,
          unselectedLabelColor: colors.muted,
          indicatorColor: colors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            for (final t in _tabs)
              Tab(
                key: ValueKey('lyrics-tab-$t'),
                height: 40,
                child: Text(_tabNames[t]!, maxLines: 1, softWrap: false),
              ),
          ],
        ),
      ),
    );
  }

  /// + Song, + Bible verses and + Announcement in one quiet row.
  Widget _addRow() => SlidesAddRow(
    buttons: [
      SlidesAdd(
        'lyrics-add-song',
        '+ Song',
        '+ Song',
        'Add a song',
        enabled ? () => _edit() : null,
      ),
      SlidesAdd(
        'lyrics-add-scripture',
        '+ Bible verses',
        '+ Verses',
        'Add Bible verses',
        enabled ? () => _edit(null, 'scripture') : null,
      ),
      SlidesAdd(
        'lyrics-add-announcement',
        '+ Announcement',
        '+ Notice',
        'Add an announcement',
        enabled ? () => _edit(null, 'announcement') : null,
      ),
    ],
  );

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
            // Built again as the search, the tab or the library changes:
            // the sheet is not rebuilt with the page.
            child: ListenableBuilder(
              listenable: Listenable.merge([c, _search, _tab]),
              builder: (sheet, _) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheet).height * .85,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _label('Library'),
                    ..._stored(picked: () => Navigator.pop(sheet)),
                    const SizedBox(height: 12),
                    _addRow(),
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

  /// The chosen item's title, with its line from the list under it.
  Widget _slidesHeader() {
    final item = selected;
    if (item == null) return _label('Slides');
    final colors = appColors(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                key: const ValueKey('lyrics-slides-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
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

  /// One quiet line under the slides: the keys on a computer, how to use
  /// the slides on a touch screen.
  Widget _tip() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: widget.desktop
        ? const SlidesKeysLine()
        : Text(
            'Tap a slide to show it. The dashed slide is next.',
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

  /// The screens the slides go to, as the Screens row lists them.
  List<String> _targetNames() {
    final look = c.lyrics.look;
    return [
      if (look.toSecond) widget.desktop ? 'Second screen' : 'Full screen',
      if (look.toWeb) 'Web screens',
      if (look.toStage) 'Stage screens',
    ];
  }

  /// One line, never wrapped: what is on the screens and where in it.
  Widget _status() {
    final l = c.lyrics, colors = appColors(context);
    final on = l.showing;
    final item = l.item, index = l.index;
    final where = item != null && index != null && item.slides.length > 1
        ? ' · ${index + 1} of ${item.slides.length}'
        : '';
    final nowhere = on && _targetNames().isEmpty ? ' · on no screen' : '';
    final text = l.black
        ? 'Black on the screens$nowhere'
        : on
        ? '${l.statusLine}$where$nowhere'
        : c.state.session.active
        ? 'Showing the countdown'
        : 'No slide on the screens';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on && !l.black ? colors.error : colors.muted,
              boxShadow: on && !l.black
                  ? [
                      BoxShadow(
                        color: colors.error.withValues(alpha: .25),
                        spreadRadius: 3,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('lyrics-status'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _previous() => c.lyrics.previous(selected: c.lyrics.selectedId);
  void _next() => c.lyrics.next(selected: c.lyrics.selectedId);

  /// Previous, Next, Clear and Black, in one row.
  Widget _controls() {
    final l = c.lyrics;
    return SlidesTransport(
      enabled: enabled,
      showing: l.showing,
      black: l.black,
      keyHints: widget.keyHints,
      onPrevious: _previous,
      onNext: _next,
      onClear: l.clear,
      onBlack: l.toggleBlack,
    );
  }

  /// On a narrow screen, the four controls along the bottom, under the
  /// thumb.
  Widget _bar() {
    final colors = appColors(context);
    final finish = finishLook(context).active;
    final bar = Material(
      color: finish ? Colors.transparent : colors.surface,
      child: Container(
        key: const ValueKey('lyrics-bar'),
        decoration: finish
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: _controls(),
      ),
    );
    // On a finish the bar is a plate of the material across the window.
    return finish
        ? FinishPane(strip: true, seams: finishSeamAbove, child: bar)
        : bar;
  }

  // ---- Send to and the look ------------------------------------------------------------

  void _setLook(LyricsLook next) => unawaited(c.lyrics.setLook(next));

  /// Screens, Background and Look: one row each, with a hairline
  /// between, each opening in place. Background and Look are closed to
  /// begin with and stay as this device left them.
  List<Widget> _rows({bool first = false}) {
    final l = c.lyrics, look = l.look, colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final second = c.secondScreen;
    final secondShut =
        widget.desktop && second != null && look.toSecond && !second.host.open;
    final names = _targetNames();
    return [
      if (!first) const SlidesHairline(),
      SlidesFold(
        key: const ValueKey('lyrics-screens-row'),
        name: 'Screens',
        value: names.isEmpty ? 'None chosen' : names.join(' · '),
        valueColor: names.isEmpty ? colors.warning : null,
        action: 'Change',
        open: _screensOpen,
        onToggle: () => setState(() => _screensOpen = !_screensOpen),
        body: _sendTo(muted),
      ),
      // Said even with the row closed: the slides are not being seen.
      if (secondShut)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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
      const SlidesHairline(),
      SlidesFold(
        key: const ValueKey('lyrics-background-row'),
        name: 'Background',
        value: lyricBackgroundName(look.background),
        swatch: LyricBackgroundSwatch(
          key: const ValueKey('lyrics-bg-swatch'),
          thumb: LyricBackgroundTile.thumb(look.background),
        ),
        open: _open.contains('background'),
        onToggle: () => _toggle('background'),
        body: _backgrounds(muted),
      ),
      const SlidesHairline(),
      SlidesFold(
        key: const ValueKey('lyrics-look'),
        name: 'Look',
        value: lyricLookSummary(look),
        open: _open.contains('look'),
        onToggle: () => _toggle('look'),
        body: _lookControls(muted),
      ),
    ];
  }

  /// The Screens row's choices: where the slides go, and what each
  /// screen does with them.
  Widget _sendTo(TextStyle muted) {
    final look = c.lyrics.look;
    Widget tick(
      String key,
      String name,
      bool on,
      LyricsLook Function(bool v) change,
    ) => FilterChip(
      key: ValueKey('lyrics-send-$key'),
      label: Text(name),
      selected: on,
      onSelected: enabled ? (v) => _setLook(change(v)) : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            tick(
              'second',
              widget.desktop ? 'Second screen' : 'Full screen',
              look.toSecond,
              (v) => look.copyWith(toSecond: v),
            ),
            tick(
              'web',
              'Web screens',
              look.toWeb,
              (v) => look.copyWith(toWeb: v),
            ),
            tick(
              'stage',
              'Stage screens',
              look.toStage,
              (v) => look.copyWith(toStage: v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            look.toStage
                ? 'Stage screens show the slide in place of the speaker’s countdown.'
                : 'Stage screens keep the speaker’s countdown.',
            if (look.toSecond)
              widget.desktop
                  ? 'Full screen and the stage simulator follow the second screen.'
                  : 'Full screen and the stage simulator show the slide.',
            'The LED sign never shows slides.',
          ].join(' '),
          key: const ValueKey('lyrics-send-note'),
          style: muted,
        ),
      ],
    );
  }

  /// The background picker: a chip for each group, then its pictures.
  Widget _backgrounds(TextStyle muted) {
    final l = c.lyrics, look = l.look;
    final custom = look.background.startsWith('custom:');
    final group = _bgGroup ?? lyricBackgroundGroup(look.background);
    const groups = {
      'designs': 'Designs',
      'nature': 'Nature',
      'people': 'People',
      'yours': 'Your picture',
    };
    return Column(
      key: const ValueKey('lyrics-backgrounds'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in groups.entries)
              ChoiceChip(
                key: ValueKey('lyrics-bg-group-${g.key}'),
                label: Text(g.value),
                selected: group == g.key,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: const TextStyle(fontSize: 12.5),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _bgGroup = g.key),
              ),
          ],
        ),
        const SizedBox(height: 10),
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
            return Wrap(
              key: ValueKey('lyrics-bg-tiles-$group'),
              spacing: gap,
              runSpacing: gap,
              children: switch (group) {
                'nature' || 'people' => [
                  for (final p in lyricPhotos)
                    if (p.kind == group) tile('photo:${p.id}', p.title),
                ],
                'yours' => [
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
                ],
                _ => [
                  for (final e in lyricDrawnBackgrounds.entries)
                    tile(e.key, e.value),
                ],
              },
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
      ],
    );
  }

  /// The Look row's controls: Dim, text size, alignment, motion and the
  /// countdown in the corner, one to a line, the name on the left.
  Widget _lookControls(TextStyle muted) {
    final look = c.lyrics.look;
    final dim = _dimming ?? look.dim.toDouble();
    Widget option(String name, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [Text(name), control],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Dim'),
            Expanded(
              child: Slider(
                key: const ValueKey('lyrics-dim'),
                value: look.darkInk ? 0 : dim,
                min: 0,
                max: 90,
                divisions: 18,
                label: '${dim.round()}%',
                semanticFormatterCallback: (v) => '${v.round()}%',
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
        option(
          'Text size',
          _segments('size', look.size, const {
            's': 'S',
            'm': 'M',
            'l': 'L',
          }, (v) => look.copyWith(size: v)),
        ),
        option(
          'Align',
          _segments('align', look.align, const {
            'center': 'Centre',
            'left': 'Left',
          }, (v) => look.copyWith(align: v)),
        ),
        option(
          'Motion',
          _segments('motion', look.motion, const {
            'still': 'Still',
            'gentle': 'Gentle',
          }, (v) => look.copyWith(motion: v)),
        ),
        MergeSemantics(
          child: Row(
            children: [
              const Expanded(child: Text('Countdown in the corner')),
              Switch(
                key: const ValueKey('lyrics-chip-toggle'),
                value: look.chip,
                onChanged: enabled
                    ? (v) => _setLook(look.copyWith(chip: v))
                    : null,
              ),
            ],
          ),
        ),
        if (look.chip)
          Text(
            'A small countdown stays on the slide while a service runs.',
            style: muted,
          ),
      ],
    );
  }

  Widget _segments(
    String key,
    String value,
    Map<String, String> options,
    LyricsLook Function(String v) change,
  ) => SegmentedButton<String>(
    key: ValueKey('lyrics-$key'),
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: [
      for (final e in options.entries)
        ButtonSegment(value: e.key, label: Text(e.value)),
    ],
    selected: {value},
    onSelectionChanged: enabled ? (v) => _setLook(change(v.single)) : null,
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
                ExcludeSemantics(child: thumb(id)),
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

  /// A still copy of background [id], cut to whatever box holds it.
  static Widget thumb(String id) {
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
