import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';

/// Font ids used before 0.28 or retired earlier, still read from saved
/// state, program files and backups and mapped to today's ids.
const legacyFontIds = {
  'cuekeeper_matrix': 'i-proton_matrix',
  'cuekeeper_sq_matrix': 'i-proton_sq_matrix',
  // Retired 0.2 faces migrate to the preserved original face.
  'service_serif': 'i-proton_matrix',
  'clear_sans': 'i-proton_matrix',
  'times_new_roman': 'tinos',
};

const displayFontNames = {
  'i-proton_matrix': 'I-Proton Matrix',
  'i-proton_sq_matrix': 'I-Proton Sq-Matrix',
  'tinos': 'Tinos',
};

class WarningRule {
  final int seconds;
  final bool enabled;
  final String destination;
  final int durationSeconds;
  final bool scrollOnce;
  final TextLayout cue;
  const WarningRule(
    this.seconds,
    this.cue, {
    this.enabled = true,
    this.destination = 'operator',
    this.durationSeconds = 8,
    this.scrollOnce = false,
  });
  factory WarningRule.fromJson(Json j) {
    keys(j, {
      'seconds',
      'enabled',
      'destination',
      'cue',
      'durationSeconds',
      'scrollOnce',
    }, 'Warning rule');
    require(
      j['seconds'] is int && j['seconds'] >= 0 && j['seconds'] <= 5999,
      'Warning time must be 0–99:59.',
    );
    require(
      j['enabled'] is bool && {'operator', 'stage'}.contains(j['destination']),
      'Invalid warning destination or enabled state.',
    );
    require(
      j['durationSeconds'] == null ||
          (j['durationSeconds'] is int &&
              j['durationSeconds'] >= 1 &&
              j['durationSeconds'] <= 120),
      'Warning duration must be 1–120 seconds.',
    );
    require(
      j['scrollOnce'] == null || j['scrollOnce'] is bool,
      'Invalid warning duration mode.',
    );
    return WarningRule(
      j['seconds'],
      TextLayout.fromJson(Map<String, dynamic>.from(j['cue'])),
      enabled: j['enabled'],
      destination: j['destination'],
      durationSeconds: j['durationSeconds'] ?? 8,
      scrollOnce: j['scrollOnce'] ?? false,
    );
  }
  Json toJson() => {
    'seconds': seconds,
    'enabled': enabled,
    'destination': destination,
    'durationSeconds': durationSeconds,
    'scrollOnce': scrollOnce,
    'cue': cue.toJson(),
  };
}

const defaultWarnings = [
  WarningRule(120, TextLayout('2 MIN LEFT'), destination: 'stage'),
  WarningRule(30, TextLayout('WRAP UP', bold: true), destination: 'stage'),
  WarningRule(0, TextLayout("TIME'S UP", bold: true), destination: 'stage'),
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
  final canDisplay = allowStage && !s.held && !s.disconnected && !s.outputBlank;
  s.warningNotice =
      '${rule.cue.text} · ${rule.seconds == 0 ? 'Time complete' : '${formatTime(rule.seconds * 1000)} remaining'}';
  addServiceEvent(
    s.events,
    ServiceEvent(
      now.wall,
      'warning',
      '${rule.cue.text} · ${rule.destination == 'stage' && canDisplay ? 'stage warning requested' : 'operator warning'}',
    ),
  );
  if (rule.destination == 'stage') {
    if (canDisplay) {
      s.alert = null; // Warning completion returns to the current timer.
      s.automaticCue = rule.cue;
      s.automaticCueDurationMs = rule.durationSeconds * 1000;
      s.automaticCueAt = now;
      s.warningNotice =
          '${s.warningNotice} · ${rule.scrollOnce ? 'scroll once' : 'stage cue for ${rule.durationSeconds} seconds'}';
    } else {
      s.warningNotice =
          '${s.warningNotice} · stage cue skipped (blank, disconnected, held output, or recovery)';
    }
  }
}

