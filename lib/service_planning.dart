part of 'domain.dart';

void replaceUpcoming(Session s, List<Segment> upcoming, Stamp now) {
  require(
    s.active && s.timeline != null,
    'Start a service before editing its rundown.',
  );
  require(s.index + 1 + upcoming.length <= 200, 'Keep at most 200 segments.');
  final checked = upcoming.map((e) => Segment.fromJson(e.toJson())).toList();
  final prefix = s.timeline!.segments.take(s.index + 1).toList();
  s.timeline = Timeline(
    s.timeline!.name,
    [...prefix, ...checked],
    s.timeline!.display,
    type: s.timeline!.type,
  );
  if (s.run != null) {
    final r = s.run!;
    s.run = RunMetrics(
      r.startedWall,
      r.anchor,
      [
        ...r.actualMs.take(prefix.length),
        ...List<int?>.filled(checked.length, null),
      ],
      [
        ...r.pausedMs.take(prefix.length),
        ...List<int>.filled(checked.length, 0),
      ],
      [
        ...r.adjustmentsMs.take(prefix.length),
        ...List<int>.filled(checked.length, 0),
      ],
      endedWall: r.endedWall,
      totalMs: r.totalMs,
      currentMs: r.currentMs,
    );
  }
  s.undo = null;
  s.revision++;
  addServiceEvent(
    s.events,
    ServiceEvent(
      now.wall,
      'rundown',
      'Upcoming rundown updated · ${checked.length} segments',
    ),
  );
}

List<Segment> catchUpPlan(Session s, Stamp now, int targetWall) {
  require(s.active && !s.uncertain, 'Review timing before planning a finish.');
  final pending = s.timeline!.segments.skip(s.index + 1).toList();
  require(pending.isNotEmpty, 'No upcoming segments to shorten.');
  final budget = (((targetWall - now.wall) * s.rate - s.remaining(now)) / 60000)
      .floor();
  require(
    budget >= pending.length,
    'This finish cannot be reached while keeping the current timer and at least one minute per upcoming segment.',
  );
  final minutes = pending.map((e) => e.minutes).toList();
  var total = minutes.fold<int>(0, (a, b) => a + b);
  while (total > budget) {
    var largest = 0;
    for (var i = 1; i < minutes.length; i++) {
      if (minutes[i] > minutes[largest]) largest = i;
    }
    minutes[largest]--;
    total--;
  }
  return [
    for (var i = 0; i < pending.length; i++)
      Segment(
        pending[i].name,
        minutes[i],
        speaker: pending[i].speaker,
        notes: pending[i].notes,
      ),
  ];
}

