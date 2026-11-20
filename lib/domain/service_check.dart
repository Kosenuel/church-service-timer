/// "Check this service": the whole program run through at high speed on
/// a copy of the service engine, so each warning and cue can be seen to
/// fire before the day.
///
/// It runs the service engine itself, with the same transitions and
/// warning rules as a service or rehearsal, on a [Session] that belongs
/// to the check alone and on a clock of its own that runs fast. That
/// session is never saved, never becomes the app's service and is never
/// sent to the LED sign, stage screens, web screens or a second screen, so
/// ending it saves no report and changes nothing.
library;

import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';

/// About how long a whole check takes in real time, warnings included.
const serviceCheckTargetMs = 18000;

/// The least real time the program itself runs for, however many
/// warnings it has.
const serviceCheckRunMinMs = 6000;

/// The real time the pauses on warnings share, so each is held for less
/// when there are many.
const serviceCheckHoldBudgetMs = 8000;

/// How long the check holds on each warning, at most and at least, so it
/// can be read.
const serviceCheckHoldMaxMs = 1200, serviceCheckHoldMinMs = 250;

/// How long the check holds on each of [warnings] warnings.
int serviceCheckHold(int warnings) => warnings == 0
    ? 0
    : (serviceCheckHoldBudgetMs ~/ warnings).clamp(
        serviceCheckHoldMinMs,
        serviceCheckHoldMaxMs,
      );

/// How many times faster than real time the check runs [plannedMs] of
/// service with [warnings] warnings to hold on, so that the whole check
/// takes about [serviceCheckTargetMs]: a 90-minute service with three
/// warnings in each of five segments runs at 540×.
///
/// Rehearsals stop at 60×, which would still take a minute and a half for
/// that service, and their speed is saved with the service and checked by
/// the LED sign. The check's speed is never saved: its session keeps the
/// normal speed and the check runs its own clock this much faster.
int serviceCheckRate(int plannedMs, {int warnings = 0}) {
  final run = math.max(
    serviceCheckRunMinMs,
    serviceCheckTargetMs - warnings * serviceCheckHold(warnings),
  );
  return math.max(1, (plannedMs / run).ceil());
}

/// A warning in the check's list: one that fired, or one that could not.
class CheckedWarning {
  final int segment;
  final WarningRule rule;

  /// The time left when it showed, or null when it could not fire.
  final int? remainingMs;
  const CheckedWarning(this.segment, this.rule, this.remainingMs);
  bool get fired => remainingMs != null;

  /// Where it showed, in the words of Settings › Warnings & alerts.
  String get where =>
      rule.destination == 'stage' ? 'Operator and stage' : 'Operator only';
}

/// The warnings of [t] that can never fire in a segment because the
/// countdown starts at or below their time: a threshold as long as the
/// segment, or longer. A warning fires when the countdown comes down to
/// its time, never at the start of a segment.
List<CheckedWarning> unreachableWarnings(Timeline t) => [
  for (var i = 0; i < t.segments.length; i++)
    for (final rule in t.display.warnings)
      if (rule.enabled && rule.seconds * 1000 >= t.segments[i].durationMs)
        CheckedWarning(i, rule, null),
];

/// The check itself: [step] moves it on by real time, and [session] at
/// [now] is what the Simulator shows.
class ServiceCheckRun {
  final Timeline timeline;
  final int rate, holdMs;
  late Session session;

  /// The check's own clock: service time, running [rate] times faster
  /// than real time and standing still while a warning is held.
  late Stamp now;

  /// The warnings that fired, in the order they did.
  final fired = <CheckedWarning>[];
  late final List<CheckedWarning> unreachable = unreachableWarnings(timeline);

  /// Real time the check has run for, holds included.
  int elapsedMs = 0;
  bool get done => session.phase == 'ended';

  /// Whether a warning is being held on screen just now.
  bool get holding => _hold > 0;
  int _hold = 0;

  ServiceCheckRun(this.timeline, Stamp start, {int? rate})
    : rate =
          rate ??
          serviceCheckRate(_planned(timeline), warnings: _reachable(timeline)),
      holdMs = serviceCheckHold(_reachable(timeline)) {
    now = start;
    final ready = transition(
      Session(id: 'check', anchor: start),
      'load',
      start,
      value: timeline,
    )..noReport = true;
    session = transition(ready, 'start', start);
    _warn();
  }

  static int _planned(Timeline t) =>
      t.segments.fold<int>(0, (n, s) => n + s.durationMs);

  /// How many warnings can fire: one per enabled warning set for less
  /// time than a segment has.
  static int _reachable(Timeline t) => [
    for (final segment in t.segments)
      for (final rule in t.display.warnings)
        if (rule.enabled && rule.seconds * 1000 < segment.durationMs) rule,
  ].length;

  /// About how long the whole check takes in real time.
  int get expectedMs =>
      (_planned(timeline) / rate).ceil() + _reachable(timeline) * holdMs;

  /// Where the check is: e.g. `Segment 2 of 5 · Sermon`.
  String get progress =>
      'Segment ${session.index + 1} of ${timeline.segments.length} · '
      '${timeline.segments[session.index].name}';

  void _warn() {
    final due = dueWarnings(session, now);
    if (due.isEmpty) return;
    final left = session.remaining(now);
    for (final i in due) {
      fired.add(
        CheckedWarning(session.index, timeline.display.warnings[i], left),
      );
    }
    session = transition(session, 'warnings', now);
    _hold = holdMs;
  }

  /// Moves the check on by [ms] of real time.
  void step(int ms) {
    var budget = ms;
    while (budget > 0 && !done) {
      if (_hold > 0) {
        // The clock stands still, so the warning stays on screen.
        final use = math.min(budget, _hold);
        elapsedMs += use;
        budget -= use;
        _hold -= use;
        if (_hold == 0) {
          // Back to the countdown: the warning has been seen.
          session = transition(session, 'clearCue', now);
        }
        continue;
      }
      final left = session.remaining(now);
      if (left == 0) {
        // Time is up: on to the next segment, or the end of the service.
        final last = session.index + 1 >= timeline.segments.length;
        session = transition(session, last ? 'end' : 'advance', now);
        if (!last) _warn();
        continue;
      }
      // The next moment something happens: a warning's time, or zero.
      final next = timeline.display.warnings
          .asMap()
          .entries
          .where(
            (e) =>
                e.value.enabled &&
                !session.warningSeen.contains(e.key) &&
                e.value.seconds * 1000 < session.warningCeiling &&
                e.value.seconds * 1000 < left,
          )
          .map((e) => e.value.seconds * 1000)
          .fold<int>(0, math.max);
      // Service time to move on: up to that moment and no further.
      final service = math.min(budget * rate, left - next);
      final real = math.max(1, (service / rate).ceil());
      now = Stamp(now.mono + service, now.wall + service, now.boot);
      elapsedMs += real;
      budget -= real;
      _warn();
    }
  }

  /// The warnings that fired in a segment, and those that could not.
  List<CheckedWarning> firedIn(int segment) =>
      fired.where((w) => w.segment == segment).toList();
  List<CheckedWarning> unreachableIn(int segment) =>
      unreachable.where((w) => w.segment == segment).toList();
}