class RunMetrics {
  final Set<int> skipped;
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
    Set<int>? skipped,
  }) : skipped = skipped ?? {};
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
      skipped: Set<int>.from(j['skipped'] ?? []),
    );
    require(
      r.totalMs >= 0 &&
          r.skipped.every(
            (i) => i >= 0 && i < r.actualMs.length && r.actualMs[i] == null,
          ) &&
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
    'skipped': skipped.toList(),
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
  final bool skipped;
  final String name;
  final int plannedMs, pausedMs, adjustmentMs;
  final int? actualMs;
  const ReportRow(
    this.name,
    this.plannedMs,
    this.actualMs,
    this.pausedMs,
    this.adjustmentMs, {
    this.skipped = false,
  });
  factory ReportRow.fromJson(Json j) => ReportRow(
    j['name'],
    j['plannedMs'],
    j['actualMs'],
    j['pausedMs'],
    j['adjustmentMs'],
    skipped: j['skipped'] == true,
  );
  Json toJson() => {
    'name': name,
    'plannedMs': plannedMs,
    'actualMs': actualMs,
    'pausedMs': pausedMs,
    'adjustmentMs': adjustmentMs,
    if (skipped) 'skipped': true,
  };
}

class ServiceReport {
  final Timeline? program;
  final String id, name;
  final String churchName;
  final int? startedWall, totalMs;
  final int endedWall, rate;
  final bool uncertain;
  final List<ReportRow> rows;
  final List<ServiceEvent> events;

  /// After-service reflection, separate from the recorded timings.
  final ReviewNote? review;
  ServiceReport(
    this.id,
    this.name,
    this.startedWall,
    this.endedWall,
    this.totalMs,
    this.rate,
    this.uncertain,
    List<ReportRow> rows, {
    this.churchName = '',
    this.program,
    List<ServiceEvent> events = const [],
    this.review,
  }) : rows = List.unmodifiable(rows),
       events = List.of(events);

  /// A copy with a different review note; timings are unchanged.
  ServiceReport withReview(ReviewNote? note) => ServiceReport(
    id,
    name,
    startedWall,
    endedWall,
    totalMs,
    rate,
    uncertain,
    rows,
    churchName: churchName,
    program: program,
    events: events,
    review: note,
  );
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
              e.value.durationMs,
              s.run?.actualMs[e.key],
              s.run?.pausedMs[e.key] ?? 0,
              s.run?.adjustmentsMs[e.key] ?? 0,
              skipped: s.run?.skipped.contains(e.key) ?? false,
            ),
          )
          .toList(),
      churchName: s.churchName,
      program: s.timeline,
      events: s.events,
    );
  }
  bool get rehearsal => rate > 1;
  int get plannedMs => rows.fold(0, (n, row) => n + row.plannedMs);
  int get pausedMs => rows.fold(0, (n, row) => n + row.pausedMs);
  int get adjustmentMs => rows.fold(0, (n, row) => n + row.adjustmentMs);
  bool get comparable =>
      !uncertain &&
      totalMs != null &&
      rows.isNotEmpty &&
      rows.every((r) => r.actualMs != null);
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
    churchName: churchNameValue(j['churchName'] ?? ''),
    program: j['program'] == null
        ? null
        : Timeline.fromJson(Map<String, dynamic>.from(j['program'])),
    events: readServiceEvents(j['events']),
    review: j['review'] == null ? null : ReviewNote.fromJson(j['review']),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'churchName': churchName,
    if (program != null) 'program': program!.toJson(),
    'startedWall': startedWall,
    'endedWall': endedWall,
    'totalMs': totalMs,
    'rate': rate,
    'uncertain': uncertain,
    'rows': rows.map((e) => e.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    if (review != null) 'review': review!.toJson(),
  };

  /// JSON for export; the review note is included only when asked.
  Json exportJson({bool includeReview = false}) {
    final j = toJson();
    if (!includeReview) j.remove('review');
    if (j['program'] is Json) j['program'] = portableProgram(j['program']);
    return j;
  }
}

