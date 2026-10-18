import 'dart:convert';

import 'domain.dart';

/// Desired output only. The adapter must validate the controller, clock and
/// rendering capabilities before encoding or publishing these intents.
enum HardwareOutputKind { countdown, text, blank, retain, blocked }

enum HardwareOutputReason {
  running,
  paused,
  manualCue,
  automaticCue,
  atZero,
  endScreen,
  operatorBlank,
  idle,
  ready,
  held,
  disconnected,
  uncertain,
  acceleratedRehearsal,
  untrustedClock,
  clockChanged,
  countdownRange,
  invalidSession,
}

/// Hours-hidden rollover must not silently turn 60 minutes into 00:00.
/// Raise this only after total-minute rendering is verified on the controller.
const observedW2CountdownLimitMs = 59 * 60000 + 59000;
const hardwareClockDriftToleranceMs = 1000;

class HardwareOutputPlan {
  final HardwareOutputKind kind;
  final HardwareOutputReason reason;
  final String sessionId;
  final int revision, segmentIndex, connectionGeneration;
  final TextLayout? layout;
  final int? deadlineWallMs, deadlineMonoMs;
  final String? deadlineBoot;

  const HardwareOutputPlan._({
    required this.kind,
    required this.reason,
    required this.sessionId,
    required this.revision,
    required this.segmentIndex,
    required this.connectionGeneration,
    this.layout,
    this.deadlineWallMs,
    this.deadlineMonoMs,
    this.deadlineBoot,
  });

  bool get canPublish =>
      kind == HardwareOutputKind.countdown ||
      kind == HardwareOutputKind.text ||
      kind == HardwareOutputKind.blank;

  /// This does not establish that the controller clock has been synchronized.
  bool get requiresAlignedControllerClock =>
      kind == HardwareOutputKind.countdown;

  /// Stable across ticks and unrelated revisions. For countdown, layout carries
  /// style only: its 00:00 text is not a frame to send every tick. Matrix glyph
  /// definitions remain owned by the existing renderer.
  Json get canonicalIntent => {
    'schema': 1,
    'session': sessionId,
    'segment': segmentIndex,
    'connectionGeneration': connectionGeneration,
    'kind': kind.name,
    'reason': reason.name,
    if (layout != null) 'layout': layout!.toJson(),
    if (deadlineWallMs != null) 'deadlineWallMs': deadlineWallMs,
    if (deadlineMonoMs != null) 'deadlineMonoMs': deadlineMonoMs,
    if (deadlineBoot != null) 'deadlineBoot': deadlineBoot,
  };

  /// Canonical comparison key, not a cryptographic digest.
  String get fingerprint => jsonEncode(canonicalIntent);

  /// Pass only an output whose delivery the adapter actually confirmed.
  /// Held/disconnected/idle means send nothing, not blank the sign.
  bool replaces(HardwareOutputPlan? confirmedOutput) =>
      canPublish && fingerprint != confirmedOutput?.fingerprint;

  /// Recheck before sending and before accepting an async result. This cannot
  /// cancel bytes on the wire: an adapter must serialize writes and reconcile
  /// newer desired state after each completion. Fingerprints catch expiry/zero
  /// even when the Session revision has not changed.
  bool isCurrent(
    Session session,
    Stamp now, {
    required int connectionGeneration,
    int maximumCountdownMs = observedW2CountdownLimitMs,
  }) {
    if (!canPublish ||
        session.id != sessionId ||
        session.revision != revision ||
        this.connectionGeneration != connectionGeneration) {
      return false;
    }
    final desired = planHardwareOutput(
      session,
      now,
      connectionGeneration: connectionGeneration,
      maximumCountdownMs: maximumCountdownMs,
    );
    return desired.canPublish && fingerprint == desired.fingerprint;
  }
}

