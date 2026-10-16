import 'dart:convert';
import 'dart:math' as math;

part 'service_features.dart';

typedef Json = Map<String, dynamic>;
const maxRemainingMs = 5999000;
const recoveryLimitMs = 30 * 60 * 1000;

class RuleError implements Exception {
  final String message;
  RuleError(this.message);
  @override
  String toString() => message;
}

void require(bool condition, String message) {
  if (!condition) throw RuleError(message);
}

String nameValue(dynamic value, String label) {
  require(value is String, '$label must be text.');
  final s = (value as String).trim();
  require(
    s.isNotEmpty && s.runes.length <= 80,
    '$label must contain 1–80 characters.',
  );
  return s;
}

void keys(Json j, Set<String> allowed, String context) {
  final extra = j.keys.where((k) => !allowed.contains(k));
  require(
    extra.isEmpty,
    '$context contains unsupported fields: ${extra.join(', ')}. Hardware settings and approvals cannot be imported.',
  );
}

class Stamp {
  final int mono, wall;
  final String boot;
  const Stamp(this.mono, this.wall, this.boot);
  factory Stamp.fromJson(Json j) =>
      Stamp(j['mono'] as int, j['wall'] as int, j['boot'] as String);
  Json toJson() => {'mono': mono, 'wall': wall, 'boot': boot};
  bool sameBoot(Stamp other) =>
      boot != 'unknown' &&
      boot != '-1' &&
      boot == other.boot &&
      mono >= other.mono;
  int since(Stamp other) =>
      math.max(0, sameBoot(other) ? mono - other.mono : wall - other.wall);
}

class TextLayout {
  final String text, effect, align, font;
  final bool bold, italic;
  final int speed, height;
  const TextLayout(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.effect = 'scroll',
    this.align = 'center',
    this.speed = 12,
    this.height = 1,
    this.font = 'cuekeeper_matrix',
  });
  factory TextLayout.fromJson(Json j) {
    keys(j, {
      'text',
      'bold',
      'italic',
      'effect',
      'align',
      'speed',
      'height',
      'font',
    }, 'Text layout');
    require(
      j['text'] is String &&
          j['bold'] is bool &&
          j['italic'] is bool &&
          j['speed'] is int &&
          j['height'] is int,
      'Text layout has missing or invalid fields.',
    );
    final s = TextLayout(
      j['text'],
      bold: j['bold'],
      italic: j['italic'],
      effect: j['effect'],
      align: j['align'],
      speed: j['speed'],
      height: j['height'],
      font: j['font'] ?? 'cuekeeper_matrix',
    );
    s.validate();
    return s;
  }
  void validate() {
    require(displayFontNames.containsKey(font), 'Unknown display font: $font.');
    require(
      text.trim().isNotEmpty && text.runes.length <= 160,
      'Display text must contain 1–160 characters.',
    );
    require(
      {'static', 'scroll', 'flash'}.contains(effect),
      'Unsupported text effect.',
    );
    require(
      {'left', 'center', 'right'}.contains(align),
      'Unsupported alignment.',
    );
    require(
      speed >= 4 && speed <= 24 && (height == 1 || height == 2),
      'Invalid text size or scrolling speed.',
    );
  }

  Json toJson() => {
    'text': text,
    'bold': bold,
    'italic': italic,
    'effect': effect,
    'align': align,
    'speed': speed,
    'height': height,
    'font': font,
  };
}

