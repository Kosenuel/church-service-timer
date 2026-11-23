import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/bible_loader.dart';
import 'package:church_service_timer/lyrics/ready_tray.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// The search index of the bundled Bible, built once in a background
/// isolate the first time it is needed and kept for the session.
/// Translations other than the KJV are indexed the same way when they are
/// added (see docs/LYRICS-DESIGN.md).
class ScriptureIndex {
  ScriptureIndex._();

  static final state = ValueNotifier<ScriptureIndexState>(
    ScriptureIndexState.idle,
  );
  static final _indexes = <String, Future<BibleSearchIndex>>{};
  static final _ready = <String, BibleSearchIndex>{};

  /// How long the last build took, for the tests and the design note.
  static Duration? lastBuild;

  /// The index of [code], built on the first call. Safe to call at once
  /// from anywhere; the build runs once.
  static Future<BibleSearchIndex> load([String code = 'KJV']) =>
      _indexes[code] ??= _build(code);

  /// The index of [code] if it has been built.
  static BibleSearchIndex? of([String code = 'KJV']) => _ready[code];

  static Future<BibleSearchIndex> _build(String code) async {
    state.value = ScriptureIndexState.preparing;
    final sw = Stopwatch()..start();
    try {
      final asset = BibleLibrary.bundled[code];
      if (asset == null) throw RuleError('The $code is not on this device.');
      final data = await rootBundle.load(asset);
      final bytes = Uint8List.sublistView(data);
      final index = await Isolate.run(() => buildIndexFromGzip(bytes));
      // The same parsed text serves the lookups, so it is read only once.
      BibleLibrary.adopt(index.bible);
      _ready[code] = index;
      lastBuild = sw.elapsed;
      state.value = ScriptureIndexState.ready;
      return index;
    } catch (e) {
      _indexes.remove(code);
      state.value = ScriptureIndexState.failed;
      rethrow;
    }
  }

  /// Uses [index] as the search index of its translation, without
  /// reading the asset: for tests, which build it once from the file.
  @visibleForTesting
  static void useForTest(BibleSearchIndex index) {
    _indexes[index.code] = Future.value(index);
    _ready[index.code] = index;
    BibleLibrary.adopt(index.bible);
    state.value = ScriptureIndexState.ready;
  }

  @visibleForTesting
  static void resetForTest() {
    _indexes.clear();
    _ready.clear();
    state.value = ScriptureIndexState.idle;
  }
}

enum ScriptureIndexState { idle, preparing, ready, failed }

/// Reads a gzipped `CSTBIBLE` file and indexes it. A top-level function so
/// it can run in an isolate.
BibleSearchIndex buildIndexFromGzip(Uint8List gz) =>
    BibleSearchIndex.build(Bible.parse(utf8.decode(gzip.decode(gz))));

/// One line of the unified results: a Library item or a Bible passage.
class SearchEntry {
  final LyricItem? item;
  final SearchHit? hit;
  const SearchEntry.library(LyricItem this.item) : hit = null;
  const SearchEntry.bible(SearchHit this.hit) : item = null;
  bool get isBible => hit != null;
}

/// The Slides page's search box state: what was typed, what it found and
/// which result is highlighted. One box searches the Library and the
/// Bible; the results are grouped, Library then Bible (the Bible first
/// when the text reads as a reference).
class ScriptureSearchController extends ChangeNotifier {
  final AppController app;
  ScriptureSearchController(this.app) {
    _requests = ScriptureSearchFocus.requests;
    _requests.addListener(_requested);
    ScriptureIndex.state.addListener(_indexChanged);
    if (ScriptureSearchFocus.takePending()) {
      // Asked for before the page was built (Commands, from another page).
      scheduleMicrotask(_requested);
    }
  }
  late final ValueNotifier<int> _requests;

  /// Holds the keyboard for the box on a wide page.
  final focus = FocusNode(debugLabel: 'Bible search');

  /// On a narrow page, how the box is opened (a full-height sheet);
  /// null on a wide one, where the box itself is focused.
  VoidCallback? openSheet;

  String _query = '';
  String get query => _query;
  var _limit = 30;
  var _highlight = 0;
  SearchResult? _result;
  List<LyricItem> _library = const [];
  bool _showAllLibrary = false;

  /// How long the last search took, in microseconds.
  int lastMicros = 0;

  SearchResult? get result => _result;
  int get highlight => _highlight;
  bool get active => _query.trim().isNotEmpty;
  bool get preparing =>
      ScriptureIndex.state.value == ScriptureIndexState.preparing ||
      (active && ScriptureIndex.of() == null && !failed);
  bool get failed => ScriptureIndex.state.value == ScriptureIndexState.failed;

