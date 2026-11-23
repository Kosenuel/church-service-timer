import 'dart:math' as math;

import 'package:church_service_timer/domain/core.dart';
import 'package:church_service_timer/domain/stage_output.dart';

/// What a group of screens can show, by the name the snapshot carries,
/// with the words the Screens panel uses: the four countdown layouts
/// ([stageLayouts]), the slide on the screens, and the confidence monitor
/// (the slide's words beside the countdown).
const screenShows = {
  ...stageLayouts,
  'slides': 'Slides',
  'monitor': 'Slides and timer',
};

/// Whether [show] puts the slide on the screens: Slides, or Slides and
/// timer.
bool showsSlides(String show) => show == 'slides' || show == 'monitor';

/// A group's choice from saved data; anything unknown is 'timer'.
String screenShowValue(dynamic value) =>
    screenShows.containsKey(value) ? value as String : 'timer';

/// The fields of a stage snapshot that a cue changes: what a screen whose
/// group does not show cues takes from the snapshot without the cue.
const stageCueKeys = {
  'displayText',
  'displayIsTimer',
  'outputMode',
  'effect',
  'screenEffect',
  'speed',
  'screenSpeed',
  'cueColor',
  'screenWrap',
  'screenWords',
  'cuePosition',
  'underText',
  'underMode',
  'bold',
  'italic',
  'cueTotalMs',
  'cueLeftMs',
  'clockFace',
  'afterEnd',
};

/// The most groups and scenes kept, and the longest name either may have.
const screenGroupLimit = 12, screenSceneLimit = 24, screenNameLimit = 40;

/// The screen key of this device's own stage picture: the second screen
/// window on a PC, host Full screen and the stage simulator.
const thisScreenKey = 'this';

/// The screen key of a paired phone or tablet, by its saved identity.
String pairedScreenKey(String id) => 'pair:$id';

/// A short id kept for life.
String newScreenId(String prefix, [math.Random? random]) {
  final r = random ?? math.Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return '$prefix${List.generate(8, (_) => chars[r.nextInt(chars.length)]).join()}';
}

/// A name for a group or scene: trimmed, 1 to [screenNameLimit] characters
/// with no control characters.
String screenNameValue(dynamic value, String label) {
  require(value is String, '$label must be text.');
  final s = (value as String).trim();
  require(
    s.isNotEmpty &&
        s.runes.length <= screenNameLimit &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(s),
    'Give the $label a name of 1–$screenNameLimit characters.',
  );
  return s;
}

/// A named group of screens and the one thing they all show.
class ScreenGroup {
  final String id, name;

  /// One of [screenShows].
  final String show;

  /// The countdown layout shown while [show] is Slides or Slides and timer
  /// and no slide is up: the last of [stageLayouts] the group showed.
  final String fallback;

  /// "Shows cues": the screens face the person speaking, so they show
  /// stage cues, warning cues and quick messages. Off, they never do (a
  /// screen facing the congregation). It says who looks at the screens,
  /// not what the moment needs, so scenes leave it alone.
  final bool cues;
  const ScreenGroup(
    this.id,
    this.name,
    this.show, {
    this.fallback = 'timer',
    this.cues = false,
  });

  /// The countdown layout the group's screens use now: its choice, or for
  /// slides its fallback. Every screen, however old, knows these four.
  String get layout => stageLayouts.containsKey(show) ? show : fallback;

  ScreenGroup withShow(String next) => ScreenGroup(
    id,
    name,
    next,
    fallback: stageLayouts.containsKey(next) ? next : fallback,
    cues: cues,
  );
  ScreenGroup renamed(String next) =>
      ScreenGroup(id, next, show, fallback: fallback, cues: cues);
  ScreenGroup withCues(bool on) =>
      ScreenGroup(id, name, show, fallback: fallback, cues: on);

  Json toJson() => {
    'id': id,
    'name': name,
    'show': show,
    'fallback': fallback,
    'cues': cues,
  };

  static ScreenGroup? tryRead(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'];
    if (id is! String || !_idPattern.hasMatch(id) || name is! String) {
      return null;
    }
    try {
      final show = screenShowValue(j['show']);
      return ScreenGroup(
        id,
        screenNameValue(name, 'group'),
        show,
        fallback: stageLayouts.containsKey(show)
            ? show
            : stageLayoutValue(j['fallback']),
        cues: j['cues'] == true,
      );
    } on RuleError {
      return null;
    }
  }
}

