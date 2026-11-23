/// Everything the app saves: programs, reports, settings and the session.
library;

import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';

class AppState {
  AppearancePreferences appearance;
  ProgramLibrary programLibrary;
  String clockFormat;
  bool clockBlink;
  int notificationClearSeconds;
  PrintPreferences printPreferences;
  Map<String, Json> editDrafts;

  /// Earlier versions of saved programs by program ID, newest first.
  Map<String, List<ProgramRevision>> programHistory;

  /// Programs sent from other phones, waiting for review.
  List<ReceivedProgram> programInbox;

  /// Reusable segments to insert into any program, newest first.
  List<Segment> segmentLibrary;

  /// Record performance metrics during the next service (Diagnostics).
  /// Switches itself off when that service ends.
  bool recordMetrics;

  /// Battery use (% per hour) in this phone's last measured recording; the
  /// next report marks against it. Local only.
  double? metricsBatteryBaseline;

  /// Column mappings chosen for imported spreadsheets, by header row, so
  /// next week's sheet in the same layout imports in one tap. Local only.
  Map<String, Json> importMappings;

  /// Web screen settings (order-of-service access and code, speakers, the
  /// .local name). Local only; see WebStageSettings.
  Json webStage;
  String? outputDestination;
  List<QuickMessage> quickMessages;
  List<Timeline> templates;
  DisplaySettings defaults;
  Session session;
  List<ServiceReport> reports;
  List<TextLayout> stageCues;
  String pixelShape;
  bool groupTemplates;
  String churchName, themeId, churchBanner;

  /// Layout and theme combinations saved under a name.
  List<SavedLook> savedLooks;

  /// The church's square logo, shown at the top left of every page in
  /// place of the built-in mark; empty for the built-in mark.
  String churchLogo;

  /// Whether the screen is kept awake while a service is running. Off is
  /// "Never"; on is "While a service is running", or "Always" with
  /// [keepScreenAlways]. Kept as a plain switch so older versions can
  /// still read the saved data.
  bool keepScreenAwake;

  /// Hold the screen awake whenever the app is open, running or not. Local
  /// to this device; not part of portable backups.
  bool keepScreenAlways;

  /// The three choices as one value: 'never', 'service' or 'always'.
  String get screenAwake => !keepScreenAwake
      ? 'never'
      : keepScreenAlways
      ? 'always'
      : 'service';
  set screenAwake(String value) {
    require(
      screenAwakeChoices.contains(value),
      'Choose a screen-awake option.',
    );
    keepScreenAwake = value != 'never';
    keepScreenAlways = value == 'always';
  }

  /// Show the service with Pause and Next on the lock-screen notification.
  /// Local to this phone; not part of portable backups.
  bool lockScreenControls;

  /// Optional Settings PIN; never included in backups.
  SettingsLock? settingsLock;

  /// Presentation clickers and foot pedals drive Next and Pause on Live.
  bool clickerControls;

  /// What Full screen on Live shows on this device's own screen: 'timer',
  /// 'current' or 'next'. A PC uses its second screen's choice instead.
  /// Local to this phone; not part of backups.
  String fullScreenLayout;

  /// What the Simulator stands in for when it is the display: 'led', an
  /// LED sign, or 'stage', a stage screen. Local to this phone; not part
  /// of backups.
  String simulatorKind;

  /// How strongly stage screens show overtime: 'gentle', 'strong' or
  /// 'strongest', as [overtimeAlerts] names them. Kept on this device
  /// with the other stage display choices; not part of backups.
  String overtimeAlert;

  /// What the Simulator shows under the time while it stands in for a
  /// stage screen: 'timer', 'current' or 'next'. Local to this phone; not
  /// part of backups.
  String simulatorLayout;

  /// When guided practice was last finished on this phone, and whether
  /// Live still offers it. Local to this phone; not part of backups.
  int? practisedWall;
  bool practicePrompt;

  /// Approved stage screens may send fixed requests (Need 2 minutes, Ready
  /// to finish, Microphone issue). Off by default; local to this phone.
  bool stageRequests;