String exportReportJson(ServiceReport r, {bool includeReview = false}) =>
    const JsonEncoder.withIndent('  ').convert({
      'type': 'church-service-timer-report',
      'schemaVersion': 2,
      ...r.exportJson(includeReview: includeReview),
    });

class ReportSummary {
  final List<ServiceReport> records;
  ReportSummary(Iterable<ServiceReport> records)
    : records = List.unmodifiable(records);
  Iterable<ServiceReport> get comparable => records.where((r) => r.comparable);
  int get timedCount => records.where((r) => r.totalMs != null).length;
  int get recordedMs => records.fold(0, (n, r) => n + (r.totalMs ?? 0));
  int? get averageVarianceMs => comparable.isEmpty
      ? null
      : (comparable.fold<int>(0, (n, r) => n + r.totalMs! - r.plannedMs) /
                comparable.length)
            .round();
  int get ahead =>
      comparable.where((r) => r.totalMs! - r.plannedMs <= -1000).length;
  int get behind =>
      comparable.where((r) => r.totalMs! - r.plannedMs >= 1000).length;
  int get onTime => comparable.length - ahead - behind;
}

String exportReportsJson(
  List<ServiceReport> records, {
  bool includeReview = false,
}) => const JsonEncoder.withIndent('  ').convert({
  'type': 'church-service-timer-reports',
  'schemaVersion': 2,
  'recordCount': records.length,
  'reports': records
      .map((r) => r.exportJson(includeReview: includeReview))
      .toList(),
});

String reportCsvText(String s) {
  final safe = RegExp(r'^\s*[=+@\-]').hasMatch(s) ? "'$s" : s;
  return '"${safe.replaceAll('"', '""')}"';
}

String exportReportsCsv(
  List<ServiceReport> records, {
  bool includeReview = false,
}) {
  String seconds(int? n) => n == null ? '' : (n / 1000).toStringAsFixed(3);
  String utc(int? n) => n == null
      ? ''
      : DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toIso8601String();
  final lines = <String>[
    'Service ID,Service,Mode,Speed,Started UTC,Ended UTC,Timing uncertain,Service planned seconds,Service actual seconds,Segment number,Segment,Planned seconds,Actual seconds,Variance seconds,Paused seconds,Adjustment seconds,Status,Church${includeReview ? ',Review note' : ''}',
  ];
  for (final r in records) {
    final metadata = [
      reportCsvText(r.id),
      reportCsvText(r.name),
      r.rehearsal ? 'Rehearsal' : 'Live',
      '${r.rate}',
      utc(r.startedWall),
      utc(r.endedWall),
      '${r.uncertain}',
      seconds(r.plannedMs),
      seconds(r.totalMs),
    ];
    if (r.rows.isEmpty)
      lines.add(
        [
          ...metadata,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          'No segment records',
          reportCsvText(r.churchName),
          if (includeReview) reportCsvText(r.review?.text ?? ''),
        ].join(','),
      );
    for (var i = 0; i < r.rows.length; i++) {
      final row = r.rows[i];
      lines.add(
        [
          ...metadata,
          '${i + 1}',
          reportCsvText(row.name),
          seconds(row.plannedMs),
          seconds(row.actualMs),
          seconds(row.actualMs == null ? null : row.actualMs! - row.plannedMs),
          seconds(row.pausedMs),
          seconds(row.adjustmentMs),
          row.skipped
              ? 'Skipped'
              : row.actualMs == null
              ? 'Not recorded'
              : 'Recorded',
          reportCsvText(r.churchName),
          if (includeReview) reportCsvText(r.review?.text ?? ''),
        ].join(','),
      );
    }
  }
  return '${lines.join('\r\n')}\r\n';
}

