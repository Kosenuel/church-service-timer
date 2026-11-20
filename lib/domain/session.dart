/// The running service: its state, transitions, undo and crash recovery.
library;

import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';

/// The pre-service countdown runs for the last hour before the start.
const preServiceCountdownMs = 59 * 60000 + 59000;
const startingSoonLayout = TextLayout('STARTING SOON', effect: 'scroll');

/// How long after starting a service its start can still be undone.
const unstartWindowMs = 15000;

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
  int rate;

  /// Warnings fire only for a time left below this: the time the segment
  /// started with, or more once time is added. So a warning fires when the
  /// countdown comes down to its time, never at the start of a segment
  /// that is that long or shorter.
  int warningCeiling;
  RunMetrics? run;
  List<int> warningSeen;
  String? warningNotice;
  TextLayout? automaticCue;
  Stamp? automaticCueAt;
  int automaticCueDurationMs;
  List<ServiceEvent> events;
  int? targetFinishWall;

  /// Scheduled start while in Ready; drives the pre-service countdown.
  int? startsAtWall;

  /// A test or practice run: ending it saves no report.
  bool noReport;

  /// A one-segment Quick timer started from Live, not a service.
  bool quickTimer;
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
    this.startsAtWall,
    this.noReport = false,
    this.quickTimer = false,
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

  /// What a scheduled Ready service shows before it starts, or null.
  /// The clock until the last hour, then a countdown, then "Starting soon".
  /// It never starts the service by itself.
  TextLayout? preService(Stamp now) {
    final at = startsAtWall;
    if (phase != 'ready' || at == null) return null;
    final left = at - now.wall;
    if (left > preServiceCountdownMs) return clockLayout(now.wall, clockFormat);
    if (left > 0)
      return TextLayout(formatTime(left), effect: 'static', height: 2);
    return startingSoonLayout;
  }

  TextLayout? intended(Stamp now) {
    if (outputBlank) return null;
    if (phase == 'ready' && startsAtWall != null) return preService(now);
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
      : phase == 'ready' && startsAtWall != null
      ? 'Pre-service'
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
    require(
      j['startsAtWall'] == null ||
          (j['startsAtWall'] is int &&
              j['startsAtWall'] >= 0 &&
              j['startsAtWall'] <= 8640000000000000),
      'Invalid scheduled start.',
    );
    final s = Session(
      id: j['id'],
      events: readServiceEvents(j['events']),
      targetFinishWall: j['targetFinishWall'] as int?,
      startsAtWall: j['startsAtWall'] as int?,
      noReport: j['noReport'] == true,
      quickTimer: j['quickTimer'] == true,
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
    'startsAtWall': startsAtWall,
    if (noReport) 'noReport': true,
    if (quickTimer) 'quickTimer': true,
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
    require(!s.active, 'End the current service before loading another.');
    final t = Timeline.fromJson((value as Timeline).toJson());
    validateProgramDuration(t);
    // Loading over a setup swaps the program: the setup's start time and
    // service mode stay, and Cancel setup still returns to what was before.
    final swap = s.phase == 'ready';
    final scheduled = swap && original.startsAtWall != null;
    s = Session(
      id: '${now.boot}-${now.mono}-${original.revision + 1}',
      // Keeping the anchor keeps the sign's countdown deadline unchanged.
      anchor: scheduled ? original.anchor : now,
      phase: 'ready',
      timeline: t,
      baseMs: t.segments.first.durationMs,
      disconnected: original.disconnected,
      held: swap && original.held,
      rate: swap ? original.rate : 1,
      startsAtWall: swap ? original.startsAtWall : null,
      noReport: swap && original.noReport,
      prior: swap ? original.prior : (original.copy()..prior = null),
    );
  } else if (action == 'cancelReady') {
    require(s.phase == 'ready', 'No setup to cancel.');
    final previous = s.prior;
    s = previous ?? Session(id: s.id, anchor: now);
    s.id = '${original.id}-cancelled';
    // Never resurrect output the display did not receive (an end screen
    // pending while disconnected or held); otherwise nothing needs review.
    s.held = previous != null && (previous.held || previous.disconnected);
    s.prior = null;
  } else if (action == 'schedule') {
    require(s.phase == 'ready', 'Load a service before scheduling its start.');
    require(
      value == null ||
          (value is int && value > now.wall && value - now.wall <= 86400000),
      'Choose a start time within the next 24 hours.',
    );
    s.startsAtWall = value as int?;
    // Anchor the schedule so the sign's countdown deadline stays stable.
    s.anchor = now;
    s.checkpoint = now;
    // Scheduling sends the clock or countdown, so the output is no longer held.
    if (value != null) s.held = false;
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
    s.startsAtWall = null;
    s.showClock = false;
    s.run = RunMetrics.fresh(now, s.timeline!.segments.length);
    s.warningCeiling = s.baseMs;
    s.warningSeen = [];
    s.anchor = now;
    s.checkpoint = now;
    s.held = false;
    s.uncertain = false;
    s.prior = null;
  } else if (action == 'unstart') {
    // Undo an accidental start: only the first segment, within moments.
    require(
      s.phase == 'active' &&
          s.index == 0 &&
          s.undo == null &&
          now.sameBoot(s.anchor) &&
          now.since(s.anchor) <= unstartWindowMs,
      'The service has been running too long to undo its start.',
    );
    s.phase = 'ready';
    s.run = null;
    s.paused = false;
    s.alert = null;
    s.automaticCue = null;
    s.warningSeen = [];
    s.warningNotice = null;
    s.baseMs = s.timeline!.segments.first.durationMs;
    s.warningCeiling = s.baseMs;
    s.anchor = now;
    s.checkpoint = now;
    // Nothing is timed in Ready, so there is nothing to review; the display
    // keeps its last frame until a start time is set or the service starts.
    s.held = false;
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
        // Time added above a warning's time lets it fire when the countdown
        // comes down to it again, if it has not fired in this segment.
        s.warningCeiling = math.max(s.warningCeiling, s.baseMs);
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
        s.warningCeiling = s.baseMs;
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