final _idPattern = RegExp(r'^[a-z0-9-]{1,24}$');

/// What every group showed when the scene was saved, applied in one tap.
class ScreenScene {
  final String id, name;

  /// Group id to what it shows, for the groups that existed when saved.
  final Map<String, String> shows;
  const ScreenScene(this.id, this.name, this.shows);

  ScreenScene renamed(String next) => ScreenScene(id, next, shows);

  Json toJson() => {'id': id, 'name': name, 'shows': shows};

  static ScreenScene? tryRead(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], shows = j['shows'];
    if (id is! String || !_idPattern.hasMatch(id) || shows is! Map) {
      return null;
    }
    try {
      return ScreenScene(id, screenNameValue(name, 'scene'), {
        for (final e in shows.entries)
          if (e.key is String &&
              _idPattern.hasMatch(e.key as String) &&
              screenShows.containsKey(e.value))
            e.key as String: e.value as String,
      });
    } on RuleError {
      return null;
    }
  }
}

/// The groups, the scenes and which group each screen of this device is
/// in. Immutable: every change returns a new setup, checked, so a draft
/// state can take it whole.
class ScreenSetup {
  final List<ScreenGroup> groups;
  final String defaultGroup;
  final List<ScreenScene> scenes;

  /// Screen key ([thisScreenKey], [pairedScreenKey]) to group id. On this
  /// device only: not in backups.
  final Map<String, String> members;
  ScreenSetup({
    required List<ScreenGroup> groups,
    required String defaultGroup,
    List<ScreenScene> scenes = const [],
    Map<String, String> members = const {},
  }) : groups = List.unmodifiable(groups),
       scenes = List.unmodifiable(scenes),
       members = Map.unmodifiable(members),
       defaultGroup = groups.any((g) => g.id == defaultGroup)
           ? defaultGroup
           : groups.first.id {
    require(groups.isNotEmpty, 'Keep at least one group.');
  }