  /// One-time hints this phone has dismissed, such as "press and hold to
  /// select". Local to this phone; not part of portable backups.
  Set<String> dismissedHints;

  /// The last few Quick timers, newest first. Local to this phone.
  List<QuickTimerChoice> recentQuickTimers;

  /// Check for updates automatically, and what that last found. Local to
  /// this device; not part of backups.
  AutoUpdateSettings autoUpdate;

  /// The app version the "what's new" notice on Live was last dealt with
  /// for (x.y.z or x.y.z-pre), or null when nothing was seen. Local to this
  /// device; not part of backups.
  String? seenVersion;

  /// Stored songs, Bible verses and announcements, and how their slides
  /// look and where they go. In backups (except Your picture).
  LyricsLibrary lyrics;

  /// The groups of stage screens, their scenes and which group each
  /// screen of this device is in (see docs/SCREENS-PANEL-DESIGN.md). Null
  /// in data saved before groups, until the app migrates it at start.
  /// Groups and scenes are in backups when there are scenes; which screen
  /// is in which group stays on this device.
  ScreenSetup? screens;
  AppState(
    this.templates,
    this.defaults,
    this.session, {
    this.clockFormat = '24h',
    this.clockBlink = true,
    List<ServiceReport>? reports,
    List<TextLayout>? stageCues,
    this.pixelShape = 'square',
    this.groupTemplates = true,
    this.churchName = '',
    this.churchBanner = '',
    this.churchLogo = '',
    this.themeId = 'midnight_lime',
    List<SavedLook>? savedLooks,
    this.keepScreenAwake = true,
    this.keepScreenAlways = false,
    this.lockScreenControls = true,
    this.settingsLock,
    this.clickerControls = true,
    this.fullScreenLayout = 'timer',
    this.simulatorKind = 'led',
    this.simulatorLayout = 'timer',
    this.overtimeAlert = 'strong',
    this.practisedWall,
    this.practicePrompt = true,
    this.stageRequests = false,
    Set<String>? dismissedHints,
    List<QuickTimerChoice>? recentQuickTimers,
    AutoUpdateSettings? autoUpdate,
    this.seenVersion,
    this.lyrics = const LyricsLibrary(),
    this.screens,
    this.outputDestination,
    List<QuickMessage>? quickMessages,
    this.appearance = const AppearancePreferences(),
    this.notificationClearSeconds = 30,
    this.printPreferences = const PrintPreferences(),
    Map<String, Json>? editDrafts,
    ProgramLibrary? programLibrary,
    Map<String, List<ProgramRevision>>? programHistory,
    List<ReceivedProgram>? programInbox,
    List<Segment>? segmentLibrary,
    this.recordMetrics = false,
    this.metricsBatteryBaseline,
    Map<String, Json>? importMappings,
    Json? webStage,
  }) : webStage = webStage ?? {},
       autoUpdate = autoUpdate ?? AutoUpdateSettings(),
       dismissedHints = dismissedHints ?? {},
       savedLooks = savedLooks ?? [],
       recentQuickTimers = recentQuickTimers ?? [],
       importMappings = importMappings ?? {},
       segmentLibrary = segmentLibrary ?? [],
       programLibrary = programLibrary ?? ProgramLibrary(),
       programHistory = programHistory ?? {},
       programInbox = programInbox ?? [],
       editDrafts = editDrafts ?? {},
       reports = reports ?? [],
       quickMessages = quickMessages ?? [...defaultQuickMessages],
       stageCues = stageCues ?? [...defaults.cues] {
    ensureProgramIds();
  }