String exportReportCsv(ServiceReport r, {bool includeReview = false}) {
  String textCell(String s) {
    return reportCsvText(s);
  }

  String seconds(int? n) => n == null ? '' : (n / 1000).toStringAsFixed(3);
  final header =
      'Service,Mode,Speed,Started,Ended,Timing uncertain,Segment,Planned seconds,Actual seconds,Variance seconds,Paused seconds,Adjustment seconds,Status,Church${includeReview ? ',Review note' : ''}';
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
  return '$header\r\n${r.rows.map((row) => [...metadata, textCell(row.name), seconds(row.plannedMs), seconds(row.actualMs), seconds(row.actualMs == null ? null : row.actualMs! - row.plannedMs), seconds(row.pausedMs), seconds(row.adjustmentMs), row.skipped
      ? 'Skipped'
      : row.actualMs == null
      ? 'Not recorded'
      : 'Recorded', textCell(r.churchName), if (includeReview) textCell(r.review?.text ?? '')].join(',')).join('\r\n')}\r\n';
}

String durationLabel(int ms) {
  final total = (ms.abs() / 1000).round();
  final h = total ~/ 3600, m = total % 3600 ~/ 60, sec = total % 60;
  return h > 0 ? '${h}h ${m}m ${sec}s' : '${m}m ${sec}s';
}

String varianceLabel(int ms) => ms.abs() < 1000
    ? 'On time'
    : '${durationLabel(ms)} ${ms > 0 ? 'behind' : 'ahead'}';

int readCueDuration(dynamic value) {
  require(
    value == null || (value is int && value >= 1000 && value <= 120000),
    'Invalid cue duration.',
  );
  return value ?? 8000;
}

class ServiceEvent {
  final int wall;
  final String kind, message;
  const ServiceEvent(this.wall, this.kind, this.message);
  Json toJson() => {'wall': wall, 'kind': kind, 'message': message};
  factory ServiceEvent.fromJson(Json j) {
    require(
      j['wall'] is int &&
          j['wall'] >= 0 &&
          j['wall'] <= 8640000000000000 &&
          j['kind'] is String &&
          j['kind'].length <= 40 &&
          j['message'] is String &&
          j['message'].length <= 500,
      'Invalid service event.',
    );
    return ServiceEvent(j['wall'], j['kind'], j['message']);
  }
}

List<ServiceEvent> readServiceEvents(dynamic value) {
  if (value == null) return [];
  require(value is List && value.length <= 1000, 'Invalid activity timeline.');
  final events = <ServiceEvent>[];
  for (final item in value as List) {
    addServiceEvent(
      events,
      ServiceEvent.fromJson(Map<String, dynamic>.from(item)),
    );
  }
  return events;
}

void addServiceEvent(List<ServiceEvent> events, ServiceEvent event) {
  // Transport callbacks can be persisted after a later operator action.
  // Keep their original timestamps and preserve arrival order for ties.
  var index = events.length;
  while (index > 0 && events[index - 1].wall > event.wall) {
    index--;
  }
  events.insert(index, event);
  if (events.length > 1000) events.removeRange(0, events.length - 1000);
}

String? serviceActionDescription(
  String action,
  Session s,
  dynamic value,
) => switch (action) {
  'start' => '${s.timeline!.segments[s.index].name} started',
  'advance' =>
    '${s.timeline!.segments[s.index].name} started${s.outputBlank ? ' · display kept blank' : ''}',
  'jump' =>
    'Jumped to ${s.timeline!.segments[s.index].name} · ${(s.index - (s.undo?.index ?? s.index) - 1).clamp(0, 200)} segments skipped${s.paused ? ' · paused' : ''}',
  'clock' => 'Current clock requested',
  'message' => 'Stage message requested: ${s.alert!.text}',
  'clearCue' => 'Stage message cleared',
  'endScreen' => 'End screen restored',
  'undo' => 'Previous segment restored',
  'pause' => s.paused ? 'Timer paused' : 'Timer resumed',
  'adjust' =>
    '${(value as int) >= 0 ? '+' : ''}$value seconds requested · ${formatTime(s.remaining(s.anchor))} remaining',
  'cue' => 'Stage cue requested: ${s.alert!.text}',
  'blank' => 'Blank display requested',
  'timer' || 'releaseTimer' => 'Current timer requested',
  'end' => 'Service ended',
  'disconnect' => 'Simulator disconnected',
  'connect' => 'Simulator reconnected',
  _ => null,
};