class DisplaySettings {
  final TextLayout? zero;
  final TextLayout end;
  final List<TextLayout> cues;
  final List<WarningRule> warnings;
  DisplaySettings({
    this.zero,
    this.end = const TextLayout('Hallelujah'),
    List<TextLayout>? cues,
    List<WarningRule>? warnings,
  }) : warnings = List.unmodifiable(warnings ?? defaultWarnings),
       cues = List.unmodifiable(
         cues ??
             const [
               TextLayout('WRAP UP'),
               TextLayout("TIME'S UP"),
               TextLayout('MIC LOW'),
               TextLayout('NURSERY CALL'),
             ],
       );
  factory DisplaySettings.fromJson(Json j) {
    keys(j, {'zero', 'end', 'cues', 'warnings'}, 'Display settings');
    require(
      j.containsKey('zero') && j['end'] is Map && j['cues'] is List,
      'Display settings are incomplete.',
    );
    final c = (j['cues'] as List)
        .map((e) => TextLayout.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    require(c.length >= 4 && c.length <= 6, 'Configure 4–6 quick cues.');
    return DisplaySettings(
      zero: j['zero'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['zero'])),
      end: TextLayout.fromJson(Map<String, dynamic>.from(j['end'])),
      cues: c,
      warnings: readWarnings(j['warnings']),
    );
  }
  DisplaySettings withCues(List<TextLayout> value) =>
      DisplaySettings(zero: zero, end: end, cues: value, warnings: warnings);
  DisplaySettings withWarnings(List<WarningRule> value) =>
      DisplaySettings(zero: zero, end: end, cues: cues, warnings: value);
  Json toJson() => {
    'zero': zero?.toJson(),
    'end': end.toJson(),
    'cues': cues.map((e) => e.toJson()).toList(),
    'warnings': warnings.map((e) => e.toJson()).toList(),
  };
}

class Segment {
  final String name;
  final int minutes;
  const Segment(this.name, this.minutes);
  factory Segment.fromJson(Json j) {
    keys(j, {'name', 'minutes'}, 'Segment');
    require(
      j['minutes'] is int && j['minutes'] >= 1 && j['minutes'] <= 99,
      'Segment duration must be an integer from 1 to 99 minutes.',
    );
    return Segment(nameValue(j['name'], 'Segment name'), j['minutes']);
  }
  Json toJson() => {'name': name, 'minutes': minutes};
}

class Timeline {
  final String name;
  final List<Segment> segments;
  final DisplaySettings display;
  Timeline(this.name, List<Segment> segments, this.display)
    : segments = List.unmodifiable(segments);
  factory Timeline.fromJson(Json j) {
    keys(j, {'schemaVersion', 'name', 'segments', 'display'}, 'Template');
    require(
      j['schemaVersion'] is int && {1, 2}.contains(j['schemaVersion']),
      'Supported template schema versions are 1 and 2.',
    );
    require(j['segments'] is List, 'segments must be a list.');
    final entries = j['segments'] as List;
    require(
      entries.isNotEmpty && entries.length <= 200,
      'A timeline needs 1–200 segments.',
    );
    final segs = <Segment>[];
    for (var i = 0; i < entries.length; i++) {
      try {
        segs.add(Segment.fromJson(Map<String, dynamic>.from(entries[i])));
      } catch (e) {
        throw RuleError('segments[$i]: $e');
      }
    }
    return Timeline(
      nameValue(j['name'], 'Template name'),
      segs,
      DisplaySettings.fromJson(Map<String, dynamic>.from(j['display'])),
    );
  }
  Timeline renamed(String n) =>
      Timeline(nameValue(n, 'Template name'), segments, display);
  Json toJson() => {
    'schemaVersion': 2,
    'name': name,
    'segments': segments.map((s) => s.toJson()).toList(),
    'display': display.toJson(),
  };
}

class UndoPoint {
  final int index, remaining;
  final bool paused, modified;
  final Stamp at;
  final Json? runCheckpoint;
  final List<int> warningSeen;
  final int warningCeiling;
  const UndoPoint(
    this.index,
    this.remaining,
    this.paused,
    this.at, {
    this.modified = false,
    this.runCheckpoint,
    this.warningSeen = const [],
    this.warningCeiling = 0,
  });
  UndoPoint markModified() => UndoPoint(
    index,
    remaining,
    paused,
    at,
    modified: true,
    runCheckpoint: runCheckpoint,
    warningSeen: warningSeen,
    warningCeiling: warningCeiling,
  );
  factory UndoPoint.fromJson(Json j) => UndoPoint(
    j['index'],
    j['remaining'],
    j['paused'],
    Stamp.fromJson(Map<String, dynamic>.from(j['at'])),
    modified: j['modified'],
    runCheckpoint: j['runCheckpoint'] == null
        ? null
        : Map<String, dynamic>.from(j['runCheckpoint']),
    warningSeen: List<int>.from(j['warningSeen'] ?? []),
    warningCeiling: j['warningCeiling'] ?? 0,
  );
  Json toJson() => {
    'index': index,
    'remaining': remaining,
    'paused': paused,
    'at': at.toJson(),
    'modified': modified,
    'runCheckpoint': runCheckpoint,
    'warningSeen': warningSeen,
    'warningCeiling': warningCeiling,
  };
}

