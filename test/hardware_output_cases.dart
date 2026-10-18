import 'dart:convert';

import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/hardware_output.dart';

import 'feature_cases.dart' show epoch, at, equal, rejects, service;

void blockedAs(HardwareOutputPlan plan, String reason) {
  equal(plan.kind.name, 'blocked');
  equal(plan.reason.name, reason);
  equal(plan.canPublish, false);
  equal(plan.replaces(null), false);
}

final hardwareOutputCases = <String, void Function()>{
  'Running countdown has one stable deadline and does not mutate the session':
      () {
        final s = service();
        final before = jsonEncode(s.toJson());
        final first = planHardwareOutput(s, epoch);
        equal(first.kind.name, 'countdown');
        equal(first.deadlineWallMs, epoch.wall + 180000);
        equal(first.deadlineMonoMs, epoch.mono + 180000);
        equal(first.requiresAlignedControllerClock, true);
        for (var second = 1; second < 180; second++) {
          final next = planHardwareOutput(s, at(second));
          equal(next.fingerprint, first.fingerprint);
          equal(next.replaces(first), false);
          equal(first.isCurrent(s, at(second), connectionGeneration: 0), true);
        }
        equal(jsonEncode(s.toJson()), before);
      },
  'Adding and removing time replace the deadline and invalidate queued work':
      () {
        var s = service();
        final first = planHardwareOutput(s, epoch);
        s = transition(s, 'adjust', at(30), value: 120);
        final added = planHardwareOutput(s, at(30));
        equal(added.deadlineWallMs, epoch.wall + 300000);
        equal(added.replaces(first), true);
        equal(first.isCurrent(s, at(30), connectionGeneration: 0), false);
        s = transition(s, 'adjust', at(35), value: -120);
        final reduced = planHardwareOutput(s, at(35));
        equal(reduced.deadlineWallMs, epoch.wall + 180000);
        equal(reduced.replaces(added), true);
      },
  'Pause freezes Matrix digits; resume starts from the preserved remaining time':
      () {
        var s = service();
        s = transition(s, 'pause', at(30));
        final paused = planHardwareOutput(s, at(30));
        equal(paused.kind.name, 'text');
        equal(paused.reason.name, 'paused');
        equal(paused.layout!.text, '02:30');
        equal(paused.layout!.font, 'cuekeeper_matrix');
        equal(paused.layout!.height, 2);
        equal(paused.requiresAlignedControllerClock, false);
        equal(planHardwareOutput(s, at(59)).fingerprint, paused.fingerprint);
        s = transition(s, 'pause', at(60));
        final resumed = planHardwareOutput(s, at(60));
        equal(resumed.deadlineWallMs, epoch.wall + 210000);
        equal(paused.isCurrent(s, at(60), connectionGeneration: 0), false);
      },
  'Manual cue restores the original deadline rather than restarting the timer':
      () {
        var s = service();
        const cue = TextLayout(
          'AMEN',
          font: 'cuekeeper_sq_matrix',
          bold: true,
          italic: true,
          speed: 18,
          height: 2,
        );
        final timer = planHardwareOutput(s, epoch);
        s = transition(s, 'cue', at(15), value: cue);
        final message = planHardwareOutput(s, at(15));
        equal(message.reason.name, 'manualCue');
        equal(message.layout!.toJson(), cue.toJson());
        equal(planHardwareOutput(s, at(35)).fingerprint, message.fingerprint);
        s = transition(s, 'timer', at(45));
        final restored = planHardwareOutput(s, at(45));
        equal(s.remaining(at(45)), 135000);
        equal(restored.deadlineWallMs, timer.deadlineWallMs);
        equal(restored.replaces(message), true);
      },
  'Automatic warning expires without a revision and restores countdown': () {
    var s = service(
      warnings: const [
        WarningRule(150, TextLayout('WARN'), destination: 'stage'),
      ],
    );
    s = transition(s, 'cue', at(10), value: const TextLayout('MANUAL'));
    s = transition(s, 'warnings', at(30));
    final warning = planHardwareOutput(s, at(30));
    equal(warning.reason.name, 'automaticCue');
    equal(warning.layout!.text, 'WARN');
    equal(warning.isCurrent(s, at(37), connectionGeneration: 0), true);
    equal(warning.isCurrent(s, at(38), connectionGeneration: 0), false);
    equal(planHardwareOutput(s, at(38)).reason.name, 'running');
  },
  'Automatic cue restores the correct deadline; an expired timer stays at zero':
      () {
        var s = service(
          firstMinutes: 1,
          warnings: const [
            WarningRule(30, TextLayout('WARN'), destination: 'stage'),
            WarningRule(0, TextLayout('DONE'), destination: 'stage'),
          ],
        );
        final timer = planHardwareOutput(s, epoch);
        s = transition(s, 'warnings', at(30));
        equal(
          planHardwareOutput(s, at(38)).deadlineWallMs,
          timer.deadlineWallMs,
        );
        s = transition(s, 'warnings', at(60));
        equal(planHardwareOutput(s, at(67)).layout!.text, 'DONE');
        equal(planHardwareOutput(s, at(68)).layout!.text, '00:00');
        equal(planHardwareOutput(s, at(90)).layout!.text, '00:00');
      },
  'Zero and overtime never wrap or emit negative countdown digits': () {
    final s = service(firstMinutes: 1);
    final timer = planHardwareOutput(s, at(59));
    equal(timer.kind.name, 'countdown');
    final zero = planHardwareOutput(s, at(60));
    equal(zero.kind.name, 'text');
    equal(zero.reason.name, 'atZero');
    equal(zero.layout!.text, '00:00');
    equal(timer.isCurrent(s, at(60), connectionGeneration: 0), false);
    equal(planHardwareOutput(s, at(600)).fingerprint, zero.fingerprint);
  },
  'At Zero and service end preserve the configured text styles': () {
    var s = service(firstMinutes: 1);
    const zero = TextLayout('FINISH', bold: true, font: 'cuekeeper_sq_matrix');
    const end = TextLayout('AMEN', italic: true, font: 'tinos', height: 2);
    s.timeline = s.timeline!.withDisplay(
      DisplaySettings(zero: zero, end: end, warnings: const []),
    );
    equal(planHardwareOutput(s, at(70)).layout!.toJson(), zero.toJson());
    s = transition(s, 'end', at(70));
    final ended = planHardwareOutput(s, at(70));
    equal(ended.reason.name, 'endScreen');
    equal(ended.layout!.toJson(), end.toJson());
  },
  'Explicit blank replaces output and timer restore does not reset remaining time':
      () {
        var s = service();
        final timer = planHardwareOutput(s, epoch);
        s = transition(s, 'blank', at(30));
        final blank = planHardwareOutput(s, at(30));
        equal(blank.kind.name, 'blank');
        equal(blank.layout, null);
        equal(blank.replaces(timer), true);
        equal(planHardwareOutput(s, at(50)).replaces(blank), false);
        s = transition(s, 'timer', at(60));
        equal(
          planHardwareOutput(s, at(60)).deadlineWallMs,
          timer.deadlineWallMs,
        );
      },
  'Idle and ready retain the previous sign program rather than clearing it':
      () {
        var s = Session(id: 'idle', anchor: epoch);
        final idle = planHardwareOutput(s, epoch);
        equal(idle.kind.name, 'retain');
        equal(idle.replaces(null), false);
        s = transition(s, 'load', epoch, value: service().timeline!);
        final ready = planHardwareOutput(s, epoch);
        equal(ready.reason.name, 'ready');
        equal(ready.canPublish, false);
      },
  'Held, disconnected and uncertain sessions suppress writes and stale results':
      () {
        final original = service();
        final timer = planHardwareOutput(original, epoch);
        for (final flag in ['held', 'disconnected', 'uncertain']) {
          final s = original.copy();
          if (flag == 'held') s.held = true;
          if (flag == 'disconnected') s.disconnected = true;
          if (flag == 'uncertain') s.uncertain = true;
          blockedAs(planHardwareOutput(s, at(10)), flag);
          equal(timer.isCurrent(s, at(10), connectionGeneration: 0), false);
          s.outputBlank = true;
          blockedAs(planHardwareOutput(s, at(10)), flag);
        }
      },
  'Unrelated revision needs no retransmit but invalidates its old async guard':
      () {
        final original = service();
        final timer = planHardwareOutput(original, epoch);
        final changed = transition(original, 'dismissWarning', at(10));
        final desired = planHardwareOutput(changed, at(10));
        equal(desired.fingerprint, timer.fingerprint);
        equal(desired.replaces(timer), false);
        equal(timer.isCurrent(changed, at(10), connectionGeneration: 0), false);
      },
  'Reconnect generation and a new session prevent stale acknowledgement reuse':
      () {
        final s = service();
        final old = planHardwareOutput(s, epoch, connectionGeneration: 3);
        final reconnected = planHardwareOutput(
          s,
          at(10),
          connectionGeneration: 4,
        );
        equal(reconnected.replaces(old), true);
        equal(old.isCurrent(s, at(10), connectionGeneration: 4), false);
        final newSession = s.copy()..id = 'new-service';
        equal(
          old.isCurrent(newSession, at(10), connectionGeneration: 3),
          false,
        );
        equal(
          planHardwareOutput(
            newSession,
            at(10),
            connectionGeneration: 3,
          ).replaces(old),
          true,
        );
      },
  'Next segment is a new intent even when its deadline coincides': () {
    var s = service();
    final first = planHardwareOutput(s, epoch);
    s = transition(s, 'advance', at(60));
    final next = planHardwareOutput(s, at(60));
    equal(next.deadlineWallMs, first.deadlineWallMs);
    equal(next.replaces(first), true);
    equal(first.isCurrent(s, at(60), connectionGeneration: 0), false);
  },
  'Wall-clock jumps block native deadlines; minor sampling jitter stays stable':
      () {
        final s = service();
        final first = planHardwareOutput(s, epoch);
        for (final shift in [-3600000, 3600000]) {
          blockedAs(
            planHardwareOutput(s, at(10, wallShift: shift)),
            'clockChanged',
          );
          equal(
            first.isCurrent(
              s,
              at(10, wallShift: shift),
              connectionGeneration: 0,
            ),
            false,
          );
        }
        equal(
          planHardwareOutput(s, at(10, wallShift: 200)).fingerprint,
          first.fingerprint,
        );
      },
  'Reboot, unknown boot and backwards monotonic observations cannot drive output':
      () {
        final s = service();
        blockedAs(
          planHardwareOutput(s, at(10, boot: 'other-boot')),
          'untrustedClock',
        );
        blockedAs(
          planHardwareOutput(s, at(10, boot: 'unknown')),
          'untrustedClock',
        );
        blockedAs(
          planHardwareOutput(s, const Stamp(1, 1800000001000, 'boot-a')),
          'untrustedClock',
        );
      },
  'Native range prevents hidden-hour rollover and rejects out-of-range static digits':
      () {
        final s = service(firstMinutes: 60);
        blockedAs(planHardwareOutput(s, epoch), 'countdownRange');
        equal(planHardwareOutput(s, at(1)).kind.name, 'countdown');
        s.baseMs = maxRemainingMs;
        blockedAs(planHardwareOutput(s, epoch), 'countdownRange');
        equal(
          planHardwareOutput(
            s,
            epoch,
            maximumCountdownMs: maxRemainingMs,
          ).kind.name,
          'countdown',
        );
        s.paused = true;
        equal(planHardwareOutput(s, epoch).layout!.text, '99:59');
        s.baseMs = maxRemainingMs + 1;
        blockedAs(planHardwareOutput(s, epoch), 'countdownRange');
        rejects(
          () => planHardwareOutput(
            s,
            epoch,
            maximumCountdownMs: maxRemainingMs + 1,
          ),
        );
      },
  'Accelerated rehearsals cannot send countdown, cue, blank or end output': () {
    for (final rate in [5, 10, 30, 60]) {
      var s = service(rate: rate);
      blockedAs(planHardwareOutput(s, epoch), 'acceleratedRehearsal');
      s = transition(s, 'cue', epoch, value: const TextLayout('TEST'));
      blockedAs(planHardwareOutput(s, epoch), 'acceleratedRehearsal');
      s = transition(s, 'blank', epoch);
      blockedAs(planHardwareOutput(s, epoch), 'acceleratedRehearsal');
      s = transition(s, 'end', epoch);
      blockedAs(planHardwareOutput(s, epoch), 'acceleratedRehearsal');
    }
  },
  'Invalid timeline state fails closed without throwing a null dereference':
      () {
        final s = service()..timeline = null;
        blockedAs(planHardwareOutput(s, epoch), 'invalidSession');
        rejects(
          () => planHardwareOutput(service(), epoch, connectionGeneration: -1),
        );
      },
};
