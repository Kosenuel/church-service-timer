// Runs with the Dart SDK alone when Flutter process launching is unavailable.
import 'dart:io';
import '../lib/domain.dart';

void main() {
  var checks = 0;
  void check(bool ok, String label) {
    if (!ok) throw StateError('FAIL: $label');
    checks++;
  }

  void rejects(void Function() body, String label) {
    var failed = false;
    try {
      body();
    } on RuleError {
      failed = true;
    }
    check(failed, label);
  }

  const origin = Stamp(100000, 10000000, 'boot');
  Stamp at(int seconds, {int shift = 0, String boot = 'boot'}) => Stamp(
    origin.mono + seconds * 1000,
    origin.wall + seconds * 1000 + shift,
    boot,
  );
  final timeline = Timeline('Rehearsal', const [
    Segment('First', 10),
    Segment('Second', 5),
  ], DisplaySettings());
  Session ready() => transition(
    Session(id: 'idle', anchor: origin),
    'load',
    origin,
    value: timeline,
  );
  Session running() => transition(ready(), 'start', origin);
  check(
    ready().remaining(at(100)) == 600000 && ready().intended(at(100)) == null,
    'Ready does not run or output',
  );
  check(
    running().formatted(at(90)) == '08:30',
    'Elapsed time survives missed callbacks',
  );
  check(
    running().formatted(at(90, shift: -8000000)) == '08:30',
    'Wall clock changes do not affect active time',
  );
  var s = transition(running(), 'pause', at(90));
  check(s.formatted(at(900)) == '08:30', 'Pause freezes');
  s = transition(s, 'pause', at(900));
  check(s.formatted(at(930)) == '08:00', 'Resume continues');
  s = transition(running(), 'cue', at(90), value: const TextLayout('WAIT'));
  check(
    s.formatted(at(120)) == '08:00' && s.intended(at(120))!.text == 'WAIT',
    'Cue covers a running timer',
  );
  s = transition(s, 'cue', at(121), value: const TextLayout('STOP'));
  check(s.alert!.text == 'STOP', 'Latest cue replaces');
  s = transition(s, 'timer', at(122));
  check(s.intended(at(122))!.text == '07:58', 'Dismiss shows current timer');
  s = transition(running(), 'advance', at(420));
  check(s.formatted(at(425)) == '04:55', 'Advance starts next timer');
  check(s.fastUndo(at(430)) && !s.fastUndo(at(431)), 'Quick undo boundary');
  s = transition(s, 'undo', at(425));
  check(
    s.formatted(at(425)) == '02:55' && s.undo == null,
    'Undo accounts for elapsed and consumes checkpoint',
  );
  s = transition(running(), 'pause', at(420));
  s = transition(s, 'advance', at(421));
  check(!s.paused, 'Advance from pause runs');
  s = transition(s, 'undo', at(426));
  check(
    s.paused && s.formatted(at(999)) == '03:00',
    'Undo restores prior pause',
  );
  s = transition(running(), 'advance', at(1));
  s = transition(s, 'adjust', at(2), value: 120);
  check(!s.fastUndo(at(3)), 'Adjustment requires undo confirmation');
  rejects(
    () => transition(s, 'advance', at(3)),
    'No advance past final segment',
  );
  s = transition(running(), 'adjust', at(900), value: 30);
  check(s.formatted(at(910)) == '00:20', 'Add after zero runs');
  s = transition(s, 'adjust', at(910), value: -120);
  check(s.remaining(at(910)) == 0, 'Subtract clamps zero');
  s = transition(s, 'adjust', at(910), value: 5999);
  check(s.formatted(at(910)) == '99:59', 'Upper boundary accepted');
  rejects(
    () => transition(s, 'adjust', at(910), value: 1),
    'Over maximum rejected',
  );
  check(
    !recover(running(), at(1799)).held && recover(running(), at(1800)).held,
    'Recovery age boundary',
  );
  s = recover(running(), at(90, boot: 'new'));
  check(
    s.uncertain && s.held && s.baseMs == 510000,
    'Reboot is uncertain with wall fallback',
  );
  s = transition(running(), 'disconnect', at(0));
  s = transition(s, 'connect', at(1800));
  check(s.held, 'Long disconnection holds output');
  s = transition(s, 'end', at(1801));
  check(s.alert == null && s.phase == 'ended', 'End clears and stops');
  s = transition(s, 'load', at(1802), value: timeline);
  check(s.intended(at(1803)) == null, 'New Ready cancels old end output');
  s = transition(s, 'cancelReady', at(1804));
  check(s.held, 'Cancel does not revive old output');
  rejects(
    () => transition(running(), 'advance', at(0), expectedRevision: 0),
    'Stale confirmation rejected',
  );
  final restored = importTemplate(
    exportJson(timeline),
    'roundtrip.json',
    DisplaySettings(),
  );
  check(exportJson(restored) == exportJson(timeline), 'JSON round trip');
  final csv = importTemplate(
    exportCsv(timeline),
    'Rehearsal.csv',
    DisplaySettings(),
  );
  check(exportCsv(csv) == exportCsv(timeline), 'CSV round trip');
  rejects(
    () => importTemplate(
      'Segment Name,Duration (Minutes)\nGood,1\nBad,0',
      'x.csv',
      DisplaySettings(),
    ),
    'Invalid row blocks entire import',
  );
  rejects(
    () => Timeline.fromJson(timeline.toJson()..['controller'] = 'no'),
    'Hardware field rejected',
  );
  rejects(
    () => importTemplate('x' * 1048577, 'x.csv', DisplaySettings()),
    'Oversized import rejected',
  );
  rejects(() => nameValue('a' * 81, 'Name'), 'Name limit');
  stdout.writeln(
    '$checks domain checks passed. Flutter widget and Android runtime tests are separate.',
  );
}