  ScreenGroup? byId(String? id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  ScreenScene? sceneById(String? id) {
    for (final s in scenes) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The scene a segment names: by id, else by name (so a program made on
  /// another device finds a scene of the same name here), else null.
  ScreenScene? sceneFor(String id, String name) {
    final byId = sceneById(id);
    if (byId != null) return byId;
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final s in scenes) {
      if (s.name.toLowerCase() == wanted) return s;
    }
    return null;
  }

  ScreenGroup get defaultOne => byId(defaultGroup)!;

  /// The group [screen] is in: its own, or the default group when it has
  /// none or its group was deleted. Never more than one.
  ScreenGroup groupOf(String screen) => byId(members[screen]) ?? defaultOne;

  /// A group id named by a screen (a browser's remembered group), when it
  /// still exists; otherwise the default group.
  ScreenGroup groupNamed(String? id) => byId(id) ?? defaultOne;

  ScreenSetup _with({
    List<ScreenGroup>? groups,
    String? defaultGroup,
    List<ScreenScene>? scenes,
    Map<String, String>? members,
  }) => ScreenSetup(
    groups: groups ?? this.groups,
    defaultGroup: defaultGroup ?? this.defaultGroup,
    scenes: scenes ?? this.scenes,
    members: members ?? this.members,
  );

  ScreenGroup _group(String id) {
    final g = byId(id);
    require(g != null, 'That group no longer exists.');
    return g!;
  }

  void _uniqueName(String name, Iterable<String> taken, String label) =>
      require(
        !taken.any((t) => t.toLowerCase() == name.toLowerCase()),
        'There is already a $label called “$name”.',
      );

  /// [group] shows [show], every screen in it at once.
  ScreenSetup withShow(String group, String show) {
    require(screenShows.containsKey(show), 'Choose what the group shows.');
    final g = _group(group);
    return _with(
      groups: [for (final x in groups) x.id == g.id ? x.withShow(show) : x],
    );
  }

  /// Whether [group]'s screens show cues.
  ScreenSetup withCues(String group, bool on) {
    final g = _group(group);
    return _with(
      groups: [for (final x in groups) x.id == g.id ? x.withCues(on) : x],
    );
  }

  /// [screen] moves to [group].
  ScreenSetup moved(String screen, String group) {
    _group(group);
    return _with(members: {...members, screen: group});
  }

  /// [screen] forgotten, as when its pairing is forgotten.
  ScreenSetup without(String screen) =>
      _with(members: {...members}..remove(screen));

  ScreenSetup added(String name, {required String id, String show = 'timer'}) {
    require(
      groups.length < screenGroupLimit,
      'Keep at most $screenGroupLimit groups.',
    );
    final clean = screenNameValue(name, 'group');
    _uniqueName(clean, groups.map((g) => g.name), 'group');
    require(byId(id) == null && _idPattern.hasMatch(id), 'Try again.');
    return _with(
      groups: [...groups, ScreenGroup(id, clean, screenShowValue(show))],
    );
  }

  ScreenSetup renamed(String group, String name) {
    final g = _group(group);
    final clean = screenNameValue(name, 'group');
    _uniqueName(
      clean,
      groups.where((x) => x.id != g.id).map((x) => x.name),
      'group',
    );
    return _with(
      groups: [for (final x in groups) x.id == g.id ? x.renamed(clean) : x],
    );
  }

  /// Deletes [group]: its screens are then in the default group (another
  /// group becomes the default when it was the default). The last group
  /// stays. Scenes forget it.
  ScreenSetup deleted(String group) {
    final g = _group(group);
    require(groups.length > 1, 'Keep at least one group.');
    final rest = [
      for (final x in groups)
        if (x.id != g.id) x,
    ];
    final nextDefault = defaultGroup == g.id ? rest.first.id : defaultGroup;
    return _with(
      groups: rest,
      defaultGroup: nextDefault,
      members: {
        for (final e in members.entries)
          if (e.value != g.id) e.key: e.value,
      },
      scenes: [
        for (final s in scenes)
          ScreenScene(s.id, s.name, {...s.shows}..remove(g.id)),
      ],
    );
  }

  ScreenSetup withDefault(String group) =>
      _with(defaultGroup: _group(group).id);

  /// What every group shows now.
  Map<String, String> get current => {for (final g in groups) g.id: g.show};

  ScreenSetup sceneSaved(String name, {required String id}) {
    require(
      scenes.length < screenSceneLimit,
      'Keep at most $screenSceneLimit scenes.',
    );
    final clean = screenNameValue(name, 'scene');
    _uniqueName(clean, scenes.map((s) => s.name), 'scene');
    require(sceneById(id) == null && _idPattern.hasMatch(id), 'Try again.');
    return _with(scenes: [...scenes, ScreenScene(id, clean, current)]);
  }

  ScreenScene _scene(String id) {
    final s = sceneById(id);
    require(s != null, 'That scene no longer exists.');
    return s!;
  }

  /// [scene] now remembers what every group shows now.
  ScreenSetup sceneUpdated(String scene) {
    final s = _scene(scene);
    return _with(
      scenes: [
        for (final x in scenes)
          x.id == s.id ? ScreenScene(x.id, x.name, current) : x,
      ],
    );
  }

  ScreenSetup sceneRenamed(String scene, String name) {
    final s = _scene(scene);
    final clean = screenNameValue(name, 'scene');
    _uniqueName(
      clean,
      scenes.where((x) => x.id != s.id).map((x) => x.name),
      'scene',
    );
    return _with(
      scenes: [for (final x in scenes) x.id == s.id ? x.renamed(clean) : x],
    );
  }

  ScreenSetup sceneDeleted(String scene) {
    final s = _scene(scene);
    return _with(
      scenes: [
        for (final x in scenes)
          if (x.id != s.id) x,
      ],
    );
  }

  /// Every group [scene] lists shows what it says; other groups, and
  /// groups deleted since it was saved, are left alone.
  ScreenSetup sceneApplied(ScreenScene scene) => _with(
    groups: [
      for (final g in groups)
        if (scene.shows[g.id] case final show?) g.withShow(show) else g,
    ],
  );

  /// Whether the groups show what [scene] says, for every group it lists
  /// that still exists (and it lists at least one).
  bool sceneShowing(ScreenScene scene) {
    var any = false;
    for (final g in groups) {
      final show = scene.shows[g.id];
      if (show == null) continue;
      if (show != g.show) return false;
      any = true;
    }
    return any;
  }

  Json toJson() => {
    'groups': [for (final g in groups) g.toJson()],
    'default': defaultGroup,
    'scenes': [for (final s in scenes) s.toJson()],
    'members': members,
  };

  /// What a backup carries: groups and scenes, never which screen of this
  /// device is in which group.
  Json toBackupJson() => toJson()..remove('members');

  /// Reads saved groups; null when there are none to read (data from
  /// before groups, or nothing usable), and the caller migrates.
  static ScreenSetup? tryRead(dynamic j) {
    if (j is! Map) return null;
    final seenIds = <String>{}, seenNames = <String>{};
    final groups = <ScreenGroup>[
      for (final raw in (j['groups'] is List ? j['groups'] as List : const []))
        if (ScreenGroup.tryRead(raw) case final g?)
          if (seenIds.add(g.id) && seenNames.add(g.name.toLowerCase())) g,
    ].take(screenGroupLimit).toList();
    if (groups.isEmpty) return null;
    final sceneIds = <String>{}, sceneNames = <String>{};
    final scenes = <ScreenScene>[
      for (final raw in (j['scenes'] is List ? j['scenes'] as List : const []))
        if (ScreenScene.tryRead(raw) case final s?)
          if (sceneIds.add(s.id) && sceneNames.add(s.name.toLowerCase())) s,
    ].take(screenSceneLimit).toList();
    final members = <String, String>{
      if (j['members'] case final Map m)
        for (final e in m.entries)
          if (e.key is String &&
              (e.key as String).length <= 100 &&
              e.value is String &&
              seenIds.contains(e.value))
            e.key as String: e.value as String,
    };
    final def = j['default'];
    return ScreenSetup(
      groups: groups,
      defaultGroup: def is String ? def : groups.first.id,
      scenes: scenes,
      members: members,
    );
  }
}

/// One screen's settings from before groups: its countdown layout and
/// whether its Send to box was ticked.
typedef OldScreenChoice = ({String layout, bool slides});

/// The groups made from settings saved before groups existed, so that no
/// screen changes what it shows until the operator changes it (see
/// docs/SCREENS-PANEL-DESIGN.md, Migration):
///
/// - **Room 1**: this device's own picture (the second screen, Full
///   screen, the stage simulator) and the web screens, or only this
///   device, with **Web screens** for the browsers, when the two differed;
/// - **Stage**: the paired phones and tablets, split into **Stage 2**,
///   **Stage 3** ... where they had different choices.
///
/// The group holding the web screens is the default, because every
/// browser joins as a new screen after the update.
ScreenSetup migrateScreens({
  required OldScreenChoice self,
  required OldScreenChoice web,
  required List<({String id, String layout})> paired,
  required bool pairedSlides,
}) {
  String show(OldScreenChoice c) => c.slides ? 'slides' : c.layout;
  // Cues: on for paired stage screens, which face the speaker; off for
  // this device's own screen and web screens, which usually face the room.
  ScreenGroup group(
    String id,
    String name,
    OldScreenChoice c, {
    bool cues = false,
  }) => ScreenGroup(
    id,
    name,
    show(c),
    fallback: stageLayoutValue(c.layout),
    cues: cues,
  );
  final selfChoice = (
    layout: stageLayoutValue(self.layout),
    slides: self.slides,
  );
  final webChoice = (layout: stageLayoutValue(web.layout), slides: web.slides);
  final together = selfChoice == webChoice;
  final groups = <ScreenGroup>[
    group('room', 'Room 1', selfChoice),
    if (!together) group('web', 'Web screens', webChoice),
  ];
  final members = <String, String>{thisScreenKey: 'room'};
  // Paired screens by their choice, the most common first (ties: the one
  // seen first), each choice its own group.
  final order = <String>[];
  final count = <String, int>{};
  for (final p in paired) {
    final layout = stageLayoutValue(p.layout);
    if (!count.containsKey(layout)) order.add(layout);
    count[layout] = (count[layout] ?? 0) + 1;
  }
  final ranked = [...order]
    ..sort((a, b) {
      final byCount = count[b]!.compareTo(count[a]!);
      return byCount != 0 ? byCount : order.indexOf(a) - order.indexOf(b);
    });
  if (ranked.isEmpty) ranked.add('timer');
  final stageIds = <String, String>{};
  for (var i = 0; i < ranked.length && groups.length < screenGroupLimit; i++) {
    final id = i == 0 ? 'stage' : 'stage-${i + 1}';
    stageIds[ranked[i]] = id;
    groups.add(
      group(id, i == 0 ? 'Stage' : 'Stage ${i + 1}', (
        layout: ranked[i],
        slides: pairedSlides,
      ), cues: true),
    );
  }
  for (final p in paired) {
    members[pairedScreenKey(p.id)] =
        stageIds[stageLayoutValue(p.layout)] ?? 'stage';
  }
  return ScreenSetup(
    groups: groups,
    defaultGroup: together ? 'room' : 'web',
    members: members,
  );
}
