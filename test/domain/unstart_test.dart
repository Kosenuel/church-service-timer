import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'service_timing_test.dart' show after, running, start;

void main() {
  test('An accidental start can be undone back to Ready within moments', () {
    final s = transition(running(), 'unstart', after(5));
    expect(s.phase, 'ready');
    expect(s.run, isNull);
    expect(s.held, isTrue);
    expect(s.baseMs, s.timeline!.segments.first.durationMs);
    // Starting again behaves like a fresh start.
    final again = transition(s, 'start', after(6));
    expect(again.phase, 'active');
    expect(again.index, 0);
  });

  test('Undo start is refused after the window or once advanced', () {
    expect(
      () => transition(running(), 'unstart', after(16)),
      throwsA(isA<RuleError>()),
    );
    final advanced = transition(running(), 'advance', after(2));
    expect(
      () => transition(advanced, 'unstart', after(3)),
      throwsA(isA<RuleError>()),
    );
    expect(start.mono, isNotNull);
  });
}
