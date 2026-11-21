import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/update_checker.dart';

/// Settings › About › Check for updates automatically. Off unless the
/// operator turns it on. When on, it asks the same place as Check for
/// updates at most once a day, and only while nothing is running: no
/// service, quick timer, rehearsal, practice or Check this service, and
/// the controls are not locked. It asks shortly after the app starts and
/// again whenever the app comes back to standing by. A newer version is
/// a notice on Live; nothing is downloaded or installed without asking,
/// and a check that fails says nothing.
class AutoUpdateCheck {
  final AppController app;
  AutoUpdateCheck(this.app);

  /// The least time between two automatic checks.
  static const every = Duration(hours: 24);

  /// How long after the app starts the first check waits, so starting up
  /// is not slowed and a service can be started first.
  static const startDelay = Duration(seconds: 30);

  Timer? _soon;
  bool _started = false, _asking = false, _wasIdle = false;
  int _serviceChecks = 0;

  bool get enabled => app.state.autoUpdate.enabled;

  /// Whether an automatic check is under way just now.
  bool get asking => _asking;

  /// Begins watching, once the app is ready. The first check waits
  /// [startDelay].
  void start() {
    if (_started || app.disposed) return;
    _started = true;
    _wasIdle = idle;
    app.addListener(_changed);
    if (enabled) _wait(startDelay);
  }

  void dispose() {
    _soon?.cancel();
    _soon = null;
    if (_started) app.removeListener(_changed);
    _started = false;
  }

  void _wait(Duration delay) {
    _soon?.cancel();
    _soon = Timer(delay, () {
      _soon = null;
      unawaited(checkIfDue());
    });
  }

  /// Check this service opened or closed. It counts as running.
  void serviceCheckOpened() {
    _serviceChecks++;
    _changed();
  }
  void serviceCheckClosed() {
    if (_serviceChecks > 0) _serviceChecks--;
    _changed();
  }

  /// The controls were locked or unlocked on Live.
  void lockChanged() => _changed();

  /// Asks again when the app comes back to standing by; never while the
  /// first wait after starting is still going.
  void _changed() {
    if (!_started) return;
    final now = idle;
    if (now && !_wasIdle && enabled && _soon == null) {
      unawaited(checkIfDue());
    }
    _wasIdle = now;
  }

  /// Nothing is running and nothing is locked, so a check may be made.
  bool get idle {
    if (!app.ready || app.corrupt || app.disposed || !app.foreground) {
      return false;
    }
    final s = app.liveSession;
    // A service, quick timer or rehearsal is loaded, running or saving.
    if (s.phase != 'idle' && s.phase != 'ended') return false;
    if (app.reportSavePending || s.active) return false;
    return !app.practice.active &&
        _serviceChecks == 0 &&
        !app.uiLocked &&
        app.pairing.localControl &&
        !app.pairing.joined;
  }

  /// Whether a day has passed since the last automatic check at [wall].
  /// A clock set back counts as due, so a wrong date cannot stop checks.
  bool dueAt(int wall) {
    final last = app.state.autoUpdate.checkedWall;
    return last == null || wall < last || wall - last >= every.inMilliseconds;
  }

  /// Checks when it is switched on, nothing is running and a day has
  /// passed. True when GitHub was asked.
  Future<bool> checkIfDue() async {
    if (!enabled || _asking || !idle) return false;
    _asking = true;
    try {
      final at = await app.port.clock();
      if (!dueAt(at.wall) || !idle) return false;
      // The time is noted first, so a check that fails also waits a day.
      final noted = await app.commit(
        (draft, at) => draft.autoUpdate.checkedWall = at.wall,
      );
      if (!noted || !idle) return false;
      final result = await app.port.updateChecker.check(app.appVersion);
      final found = switch (result) {
        UpdateAvailable(:final version) => version,
        UpToDate() => null,
        // Offline or an answer that made no sense: say nothing.
        UpdateUnknown() => app.state.autoUpdate.found,
      };
      if (found != app.state.autoUpdate.found && !app.disposed) {
        await app.commit((draft, _) => draft.autoUpdate.found = found);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _asking = false;
    }
  }

  /// The newer version for Live's notice, or null: none found, it is not
  /// newer than this one, Not now hid it, or the check is off.
  String? get notice {
    final saved = app.state.autoUpdate;
    final version = saved.found;
    if (!saved.enabled || version == null || version == saved.dismissed) {
      return null;
    }
    final mine = versionNumbers(app.appVersion);
    final theirs = versionNumbers(version);
    if (mine == null || theirs == null) return null;
    return compareVersions(theirs, mine) > 0 ? version : null;
  }

  /// Not now: hides the notice for [version]; a newer one shows again.
  Future<bool> dismiss(String version) =>
      app.commit((draft, _) => draft.autoUpdate.dismissed = version);

  /// Turns the automatic check on or off. Turning it on checks at once
  /// when nothing is running and a day has passed.
  Future<bool> setEnabled(bool on) async {
    final saved = await app.commit((draft, _) => draft.autoUpdate.enabled = on);
    if (!saved) return false;
    if (!on) {
      _soon?.cancel();
      _soon = null;
    } else if (_started) {
      unawaited(checkIfDue());
    }
    return true;
  }
}
