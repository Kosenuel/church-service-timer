import 'dart:async';

import 'package:church_service_timer/domain/domain.dart';

/// Delivers the operator's countdown warnings on a desktop.
///
/// Android hands the plan to system alarms because a phone may suspend the
/// app. A desktop app keeps running, so plain timers are enough: each
/// warning in the plan fires once at its moment on the sleep-proof counter
/// ([monoMs]), and is checked against that counter again when it fires, so
/// a PC that slept through a warning delivers it on waking rather than at
/// a wrong time. Follows WarningNotifications.kt for what counts as
/// already delivered.
class DesktopWarnings {
  final int Function() monoMs;
  final void Function(String title, String body) deliver;
  DesktopWarnings({required this.monoMs, required this.deliver});

  String? _session;
  final _delivered = <String>{};
  final _timers = <String, Timer>{};

  void sync(Json plan) {
    final session = plan['session'] as String;
    if (session != _session) {
      _session = session;
      _delivered.clear();
    }
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    final notice = plan['notice'];
    if (notice is Map) {
      _fire(
        notice['id'] as String,
        notice['title'] as String,
        notice['body'] as String,
      );
    }
    for (final entry in (plan['alarms'] as List? ?? const [])) {
      final alarm = entry as Map;
      final id = alarm['id'] as String;
      if (_delivered.contains(id)) continue;
      _schedule(
        id,
        (alarm['at'] as num).toInt(),
        alarm['title'] as String,
        alarm['body'] as String,
      );
    }
  }

  void _schedule(String id, int at, String title, String body) {
    final wait = at - monoMs();
    _timers[id] = Timer(Duration(milliseconds: wait < 1 ? 1 : wait), () {
      _timers.remove(id);
      // A timer can run early against the counter after a clock step.
      if (monoMs() < at) {
        _schedule(id, at, title, body);
      } else {
        _fire(id, title, body);
      }
    });
  }

  void _fire(String id, String title, String body) {
    if (!_delivered.add(id)) return;
    deliver(title, body);
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
