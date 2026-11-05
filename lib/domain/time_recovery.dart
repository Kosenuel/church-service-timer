import 'dart:math' as math;
import 'package:church_service_timer/domain/domain.dart';

/// Backward-compatible minutes API; the editor supports second precision.
List<Segment> timeRecoveryPlan(Session s, int minutes) =>
    timeRecoveryPlanSeconds(s, minutes * 60);

List<Segment> timeRecoveryPlanSeconds(Session s, int seconds) {
  require(s.active && !s.uncertain, 'Review the running service first.');
  require(seconds > 0, 'Choose time to recover.');
  final upcoming = s.timeline!.segments.skip(s.index + 1).toList();
  final allocation = upcoming.map((v) => v.durationSeconds).toList();
  final capacity = upcoming.fold<int>(
    0,
    (n, v) => n + (v.protected ? 0 : math.max(0, v.durationSeconds - 60)),
  );
  require(
    seconds <= capacity,
    'Only ${durationLabel(capacity * 1000)} can be recovered while keeping protected segments and a one-minute minimum.',
  );
  for (var remaining = seconds; remaining > 0;) {
    var index = -1;
    for (var i = 0; i < upcoming.length; i++) {
      if (!upcoming[i].protected &&
          allocation[i] > 60 &&
          (index < 0 || allocation[i] > allocation[index]))
        index = i;
    }
    final take = math.min(remaining, math.min(60, allocation[index] - 60));
    allocation[index] -= take;
    remaining -= take;
  }
  return [
    for (var i = 0; i < upcoming.length; i++)
      Segment(
        upcoming[i].name,
        allocation[i] ~/ 60,
        seconds: allocation[i] % 60,
        speaker: upcoming[i].speaker,
        notes: upcoming[i].notes,
        protected: upcoming[i].protected,
      ),
  ];
}