class Session {
  String id, phase;
  int revision, index, baseMs;
  bool paused, held, disconnected, uncertain;
  Timeline? timeline;
  TextLayout? alert;
  UndoPoint? undo;
  Stamp anchor, checkpoint;
  Stamp? outage;
  Session? prior;
  int rate, warningCeiling;
  RunMetrics? run;
  List<int> warningSeen;
  String? warningNotice;
  TextLayout? automaticCue;
  Stamp? automaticCueAt;
  Session({
    required this.id,
    required this.anchor,
    this.phase = 'idle',
    this.revision = 0,
    this.index = 0,
    this.baseMs = 0,
    this.paused = false,
    this.held = false,
    this.disconnected = false,
    this.uncertain = false,
    this.timeline,
    this.alert,
    this.undo,
    Stamp? checkpoint,
    this.outage,
    this.prior,
    this.rate = 1,
    this.run,
    List<int>? warningSeen,
    this.warningCeiling = 0,
    this.warningNotice,
    this.automaticCue,
    this.automaticCueAt,
  }) : checkpoint = checkpoint ?? anchor,
       warningSeen = warningSeen ?? [];
  bool get active => phase == 'active';
  int remaining(Stamp now) => phase == 'ready'
      ? baseMs
      : active && !paused
      ? math.max(0, baseMs - now.since(anchor) * rate)
      : baseMs;
  String formatted(Stamp now) => formatTime(remaining(now));
  int undoRemaining(Stamp now) => undo == null
      ? 0
      : undo!.paused
      ? undo!.remaining
      : math.max(0, undo!.remaining - now.since(undo!.at) * rate);
  bool fastUndo(Stamp now) =>
      undo != null &&
      !undo!.modified &&
      !uncertain &&
      now.sameBoot(undo!.at) &&
      now.since(undo!.at) <= 10000;
  TextLayout? intended(Stamp now) {
    if (phase == 'ended') return timeline!.display.end;
    if (!active) return null;
    if (alert != null) return alert;
    if (hasAutomaticCue(now)) return automaticCue;
    if (remaining(now) == 0 && timeline!.display.zero != null)
      return timeline!.display.zero;
    return TextLayout(formatted(now), effect: 'static', height: 2);
  }

  bool get rehearsal => rate > 1;
  bool hasAutomaticCue(Stamp now) =>
      active &&
      automaticCue != null &&
      automaticCueAt != null &&
      now.sameBoot(automaticCueAt!) &&
      now.since(automaticCueAt!) < 8000;
  int get plannedMs =>
      timeline?.segments.fold<int>(0, (n, s) => n + s.minutes * 60000) ?? 0;
  int totalElapsed(Stamp now) => run == null
      ? 0
      : run!.totalMs + (active ? now.since(run!.anchor) * rate : 0);
  int currentElapsed(Stamp now) => run == null
      ? 0
      : run!.currentMs + (active ? now.since(run!.anchor) * rate : 0);
  int projectedTotal(Stamp now) =>
      totalElapsed(now) +
      (active || phase == 'ready'
          ? remaining(now) +
                timeline!.segments
                    .skip(index + 1)
                    .fold<int>(0, (n, s) => n + s.minutes * 60000)
          : 0);
  void settleMetrics(Stamp now) {
    if (!active || run == null) return;
    final elapsed = now.since(run!.anchor) * rate;
    run!.totalMs += elapsed;
    run!.currentMs += elapsed;
    if (paused) run!.pausedMs[index] += elapsed;
    run!.anchor = now;
  }

