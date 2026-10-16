import 'domain.dart';

/// Absolute monotonic deadlines preserve rehearsal speed and avoid wall-clock drift.
Json warningNotificationPlan(
  Session s,
  Stamp now, {
  Set<int> newlySeen = const {},
}) {
  final alarms = <Json>[];
  Json? notice;
  if (s.active && !s.paused) {
    final remaining = s.remaining(now);
    final rules = s.timeline!.display.warnings;
    Json entry(int i) => {
      'id': '${s.id}/${s.index}/${rules[i].seconds}',
      'title': rules[i].cue.text,
      'body':
          '${s.timeline!.segments[s.index].name} · ${formatTime(rules[i].seconds * 1000)} remaining',
    };
    final justTriggered =
        newlySeen.where((i) => i >= 0 && i < rules.length).toList()
          ..sort((a, b) => rules[a].seconds.compareTo(rules[b].seconds));
    if (justTriggered.isNotEmpty) notice = entry(justTriggered.first);
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      final delta = remaining - rule.seconds * 1000;
      if (rule.enabled &&
          !s.warningSeen.contains(i) &&
          rule.seconds * 1000 < s.warningCeiling &&
          delta > 0) {
        alarms.add({...entry(i), 'at': now.mono + (delta / s.rate).ceil()});
      }
    }
  }
  return {'session': s.id, 'alarms': alarms, 'notice': notice};
}
