import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

/// The active-service notification card and its Pause and Next actions.
class ServiceNotificationController {
  final AppController app;
  ServiceNotificationController(this.app);

  String? _lastCard;

  /// What the active-service notification shows. Android draws the running
  /// countdown itself from [deadlineWall], so this changes only when the
  /// segment, pause app.state or control availability changes.
  Json build() {
    final s = app.state.session, t = s.timeline;
    final active = s.active && t != null;
    final balance = active ? s.balance(app.now) : 0;
    final live = active && !s.paused && s.rate == 1;
    final canControl =
        active && app.pairing.localControl && !app.uiLocked && !app.corrupt;
    return {
      'active': active,
      'title': t?.name ?? 'Church Service Timer',
      'segment': active ? t.segments[s.index].name : '',
      'next': active && s.index + 1 < t.segments.length
          ? t.segments[s.index + 1].name
          : '',
      'paused': active && s.paused,
      'overtime': active && balance < 0,
      'rehearsal': s.rehearsal,
      // Wall time when the segment reaches zero (in the past when overtime).
      if (live) 'deadlineWall': app.now.wall + balance,
      'remaining': active ? _operatorLabel(balance) : '',
      'canPause': canControl,
      'canNext': canControl && s.index + 1 < t.segments.length,
    };
  }

  /// What a PC shows beside the Windows clock while a service or quick
  /// timer runs: "Sermon · 12:34 left", "Sermon · 01:10 over" or
  /// "Paused · Sermon · 12:34". Null when nothing is running.
  String? trayText() {
    final s = app.state.session, t = s.timeline;
    if (!s.active || t == null) return null;
    // A name has at most 80 characters, so the whole line fits the 127 a
    // Windows tooltip holds.
    final name = t.segments[s.index].name.trim();
    final balance = s.balance(app.now);
    final time = balance < 0
        ? '${formatTime(-balance)} over'
        : s.paused
        ? formatTime(balance)
        : '${formatTime(balance)} left';
    return '${s.paused ? 'Paused · ' : ''}$name · $time';
  }

  static String _operatorLabel(int balance) =>
      balance < 0 ? '+${formatTime(-balance)} over' : formatTime(balance);

  /// Sends the notification card when it changed. The running countdown is
  /// excluded from the comparison because Android animates it. With
  /// lock-screen controls off, only the plain active-service notice remains.
  /// This never starts the foreground service, so suspend and recovery rules
  /// are unchanged.
  Future<void> sync() async {
    if (!app.ready) return;
    if (app.port.isDesktop) {
      // Its own setting on the PC decides whether this shows; the port
      // only passes a change of text on to Windows.
      try {
        await app.port.showTrayCountdown(app.corrupt ? null : trayText());
      } catch (_) {}
    }
    final card = app.state.lockScreenControls
        ? build()
        : const <String, dynamic>{'active': false};
    final key = jsonEncode({
      ...card,
      if (card['deadlineWall'] != null)
        'deadlineWall': (card['deadlineWall'] as int) ~/ 1000,
      if (card['deadlineWall'] != null) 'remaining': '',
    });
    if (key == _lastCard) return;
    _lastCard = key;
    try {
      await app.port.updateServiceNotification(card);
    } catch (_) {
      _lastCard = null;
    }
  }

  /// Pause/Resume and Next from the notification follow the same rules as
  /// the Live buttons: local control, unlocked, not app.busy, current revision.
  Future<void> handleAction(String action) async {
    if (!app.ready ||
        !app.state.session.active ||
        !app.pairing.localControl ||
        app.uiLocked ||
        app.busy ||
        app.corrupt ||
        app.reportSavePending)
      return;
    final s = app.state.session;
    if (action == 'pause') {
      await app.act('pause', revision: s.revision);
    } else if (action == 'next' &&
        s.timeline != null &&
        s.index + 1 < s.timeline!.segments.length) {
      await app.act('advance', revision: s.revision);
    }
  }

  /// Sends the card again on the next sync.
  void forget() => _lastCard = null;
}
