import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_backgrounds.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';

/// The screens lyrics can be sent to, as Send to names them.
enum LyricTarget {
  /// This computer's second screen, with its copy on Live, host full
  /// screen and the stage simulator (on a phone: full screen and the
  /// simulator).
  second,

  /// Web Stage displays.
  web,

  /// Paired phones and tablets showing the stage.
  stage,
}

/// What is on the screens from the Lyrics page: the item, the slide and
/// Black. Kept in memory only, so a restart starts with no lyrics showing.
/// Owned by [AppController], which adds [field] to each screen's picture.
class LyricsController {
  final AppController app;
  LyricsController(this.app);

  /// The item chosen on the Lyrics page, whose slides it shows; Next
  /// with nothing on the screens starts it. Kept here so it survives
  /// leaving the page.
  String? selectedId;

  String? _itemId;
  int? _index;
  bool _black = false;

  /// Your picture, once read, for the screens drawn in this app.
  Uint8List? pictureBytes;

  /// Where Your picture is kept on this device, for the second screen.
  String? picturePath;

  LyricsLibrary get library => app.state.lyrics;
  LyricsLook get look => library.look;

  /// The item whose slide is on the screens, if any.
  LyricItem? get item => library.byId(_itemId);

  /// The slide on the screens, if any (also while Black hides it).
  int? get index {
    final i = item, n = _index;
    if (i == null || n == null || n < 0 || n >= i.slides.length) return null;
    return n;
  }

  LyricSlide? get slide => index == null ? null : item!.slides[index!];
  bool get black => _black;

  /// Whether lyrics cover anything on the ticked screens: a slide, or
  /// Black.
  bool get showing => _black || slide != null;

  /// Whether a slide or Black is on at least one screen: showing, and a
  /// Send to box ticked. This is the job the screen is kept awake for.
  bool get onScreens =>
      showing && (look.toSecond || look.toWeb || look.toStage);

  bool sendsTo(LyricTarget target) => switch (target) {
    LyricTarget.second => look.toSecond,
    LyricTarget.web => look.toWeb,
    LyricTarget.stage => look.toStage,
  };

  /// "Amazing Grace · Verse 2" for status lines.
  String get statusLine {
    if (_black) return 'Black';
    final s = slide;
    if (s == null) return '';
    return '${item!.title} · ${s.label}';
  }

  void _changed() {
    app.notifyChanged();
    unawaited(app.pairing.publish());
    // Lyrics on a screen are the job the screen is held awake for.
    unawaited(app.syncScreenAwake());
  }

  /// Puts slide [slideIndex] of [id] on the ticked screens.
  void show(String id, int slideIndex) {
    final i = library.byId(id);
    if (i == null || slideIndex < 0 || slideIndex >= i.slides.length) return;
    final fresh = id != _itemId;
    _itemId = id;
    _index = slideIndex;
    _black = false;
    _changed();
    // Stored songs lists the most recently used first.
    if (fresh) {
      unawaited(
        _commit((draft, at) {
          draft.lyrics = draft.lyrics.usedAt(id, at.wall);
        }),
      );
    }
  }

  /// The next slide of the item showing, or of [selected] when nothing
  /// is: its first slide.
  void next({String? selected}) => _step(1, selected);
  void previous({String? selected}) => _step(-1, selected);

  void _step(int by, String? selected) {
    final current = index;
    final id = current == null ? selected : _itemId;
    final i = library.byId(id);
    if (i == null || i.slides.isEmpty) {
      if (_black) {
        _black = false;
        _changed();
      }
      return;
    }
    if (current == null) {
      if (by > 0) show(i.id, 0);
      return;
    }
    show(i.id, (current + by).clamp(0, i.slides.length - 1));
  }

  /// Takes lyrics off every screen: each goes back to what it shows
  /// without them.
  void clear() {
    if (!showing && _itemId == null) return;
    _itemId = null;
    _index = null;
    _black = false;
    _changed();
  }

  /// Black on the ticked screens; again brings the slide back.
  void toggleBlack() {
    _black = !_black;
    _changed();
  }

  /// Keeps what is showing in step with the library after an edit or a
  /// delete: a deleted item leaves the screens; an edited one keeps its
  /// place where it still can.
  void libraryChanged() {
    if (_itemId != null && item == null) {
      _itemId = null;
      _index = null;
    }
  }

  // ---- What screens get --------------------------------------------------

