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
}) {
  String esc(String s) =>
      const HtmlEscape().convert(s).replaceAll('\n', '<br>');
  var elapsed = 0;
  final rows = <String>[];
  for (final e in timeline.segments) {
    rows.add(
      '<tr><td>${rows.length + 1}</td><td>${esc(e.name)}${e.speaker.isEmpty ? '' : '<div class="speaker">${esc(e.speaker)}</div>'}${privateNotes && e.notes.isNotEmpty ? '<div class="note">Private: ${esc(e.notes)}</div>' : ''}</td><td>${e.minutes} min</td><td>+${elapsed} min</td></tr>',
    );
    elapsed += e.minutes;
  }
  return '<!doctype html><html><head><meta charset="utf-8"><style>@page{size:A4;margin:18mm}body{font:12pt sans-serif;color:#172c25}h1{margin:8px 0}p{color:#43534c}table{border-collapse:collapse;width:100%}th,td{text-align:left;border-bottom:1px solid #ccd5ce;padding:10px;vertical-align:top}thead{display:table-header-group}tr{break-inside:avoid}.speaker{font-size:10pt;color:#52635b;margin-top:4px}.note{font-size:10pt;margin-top:8px;white-space:normal;overflow-wrap:anywhere}</style></head><body><p>${esc(church)}</p><h1>${esc(timeline.name)}</h1><p>Service sheet · $elapsed minutes · ${privateNotes ? 'Includes private operator notes' : 'Private notes excluded'}</p><table><thead><tr><th>#</th><th>Segment / speaker</th><th>Duration</th><th>Planned start</th></tr></thead><tbody>${rows.join()}</tbody></table><p>Church Service Timer · I-Proton</p></body></html>';
}