  String get outputKind => phase == 'ended'
      ? 'End screen'
      : alert != null
      ? 'Alert'
      : 'Countdown';
  factory Session.fromJson(Json j) {
    final s = Session(
      id: j['id'],
      phase: j['phase'],
      revision: j['revision'],
      index: j['index'],
      baseMs: j['baseMs'],
      paused: j['paused'],
      held: j['held'],
      disconnected: j['disconnected'],
      uncertain: j['uncertain'],
      anchor: Stamp.fromJson(Map<String, dynamic>.from(j['anchor'])),
      checkpoint: Stamp.fromJson(Map<String, dynamic>.from(j['checkpoint'])),
      timeline: j['timeline'] == null
          ? null
          : Timeline.fromJson(Map<String, dynamic>.from(j['timeline'])),
      alert: j['alert'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['alert'])),
      undo: j['undo'] == null
          ? null
          : UndoPoint.fromJson(Map<String, dynamic>.from(j['undo'])),
      outage: j['outage'] == null
          ? null
          : Stamp.fromJson(Map<String, dynamic>.from(j['outage'])),
      rate: j['rate'] ?? 1,
      run: j['run'] == null
          ? null
          : RunMetrics.fromJson(Map<String, dynamic>.from(j['run'])),
      warningSeen: List<int>.from(j['warningSeen'] ?? []),
      warningCeiling: j['warningCeiling'] ?? 0,
      warningNotice: j['warningNotice'],
      automaticCue: j['automaticCue'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['automaticCue'])),
      automaticCueAt: j['automaticCueAt'] == null
          ? null
          : Stamp.fromJson(Map<String, dynamic>.from(j['automaticCueAt'])),
      prior: j['prior'] == null
          ? null
          : Session.fromJson(Map<String, dynamic>.from(j['prior'])),
    );
    require({1, 5, 10, 30, 60}.contains(s.rate), 'Invalid rehearsal speed.');
    require(
      s.run == null ||
          (s.timeline != null &&
              s.run!.actualMs.length == s.timeline!.segments.length),
      'Invalid service metrics.',
    );
    require(
      {'idle', 'ready', 'active', 'ended'}.contains(s.phase),
      'Invalid saved service phase.',
    );
    require(
      s.revision >= 0 && s.baseMs >= 0 && s.baseMs <= maxRemainingMs,
      'Invalid saved timing state.',
    );
    require(
      s.phase == 'idle' ||
          (s.timeline != null &&
              s.index >= 0 &&
              s.index < s.timeline!.segments.length),
      'Invalid saved timeline position.',
    );
    require(
      s.phase != 'ended' || s.alert == null,
      'Ended service cannot have an alert.',
    );
    require(
      s.undo == null ||
          (s.timeline != null &&
              s.undo!.index >= 0 &&
              s.undo!.index < s.timeline!.segments.length),
      'Invalid undo checkpoint.',
    );
    return s;
  }
  Json toJson() => {
    'id': id,
    'phase': phase,
    'revision': revision,
    'index': index,
    'baseMs': baseMs,
    'paused': paused,
    'held': held,
    'disconnected': disconnected,
    'uncertain': uncertain,
    'anchor': anchor.toJson(),
    'checkpoint': checkpoint.toJson(),
    'timeline': timeline?.toJson(),
    'alert': alert?.toJson(),
    'undo': undo?.toJson(),
    'outage': outage?.toJson(),
    'prior': prior?.toJson(),
    'rate': rate,
    'run': run?.toJson(),
    'warningSeen': warningSeen,
    'warningCeiling': warningCeiling,
    'warningNotice': warningNotice,
    'automaticCue': automaticCue?.toJson(),
    'automaticCueAt': automaticCueAt?.toJson(),
  };
  Session copy() => Session.fromJson(toJson());
}