String serviceSheetHtml(
  Timeline timeline,
  String church, {
  bool privateNotes = false,
  bool includeBanner = true,
  String banner = '',
  int? serviceDate,
}) {
  String esc(String s) =>
      const HtmlEscape().convert(s).replaceAll('\n', '<br>');
  churchBannerValue(banner);
  final image = banner.isEmpty
      ? ''
      : '<img alt="Church banner" src="data:image/jpeg;base64,$banner">';
  final heading = includeBanner
      ? '<header class="banner">$image<div class="shade"></div><div class="heading"><p>${esc(church)}</p><h1>${esc(timeline.name)}</h1></div></header>'
      : '<p>${esc(church)}</p><h1>${esc(timeline.name)}</h1>';
  final date = serviceDateLabel(
    serviceDate ?? DateTime.now().millisecondsSinceEpoch,
  );
  var elapsed = 0;
  final rows = <String>[];
  for (final e in timeline.segments) {
    rows.add(
      '<tr><td>${rows.length + 1}</td><td>${esc(e.name)}${e.speaker.isEmpty ? '' : '<div class="speaker">${esc(e.speaker)}</div>'}${privateNotes && e.notes.isNotEmpty ? '<div class="note">Private: ${esc(e.notes)}</div>' : ''}</td><td>${e.minutes} min</td></tr>',
    );
    elapsed += e.minutes;
  }
  return '<!doctype html><html><head><meta charset="utf-8"><style>@page{size:A4;margin:18mm}body{font:12pt sans-serif;color:#172c25}h1{margin:8px 0}.service-date{font-size:13pt;letter-spacing:.03em;margin:6mm 0;padding-bottom:3mm;border-bottom:2px solid #214e48}p{color:#43534c}table{border-collapse:collapse;width:100%}th,td{text-align:left;border-bottom:1px solid #ccd5ce;padding:10px;vertical-align:top}thead{display:table-header-group}tr{break-inside:avoid}.speaker{font-size:10pt;color:#52635b;margin-top:4px}.note{font-size:10pt;margin-top:8px;white-space:normal;overflow-wrap:anywhere}.banner{position:relative;height:58mm;border-radius:5mm;overflow:hidden;background:linear-gradient(120deg,#214e48,#476e80);-webkit-print-color-adjust:exact;print-color-adjust:exact;break-inside:avoid}.banner img{width:100%;height:100%;object-fit:cover}.shade{position:absolute;inset:0;background:linear-gradient(0deg,rgba(0,0,0,.78),rgba(0,0,0,.05))}.heading{position:absolute;bottom:7mm;left:7mm;right:7mm;color:white}.heading p{color:white;margin:0}.heading h1{font-size:24pt;overflow-wrap:anywhere}</style></head><body>$heading<div class="service-date">${esc(date)}</div><p>Service sheet · $elapsed minutes · ${privateNotes ? 'Includes private operator notes' : 'Private notes excluded'}</p><table><thead><tr><th>#</th><th>Segment / speaker</th><th>Duration</th></tr></thead><tbody>${rows.join()}</tbody></table><p>Church Service Timer · I-Proton</p></body></html>';
}

/// Uses the immutable completed record, never a subsequently edited program.
String reportServiceHtml(
  ServiceReport report, {
  bool fullReport = true,
  bool privateNotes = false,
  bool includeBanner = true,
  String banner = '',
}) {
  final timeline =
      report.program ??
      Timeline(
        report.name,
        report.rows.map((r) => Segment(r.name, r.plannedMs ~/ 60000)).toList(),
        DisplaySettings(),
      );
  var html = serviceSheetHtml(
    timeline,
    report.churchName,
    privateNotes: privateNotes,
    includeBanner: includeBanner,
    banner: banner,
    serviceDate: report.startedWall ?? report.endedWall,
  );
  if (report.program == null)
    html = html.replaceFirst(
      '<table>',
      '<p>Older record: speaker names and private notes were not recorded.</p><table>',
    );
  if (!fullReport) return html;
  String esc(String s) =>
      const HtmlEscape().convert(s).replaceAll('\n', '<br>');
  final rows = <String>[];
  for (var i = 0; i < report.rows.length; i++) {
    final r = report.rows[i];
    final segment = i < timeline.segments.length ? timeline.segments[i] : null;
    rows.add(
      '<tr><td>${i + 1}</td><td>${esc(r.name)}${segment != null && segment.speaker.isNotEmpty ? '<div class="speaker">${esc(segment.speaker)}</div>' : ''}${privateNotes && segment != null && segment.notes.isNotEmpty ? '<div class="note">Private: ${esc(segment.notes)}</div>' : ''}</td><td>${durationLabel(r.plannedMs)}</td><td>${r.actualMs == null ? 'Not completed' : durationLabel(r.actualMs!)}</td><td>${durationLabel(r.pausedMs)}</td></tr>',
    );
  }
  html = html.replaceFirst(
    RegExp(r'<table>.*?</table>', dotAll: true),
    '<table><thead><tr><th>#</th><th>Segment / speaker</th><th>Planned</th><th>Actual</th><th>Paused</th></tr></thead><tbody>${rows.join()}</tbody></table>',
  );
  html = html.replaceFirst(
    'Service sheet ·',
    '${report.rehearsal ? 'Rehearsal report' : 'Service report'} ·',
  );
  return html.replaceFirst(
    '<table>',
    '<p>Total recorded: ${report.totalMs == null ? 'Unavailable' : durationLabel(report.totalMs!)} · Ended ${printClockLabel(report.endedWall)}${report.uncertain ? ' · Timing requires review' : ''}</p><table>',
  );
}
