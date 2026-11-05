import 'dart:convert';
import 'dart:math' as math;

import 'package:church_service_timer/domain/service_features.dart';
export 'package:church_service_timer/domain/service_features.dart';
import 'package:church_service_timer/domain/app_settings.dart';
export 'package:church_service_timer/domain/app_settings.dart';
import 'package:church_service_timer/domain/program_library.dart';
export 'package:church_service_timer/domain/program_library.dart';
export 'package:church_service_timer/domain/service_planning.dart';
import 'package:church_service_timer/domain/quick_message.dart';
import 'package:church_service_timer/domain/edit_drafts.dart';
import 'package:church_service_timer/domain/notification_settings.dart';
import 'package:church_service_timer/domain/print_preferences.dart';
import 'package:church_service_timer/domain/program_io.dart';
import 'package:church_service_timer/domain/stage_output.dart';
export 'package:church_service_timer/domain/quick_message.dart';
export 'package:church_service_timer/domain/duration_insights.dart';
export 'package:church_service_timer/domain/edit_drafts.dart';
export 'package:church_service_timer/domain/notification_settings.dart';
export 'package:church_service_timer/domain/print_preferences.dart';
export 'package:church_service_timer/domain/program_io.dart';
export 'package:church_service_timer/domain/stage_output.dart';
export 'package:church_service_timer/domain/time_recovery.dart';

typedef Json = Map<String, dynamic>;
const maxRemainingMs = 5999000;
// Retain the old deserialization ceiling above so existing records remain readable.
const supportedCountdownMs = 3599000;
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
      // Retired 0.2 fonts migrate to the preserved original face.
      font: {'service_serif', 'clear_sans'}.contains(j['font'])
          ? 'cuekeeper_matrix'
          : j['font'] == 'times_new_roman'
          ? 'tinos'
          : j['font'] ?? 'cuekeeper_matrix',
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

const defaultEndScreen = TextLayout(
  'Hallelujah',
  bold: true,
  italic: true,
  height: 2,
);