  /// Gives every saved program an ID and moves name-keyed pins, recents
  /// and unsaved edits over to it. Programs saved before IDs existed get a
  /// repeatable ID from their name.
  void ensureProgramIds() {
    if (templates.every((t) => t.id.isNotEmpty) &&
        templates.map((t) => t.id).toSet().length == templates.length)
      return;
    final taken = <String>{};
    final byName = <String, String>{};
    templates = [
      for (final t in templates)
        () {
          var id = t.id.isEmpty || taken.contains(t.id)
              ? legacyProgramId(t.name)
              : t.id;
          for (var n = 2; taken.contains(id); n++) {
            id = '${legacyProgramId(t.name)}-$n';
          }
          taken.add(id);
          byName[t.name] = id;
          return t.id == id ? t : t.withId(id);
        }(),
    ];
    final lib = programLibrary;
    String? key(String k) => taken.contains(k) ? k : byName[k];
    final pins = {...lib.favourites.map(key).nonNulls};
    final recent = <String, int>{
      for (final e in lib.recent.entries) ?key(e.key): e.value,
    };
    lib.favourites
      ..clear()
      ..addAll(pins);
    lib.recent
      ..clear()
      ..addAll(recent);
    for (final k in editDrafts.keys.toList()) {
      if (!k.startsWith('program:') || k == 'program:new') continue;
      final id = key(k.substring(8));
      final draft = editDrafts.remove(k);
      if (id != null && draft != null) editDrafts['program:$id'] = draft;
    }
    void link(Session? s) {
      final t = s?.timeline;
      if (s == null || t == null) return;
      if (t.id.isEmpty && byName[t.name] != null)
        s.timeline = t.withId(byName[t.name]!);
      link(s.prior);
    }

    link(session);
  }

