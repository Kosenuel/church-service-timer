import 'dart:convert';
import 'dart:math' as math;
import 'domain.dart';

class PrintPreferences {
  final bool watermark, inkSaving;
  const PrintPreferences({this.watermark = true, this.inkSaving = false});
  factory PrintPreferences.fromJson(Json j) => PrintPreferences(
    watermark: boolSetting(j['watermark'] ?? true),
    inkSaving: boolSetting(j['inkSaving'] ?? false),
  );
  Json toJson() => {'watermark': watermark, 'inkSaving': inkSaving};
}

int notificationTimeoutValue(dynamic value) {
  require(
    value is int && {0, 15, 30, 60}.contains(value),
    'Choose 15, 30, 60 seconds or Until dismissed.',
  );
  return value as int;
}

/// Drafts are local, bounded and never included in portable backups or pairing.
Map<String, Json> readEditDrafts(dynamic value) {
  if (value == null) return {};
  require(value is Map && value.length <= 50, 'Invalid saved drafts.');
  require(
    utf8.encode(jsonEncode(value)).length <= 2 * 1024 * 1024,
    'Saved drafts exceed 2 MiB.',
  );
  return {
    for (final e in (value as Map).entries)
      e.key as String: Map<String, dynamic>.from(e.value),
  };
}

/// Does not parse the whole program: drafts can have an empty name or rundown.
Timeline programFromDraft(Json raw, DisplaySettings defaults) => Timeline(
  raw['name'] as String,
  (raw['segments'] as List)
      .map((v) => Segment.fromJson(Map<String, dynamic>.from(v)))
      .toList(),
  defaults.withEnd(TextLayout.fromJson(Map<String, dynamic>.from(raw['end']))),
  type: raw['type'] as String,
);

QuickMessage messageFromDraft(Json j) => QuickMessage(
  headline: j['headline'] as String? ?? '',
  body: j['body'] as String? ?? '',
  bold: j['bold'] == true,
  italic: j['italic'] == true,
  requestSeen: j['requestSeen'] == true,
  align: j['align'] as String? ?? 'center',
  palette: j['palette'] as String? ?? 'white',
  seconds: j['seconds'] as int? ?? 10,
  scale: (j['scale'] as num? ?? 1).toDouble(),
);

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

String preparedDateLabel(int wall) {
  final d = DateTime.fromMillisecondsSinceEpoch(wall);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final zone = d.timeZoneOffset;
  final offset =
      '${zone.isNegative ? '-' : '+'}${zone.inHours.abs().toString().padLeft(2, '0')}:${(zone.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${printClockLabel(wall)} (UTC$offset)';
}