class DisplaySettings {
  final TextLayout? zero;
  final TextLayout end;
  final List<TextLayout> cues;
  final List<WarningRule> warnings;
  DisplaySettings({
    this.zero,
    this.end = defaultEndScreen,
    List<TextLayout>? cues,
    List<WarningRule>? warnings,
  }) : warnings = List.unmodifiable(warnings ?? defaultWarnings),
       cues = List.unmodifiable(
         cues ??
             const [
               TextLayout('WRAP UP'),
               TextLayout("TIME'S UP"),
               TextLayout('MIC LOW'),
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
    require(c.length <= 6, 'Configure at most 6 program cues.');
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
  DisplaySettings withZero(TextLayout? value) =>
      DisplaySettings(zero: value, end: end, cues: cues, warnings: warnings);
  DisplaySettings withEnd(TextLayout value) =>
      DisplaySettings(zero: zero, end: value, cues: cues, warnings: warnings);
  Json toJson() => {
    'zero': zero?.toJson(),
    'end': end.toJson(),
    'cues': cues.map((e) => e.toJson()).toList(),
    'warnings': warnings.map((e) => e.toJson()).toList(),
  };
}

class Segment {
  final String name, speaker, notes;
  final int minutes;
  final int seconds;
  int get durationSeconds => minutes * 60 + seconds;
  int get durationMs => durationSeconds * 1000;
  String get durationText =>
      seconds == 0 ? '$minutes min' : formatTime(durationMs);
  final bool protected;
  const Segment(
    this.name,
    this.minutes, {
    this.seconds = 0,
    this.speaker = '',
    this.notes = '',
    this.protected = false,
  });
  factory Segment.fromJson(Json j) {
    keys(j, {
      'name',
      'minutes',
      'seconds',
      'speaker',
      'notes',
      'protected',
    }, 'Segment');
    require(
      j['minutes'] is int &&
          j['minutes'] >= 0 &&
          j['minutes'] <= 99 &&
          (j['seconds'] ?? 0) is int &&
          (j['seconds'] ?? 0) >= 0 &&
          (j['seconds'] ?? 0) <= 59 &&
          j['minutes'] * 60 + (j['seconds'] ?? 0) > 0,
      'Enter a positive duration with seconds from 0 to 59.',
    );
    String optional(
      dynamic value,
      int limit,
      String label, {
      bool multiline = false,
    }) {
      require(value == null || value is String, '$label must be text.');
      final text = ((value ?? '') as String).replaceAll('\r\n', '\n').trim();
      require(
        text.runes.length <= limit &&
            !RegExp(
              multiline ? r'[\x00-\x08\x0b-\x1f\x7f]' : r'[\x00-\x1f\x7f]',
            ).hasMatch(text),
        '$label must contain at most $limit characters without control characters.',
      );
      return text;
    }

    return Segment(
      nameValue(j['name'], 'Segment name'),
      j['minutes'],
      seconds: j['seconds'] ?? 0,
      speaker: optional(j['speaker'], 80, 'Speaker'),
      notes: optional(j['notes'], 1000, 'Private notes', multiline: true),
      protected: boolSetting(j['protected'] ?? false),
    );
  }
  Json toJson() => {
    'name': name,
    'minutes': minutes,
    if (seconds != 0) 'seconds': seconds,
    if (speaker.isNotEmpty) 'speaker': speaker,
    if (notes.isNotEmpty) 'notes': notes,
    if (protected) 'protected': true,
  };
}

class Timeline {
  final String name;
  final String type;
  final List<Segment> segments;
  final DisplaySettings display;
  Timeline(
    this.name,
    List<Segment> segments,
    this.display, {
    this.type = 'service',
  }) : segments = List.unmodifiable(segments);
  factory Timeline.fromJson(Json j) {
    keys(j, {
      'schemaVersion',
      'name',
      'segments',
      'display',
      'type',
    }, 'Program');
    require(
      j['schemaVersion'] is int && {1, 2, 3, 4, 5}.contains(j['schemaVersion']),
      'Supported program schema versions are 1–5.',
    );
    final type =
        j['type'] ??
        (j['schemaVersion'] >= 3
            ? null
            : j['name'] == 'Quick rehearsal'
            ? 'rehearsal'
            : 'service');
    require(
      {'service', 'rehearsal'}.contains(type),
      'Program type must be service or rehearsal.',
    );
    require(j['segments'] is List, 'segments must be a list.');
    final entries = j['segments'] as List;
    require(
      entries.isNotEmpty && entries.length <= 200,
      'A program needs 1–200 segments.',
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
      nameValue(j['name'], 'Program name'),
      segs,
      DisplaySettings.fromJson(Map<String, dynamic>.from(j['display'])),
      type: type as String,
    );
  }
  Timeline renamed(String n) =>
      Timeline(nameValue(n, 'Program name'), segments, display, type: type);
  Timeline withDisplay(DisplaySettings value) =>
      Timeline(name, segments, value, type: type);
  Json toJson() => {
    'schemaVersion': segments.any((s) => s.seconds != 0) ? 5 : 4,
    'name': name,
    'type': type,
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
  String churchName;
  int revision, index, baseMs;
  bool paused, held, disconnected, uncertain, outputBlank;
  Timeline? timeline;
  TextLayout? alert;
  bool showClock;
  String clockFormat;
  bool clockBlink;
  Stamp? alertAt;
  int alertDurationSeconds;
  bool alertIsMessage;
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
  int automaticCueDurationMs;
  List<ServiceEvent> events;
  int? targetFinishWall;
  Session({
    required this.id,
    required this.anchor,
    this.churchName = '',
    this.phase = 'idle',
    this.revision = 0,
    this.index = 0,
    this.baseMs = 0,
    this.paused = false,
    this.held = false,
    this.disconnected = false,
    this.uncertain = false,
    this.outputBlank = false,
    this.timeline,
    this.alert,
    this.showClock = false,
    this.clockFormat = '24h',
    this.clockBlink = true,
    this.alertAt,
    this.alertDurationSeconds = 0,
    this.alertIsMessage = false,
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
    this.automaticCueDurationMs = 8000,
    this.targetFinishWall,
    List<ServiceEvent>? events,
  }) : checkpoint = checkpoint ?? anchor,
       warningSeen = warningSeen ?? [],
       events = events ?? [];
  bool get active => phase == 'active';

  /// Signed operator clock. Stage output continues to obey the shared At Zero
  /// setting; a negative balance never changes the 32 × 16 countdown format.
  int balance(Stamp now) =>
      active && !paused ? baseMs - now.since(anchor) * rate : baseMs;
  int remaining(Stamp now) => math.max(0, balance(now));
  int overtime(Stamp now) => math.max(0, -balance(now));
  int get allocatedMs => timeline == null
      ? 0
      : math.max(
          0,
          timeline!.segments[index].durationMs +
              (run?.adjustmentsMs[index] ?? 0),
        );
  int get undoAllocatedMs => undo == null || timeline == null
      ? 0
      : math.max(
          0,
          timeline!.segments[undo!.index].durationMs +
              (undo!.runCheckpoint == null
                  ? 0
                  : RunMetrics.fromJson(
                      undo!.runCheckpoint!,
                    ).adjustmentsMs[undo!.index]),
        );
  bool nearWarning(Stamp now) =>
      active &&
      remaining(now) > 0 &&
      timeline!.display.warnings.any(
        (w) =>
            w.enabled &&
            w.seconds > 0 &&
            w.seconds * 1000 < warningCeiling &&
            remaining(now) <= w.seconds * 1000,
      );
  String formatted(Stamp now) => formatTime(remaining(now));
  int undoBalance(Stamp now) => undo == null
      ? 0
      : undo!.paused
      ? undo!.remaining
      : undo!.remaining - now.since(undo!.at) * rate;
  int undoRemaining(Stamp now) => math.max(0, undoBalance(now));
  bool fastUndo(Stamp now) =>
      undo != null &&
      !undo!.modified &&
      !uncertain &&
      now.sameBoot(undo!.at) &&
      now.since(undo!.at) <= 10000;
  TextLayout? intended(Stamp now) {
    if (outputBlank) return null;
    if (!active && phase != 'ended') return null;
    if (hasAutomaticCue(now)) return automaticCue;
    if (hasManualCue(now)) return alert;
    if (showClock) return clockLayout(now.wall, clockFormat);
    if (phase == 'ended') return timeline!.display.end;
    if (remaining(now) == 0 && timeline!.display.zero != null)
      return timeline!.display.zero;
    return TextLayout(formatted(now), effect: 'static', height: 2);
  }

  bool hasManualCue(Stamp now) =>
      alert != null &&
      (alertDurationSeconds == 0 ||
          (alertAt != null &&
              now.sameBoot(alertAt!) &&
              now.since(alertAt!) < alertDurationSeconds * 1000));

  String outputMode(Stamp now) => outputBlank
      ? 'Blank'
      : hasAutomaticCue(now)
      ? 'Cue'
      : hasManualCue(now)
      ? (alertIsMessage ? 'Message' : 'Cue')
      : showClock
      ? 'Clock'
      : phase == 'ended'
      ? 'End screen'
      : active
      ? 'Countdown'
      : 'Standby';

  bool get rehearsal => rate > 1;
  bool hasAutomaticCue(Stamp now) =>
      active &&
      automaticCue != null &&
      automaticCueAt != null &&
      now.sameBoot(automaticCueAt!) &&
      now.since(automaticCueAt!) < automaticCueDurationMs;
  int get plannedMs =>
      timeline?.segments.fold<int>(0, (n, s) => n + s.durationMs) ?? 0;
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
                    .fold<int>(0, (n, s) => n + s.durationMs)
          : 0);
  void settleMetrics(Stamp now) {
    if (!active || run == null) return;
    final elapsed = now.since(run!.anchor) * rate;
    run!.totalMs += elapsed;
    run!.currentMs += elapsed;
    if (paused) run!.pausedMs[index] += elapsed;
    run!.anchor = now;
  }

  String get outputKind => outputBlank
      ? 'Blank'
      : phase == 'ended'
      ? 'End screen'
      : alert != null
      ? 'Alert'
      : 'Countdown';
  factory Session.fromJson(Json j) {
    require(
      j['targetFinishWall'] == null ||
          (j['targetFinishWall'] is int &&
              j['targetFinishWall'] >= 0 &&
              j['targetFinishWall'] <= 8640000000000000),
      'Invalid target finish.',
    );
    final s = Session(
      id: j['id'],
      events: readServiceEvents(j['events']),
      targetFinishWall: j['targetFinishWall'] as int?,
      automaticCueDurationMs: readCueDuration(j['automaticCueDurationMs']),
      churchName: churchNameValue(j['churchName'] ?? ''),
      phase: j['phase'],
      revision: j['revision'],
      index: j['index'],
      baseMs: j['baseMs'],
      paused: j['paused'],
      held: j['held'],
      disconnected: j['disconnected'],
      uncertain: j['uncertain'],
      outputBlank: j['outputBlank'] ?? false,
      anchor: Stamp.fromJson(Map<String, dynamic>.from(j['anchor'])),
      checkpoint: Stamp.fromJson(Map<String, dynamic>.from(j['checkpoint'])),
      timeline: j['timeline'] == null
          ? null
          : Timeline.fromJson(Map<String, dynamic>.from(j['timeline'])),
      alert: j['alert'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['alert'])),
      showClock: j['showClock'] == true,
      clockFormat: readClockFormat(j['clockFormat'] ?? '24h'),
      clockBlink: boolSetting(j['clockBlink'] ?? true),
      alertAt: j['alertAt'] == null
          ? null
          : Stamp.fromJson(Map<String, dynamic>.from(j['alertAt'])),
      alertDurationSeconds: readMessageDuration(j['alertDurationSeconds'] ?? 0),
      alertIsMessage: j['alertIsMessage'] == true,
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
      s.revision >= 0 && s.baseMs <= maxRemainingMs,
      'Invalid saved timing state.',
    );
    require(
      s.phase == 'idle' ||
          (s.timeline != null &&
              s.index >= 0 &&
              s.index < s.timeline!.segments.length),
      'Invalid saved program position.',
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
    'churchName': churchName,
    'phase': phase,
    'revision': revision,
    'index': index,
    'baseMs': baseMs,
    'paused': paused,
    'held': held,
    'disconnected': disconnected,
    'uncertain': uncertain,
    'outputBlank': outputBlank,
    'anchor': anchor.toJson(),
    'checkpoint': checkpoint.toJson(),
    'timeline': timeline?.toJson(),
    'alert': alert?.toJson(),
    'showClock': showClock,
    'clockFormat': clockFormat,
    'clockBlink': clockBlink,
    'alertAt': alertAt?.toJson(),
    'alertDurationSeconds': alertDurationSeconds,
    'alertIsMessage': alertIsMessage,
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
    'automaticCueDurationMs': automaticCueDurationMs,
    'events': events.map((e) => e.toJson()).toList(),
    'targetFinishWall': targetFinishWall,
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
    validateProgramDuration(t);
    s = Session(
      id: '${now.boot}-${now.mono}-${original.revision + 1}',
      anchor: now,
      phase: 'ready',
      timeline: t,
      baseMs: t.segments.first.durationMs,
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
    s.showClock = false;
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
      s.outputBlank = false;
      s.alert = null;
      s.automaticCue = null;
    }
    s.held = false;
    s.disconnected = false;
    s.outage = null;
    s.checkpoint = now;
  } else {
    require(
      s.active ||
          ({
                'blank',
                'clock',
                'cue',
                'message',
                'clearCue',
                'timer',
                'endScreen',
              }.contains(action) &&
              s.phase == 'ended'),
      'Start the first segment to use live controls.',
    );
    switch (action) {
      case 'pause':
        s.baseMs = s.balance(now);
        s.anchor = now;
        s.paused = !s.paused;
        s.undo = s.undo?.markModified();
      case 'adjust':
        final delta = value as int;
        // Removal stops at zero. Added allocation first covers existing overtime.
        final applied = delta < 0
            ? math.max(-s.remaining(now), delta * 1000)
            : delta * 1000;
        final result = s.balance(now) + applied;
        require(
          result <= supportedCountdownMs,
          'The maximum remaining time is 59:59.',
        );
        if (s.run != null) s.run!.adjustmentsMs[s.index] += applied;
        s.baseMs = result;
        s.warningCeiling = math.max(s.warningCeiling, s.baseMs + 1);
        s.anchor = now;
        s.undo = s.undo?.markModified();
      case 'advance':
      case 'jump':
        final target = action == 'jump' ? value as int : s.index + 1;
        require(
          target > s.index && target < s.timeline!.segments.length,
          'Choose an upcoming segment.',
        );
        final wasPaused = s.paused;
        s.undo = UndoPoint(
          s.index,
          s.balance(now),
          s.paused,
          now,
          runCheckpoint: s.run?.toJson(),
          warningSeen: [...s.warningSeen],
          warningCeiling: s.warningCeiling,
        );
        if (s.run != null) {
          s.run!.actualMs[s.index] = s.run!.currentMs;
          s.run!.currentMs = 0;
          for (var i = s.index + 1; i < target; i++) {
            s.run!.skipped.add(i);
          }
        }
        s.index = target;
        s.alert = null;
        s.showClock = false;
        s.outputBlank = value == true; // Explicit Keep blank choice.
        s.held = false;
        s.baseMs = s.timeline!.segments[s.index].durationMs;
        s.warningCeiling = s.baseMs + 1;
        s.warningSeen = [];
        s.warningNotice = null;
        s.automaticCue = null;
        s.anchor = now;
        s.paused = action == 'jump' ? wasPaused : false;
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
        s.baseMs = s.undoBalance(now);
        s.index = s.undo!.index;
        s.paused = s.undo!.paused;
        s.anchor = now;
        s.undo = null;
      case 'blank':
        s.outputBlank = !s.outputBlank;
        s.automaticCue = null;
      case 'cue':
        s.outputBlank = false;
        final cue = value as TextLayout;
        cue.validate();
        s.alert = cue;
        s.alertAt = now;
        s.alertDurationSeconds = 0;
        s.alertIsMessage = false;
        s.automaticCue = null;
      case 'message':
        final message = value as StageOutputMessage;
        message.layout.validate();
        readMessageDuration(message.seconds);
        s.outputBlank = false;
        s.alert = message.layout;
        s.alertAt = now;
        s.alertDurationSeconds = message.seconds;
        s.alertIsMessage = true;
        s.automaticCue = null;
      case 'clearCue':
        s.alert = null;
        s.automaticCue = null;
      case 'clock':
        s.showClock = true;
        s.outputBlank = false;
        s.alert = null;
        s.automaticCue = null;
      case 'endScreen':
        require(
          s.phase == 'ended',
          'End the service before restoring its end screen.',
        );
        s.showClock = false;
        s.outputBlank = false;
        s.alert = null;
        s.automaticCue = null;
      case 'timer':
        s.showClock = false;
        s.outputBlank = false;
        s.alert = null;
        s.automaticCue = null;
      case 'warnings':
        applyWarnings(s, now);
      case 'dismissWarning':
        s.warningNotice = null;
      case 'end':
        s.showClock = false;
        s.outputBlank = false;
        s.baseMs = s.balance(now);
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
  if (action != 'warnings' && action != 'dismissWarning' && action != 'load') {
    final description = serviceActionDescription(action, s, value);
    if (description != null)
      addServiceEvent(s.events, ServiceEvent(now.wall, action, description));
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
    s.baseMs = s.balance(now);
    s.anchor = now;
    s.uncertain = true;
  }
  return s;
}

class AppState {
  AppearancePreferences appearance;
  ProgramLibrary programLibrary;
  String clockFormat;
  bool clockBlink;
  int notificationClearSeconds;
  PrintPreferences printPreferences;
  Map<String, Json> editDrafts;
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
  bool keepScreenAwake;

  /// Show the service with Pause and Next on the lock-screen notification.
  /// Local to this phone; not part of portable backups.
  bool lockScreenControls;
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
    this.themeId = 'midnight_lime',
    this.keepScreenAwake = true,
    this.lockScreenControls = true,
    this.outputDestination,
    List<QuickMessage>? quickMessages,
    this.appearance = const AppearancePreferences(),
    this.notificationClearSeconds = 30,
    this.printPreferences = const PrintPreferences(),
    Map<String, Json>? editDrafts,
    ProgramLibrary? programLibrary,
  }) : programLibrary = programLibrary ?? ProgramLibrary(),
       editDrafts = editDrafts ?? {},
       reports = reports ?? [],
       quickMessages = quickMessages ?? [...defaultQuickMessages],
       stageCues = stageCues ?? [...defaults.cues];
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
      {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}.contains(j['version']),
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
      quickMessages: (j['quickMessages'] as List?)
          ?.map((e) => QuickMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      pixelShape: j['pixelShape'] ?? 'square',
      groupTemplates: (j['version'] as int) < 9
          ? true
          : j['groupTemplates'] ?? true,
      churchName: churchNameValue(j['churchName'] ?? ''),
      churchBanner: churchBannerValue(j['churchBanner'] ?? ''),
      themeId: themeIdValue(j['themeId'] ?? 'midnight_lime'),
      keepScreenAwake: boolSetting(j['keepScreenAwake'] ?? true),
      lockScreenControls: boolSetting(j['lockScreenControls'] ?? true),
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
                  defaultWarnings.any(
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
          jsonEncode(d.end.toJson()) ==
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
    a.session.clockFormat = a.clockFormat;
    a.session.clockBlink = a.clockBlink;
    a.applySharedZero();
    a.applySharedWarnings(now);
    return a;
  }
  Json toJson() => {
    'version': 13,
    'appearance': appearance.toJson(),
    'programLibrary': programLibrary.toJson(),
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
    'themeId': themeId,
    'keepScreenAwake': keepScreenAwake,
    'lockScreenControls': lockScreenControls,
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

  void saveTemplate(Timeline t, {int? replacing}) {
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
      templates.add(t);
    } else {
      programLibrary.rename(templates[replacing].name, t.name);
      templates[replacing] = t;
    }
  }

  /// Identify the reviewed saved template, never a stale list position.
  int templateIndex(Timeline expected) {
    final index = templates.indexWhere((t) => t.name == expected.name);
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
    final copy = Timeline.fromJson(original.toJson()).renamed(candidate);
    saveTemplate(copy);
    return copy;
  }

  void deleteTemplate(Timeline expected) {
    templates.removeAt(templateIndex(expected));
    programLibrary.remove(expected.name);
  }
}

String exportJson(Timeline t) =>
    const JsonEncoder.withIndent('  ').convert(t.toJson());
String exportCsv(Timeline t) {
  final precise = t.segments.any((s) => s.seconds != 0);
  String field(String s) => '"${s.replaceAll('"', '""')}"';
  return 'Segment Name,Duration (Minutes)${precise ? ',Seconds' : ''}\r\n${t.segments.map((s) => '${field(s.name)},${s.minutes}${precise ? ',${s.seconds}' : ''}').join('\r\n')}\r\n';
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
      final t = Timeline.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
      return t.withDisplay(
        t.display.withZero(defaults.zero).withWarnings(defaults.warnings),
      );
    } on RuleError {
      rethrow;
    } catch (_) {
      throw RuleError(
        'Invalid JSON structure. Select a version 1, 2 or 3 program file.',
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
          'seconds': header.contains('Seconds')
              ? int.tryParse(row.value[header.indexOf('Seconds')])
              : 0,
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
    nameValue(filename.replaceFirst(RegExp(r'\.[^.]+$'), ''), 'Program name'),
    segs,
    DisplaySettings.fromJson(defaults.toJson()),
  );
}