String formatTime(int ms) {
  final seconds = (ms / 1000).ceil();
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Pure service transitions. The controller saves the returned candidate before
/// publishing it to the UI or simulator. No transport callback invokes this.
Session transition(
  Session original,
  String action,
  Stamp now, {
  dynamic value,
  int? expectedRevision,
}) {
  require(
    expectedRevision == null || expectedRevision == original.revision,
    'The service changed. Review the action again.',
  );
  var s = original.copy();
  s.settleMetrics(now);
  if (action == 'load') {
    require(
      !s.active && s.phase != 'ready',
      'End the current service before loading another.',
    );
    final t = Timeline.fromJson((value as Timeline).toJson());
    s = Session(
      id: '${now.boot}-${now.mono}-${original.revision + 1}',
      anchor: now,
      phase: 'ready',
      timeline: t,
      baseMs: t.segments.first.minutes * 60000,
      disconnected: original.disconnected,
      prior: original.copy()..prior = null,
    );
  } else if (action == 'cancelReady') {
    require(s.phase == 'ready', 'No setup to cancel.');
    final previous = s.prior;
    s = previous ?? Session(id: s.id, anchor: now);
    s.id = '${original.id}-cancelled';
    s.held = true; // Cancelling Ready must never resurrect a prior output job.
    s.prior = null;
  } else if (action == 'rate') {
    require(s.phase == 'ready', 'Select rehearsal speed before starting.');
    require(
      value is int && {1, 5, 10, 30, 60}.contains(value),
      'Invalid rehearsal speed.',
    );
    s.rate = value as int;
  } else if (action == 'start') {
    require(s.phase == 'ready', 'Load a service first.');
    s.phase = 'active';
    s.run = RunMetrics.fresh(now, s.timeline!.segments.length);
    s.warningCeiling = s.baseMs + 1;
    s.warningSeen = [];
    s.anchor = now;
    s.checkpoint = now;
    s.held = false;
    s.uncertain = false;
    s.prior = null;
  } else if (action == 'disconnect') {
    s.disconnected = true;
    s.outage ??= now;
  } else if (action == 'connect') {
    s.disconnected = false;
    if (s.outage != null &&
        (!now.sameBoot(s.outage!) || now.since(s.outage!) >= recoveryLimitMs))
      s.held = true;
    if (!s.held) s.outage = null;
  } else if (action == 'release' || action == 'releaseTimer') {
    if (action == 'releaseTimer') {
      s.alert = null;
      s.automaticCue = null;
    }
    s.held = false;
    s.disconnected = false;
    s.outage = null;
    s.checkpoint = now;
  } else {
    require(s.active, 'Start the first segment to use live controls.');
    switch (action) {
      case 'pause':
        s.baseMs = s.remaining(now);
        s.anchor = now;
        s.paused = !s.paused;
        s.undo = s.undo?.markModified();
      case 'adjust':
        final delta = value as int;
        final result = s.remaining(now) + delta * 1000;
        require(
          result <= maxRemainingMs,
          'The maximum remaining time is 99:59.',
        );
        if (s.run != null)
          s.run!.adjustmentsMs[s.index] +=
              (math.max(0, result) - s.remaining(now));
        s.baseMs = math.max(0, result);
        s.warningCeiling = math.max(s.warningCeiling, s.baseMs + 1);
        s.anchor = now;
        s.undo = s.undo?.markModified();
      case 'advance':
        require(
          s.index + 1 < s.timeline!.segments.length,
          'This is the final segment.',
        );
        s.undo = UndoPoint(
          s.index,
          s.remaining(now),
          s.paused,
          now,
          runCheckpoint: s.run?.toJson(),
          warningSeen: [...s.warningSeen],
          warningCeiling: s.warningCeiling,
        );
        if (s.run != null) {
          s.run!.actualMs[s.index] = s.run!.currentMs;
          s.run!.currentMs = 0;
        }
        s.index++;
        s.baseMs = s.timeline!.segments[s.index].minutes * 60000;
        s.warningCeiling = s.baseMs + 1;
        s.warningSeen = [];
        s.warningNotice = null;
        s.automaticCue = null;
        s.anchor = now;
        s.paused = false;
      case 'undo':
        require(s.undo != null, 'There is no advance to undo.');
        if (s.undo!.runCheckpoint != null) {
          final priorRun = RunMetrics.fromJson(s.undo!.runCheckpoint!);
          final elapsed = now.since(s.undo!.at) * s.rate;
          priorRun.currentMs += elapsed;
          priorRun.totalMs += elapsed;
          if (s.undo!.paused) priorRun.pausedMs[s.undo!.index] += elapsed;
          priorRun.anchor = now;
          s.run = priorRun;
        }
        s.warningSeen = [...s.undo!.warningSeen];
        s.warningCeiling = s.undo!.warningCeiling;
        s.warningNotice = null;
        s.automaticCue = null;
        s.baseMs = s.undoRemaining(now);
        s.index = s.undo!.index;
        s.paused = s.undo!.paused;
        s.anchor = now;
        s.undo = null;
      case 'cue':
        final cue = value as TextLayout;
        cue.validate();
        s.alert = cue;
        s.automaticCue = null;
      case 'timer':
        s.alert = null;
        s.automaticCue = null;
      case 'warnings':
        applyWarnings(s, now);
      case 'dismissWarning':
        s.warningNotice = null;
      case 'end':
        s.baseMs = s.remaining(now);
        s.anchor = now;
        s.phase = 'ended';
        if (s.run != null) {
          s.run!.actualMs[s.index] = s.run!.currentMs;
          s.run!.endedWall = now.wall;
        }
        s.automaticCue = null;
        s.warningNotice = null;
        s.alert = null;
        s.undo = null;
        s.paused = false;
      default:
        throw RuleError('Unknown action: $action');
    }
  }
  s.revision = original.revision + 1;
  s.checkpoint = now;
  return s;
}

Session recover(Session original, Stamp now) {
  final s = original.copy();
  s.settleMetrics(now);
  s.automaticCue = null;
  applyWarnings(s, now, allowStage: false);
  if (!s.active && s.phase != 'ended') return s;
  final trust = now.sameBoot(s.anchor) && now.sameBoot(s.checkpoint);
  if (!trust ||
      now.since(s.checkpoint) >= recoveryLimitMs ||
      (s.outage != null && now.since(s.outage!) >= recoveryLimitMs))
    s.held = true;
  if (!trust) {
    s.baseMs = s.remaining(now);
    s.anchor = now;
    s.uncertain = true;
  }
  return s;
}

class AppState {
  List<Timeline> templates;
  DisplaySettings defaults;
  Session session;
  List<ServiceReport> reports;
  List<SavedCue> savedCues;
  AppState(
    this.templates,
    this.defaults,
    this.session, {
    List<ServiceReport>? reports,
    List<SavedCue>? savedCues,
  }) : reports = reports ?? [],
       savedCues = savedCues ?? [];
  factory AppState.fresh(Stamp now) => AppState(
    [
      Timeline('Sunday Service', const [
        Segment('Praise & Worship', 15),
        Segment('Announcements', 5),
        Segment('Sermon', 30),
        Segment('Closing', 5),
      ], DisplaySettings()),
      Timeline('Quick rehearsal', const [
        Segment('Welcome', 1),
        Segment('Message', 2),
        Segment('Closing', 1),
      ], DisplaySettings()),
    ],
    DisplaySettings(),
    Session(id: 'idle', anchor: now),
  );
  factory AppState.fromJson(Json j) {
    require({1, 2}.contains(j['version']), 'Unsupported saved-state version.');
    final a = AppState(
      (j['templates'] as List)
          .map((e) => Timeline.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      DisplaySettings.fromJson(Map<String, dynamic>.from(j['defaults'])),
      Session.fromJson(Map<String, dynamic>.from(j['session'])),
      reports: (j['reports'] as List? ?? [])
          .map((e) => ServiceReport.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      savedCues: (j['savedCues'] as List? ?? [])
          .map((e) => SavedCue.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
    require(
      a.templates.map((t) => t.name.toLowerCase()).toSet().length ==
          a.templates.length,
      'Saved templates contain duplicate names.',
    );
    return a;
  }
  Json toJson() => {
    'version': 2,
    'templates': templates.map((t) => t.toJson()).toList(),
    'defaults': defaults.toJson(),
    'session': session.toJson(),
    'reports': reports.map((e) => e.toJson()).toList(),
    'savedCues': savedCues.map((e) => e.toJson()).toList(),
  };
  AppState copy() => AppState.fromJson(toJson());
  void saveTemplate(Timeline t, {int? replacing}) {
    require(
      !templates.asMap().entries.any(
        (e) =>
            e.key != replacing &&
            e.value.name.toLowerCase() == t.name.toLowerCase(),
      ),
      'A template named "${t.name}" already exists. Rename it before saving.',
    );
    if (replacing == null) {
      templates.add(t);
    } else {
      templates[replacing] = t;
    }
  }
}

String exportJson(Timeline t) =>
    const JsonEncoder.withIndent('  ').convert(t.toJson());
String exportCsv(Timeline t) {
  String field(String s) => '"${s.replaceAll('"', '""')}"';
  return 'Segment Name,Duration (Minutes)\r\n${t.segments.map((s) => '${field(s.name)},${s.minutes}').join('\r\n')}\r\n';
}

List<List<String>> parseCsv(String raw) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  var closed = false;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < raw.length && raw[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      require(
        field.isEmpty && !closed,
        'Malformed CSV quoting near row ${rows.length + 1}.',
      );
      quoted = true;
    } else if (c == ',' || c == '\n' || c == '\r') {
      row.add(field.toString());
      field = StringBuffer();
      closed = false;
      if (c != ',') {
        rows.add(row);
        row = [];
        if (c == '\r' && i + 1 < raw.length && raw[i + 1] == '\n') i++;
      }
    } else {
      require(!closed, 'Unexpected text after a quoted CSV field.');
      field.write(c);
    }
  }
  require(!quoted, 'CSV contains an unclosed quote.');
  if (field.isNotEmpty || row.isNotEmpty || closed) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

Timeline importTemplate(
  String content,
  String filename,
  DisplaySettings defaults,
) {
  require(utf8.encode(content).length <= 1048576, 'Import exceeds 1 MiB.');
  final raw = content.startsWith('\uFEFF') ? content.substring(1) : content;
  if (filename.toLowerCase().endsWith('.json')) {
    try {
      return Timeline.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } on RuleError {
      rethrow;
    } catch (_) {
      throw RuleError(
        'Invalid JSON structure. Select a version 1 or 2 template file.',
      );
    }
  }
  require(
    filename.toLowerCase().endsWith('.csv'),
    'Choose CSV or JSON. Export Excel files as CSV first.',
  );
  final rows = parseCsv(raw);
  final nonblank = rows
      .asMap()
      .entries
      .where((e) => e.value.any((v) => v.trim().isNotEmpty))
      .toList();
  require(nonblank.isNotEmpty, 'The CSV is empty.');
  final header = nonblank.first.value.map((v) => v.trim()).toList();
  require(
    header.where((h) => h == 'Segment Name').length == 1 &&
        header.where((h) => h == 'Duration (Minutes)').length == 1,
    'Required CSV columns: Segment Name,Duration (Minutes).',
  );
  final ni = header.indexOf('Segment Name'),
      di = header.indexOf('Duration (Minutes)');
  final segs = <Segment>[];
  final errors = <String>[];
  for (final row in nonblank.skip(1)) {
    try {
      require(
        row.value.length == header.length,
        'Column count does not match the header.',
      );
      final value = row.value[di].trim();
      require(
        RegExp(r'^\d+$').hasMatch(value),
        'Duration must be an integer from 1 to 99.',
      );
      segs.add(
        Segment.fromJson({
          'name': row.value[ni],
          'minutes': int.tryParse(value),
        }),
      );
    } catch (e) {
      errors.add('Row ${row.key + 1}: $e');
    }
  }
  require(
    errors.isEmpty,
    '${errors.join('\n')}\nNothing was imported. Correct the file and select it again.',
  );
  require(
    segs.isNotEmpty && segs.length <= 200,
    'Import must contain 1–200 segments.',
  );
  return Timeline(
    nameValue(filename.replaceFirst(RegExp(r'\.[^.]+$'), ''), 'Template name'),
    segs,
    DisplaySettings.fromJson(defaults.toJson()),
  );
}
