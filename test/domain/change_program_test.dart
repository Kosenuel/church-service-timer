import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'service_timing_test.dart' show after, loaded, running, start;

final other = Timeline('Evening', const [
  Segment('Welcome', 3),
  Segment('Talk', 20),
], DisplaySettings());

void main() {
  test('Loading over Ready swaps the program and keeps the setup', () {
    final startsAt = start.wall + 90 * 60000;
    var s = transition(loaded(), 'schedule', start, value: startsAt);
    s = transition(s, 'rate', after(1), value: 5);
    final swapped = transition(s, 'load', after(2), value: other);
    expect(swapped.phase, 'ready');
    expect(swapped.timeline!.name, 'Evening');
    expect(swapped.baseMs, 3 * 60000);
    expect(swapped.startsAtWall, startsAt);
    expect(swapped.rate, 5);
    // Same anchor: the sign's countdown deadline does not move.
    expect(swapped.anchor.mono, s.anchor.mono);
    // Cancel setup still returns to what was before the first load.
    final cancelled = transition(swapped, 'cancelReady', after(3));
    expect(cancelled.phase, 'idle');
    expect(cancelled.timeline, isNull);
  });

  test('A fresh load starts at live timing with no schedule', () {
    final s = transition(loaded(), 'load', after(1), value: other);
    expect(s.startsAtWall, isNull);
    expect(s.rate, 1);
  });

  test('A running service cannot be swapped', () {
    expect(
      () => transition(running(), 'load', after(1), value: other),
      throwsA(isA<RuleError>()),
    );
  });
}
