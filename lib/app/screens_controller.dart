import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';

/// One stage screen as the Screens panel lists it.
class StageScreenInfo {
  /// [thisScreenKey], `pair:<id>` or `web:<token>`.
  final String key;

  /// 'this', 'paired' or 'web'.
  final String kind;

  /// The device's own name; empty for this device, which the panel names.
  final String name;
  final bool connected;

  /// A paired screen whose app is too old for Slides and timer: it shows
  /// the countdown instead.
  final bool olderApp;
  const StageScreenInfo({
    required this.key,
    required this.kind,
    required this.name,
    required this.connected,
    this.olderApp = false,
  });
}

/// Groups of stage screens, what each shows and the scenes that set them
/// all (see docs/SCREENS-PANEL-DESIGN.md). Owned by [AppController]: it
/// keeps [AppState.screens], migrates settings from before groups, and
/// adds to each screen's picture what its group shows.
class ScreensController {
  final AppController app;
  ScreensController(this.app);

  ScreenSetup? _provisional;

  /// The groups and scenes: as saved, or before the first save, as the
  /// migration makes them from the old settings.
  ScreenSetup get setup => app.state.screens ?? (_provisional ??= migrated());

  /// The groups made from this device's settings from before groups.
  ScreenSetup migrated() {
    final look = app.state.lyrics.look;
    return migrateScreens(
      self: (
        layout: app.secondScreen?.layout ?? app.state.fullScreenLayout,
        slides: look.toSecond,
      ),
      web: (layout: app.webStageSettings.stageLayout, slides: look.toWeb),
      paired: [
        for (final d in app.pairing.savedDevices)
          if (d.role != 'operator') (id: d.id, layout: d.layout),
      ],
      pairedSlides: look.toStage,
    );
  }

  /// Saves the groups made from the old settings, once, at start: after
  /// the second screen's settings and the pairing memory are read.
  Future<void> migrate() async {
    if (app.state.screens != null) return;
    final made = _provisional = migrated();
    await app.commit((draft, _) => draft.screens ??= made);
  }

  // ---- Which screen is where --------------------------------------------

  WebDevice? _web(String key) =>
      key.startsWith('web:') ? app.webStage.devices[key.substring(4)] : null;

  /// The group [key] is in. A web screen's group is the one its browser
  /// named, or the default group.
  ScreenGroup groupOf(String key) {
    if (key.startsWith('web:')) return setup.groupNamed(_web(key)?.group);
    return setup.groupOf(key);
  }

  /// The group the web screens join when their browser names none.
  ScreenGroup get webDefault => setup.defaultOne;

  /// Every stage screen of this service: this device, saved paired phones
  /// and tablets (not operators), and web Stage displays that joined.
  List<StageScreenInfo> get screens {
    final synced = app.webStage.syncedStageDevices.toSet();
    return [
      StageScreenInfo(
        key: thisScreenKey,
        kind: 'this',
        name: '',
        connected:
            app.port.stageOutput?.connected == true || app.stageSimulator,
      ),
      for (final d in app.pairing.savedDevices)
        if (d.role != 'operator')
          () {
            final peer = app.pairing.peerFor(d.id);
            final on = peer != null && peer.connected && peer.viewingStage;
            return StageScreenInfo(
              key: pairedScreenKey(d.id),
              kind: 'paired',
              name: d.name,
              connected: on,
              olderApp: on && !peer.features.contains(confidenceMonitorFeature),
            );
          }(),
      for (final d in app.webStage.devices.values)
        if (d.role == WebRole.stage)
          StageScreenInfo(
            key: 'web:${d.token}',
            kind: 'web',
            name: d.label,
            connected: synced.contains(d),
          ),
    ];
  }

  List<StageScreenInfo> membersOf(String group) => [
    for (final s in screens)
      if (groupOf(s.key).id == group) s,
  ];

  /// The groups showing slides now, Slides or Slides and timer.
  List<ScreenGroup> get slideGroups => [
    for (final g in setup.groups)
      if (showsSlides(g.show)) g,
  ];

  /// Whether a slide put up now reaches a screen: a group with a screen
  /// in it shows Slides or Slides and timer. The screen is kept awake for
  /// a slide only then.
  bool get slidesReachAScreen {
    final groups = {for (final g in slideGroups) g.id};
    if (groups.isEmpty) return false;
    return screens.any((s) => groups.contains(groupOf(s.key).id));
  }

  /// The scene lit in the panel: every group it lists shows what it says.
  ScreenScene? get showingScene {
    for (final s in setup.scenes) {
      if (setup.sceneShowing(s)) return s;
    }
    return null;
  }

  // ---- What each screen gets ---------------------------------------------

