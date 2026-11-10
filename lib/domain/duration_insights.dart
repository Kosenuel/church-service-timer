import 'dart:math' as math;
import 'package:church_service_timer/domain/domain.dart';

class DurationInsight {
  final int index, samples, exceeded, suggestedMinutes, currentMinutes;
  final String name;
  const DurationInsight(
    this.index,
    this.name,
    this.samples,
    this.exceeded,
    this.suggestedMinutes,
    this.currentMinutes,
  );
}

/// Comparable normal-speed services only; unique names prevent ambiguous matches.
/// Use the last five observations and a median of active time, excluding pauses.
List<DurationInsight> durationInsights(
  Timeline program,
  List<ServiceReport> reports,
) {
  final records =
      reports
          .where(
            (r) =>
                r.name.trim().toLowerCase() ==
                    program.name.trim().toLowerCase() &&
                r.comparable &&
                !r.rehearsal &&
                !r.quickTimer &&
                r.program?.type != 'rehearsal',
          )
          .toList()
        ..sort((a, b) => b.endedWall.compareTo(a.endedWall));
  final result = <DurationInsight>[];
  for (var i = 0; i < program.segments.length; i++) {
    final segment = program.segments[i];
    final key = segment.name.trim().toLowerCase();
    if (program.segments
            .where((v) => v.name.trim().toLowerCase() == key)
            .length !=
        1)
      continue;
    final durations = <int>[];
    var exceeded = 0;
    for (final r in records) {
      final rows = r.rows
          .where((v) => v.name.trim().toLowerCase() == key)
          .toList();
      if (rows.length != 1 || rows.single.actualMs == null) continue;
      final row = rows.single;
      final active = math.max(0, row.actualMs! - row.pausedMs);
      if (active == 0) continue;
      durations.add(active);
      if (active > row.plannedMs + 1000) exceeded++;
      if (durations.length == 5) break;
    }
    if (durations.length < 3) continue;
    durations.sort();
    final middle = durations.length ~/ 2;
    final median = durations.length.isOdd
        ? durations[middle]
        : (durations[middle - 1] + durations[middle]) ~/ 2;
    final suggested = (median / 60000).ceil().clamp(1, 59);
    result.add(
      DurationInsight(
        i,
        segment.name,
        durations.length,
        exceeded,
        suggested,
        segment.minutes,
      ),
    );
  }
  return result;
}