/// Use the durably saved session, never an uncommitted UI candidate. Increment
/// connectionGeneration on reconnect, adapter replacement or controller clock
/// reset, even if the Session revision did not change. maximumCountdownMs is a
/// verified adapter capability, not an operator preference.
HardwareOutputPlan planHardwareOutput(
  Session session,
  Stamp now, {
  int connectionGeneration = 0,
  int maximumCountdownMs = observedW2CountdownLimitMs,
}) {
  require(connectionGeneration >= 0, 'Invalid connection generation.');
  require(
    maximumCountdownMs > 0 && maximumCountdownMs <= maxRemainingMs,
    'Hardware countdown limit must be between 1 ms and 99:59.',
  );
  HardwareOutputPlan make(
    HardwareOutputKind kind,
    HardwareOutputReason reason, {
    TextLayout? layout,
    int? deadlineWallMs,
    int? deadlineMonoMs,
    String? deadlineBoot,
  }) => HardwareOutputPlan._(
    kind: kind,
    reason: reason,
    sessionId: session.id,
    revision: session.revision,
    segmentIndex: session.index,
    connectionGeneration: connectionGeneration,
    layout: layout,
    deadlineWallMs: deadlineWallMs,
    deadlineMonoMs: deadlineMonoMs,
    deadlineBoot: deadlineBoot,
  );
  HardwareOutputPlan blocked(HardwareOutputReason reason) =>
      make(HardwareOutputKind.blocked, reason);

  if (session.disconnected) return blocked(HardwareOutputReason.disconnected);
  if (session.held) return blocked(HardwareOutputReason.held);
  if (session.uncertain) return blocked(HardwareOutputReason.uncertain);
  // Never send accelerated simulator time to a real-time hardware countdown,
  // including cues/end screens belonging to the accelerated session.
  if (session.rate != 1) {
    return blocked(HardwareOutputReason.acceleratedRehearsal);
  }
  if (!{'idle', 'ready', 'active', 'ended'}.contains(session.phase) ||
      session.revision < 0 ||
      session.id.isEmpty ||
      (session.phase != 'idle' &&
          (session.timeline == null ||
              session.index < 0 ||
              session.index >= session.timeline!.segments.length))) {
    return blocked(HardwareOutputReason.invalidSession);
  }
  if (session.outputBlank) {
    return make(HardwareOutputKind.blank, HardwareOutputReason.operatorBlank);
  }
  if (session.phase == 'idle' || session.phase == 'ready') {
    return make(
      HardwareOutputKind.retain,
      session.phase == 'ready'
          ? HardwareOutputReason.ready
          : HardwareOutputReason.idle,
    );
  }
  if (session.phase == 'ended') {
    return make(
      HardwareOutputKind.text,
      HardwareOutputReason.endScreen,
      layout: session.timeline!.display.end,
    );
  }
  // Do not use wall-time fallback after reboot for an active timer or cue expiry.
  if (!now.sameBoot(session.anchor) || !now.sameBoot(session.checkpoint)) {
    return blocked(HardwareOutputReason.untrustedClock);
  }
  if (session.hasAutomaticCue(now)) {
    return make(
      HardwareOutputKind.text,
      HardwareOutputReason.automaticCue,
      layout: session.automaticCue,
    );
  }
  if (session.alert != null) {
    return make(
      HardwareOutputKind.text,
      HardwareOutputReason.manualCue,
      layout: session.alert,
    );
  }
  final remaining = session.remaining(now);
  if (remaining > maxRemainingMs) {
    return blocked(HardwareOutputReason.countdownRange);
  }
  if (remaining == 0 || session.paused) {
    return make(
      HardwareOutputKind.text,
      remaining == 0
          ? HardwareOutputReason.atZero
          : HardwareOutputReason.paused,
      layout: session.intended(now),
    );
  }
  if (remaining > maximumCountdownMs) {
    return blocked(HardwareOutputReason.countdownRange);
  }
  final wallElapsed = now.wall - session.anchor.wall;
  final monoElapsed = now.mono - session.anchor.mono;
  if ((wallElapsed - monoElapsed).abs() > hardwareClockDriftToleranceMs) {
    // Caller must explicitly re-establish clock mapping; never silently retarget.
    return blocked(HardwareOutputReason.clockChanged);
  }
  return make(
    HardwareOutputKind.countdown,
    HardwareOutputReason.running,
    layout: const TextLayout('00:00', effect: 'static', height: 2),
    deadlineWallMs: session.anchor.wall + session.baseMs,
    deadlineMonoMs: session.anchor.mono + session.baseMs,
    deadlineBoot: session.anchor.boot,
  );
}
