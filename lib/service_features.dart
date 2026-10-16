part of 'domain.dart';

const displayFontNames = {
  'cuekeeper_matrix': 'Cuekeeper Matrix',
  'service_serif': 'Service Serif',
  'clear_sans': 'Clear Sans',
};

class WarningRule {
  final int seconds;
  final bool enabled;
  final String destination;
  final TextLayout cue;
  const WarningRule(
    this.seconds,
    this.cue, {
    this.enabled = true,
    this.destination = 'operator',
  });
  factory WarningRule.fromJson(Json j) {
    keys(j, {'seconds', 'enabled', 'destination', 'cue'}, 'Warning rule');
    require(
      j['seconds'] is int && j['seconds'] >= 0 && j['seconds'] <= 5999,
      'Warning time must be 0–99:59.',
    );
    require(
      j['enabled'] is bool && {'operator', 'stage'}.contains(j['destination']),
      'Invalid warning destination or enabled state.',
    );
    return WarningRule(
      j['seconds'],
      TextLayout.fromJson(Map<String, dynamic>.from(j['cue'])),
      enabled: j['enabled'],
      destination: j['destination'],
    );
  }
  Json toJson() => {
    'seconds': seconds,
    'enabled': enabled,
    'destination': destination,
    'cue': cue.toJson(),
  };
}

const defaultWarnings = [
  WarningRule(120, TextLayout('2 MIN LEFT')),
  WarningRule(30, TextLayout('WRAP UP', bold: true)),
  WarningRule(0, TextLayout("TIME'S UP", bold: true)),
];

List<WarningRule> readWarnings(dynamic value) {
  // Old templates retain their original behavior until warnings are configured.
  if (value == null) return [];
  require(value is List && value.length <= 6, 'Configure at most 6 warnings.');
  final rules = (value as List)
      .map((e) => WarningRule.fromJson(Map<String, dynamic>.from(e)))
      .toList();
  require(
    rules.map((r) => r.seconds).toSet().length == rules.length,
    'Each warning must use a different threshold.',
  );
  return rules;
}

List<int> dueWarnings(Session s, Stamp now) {
  if (!s.active || s.paused) return [];
  final remaining = s.remaining(now);
  return s.timeline!.display.warnings
      .asMap()
      .entries
      .where(
        (e) =>
            e.value.enabled &&
            !s.warningSeen.contains(e.key) &&
            e.value.seconds * 1000 < s.warningCeiling &&
            remaining <= e.value.seconds * 1000,
      )
      .map((e) => e.key)
      .toList();
}

void applyWarnings(Session s, Stamp now, {bool allowStage = true}) {
  final due = dueWarnings(s, now);
  if (due.isEmpty) return;
  // A delayed callback consumes all crossed thresholds, displaying only the
  // most urgent. Adding time never rearms a consumed warning in this segment.
  s.warningSeen.addAll(due);
  due.sort(
    (a, b) => s.timeline!.display.warnings[a].seconds.compareTo(
      s.timeline!.display.warnings[b].seconds,
    ),
  );
  final rule = s.timeline!.display.warnings[due.first];
  final canDisplay =
      allowStage && !s.held && !s.disconnected && s.alert == null;
  s.warningNotice =
      '${rule.cue.text} · ${rule.seconds == 0 ? 'Time complete' : '${formatTime(rule.seconds * 1000)} remaining'}';
  if (rule.destination == 'stage') {
    if (canDisplay) {
      s.automaticCue = rule.cue;
      s.automaticCueAt = now;
      s.warningNotice = '${s.warningNotice} · stage cue for 8 seconds';
    } else {
      s.warningNotice =
          '${s.warningNotice} · stage cue skipped (manual cue, held output, or recovery)';
    }
  }
}

class RunMetrics {
  final int startedWall;
  int? endedWall;
  Stamp anchor;
  int totalMs, currentMs;
  final List<int?> actualMs;
  final List<int> pausedMs, adjustmentsMs;
  RunMetrics(
    this.startedWall,
    this.anchor,
    this.actualMs,
    this.pausedMs,
    this.adjustmentsMs, {
    this.endedWall,
    this.totalMs = 0,
    this.currentMs = 0,
  });
  factory RunMetrics.fresh(Stamp now, int count) => RunMetrics(
    now.wall,
    now,
    List<int?>.filled(count, null),
    List.filled(count, 0),
    List.filled(count, 0),
  );
  factory RunMetrics.fromJson(Json j) {
    final r = RunMetrics(
      j['startedWall'],
      Stamp.fromJson(Map<String, dynamic>.from(j['anchor'])),
      List<int?>.from(j['actualMs']),
      List<int>.from(j['pausedMs']),
      List<int>.from(j['adjustmentsMs']),
      endedWall: j['endedWall'],
      totalMs: j['totalMs'],
      currentMs: j['currentMs'],
    );
    require(
      r.totalMs >= 0 &&
          r.currentMs >= 0 &&
          r.actualMs.every((n) => n == null || n >= 0) &&
          r.pausedMs.every((n) => n >= 0) &&
          r.actualMs.length == r.pausedMs.length &&
          r.actualMs.length == r.adjustmentsMs.length,
      'Invalid saved service metrics.',
    );
    return r;
  }
  Json toJson() => {
    'startedWall': startedWall,
    'endedWall': endedWall,
    'anchor': anchor.toJson(),
    'totalMs': totalMs,
    'currentMs': currentMs,
    'actualMs': [...actualMs],
    'pausedMs': [...pausedMs],
    'adjustmentsMs': [...adjustmentsMs],
  };
}

