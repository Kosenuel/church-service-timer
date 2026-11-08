import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/hardware_output.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  // Starts 90 minutes after the test epoch.
  final startsAt = start.wall + 90 * 60000;
  Session scheduled() =>
      transition(loaded(), 'schedule', start, value: startsAt);

  test('Clock until the last hour, then a countdown, then Starting soon', () {
    final s = scheduled();
    expect(s.held, isFalse);
    expect(s.outputMode(after(0)), 'Pre-service');
    expect(
      s.intended(after(10 * 60))!.toJson(),
      clockLayout(after(10 * 60).wall, s.clockFormat).toJson(),
    );
    expect(s.intended(after(60 * 60))!.text, '30:00');
    expect(s.intended(after(90 * 60)), startingSoonLayout);
    expect(s.phase, 'ready', reason: 'Never starts by itself');
  });

  test('The sign gets a clock, then one stable native countdown', () {
    final s = scheduled();
    expect(
      planHardwareOutput(s, after(10 * 60)).kind,
      HardwareOutputKind.clock,
    );
    final a = planHardwareOutput(s, after(60 * 60));
    final b = planHardwareOutput(s, after(61 * 60));
    expect(a.kind, HardwareOutputKind.countdown);
    expect(a.deadlineWallMs, startsAt);
    expect(a.fingerprint, b.fingerprint);
    final soon = planHardwareOutput(s, after(91 * 60));
    expect(soon.kind, HardwareOutputKind.text);
    expect(soon.layout, startingSoonLayout);
  });

  test(
    'Scheduling validates the time, can be cleared, and Start clears it',
    () {
      expect(
        () => transition(loaded(), 'schedule', start, value: start.wall - 1),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => transition(
          loaded(),
          'schedule',
          start,
          value: start.wall + 25 * 3600000,
        ),
        throwsA(isA<RuleError>()),
      );
      final cleared = transition(
        scheduled(),
        'schedule',
        after(1),
        value: null,
      );
      expect(cleared.startsAtWall, isNull);
      expect(cleared.intended(after(2)), isNull);
      final started = transition(scheduled(), 'start', after(5));
      expect(started.startsAtWall, isNull);
      expect(Session.fromJson(scheduled().toJson()).startsAtWall, startsAt);
    },
  );
}
