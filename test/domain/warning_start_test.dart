import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// A warning fires when the countdown comes down to its time during a
/// segment, never the moment a segment starts with that time or less.
void main() {
  const t0 = Stamp(0, 1700000000000, 'boot');
  Stamp at(int ms) => Stamp(t0.mono + ms, t0.wall + ms, t0.boot);
  const fiveMin = WarningRule(300, TextLayout('5 MIN LEFT'));
  const zero = WarningRule(0, TextLayout("TIME'S UP"));

  Session started(List<Segment> segments, {int rate = 1}) {
    var s = transition(
      Session(id: 's', anchor: t0),
      'load',
      t0,
      value: Timeline(
        'Service',
        segments,
        DisplaySettings(warnings: const [fiveMin, zero]),
      ),
    );
    if (rate != 1) s = transition(s, 'rate', t0, value: rate);
    return transition(s, 'start', t0);
  }

  List<String> due(Session s, Stamp now) => [
    for (final i in dueWarnings(s, now))
      s.timeline!.display.warnings[i].cue.text,
  ];

  test('a 5:00 segment does not start with 5 MIN LEFT', () {
    final s = started(const [Segment('Talk', 5)]);
    expect(due(s, t0), isEmpty);
    expect(due(s, at(1000)), isEmpty);
    expect(s.nearWarning(at(1000)), isFalse);
    expect(due(s, at(4 * 60000)), isEmpty);
    // TIME'S UP still fires at zero.
    expect(due(s, at(5 * 60000)), ["TIME'S UP"]);
  });

  test('a 6:00 segment fires 5 MIN LEFT at 5:00', () {
    final s = started(const [Segment('Talk', 6)]);
    expect(due(s, t0), isEmpty);
    expect(due(s, at(59999)), isEmpty);
    expect(due(s, at(60000)), ['5 MIN LEFT']);
    final fired = transition(s, 'warnings', at(60000));
    expect(fired.warningSeen, [0]);
    expect(dueWarnings(fired, at(61000)), isEmpty);
    expect(due(fired, at(6 * 60000)), ["TIME'S UP"]);
  });

  test('the next segment follows the same rule', () {
    var s = started(const [Segment('One', 6), Segment('Two', 5)]);
    s = transition(s, 'advance', at(1000));
    expect(due(s, at(1000)), isEmpty);
    expect(due(s, at(2000)), isEmpty);
    expect(due(s, at(1000 + 5 * 60000)), ["TIME'S UP"]);
    // Undo brings back the first segment as it was.
    s = transition(s, 'undo', at(3000));
    expect(due(s, at(3000)), isEmpty);
    expect(due(s, at(60000)), ['5 MIN LEFT']);
  });

  test('time added above a warning lets it fire when the countdown comes '
      'down to it again', () {
    // 5:00 segment; at 4:00 left add two minutes, so 6:00 left.
    var s = started(const [Segment('Talk', 5)]);
    s = transition(s, 'adjust', at(60000), value: 120);
    expect(due(s, at(60000)), isEmpty);
    expect(due(s, at(60000 + 59999)), isEmpty);
    expect(due(s, at(120000)), ['5 MIN LEFT']);
    s = transition(s, 'warnings', at(120000));
    // Once fired, adding time again never fires it again in this segment.
    s = transition(s, 'adjust', at(130000), value: 120);
    expect(due(s, at(130000 + 3 * 60000)), isEmpty);
  });

  test('time added that comes back to exactly the warning does not fire it '
      'at once', () {
    // 5:00 segment; at 4:00 left add one minute, so 5:00 left again.
    var s = started(const [Segment('Talk', 5)]);
    s = transition(s, 'adjust', at(60000), value: 60);
    expect(s.remaining(at(60000)), 300000);
    expect(due(s, at(60000)), isEmpty);
  });

  test('a time removed past a warning still fires it', () {
    var s = started(const [Segment('Talk', 10)]);
    s = transition(s, 'adjust', at(1000), value: -300);
    expect(due(s, at(1000)), ['5 MIN LEFT']);
  });

  test('rehearsal speeds follow the same rule', () {
    for (final rate in [5, 10, 30, 60]) {
      final five = started(const [Segment('Talk', 5)], rate: rate);
      expect(due(five, t0), isEmpty, reason: '$rate×');
      expect(due(five, at(100)), isEmpty, reason: '$rate×');
      expect(due(five, at(300000 ~/ rate)), ["TIME'S UP"], reason: '$rate×');
      final six = started(const [Segment('Talk', 6)], rate: rate);
      expect(due(six, at(60000 ~/ rate - 1)), isEmpty, reason: '$rate×');
      expect(due(six, at(60000 ~/ rate)), ['5 MIN LEFT'], reason: '$rate×');
    }
  });

  test('Check this service lists a warning as long as its segment as '
      'unable to fire', () {
    final t = Timeline('Service', const [
      Segment('Five', 5),
      Segment('Six', 6),
      Segment('Four', 4),
    ], DisplaySettings(warnings: const [fiveMin, zero]));
    expect(
      [
        for (final w in unreachableWarnings(t))
          '${w.segment} ${w.rule.cue.text}',
      ],
      ['0 5 MIN LEFT', '2 5 MIN LEFT'],
    );
    final run = ServiceCheckRun(t, t0);
    while (!run.done) {
      run.step(50);
    }
    expect(
      [for (final w in run.fired) '${w.segment} ${w.rule.cue.text}'],
      ['0 TIME\'S UP', '1 5 MIN LEFT', '1 TIME\'S UP', '2 TIME\'S UP'],
    );
    expect(formatTime(run.firedIn(1).first.remainingMs!), '05:00');
  });
}