class SavedCue {
  final String name;
  final TextLayout layout;
  const SavedCue(this.name, this.layout);
  factory SavedCue.fromJson(Json j) => SavedCue(
    nameValue(j['name'], 'Cue name'),
    TextLayout.fromJson(Map<String, dynamic>.from(j['layout'])),
  );
  Json toJson() => {'name': name, 'layout': layout.toJson()};
}

class ReportRow {
  final String name;
  final int plannedMs, pausedMs, adjustmentMs;
  final int? actualMs;
  const ReportRow(
    this.name,
    this.plannedMs,
    this.actualMs,
    this.pausedMs,
    this.adjustmentMs,
  );
  factory ReportRow.fromJson(Json j) => ReportRow(
    j['name'],
    j['plannedMs'],
    j['actualMs'],
    j['pausedMs'],
    j['adjustmentMs'],
  );
  Json toJson() => {
    'name': name,
    'plannedMs': plannedMs,
    'actualMs': actualMs,
    'pausedMs': pausedMs,
    'adjustmentMs': adjustmentMs,
  };
}

class ServiceReport {
  final String id, name;
  final int? startedWall, totalMs;
  final int endedWall, rate;
  final bool uncertain;
  final List<ReportRow> rows;
  ServiceReport(
    this.id,
    this.name,
    this.startedWall,
    this.endedWall,
    this.totalMs,
    this.rate,
    this.uncertain,
    List<ReportRow> rows,
  ) : rows = List.unmodifiable(rows);
  factory ServiceReport.fromSession(Session s, Stamp now) {
    require(s.phase == 'ended', 'Reports are finalized when a service ends.');
    return ServiceReport(
      s.id,
      s.timeline!.name,
      s.run?.startedWall,
      now.wall,
      s.run?.totalMs,
      s.rate,
      s.uncertain || s.run == null,
      s.timeline!.segments
          .asMap()
          .entries
          .map(
            (e) => ReportRow(
              e.value.name,
              e.value.minutes * 60000,
              s.run?.actualMs[e.key],
              s.run?.pausedMs[e.key] ?? 0,
              s.run?.adjustmentsMs[e.key] ?? 0,
            ),
          )
          .toList(),
    );
  }
  bool get rehearsal => rate > 1;
  int get plannedMs => rows.fold(0, (n, row) => n + row.plannedMs);
  factory ServiceReport.fromJson(Json j) => ServiceReport(
    j['id'],
    j['name'],
    j['startedWall'],
    j['endedWall'],
    j['totalMs'],
    j['rate'],
    j['uncertain'],
    (j['rows'] as List)
        .map((e) => ReportRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'startedWall': startedWall,
    'endedWall': endedWall,
    'totalMs': totalMs,
    'rate': rate,
    'uncertain': uncertain,
    'rows': rows.map((e) => e.toJson()).toList(),
  };
}

String exportReportJson(ServiceReport r) =>
    const JsonEncoder.withIndent('  ').convert({
      'type': 'cuekeeper-service-report',
      'schemaVersion': 1,
      ...r.toJson(),
    });

String exportReportCsv(ServiceReport r) {
  String textCell(String s) {
    final safe = RegExp(r'^[=+@\-]').hasMatch(s) ? "'$s" : s;
    return '"${safe.replaceAll('"', '""')}"';
  }

  String seconds(int? n) => n == null ? '' : (n / 1000).toStringAsFixed(3);
  final header =
      'Service,Mode,Speed,Started,Ended,Timing uncertain,Segment,Planned seconds,Actual seconds,Variance seconds,Paused seconds,Adjustment seconds,Status';
  final metadata = [
    textCell(r.name),
    r.rehearsal ? 'Rehearsal' : 'Live',
    '${r.rate}',
    r.startedWall == null
        ? ''
        : DateTime.fromMillisecondsSinceEpoch(r.startedWall!).toIso8601String(),
    DateTime.fromMillisecondsSinceEpoch(r.endedWall).toIso8601String(),
    '${r.uncertain}',
  ];
  return '$header\r\n${r.rows.map((row) => [...metadata, textCell(row.name), seconds(row.plannedMs), seconds(row.actualMs), seconds(row.actualMs == null ? null : row.actualMs! - row.plannedMs), seconds(row.pausedMs), seconds(row.adjustmentMs), row.actualMs == null ? 'Not recorded' : 'Recorded'].join(',')).join('\r\n')}\r\n';
}

String durationLabel(int ms) {
  final total = (ms.abs() / 1000).round();
  final h = total ~/ 3600, m = total % 3600 ~/ 60, sec = total % 60;
  return h > 0 ? '${h}h ${m}m ${sec}s' : '${m}m ${sec}s';
}

String varianceLabel(int ms) => ms.abs() < 1000
    ? 'On time'
    : '${durationLabel(ms)} ${ms > 0 ? 'behind' : 'ahead'}';