  /// Library items shown in the Library group.
  static const libraryRows = 4;

  /// The Library items the text finds (the page supplies the matcher: it
  /// is the library's own search).
  List<LyricItem> get libraryHits =>
      _showAllLibrary ? _library : _library.take(libraryRows).toList();
  int get libraryTotal => _library.length;
  bool get moreLibrary => !_showAllLibrary && _library.length > libraryRows;

  void showAllLibrary() {
    _showAllLibrary = true;
    notifyListeners();
  }

  /// The lines in the order they are drawn, which Up and Down walk.
  List<SearchEntry> get entries {
    final lib = [for (final i in libraryHits) SearchEntry.library(i)];
    final bible = [
      for (final h in _result?.hits ?? const <SearchHit>[])
        SearchEntry.bible(h),
    ];
    return (_result?.byReference ?? false)
        ? [...bible, ...lib]
        : [...lib, ...bible];
  }

  /// Whether the Bible group goes above the Library group.
  bool get bibleFirst => _result?.byReference ?? false;

  /// Starts building the index, so it is ready by the first keystroke.
  void prepare() {
    if (ScriptureIndex.state.value == ScriptureIndexState.idle ||
        ScriptureIndex.state.value == ScriptureIndexState.failed) {
      unawaited(ScriptureIndex.load().then((_) {}, onError: (_) {}));
    }
  }

  void _indexChanged() {
    if (_query.trim().isNotEmpty) _run();
    notifyListeners();
  }

  /// Sets the text, with the Library items it finds, and searches.
  void setQuery(String text, List<LyricItem> library) {
    _query = text;
    _library = library;
    _limit = 30;
    _highlight = 0;
    _showAllLibrary = false;
    _run();
    notifyListeners();
  }

  void showMore() {
    _limit += 30;
    _run();
    notifyListeners();
  }

  bool get hasMore => (_result?.total ?? 0) > (_result?.hits.length ?? 0);

  void _run() {
    final index = ScriptureIndex.of();
    if (!active) {
      _result = null;
      return;
    }
    if (index == null) {
      prepare();
      _result = null;
      return;
    }
    final sw = Stopwatch()..start();
    _result = index.search(_query, limit: _limit);
    lastMicros = sw.elapsedMicroseconds;
    final n = entries.length;
    if (_highlight >= n) _highlight = n == 0 ? 0 : n - 1;
  }

  void clear() {
    _query = '';
    _result = null;
    _library = const [];
    _highlight = 0;
    notifyListeners();
  }

  void move(int by) {
    final n = entries.length;
    if (n == 0) return;
    _highlight = (_highlight + by).clamp(0, n - 1);
    notifyListeners();
  }

  void highlightAt(int i) {
    if (i == _highlight) return;
    _highlight = i;
    notifyListeners();
  }

  /// The highlighted line, if any.
  SearchEntry? get current {
    final e = entries;
    return _highlight < e.length ? e[_highlight] : null;
  }

  /// Takes a Bible hit to the tray; with [send] puts it on the screens.
  /// Returns the tray's entry.
  ReadyPassage? addToReady(SearchHit hit, {bool send = false}) {
    final index = ScriptureIndex.of();
    if (index == null) return null;
    final BibleReading reading;
    try {
      reading = index.bible.read(referenceText(hit.passage));
    } on RuleError {
      return null;
    }
    final tray = ReadyTray.of(app);
    final entry = tray.addReady(reading);
    if (send) tray.send(app, entry.number);
    return entry;
  }

  void _requested() {
    ScriptureSearchFocus.takePending();
    if (openSheet != null) {
      openSheet!();
    } else {
      focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _requests.removeListener(_requested);
    ScriptureIndex.state.removeListener(_indexChanged);
    focus.dispose();
    super.dispose();
  }
}

/// Asks the Slides page to put the keyboard in the search box (or open
/// the search sheet on a phone): from the `/` and Ctrl+F keys and from
/// Commands.
class ScriptureSearchFocus {
  ScriptureSearchFocus._();
  static final requests = ValueNotifier<int>(0);
  static var _pending = false;

  /// Asks now; if the page is not showing, the next page built answers.
  static void request({bool pageShowing = true}) {
    _pending = !pageShowing;
    requests.value++;
  }

  static bool takePending() {
    final p = _pending;
    _pending = false;
    return p;
  }
}

/// Whether [key] opens the Bible search on the Slides page: `/` while no
/// field has the keyboard, and Ctrl+F always.
bool isScriptureSearchKey(
  LogicalKeyboardKey key, {
  required bool control,
  required bool typing,
}) =>
    (control && key == LogicalKeyboardKey.keyF) ||
    (!control && !typing && key == LogicalKeyboardKey.slash);