  /// The background [target] gets: Your picture is not sent to paired
  /// stage screens in phase 1, which show Midnight instead.
  String backgroundFor(LyricTarget target) {
    final bg = look.background;
    if (bg.startsWith('custom:') &&
        (target == LyricTarget.stage || pictureBytes == null)) {
      return lyricPictureStandIn;
    }
    if (bg.startsWith('photo:') && !lyricPhotoIds.contains(bg.substring(6))) {
      return lyricPictureStandIn;
    }
    return bg;
  }

  /// The `lyrics` field for [target]'s picture, or null when nothing is
  /// showing or [target] is not ticked. Older screens ignore it and keep
  /// showing the countdown.
  Json? field(LyricTarget target, {bool always = false}) {
    if (!app.ready || !showing || (!always && !sendsTo(target))) return null;
    final s = app.state.session, now = app.now;
    final bg = backgroundFor(target);
    final slide = this.slide;
    return {
      'v': 1,
      'key': '$_itemId:${index ?? -1}:$_black',
      if (_black)
        'black': true
      else ...{
        'kind': item!.kind,
        ...slide!.toJson(),
      },
      'bg': bg,
      if (target == LyricTarget.second &&
          bg.startsWith('custom:') &&
          picturePath != null)
        'picture': picturePath,
      'dim': look.dim,
      'size': look.size,
      'align': look.align,
      'motion': look.moving,
      // A small countdown on the slide while a service runs.
      if (look.chip && s.active) ...{
        'chip': s.overtime(now) > 0
            ? '+${formatTime(s.overtime(now))}'
            : s.formatted(now),
        'chipOver': s.overtime(now) > 0,
      },
    };
  }

  /// What the panel's preview shows: the slide as the second screen
  /// gets it, whatever is ticked, so the operator always sees it.
  Json? previewField() =>
      field(LyricTarget.second, always: true)?..remove('picture');

  /// Adds [target]'s `lyrics` field to [data], or takes it away.
  Json decorate(Json data, LyricTarget target) {
    final f = field(target);
    if (f == null) {
      data.remove('lyrics');
    } else {
      data['lyrics'] = f;
    }
    return data;
  }

  // ---- Saving --------------------------------------------------------------

  /// Saves after any save already under way, so a change made just after
  /// putting a slide up (which notes the song as used) is never dropped.
  Future<bool> _commit(void Function(AppState draft, Stamp at) change) async {
    for (var i = 0; i < 50 && app.busy; i++) {
      await (app.pendingWrite ??
          Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    return app.commit(change);
  }

  Future<bool> setLook(LyricsLook next) async {
    if (jsonEncode(next.toJson()) == jsonEncode(look.toJson())) return true;
    final saved = await _commit(
      (draft, _) => draft.lyrics = draft.lyrics.withLook(next),
    );
    if (saved) _changed();
    return saved;
  }

  /// Saves [item], new or edited; false with [AppController.error] set
  /// when it cannot be.
  Future<bool> save(LyricItem item) async {
    final saved = await _commit((draft, at) {
      draft.lyrics = draft.lyrics.saved(item.copyWith(updated: at.wall));
    });
    if (saved) {
      libraryChanged();
      _changed();
    }
    return saved;
  }

  Future<bool> delete(String id) async {
    final saved = await _commit(
      (draft, _) => draft.lyrics = draft.lyrics.without(id),
    );
    if (saved) {
      libraryChanged();
      _changed();
    }
    return saved;
  }

  // ---- Your picture --------------------------------------------------------

  /// Reads Your picture from this device, if one was kept.
  Future<void> loadPicture() async {
    try {
      final bytes = await app.port.loadLyricPicture();
      pictureBytes = LyricPictureSource.bytes = bytes;
      picturePath = bytes == null ? null : await app.port.lyricPicturePath();
    } catch (_) {
      pictureBytes = null;
      picturePath = null;
    }
  }

  /// Picks a picture, keeps it on this device and makes it the
  /// background. Returns false when nothing was picked or it failed.
  Future<bool> pickPicture() async {
    final picked = await app.port.pickChurchPhoto();
    if (picked == null) return false;
    final bytes = base64Decode(picked);
    await app.port.saveLyricPicture(bytes);
    pictureBytes = LyricPictureSource.bytes = bytes;
    picturePath = await app.port.lyricPicturePath();
    // A new name each time, so every screen sees it is a new picture.
    var hash = 0;
    for (var i = 0; i < bytes.length; i += 97) {
      hash = (hash * 31 + bytes[i]) & 0x7fffffff;
    }
    return setLook(
      look.copyWith(
        background:
            'custom:${hash.toRadixString(36)}${bytes.length.toRadixString(36)}',
      ),
    );
  }
}
