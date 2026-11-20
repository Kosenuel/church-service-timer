import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';

const epoch = Stamp(1000000, 1800000000000, 'boot-a');
Stamp at(int seconds, {int wallShift = 0, String boot = 'boot-a'}) => Stamp(
  epoch.mono + seconds * 1000,
  epoch.wall + seconds * 1000 + wallShift,
  boot,
);

void equal(Object? actual, Object? expected) {
  if (jsonEncode(actual) != jsonEncode(expected)) {
    throw StateError(
      'Expected ${jsonEncode(expected)}, got ${jsonEncode(actual)}',
    );
  }
}

void rejects(void Function() action) {
  try {
    action();
  } on RuleError {
    return;
  }
  throw StateError('Expected RuleError');
}

Session service({
  int rate = 1,
  List<WarningRule>? warnings,
  int firstMinutes = 3,
}) {
  var s = transition(
    Session(id: 'idle', anchor: epoch),
    'load',
    epoch,
    value: Timeline('Service', [
      Segment('First', firstMinutes),
      const Segment('Second', 2),
    ], DisplaySettings(warnings: warnings)),
  );
  s = transition(s, 'rate', epoch, value: rate);
  return transition(s, 'start', epoch);
}

final featureCases = <String, void Function()>{
  'Overview counts pauses, time at zero and actual segment durations': () {
    var s = service();
    s = transition(s, 'pause', at(60));
    equal(s.remaining(at(90)), 120000);
    equal(s.totalElapsed(at(90)), 90000);
    equal(s.projectedTotal(at(90)), 330000);
    s = transition(s, 'pause', at(90));
    equal(s.remaining(at(220)), 0);
    equal(s.projectedTotal(at(220)), 340000);
    s = transition(s, 'advance', at(220));
    equal(s.run!.actualMs, [220000, null]);
    equal(s.run!.pausedMs, [30000, 0]);
    s = transition(s, 'end', at(300));
    equal(s.run!.actualMs, [220000, 80000]);
    equal(s.totalElapsed(at(900)), 300000);
    equal(s.projectedTotal(at(900)), 300000);
  },
  'Undo restores metrics and discards accidental segment adjustments': () {
    var s = transition(service(), 'advance', at(60));
    s = transition(s, 'adjust', at(62), value: 120);
    s = transition(s, 'undo', at(65));
    equal(s.index, 0);
    equal(s.run!.actualMs, [null, null]);
    equal(s.run!.adjustmentsMs, [0, 0]);
    equal(s.currentElapsed(at(70)), 70000);
    equal(s.totalElapsed(at(70)), 70000);
    equal(s.remaining(at(70)), 110000);
  },
  'Undo counts accidental time as a pause if previous segment was paused': () {
    var s = transition(service(), 'pause', at(10));
    s = transition(s, 'advance', at(30));
    s = transition(s, 'undo', at(35));
    equal(s.run!.pausedMs[0], 25000);
    equal(s.currentElapsed(at(40)), 40000);
    equal(s.remaining(at(40)), 170000);
  },
  'Fast rehearsal scales elapsed time and keeps undo window in real time': () {
    var s = service(rate: 10);
    equal(s.remaining(at(6)), 120000);
    equal(s.totalElapsed(at(6)), 60000);
    s = transition(s, 'advance', at(10));
    equal(s.run!.actualMs[0], 100000);
    equal(s.fastUndo(at(15)), true);
    s = transition(s, 'undo', at(15));
    equal(s.remaining(at(15)), 30000);
    equal(s.totalElapsed(at(15)), 150000);
    rejects(() => transition(s, 'rate', at(16), value: 1));
  },
  'Rehearsal pause freezes countdown but counts simulated service delay': () {
    var s = transition(service(rate: 30), 'pause', at(2));
    equal(s.remaining(at(7)), 120000);
    equal(s.totalElapsed(at(7)), 210000);
    s = transition(s, 'pause', at(7));
    equal(s.remaining(at(8)), 90000);
    equal(s.run!.pausedMs[0], 150000);
  },
  'Wall-clock changes do not change same-boot metrics': () {
    final s = service(rate: 5);
    equal(s.totalElapsed(at(10, wallShift: 99999999)), 50000);
    equal(s.remaining(at(10, wallShift: -99999999)), 130000);
  },
  'Recovered metrics retain elapsed time and uncertainty after reboot': () {
    var s = service();
    s = transition(s, 'pause', at(10));
    s = recover(s, at(30, boot: 'boot-b'));
    equal(s.totalElapsed(at(30, boot: 'boot-b')), 30000);
    equal(s.run!.pausedMs[0], 20000);
    equal(s.uncertain, true);
    equal(s.held, true);
  },
  'Operator warnings never replace the countdown': () {
    var s = service(
      warnings: [const WarningRule(120, TextLayout('2 MIN LEFT'))],
    );
    equal(dueWarnings(s, at(59)), []);
    s = transition(s, 'warnings', at(60));
    equal(s.warningSeen, [0]);
    equal(s.intended(at(60))!.text, '02:00');
    equal(s.warningNotice!.contains('2 MIN LEFT'), true);
  },
  'Delayed callbacks consume older thresholds and show only most urgent': () {
    var s = service(
      warnings: [
        const WarningRule(120, TextLayout('TWO'), destination: 'stage'),
        const WarningRule(30, TextLayout('THIRTY'), destination: 'stage'),
        const WarningRule(0, TextLayout('ZERO'), destination: 'stage'),
      ],
    );
    s = transition(s, 'warnings', at(181));
    equal(s.warningSeen, [0, 1, 2]);
    equal(s.intended(at(181))!.text, 'ZERO');
    equal(dueWarnings(s, at(190)), []);
    equal(s.intended(at(189))!.text, '00:00');
  },
  'Adding time does not rearm warnings; advancing starts a new set': () {
    var s = transition(service(), 'warnings', at(60));
    s = transition(s, 'adjust', at(61), value: 120);
    equal(dueWarnings(s, at(180)), []);
    s = transition(s, 'advance', at(181));
    equal(s.warningSeen, []);
    s = transition(s, 'warnings', at(181));
    equal(s.warningSeen, [1]);
    s = transition(s, 'undo', at(182));
    equal(s.warningSeen, [1]);
  },
  'Short segments skip warnings above their initial duration': () {
    final s = service(firstMinutes: 1);
    equal(dueWarnings(s, at(31)), [2]);
  },
  'Automatic warning replaces a manual cue and restores the current timer': () {
    var s = service(
      warnings: [
        const WarningRule(120, TextLayout('AUTO'), destination: 'stage'),
      ],
    );
    s = transition(s, 'cue', at(50), value: const TextLayout('MANUAL'));
    s = transition(s, 'warnings', at(60));
    equal(s.intended(at(60))!.text, 'AUTO');
    equal(s.intended(at(68))!.text, '01:52');
    s = transition(s, 'timer', at(61));
    equal(s.intended(at(61))!.text, '01:59');
    equal(dueWarnings(s, at(62)), []);
  },
  'Manual cue supersedes and permanently clears an automatic overlay': () {
    var s = service(
      warnings: [
        const WarningRule(120, TextLayout('AUTO'), destination: 'stage'),
      ],
    );
    s = transition(s, 'warnings', at(60));
    s = transition(s, 'cue', at(61), value: const TextLayout('MANUAL'));
    s = transition(s, 'timer', at(62));
    equal(s.intended(at(62))!.text, '01:58');
  },
  'Stage warnings last eight real seconds even in fast rehearsal': () {
    var s = service(
      rate: 10,
      warnings: [
        const WarningRule(120, TextLayout('AUTO'), destination: 'stage'),
      ],
    );
    s = transition(s, 'warnings', at(6));
    equal(s.intended(at(13))!.text, 'AUTO');
    equal(s.intended(at(14))!.text, '00:40');
  },
  'Disconnected warnings are consumed without stage replay': () {
    var s = service(
      warnings: [
        const WarningRule(120, TextLayout('AUTO'), destination: 'stage'),
      ],
    );
    s = transition(s, 'disconnect', at(10));
    s = transition(s, 'warnings', at(60));
    equal(s.automaticCue, null);
    s = transition(s, 'connect', at(61));
    equal(s.intended(at(61))!.text, '01:59');
  },
  'Recovery consumes elapsed warnings without replaying stage cues': () {
    var s = service(
      warnings: [
        const WarningRule(120, TextLayout('AUTO'), destination: 'stage'),
      ],
    );
    s = recover(s, at(70));
    equal(s.warningSeen, [0]);
    equal(s.automaticCue, null);
    equal(s.intended(at(70))!.text, '01:50');
  },
  'Paused countdowns defer warnings until resumed': () {
    var s = transition(service(), 'pause', at(60));
    equal(dueWarnings(s, at(100)), []);
    s = transition(s, 'pause', at(100));
    equal(dueWarnings(s, at(100)), [1]);
  },
  'Report survives reload with early-end rows and rehearsal flag': () {
    var s = service(rate: 10);
    s = transition(s, 'end', at(3));
    final report = ServiceReport.fromSession(s, at(3));
    final restored = ServiceReport.fromJson(
      jsonDecode(jsonEncode(report.toJson())) as Json,
    );
    equal(restored.totalMs, 30000);
    equal(restored.rehearsal, true);
    equal(restored.rows.map((r) => r.actualMs).toList(), [30000, null]);
    equal(
      jsonDecode(exportReportJson(restored))['type'],
      'church-service-timer-report',
    );
    equal(exportReportCsv(restored).contains('Not recorded'), true);
  },
  'Saved cues and templates round-trip every formatting field': () {
    const layout = TextLayout(
      'WRAP UP',
      bold: true,
      italic: true,
      height: 2,
      align: 'right',
      speed: 23,
      effect: 'scroll',
      font: 'tinos',
    );
    final state = AppState.fresh(epoch);
    state.stageCues.add(layout);
    state.defaults = state.defaults.withWarnings([
      const WarningRule(0, layout, destination: 'stage'),
    ]);
    state.templates[0] = Timeline(
      'Styled',
      const [Segment('Talk', 5)],
      DisplaySettings(
        cues: [layout, layout, layout, layout],
        warnings: [const WarningRule(0, layout, destination: 'stage')],
      ),
    );
    final loaded = AppState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Json,
    );
    equal(loaded.stageCues.last.toJson(), layout.toJson());
    final template = importTemplate(
      exportJson(state.templates.first),
      'styled.json',
      state.defaults,
    );
    equal(template.display.cues.first.toJson(), layout.toJson());
    equal(template.display.warnings.single.cue.toJson(), layout.toJson());
  },
  'Version-one templates retain Matrix font and no automatic stage warnings':
      () {
        final j = Timeline('Old', const [
          Segment('Talk', 5),
        ], DisplaySettings()).toJson();
        j['schemaVersion'] = 1;
        (j['display'] as Json).remove('warnings');
        for (final cue in (j['display']['cues'] as List)) {
          (cue as Json).remove('font');
        }
        (j['display']['end'] as Json).remove('font');
        final old = Timeline.fromJson(j);
        equal(old.display.cues.first.font, 'i-proton_matrix');
        equal(old.display.warnings.length, 0);
        equal(old.toJson()['schemaVersion'], 4);
      },
  'Invalid font and duplicate warning thresholds are rejected': () {
    rejects(
      () => TextLayout.fromJson({
        ...const TextLayout('A').toJson(),
        'font': 'missing',
      }),
    );
    rejects(
      () => readWarnings([
        defaultWarnings.first.toJson(),
        defaultWarnings.first.toJson(),
      ]),
    );
    rejects(
      () => WarningRule.fromJson({
        ...defaultWarnings.first.toJson(),
        'seconds': -1,
      }),
    );
  },
  'Warning and font settings survive unrelated cue edits': () {
    final d = DisplaySettings(
      warnings: [
        const WarningRule(
          20,
          TextLayout('STOP', font: 'tinos'),
          destination: 'stage',
        ),
      ],
    );
    final changed = d.withCues([
      ...d.cues.take(3),
      const TextLayout('NEW', italic: true),
    ]);
    equal(changed.warnings.single.toJson(), d.warnings.single.toJson());
  },
};
