import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  test('An accidental start can be undone back to Ready within moments', () {
    final s = transition(running(), 'unstart', after(5));
    expect(s.phase, 'ready');
    expect(s.run, isNull);
    expect(s.held, isFalse, reason: 'Nothing timed in Ready to review');
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

  test('Cancelling a setup holds output only if the display missed some', () {
    // A normal end: the end screen was shown, so nothing needs review.
    var ended = transition(running(), 'end', after(10));
    var s = transition(ended, 'load', after(11), value: timeline());
    s = transition(s, 'cancelReady', after(12));
    expect(s.held, isFalse);
    // Ended while disconnected: its end screen is still pending.
    ended = transition(
      transition(running(), 'disconnect', after(1)),
      'end',
      after(10),
    );
    s = transition(ended, 'load', after(11), value: timeline());
    s = transition(s, 'cancelReady', after(12));
    expect(s.held, isTrue);
  });
}