  factory AppState.fresh(Stamp now) => AppState(
    [
      Timeline('Sunday Service', const [
        Segment('Praise & Worship', 15),
        Segment('Announcements', 5),
        Segment('Sermon', 30),
        Segment('Closing', 5),
      ], DisplaySettings()),
      Timeline(
        'Quick rehearsal',
        const [
          Segment('Welcome', 1),
          Segment('Message', 2),
          Segment('Closing', 1),
        ],
        DisplaySettings(),
        type: 'rehearsal',
      ),
    ],
    DisplaySettings(),
    Session(id: 'idle', anchor: now),
  );
  factory AppState.fromJson(Json j, {Stamp? now}) {
    require(
      {
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      }.contains(j['version']),
      'Unsupported saved-state version.',
    );
    require(
      {'square', 'circular'}.contains(j['pixelShape'] ?? 'square'),
      'Invalid simulator LED shape.',
    );
    require(
      j['groupTemplates'] == null || j['groupTemplates'] is bool,
      'Invalid program grouping preference.',
    );
    final a = AppState(
      (j['templates'] as List)
          .map((e) => Timeline.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      DisplaySettings.fromJson(Map<String, dynamic>.from(j['defaults'])),
      Session.fromJson(Map<String, dynamic>.from(j['session'])),
      clockFormat: readClockFormat(j['clockFormat'] ?? '24h'),
      clockBlink: boolSetting(j['clockBlink'] ?? true),
      appearance: AppearancePreferences.fromJson(
        Map<String, dynamic>.from(j['appearance'] ?? {}),
      ),
      programLibrary: ProgramLibrary.fromJson(
        Map<String, dynamic>.from(j['programLibrary'] ?? {}),
      ),
      outputDestination: j['outputDestination'] as String?,
      notificationClearSeconds: notificationTimeoutValue(
        j['notificationClearSeconds'] ?? 30,
      ),
      printPreferences: PrintPreferences.fromJson(
        Map<String, dynamic>.from(j['printPreferences'] ?? {}),
      ),
      editDrafts: readEditDrafts(j['editDrafts']),
      programHistory: readProgramHistory(j['programHistory']),
      programInbox: readReceivedPrograms(j['programInbox']),
      segmentLibrary: readSegmentLibrary(j['segmentLibrary']),
      recordMetrics: j['recordMetrics'] == true,
      metricsBatteryBaseline: (j['metricsBatteryBaseline'] as num?)?.toDouble(),
      webStage: Map<String, dynamic>.from(j['webStage'] as Map? ?? {}),
      importMappings: {
        for (final e in (j['importMappings'] as Map? ?? {}).entries)
          if (e.key is String && e.value is Map)
            e.key as String: Map<String, dynamic>.from(e.value as Map),
      },
      quickMessages: (j['quickMessages'] as List?)
          ?.map((e) => QuickMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      pixelShape: j['pixelShape'] ?? 'square',
      groupTemplates: (j['version'] as int) < 9
          ? true
          : j['groupTemplates'] ?? true,
      churchName: churchNameValue(j['churchName'] ?? ''),
      churchBanner: churchBannerValue(j['churchBanner'] ?? ''),
      churchLogo: churchLogoValue(j['churchLogo'] ?? ''),
      themeId: themeIdValue(j['themeId'] ?? 'midnight_lime'),
      savedLooks: readSavedLooks(j['savedLooks']),
      keepScreenAwake: boolSetting(j['keepScreenAwake'] ?? true),
      keepScreenAlways: boolSetting(j['keepScreenAlways'] ?? false),
      lockScreenControls: boolSetting(j['lockScreenControls'] ?? true),
      settingsLock: j['settingsLock'] == null
          ? null
          : SettingsLock.fromJson(Map<String, dynamic>.from(j['settingsLock'])),
      clickerControls: boolSetting(j['clickerControls'] ?? true),
      fullScreenLayout: stageLayoutValue(j['fullScreenLayout']),
      simulatorKind: simulatorKindValue(j['simulatorKind']),
      simulatorLayout: stageLayoutValue(j['simulatorLayout']),
      overtimeAlert: overtimeAlertValue(j['overtimeAlert']),
      practisedWall: j['practisedWall'] is int
          ? j['practisedWall'] as int
          : null,
      practicePrompt: boolSetting(j['practicePrompt'] ?? true),
      stageRequests: boolSetting(j['stageRequests'] ?? false),
      dismissedHints: {
        for (final h in (j['dismissedHints'] as List? ?? const []))
          if (h is String && h.length <= 40) h,
      },
      recentQuickTimers: [
        for (final r in (j['recentQuickTimers'] as List? ?? const []))
          ?QuickTimerChoice.tryRead(r),
      ].take(quickTimerRecentLimit).toList(),
      autoUpdate: AutoUpdateSettings.fromJson(j['autoUpdate']),
      seenVersion: readSeenVersion(j['seenVersion']),
      // Missing in saved data from before lyrics: an empty library.
      lyrics: LyricsLibrary.fromJson(j['lyrics']),
      // Missing in saved data from before groups: migrated at start.
      screens: ScreenSetup.tryRead(j['screens']),
      reports: (j['reports'] as List? ?? [])
          .map((e) => ServiceReport.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      stageCues: j['stageCues'] == null
          ? null
          : (j['stageCues'] as List)
                .map((e) => TextLayout.fromJson(Map<String, dynamic>.from(e)))
                .toList(),
    );
    require(
      a.outputDestination == null ||
          {'led', 'mobile', 'simulator'}.contains(a.outputDestination),
      'Invalid display destination.',
    );
    require(
      a.quickMessages.length <= 50,
      'Keep at most 50 quick message presets.',
    );
    require(
      a.templates.map((t) => t.name.toLowerCase()).toSet().length ==
          a.templates.length,
      'Saved programs contain duplicate names.',
    );
    if (j['stageCues'] == null) {
      // Keep customized cues from every old location, including the old library.
      a.stageCues = [];
      a.addStageCues([
        ...?a.session.timeline?.display.cues,
        ...a.defaults.cues,
        ...a.templates.expand((t) => t.display.cues),
        ...(j['savedCues'] as List? ?? []).map(
          (e) => TextLayout.fromJson(Map<String, dynamic>.from(e['layout'])),
        ),
      ]);
    }
    if ((j['version'] as int) < 3) {
      DisplaySettings upgrade(DisplaySettings d) {
        final oldSuggested =
            d.warnings.length == 3 &&
            d.warnings.every(
              (w) =>
                  w.destination == 'operator' &&
                  legacyDefaultWarnings.any(
                    (v) => v.seconds == w.seconds && v.cue.text == w.cue.text,
                  ),
            );
        return oldSuggested
            ? d.withWarnings(
                d.warnings
                    .map(
                      (w) => WarningRule(
                        w.seconds,
                        w.cue,
                        enabled: w.enabled,
                        destination: 'stage',
                      ),
                    )
                    .toList(),
              )
            : d;
      }

      a.defaults = upgrade(a.defaults);
      a.templates = a.templates
          .map((t) => t.withDisplay(upgrade(t.display)))
          .toList();
      void upgradeSession(Session s) {
        final t = s.timeline;
        if (t != null) s.timeline = t.withDisplay(upgrade(t.display));
        if (s.prior != null) upgradeSession(s.prior!);
      }

      upgradeSession(a.session);
    }
    if ((j['version'] as int) < 4) {
      DisplaySettings upgradeEnd(DisplaySettings d) =>
          jsonEncode(d.end?.toJson()) ==
              jsonEncode(const TextLayout('Hallelujah').toJson())
          ? d.withEnd(defaultEndScreen)
          : d;
      a.defaults = upgradeEnd(a.defaults);
      a.templates = a.templates
          .map((t) => t.withDisplay(upgradeEnd(t.display)))
          .toList();
    }
    if ((j['version'] as int) < 9) {
      // Upgrade once: retain the most recently added WRAP UP style and retire
      // the requested stock cue. Later explicit user-created cues are retained.
      var keptWrap = false;
      a.stageCues = a.stageCues.reversed
          .where((cue) {
            final name = cue.text.trim().toUpperCase();
            if (name == 'NURSERY CALL') return false;
            if (name != 'WRAP UP') return true;
            if (keptWrap) return false;
            return keptWrap = true;
          })
          .toList()
          .reversed
          .toList();
    }
    if ((j['version'] as int) < 16) a.upgradeDefaultCues();
    a.session.clockFormat = a.clockFormat;
    a.session.clockBlink = a.clockBlink;
    a.applySharedZero();
    a.applySharedWarnings(now);
    return a;
  }
  Json toJson() => {
    'version': 16,
    'appearance': appearance.toJson(),
    'programLibrary': programLibrary.toJson(),
    'programHistory': writeProgramHistory(programHistory),
    'programInbox': [for (final p in programInbox) p.toJson()],
    'segmentLibrary': [for (final s in segmentLibrary) s.toJson()],
    'recordMetrics': recordMetrics,
    'metricsBatteryBaseline': metricsBatteryBaseline,
    'importMappings': importMappings,
    'webStage': webStage,
    'clockFormat': clockFormat,
    'clockBlink': clockBlink,
    'notificationClearSeconds': notificationClearSeconds,
    'printPreferences': printPreferences.toJson(),
    'editDrafts': editDrafts,
    'outputDestination': outputDestination,
    'quickMessages': quickMessages.map((e) => e.toJson()).toList(),
    'templates': templates.map((t) => t.toJson()).toList(),
    'defaults': defaults.toJson(),
    'session': session.toJson(),
    'reports': reports.map((e) => e.toJson()).toList(),
    'stageCues': stageCues.map((e) => e.toJson()).toList(),
    'pixelShape': pixelShape,
    'groupTemplates': groupTemplates,
    'churchName': churchName,
    'churchBanner': churchBanner,
    'churchLogo': churchLogo,
    'themeId': themeId,
    'savedLooks': [for (final l in savedLooks) l.toJson()],
    'keepScreenAwake': keepScreenAwake,
    'keepScreenAlways': keepScreenAlways,
    'lockScreenControls': lockScreenControls,
    if (practisedWall != null) 'practisedWall': practisedWall,
    'practicePrompt': practicePrompt,
    'stageRequests': stageRequests,
    'dismissedHints': [...dismissedHints],
    'recentQuickTimers': [for (final r in recentQuickTimers) r.toJson()],
    'autoUpdate': autoUpdate.toJson(),
    if (seenVersion != null) 'seenVersion': seenVersion,
    if (!lyrics.isEmpty ||
        lyrics.lastUsed.isNotEmpty ||
        jsonEncode(lyrics.look.toJson()) !=
            jsonEncode(const LyricsLook().toJson()))
      'lyrics': lyrics.toJson(),
    if (screens != null) 'screens': screens!.toJson(),
    'settingsLock': settingsLock?.toJson(),
    'clickerControls': clickerControls,
    'fullScreenLayout': fullScreenLayout,
    'simulatorKind': simulatorKind,
    'simulatorLayout': simulatorLayout,
    'overtimeAlert': overtimeAlert,
  };
  AppState copy() => AppState.fromJson(toJson());

  /// The default At Zero is authoritative, including for a loaded service.
  /// End screens remain owned by each template / loaded snapshot.
  void applySharedZero() {
    Timeline normalize(Timeline t) =>
        t.withDisplay(t.display.withZero(defaults.zero));
    templates = templates.map(normalize).toList();
    void normalizeSession(Session s) {
      if (s.timeline != null) s.timeline = normalize(s.timeline!);
      if (s.prior != null) normalizeSession(s.prior!);
    }

    normalizeSession(session);
  }

  /// Replaces the stage cues and warnings installs started with before
  /// version 15 ([legacyDefaultStageCues], [legacyDefaultWarnings]) with
  /// today's [defaultStageCues] and [defaultWarnings]. It goes by what is
  /// saved, not only the version, because every backup is read as an
  /// earlier version: a cue list holding any of the old cues gets the new
  /// ones first, followed by the church's own cues (except any with the
  /// text of a new one, such as an old WRAP UP restyled), and warnings
  /// exactly as they were suggested become the new ones. Warnings that
  /// were changed stay as they are, and so does a cue list without any of
  /// the old cues.
  ///
  /// The cues and warnings version 15 started with
  /// ([version15DefaultStageCues], [version15DefaultWarnings]) become
  /// today's in their place, each one only if it is still exactly as
  /// version 15 made it.
  void upgradeDefaultCues() {
    String json(TextLayout l) => jsonEncode(l.toJson());
    final legacy = legacyDefaultStageCues.map(json).toSet();
    if (stageCues.any((l) => legacy.contains(json(l)))) {
      final replaced = {for (final c in defaultStageCues) c.text.toUpperCase()};
      final own = stageCues
          .where(
            (l) =>
                !legacy.contains(json(l)) &&
                !replaced.contains(l.text.trim().toUpperCase()),
          )
          .toList();
      stageCues = [];
      addStageCues([...defaultStageCues, ...own]);
      if (stageCues.length > 100) stageCues = stageCues.sublist(0, 100);
    }
    final version15 = {
      for (var i = 0; i < version15DefaultStageCues.length; i++)
        json(version15DefaultStageCues[i]): defaultStageCues[i],
    };
    List<TextLayout> renewed(List<TextLayout> cues) => [
      for (final l in cues) version15[json(l)] ?? l,
    ];
    final cues = renewed(stageCues);
    stageCues = [];
    addStageCues(cues);
    String list(List<TextLayout> cues) => cues.map(json).join('|');
    DisplaySettings upgrade(DisplaySettings d) =>
        list(d.cues) == list(legacyDefaultStageCues)
        ? d.withCues(defaultStageCues)
        : d.withCues(renewed(d.cues));
    templates = [for (final t in templates) t.withDisplay(upgrade(t.display))];
    void upgradeSession(Session s) {
      final t = s.timeline;
      if (t != null) s.timeline = t.withDisplay(upgrade(t.display));
      if (s.prior != null) upgradeSession(s.prior!);
    }

    upgradeSession(session);
    String rule(WarningRule r) => jsonEncode(r.toJson());
    String rules(List<WarningRule> w) =>
        jsonEncode([for (final r in w) r.toJson()]);
    defaults = upgrade(defaults);
    if (rules(defaults.warnings) == rules(legacyDefaultWarnings))
      defaults = defaults.withWarnings(defaultWarnings);
    final version15Rules = {
      for (var i = 0; i < version15DefaultWarnings.length; i++)
        rule(version15DefaultWarnings[i]): defaultWarnings[i],
    };
    defaults = defaults.withWarnings([
      for (final r in defaults.warnings) version15Rules[rule(r)] ?? r,
    ]);
  }

  void addStageCues(Iterable<TextLayout> layouts) {
    final seen = stageCues.map((l) => jsonEncode(l.toJson())).toSet();
    for (final layout in layouts) {
      if (seen.add(jsonEncode(layout.toJson()))) stageCues.add(layout);
    }
  }

  /// Settings owns warning rules. Re-map consumed thresholds rather than
  /// indexes so editing/reordering cannot replay an old warning after undo.
  void applySharedWarnings([Stamp? now]) {
    final rules = defaults.warnings;
    Timeline normalize(Timeline t) =>
        t.withDisplay(t.display.withWarnings(rules));
    templates = templates.map(normalize).toList();
    void apply(Session s) {
      final old = s.timeline?.display.warnings;
      if (old != null &&
          jsonEncode(old.map((w) => w.toJson()).toList()) !=
              jsonEncode(rules.map((w) => w.toJson()).toList())) {
        final at = now ?? s.checkpoint;
        List<int> remap(List<int> indexes, int? remaining) {
          final consumed = indexes
              .where((i) => i >= 0 && i < old.length)
              .map((i) => old[i].seconds)
              .toSet();
          return rules
              .asMap()
              .entries
              .where(
                (e) =>
                    consumed.contains(e.value.seconds) ||
                    (remaining != null && e.value.seconds * 1000 >= remaining),
              )
              .map((e) => e.key)
              .toList();
        }

        s.warningSeen = remap(s.warningSeen, s.active ? s.remaining(at) : null);
        if (s.undo != null) {
          final u = s.undo!.toJson();
          u['warningSeen'] = remap(s.undo!.warningSeen, s.undoRemaining(at));
          s.undo = UndoPoint.fromJson(u);
        }
        // A rule change affects future triggers; an in-flight cue finishes normally.
        s.timeline = normalize(s.timeline!);
      }
      if (s.prior != null) apply(s.prior!);
    }

    apply(session);
  }

  /// Saves [t] as a new program, or over the program at [replacing]. With
  /// [replacedAt], the replaced version is kept in its history.
  void saveTemplate(Timeline t, {int? replacing, int? replacedAt}) {
    validateProgramDuration(t);
    t = t.withDisplay(
      t.display.withZero(defaults.zero).withWarnings(defaults.warnings),
    );
    require(
      !templates.asMap().entries.any(
        (e) =>
            e.key != replacing &&
            e.value.name.toLowerCase() == t.name.toLowerCase(),
      ),
      'A program named "${t.name}" already exists. Rename it before saving.',
    );
    if (replacing == null) {
      // A program from elsewhere, or a copy, gets an ID of its own.
      final taken = templates.map((p) => p.id).toSet();
      var id = t.id;
      while (id.isEmpty || taken.contains(id)) {
        id = newProgramId();
      }
      templates.add(t.withId(id));
    } else {
      // Edits keep the program's identity, so pins and history follow it.
      final previous = templates[replacing];
      templates[replacing] = t.withId(previous.id);
      if (replacedAt != null) recordVersion(previous.id, previous, replacedAt);
    }
  }

  /// The saved program with [id], if it still exists.
  Timeline? programById(String id) {
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Identify the reviewed saved template, never a stale list position.
  int templateIndex(Timeline expected) {
    final index = templates.indexWhere(
      (t) =>
          expected.id.isEmpty ? t.name == expected.name : t.id == expected.id,
    );
    require(
      index >= 0 &&
          jsonEncode(templates[index].toJson()) ==
              jsonEncode(expected.toJson()),
      'This program changed. Return to Programs and review it again.',
    );
    return index;
  }

  Timeline duplicateTemplate(Timeline expected) {
    final original = templates[templateIndex(expected)];
    var count = 1;
    String candidate;
    do {
      final suffix = count == 1 ? ' (copy)' : ' (copy $count)';
      candidate =
          '${String.fromCharCodes(original.name.runes.take(80 - suffix.length))}$suffix';
      count++;
    } while (templates.any(
      (t) => t.name.toLowerCase() == candidate.toLowerCase(),
    ));
    final copy = Timeline.fromJson(
      original.toJson(),
    ).renamed(candidate).withId('');
    saveTemplate(copy);
    return templates.last;
  }

  void deleteTemplate(Timeline expected) {
    final removed = templates.removeAt(templateIndex(expected));
    programLibrary.remove(removed.id);
    programHistory.remove(removed.id);
  }
}