  /// Adds to [data] what [key]'s group shows: `stageLayout` (always one
  /// of the four countdown layouts, so every older screen draws it),
  /// `stageShow`, and for a group showing slides the slide (`lyrics`) or
  /// the confidence monitor (`confidence`). With [slides] false (a phone
  /// following the rundown, not the stage) no slide is added.
  Json decorate(Json data, String key, LyricTarget kind, {bool slides = true}) {
    final group = groupOf(key);
    data['stageLayout'] = group.layout;
    data['stageShow'] = group.show;
    data.remove('lyrics');
    data.remove('confidence');
    // A group whose screens do not show cues gets the picture as it would
    // be without the cue, and no quick message: an older screen draws
    // what it is sent, so it never sees one either.
    final plain = data.remove('plain');
    if (!group.cues) {
      if (data.remove('cue') == true && plain is Map) {
        data.removeWhere((k, _) => stageCueKeys.contains(k));
        data.addAll(Map<String, dynamic>.from(plain));
      }
      if (data.remove('quickMessage') != null) {
        data['blank'] = app.state.session.outputBlank;
      }
      data
        ..remove('messageId')
        ..remove('messageSeen');
    }
    if (!slides) return data;
    final Json? slide = switch (group.show) {
      'slides' => app.lyrics.field(kind),
      'monitor' => app.lyrics.confidenceField(),
      _ => null,
    };
    if (slide != null) {
      data[group.show == 'slides' ? 'lyrics' : 'confidence'] = slide;
    }
    return data;
  }

  // ---- Changes -----------------------------------------------------------

  /// Saves after any save already under way, so a tap mid-service is not
  /// dropped because the timer was saving.
  Future<bool> _commit(ScreenSetup Function(ScreenSetup s) change) async {
    for (var i = 0; i < 50 && app.busy; i++) {
      await (app.pendingWrite ??
          Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    final saved = await app.commit((draft, _) {
      draft.screens = change(draft.screens ?? setup);
    });
    if (saved) _changed();
    return saved;
  }

  void _changed() {
    app.notifyChanged();
    unawaited(app.pairing.publish());
    unawaited(app.syncScreenAwake());
  }

  /// Whether [group]'s screens show cues and quick messages.
  Future<bool> setCues(String group, bool on) =>
      _commit((s) => s.withCues(group, on));

  /// [group] shows [show] on all its screens at once.
  Future<bool> setShow(String group, String show) =>
      _commit((s) => s.withShow(group, show));

  /// Moves [key] to [group]; it shows that group's choice at once.
  Future<bool> move(String key, String group) async {
    final web = _web(key);
    if (key.startsWith('web:')) {
      if (web == null || setup.byId(group) == null) return false;
      // The browser keeps it: the page saves its group and names it when
      // it joins again.
      web.group = group;
      _changed();
      return true;
    }
    return _commit((s) => s.moved(key, group));
  }

  /// Adds a group and returns its id, or null when it was not saved.
  Future<String?> addGroup(String name) async {
    final id = newScreenId('g');
    return await _commit((s) => s.added(name, id: id)) ? id : null;
  }

  Future<bool> renameGroup(String group, String name) =>
      _commit((s) => s.renamed(group, name));

  /// Deletes [group]; its screens go to the default group.
  Future<bool> deleteGroup(String group) => _commit((s) => s.deleted(group));

  Future<bool> setDefault(String group) => _commit((s) => s.withDefault(group));

  /// Saves what every group shows now as a scene; its id, or null.
  Future<String?> saveScene(String name) async {
    final id = newScreenId('s');
    return await _commit((s) => s.sceneSaved(name, id: id)) ? id : null;
  }

  Future<bool> updateScene(String scene) =>
      _commit((s) => s.sceneUpdated(scene));

  Future<bool> renameScene(String scene, String name) =>
      _commit((s) => s.sceneRenamed(scene, name));

  Future<bool> deleteScene(String scene) =>
      _commit((s) => s.sceneDeleted(scene));

  /// Every group the scene lists shows what it says, in one tap.
  Future<bool> applyScene(String scene) => _commit((s) {
    final found = s.sceneById(scene);
    require(found != null, 'That scene no longer exists.');
    return s.sceneApplied(found!);
  });

  /// Applies the scene of the segment [draft] has just moved into, when
  /// that segment names one this device has. Called inside the save of
  /// the move (Start, Next, a jump, Undo), so both happen together.
  void segmentStarted(AppState draft, Session before) {
    final s = draft.session, t = s.timeline;
    if (!s.active || t == null || s.index < 0 || s.index >= t.segments.length) {
      return;
    }
    if (before.active && before.id == s.id && before.index == s.index) return;
    final segment = t.segments[s.index];
    if (!segment.hasScene) return;
    final current = draft.screens ?? setup;
    final scene = current.sceneFor(segment.sceneId, segment.sceneName);
    if (scene == null) return;
    draft.screens = current.sceneApplied(scene);
  }

  /// Forgets a paired screen's group with its pairing.
  Future<void> forget(String key) async {
    if (!setup.members.containsKey(key)) return;
    await _commit((s) => s.without(key));
  }
}
