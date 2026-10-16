import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'pixels.dart';
import 'platform.dart';
import 'native_fonts.dart';
import 'warning_notifications.dart';

/// The simulator is an output adapter, not a fake Huidu protocol implementation.
class Simulator {
  TextLayout? delivered;
  String owner = '', signature = '';
  int revision = -1, deliveredAt = 0;
  List<bool> pixels = List.filled(512, false);
  void update(Session s, Stamp now) {
    if (s.disconnected || s.held) return;
    final desired = s.intended(now);
    if (desired == null) return; // Ready/idle retain previous output.
    final next = jsonEncode(desired.toJson());
    if (owner != s.id || signature != next) {
      owner = s.id;
      signature = next;
      delivered = desired;
      deliveredAt = now.mono;
    }
    revision = s.revision;
    pixels = renderPixels(delivered, now.mono - deliveredAt);
  }
}

class AppController extends ChangeNotifier {
  final DevicePort port;
  late AppState state;
  Stamp now = const Stamp(0, 0, 'unknown');
  final simulator = Simulator();
  bool ready = false,
      busy = false,
      corrupt = false,
      storageUncertain = false,
      _ticking = false,
      _foreground = true,
      _needsRecovery = false,
      _retryIsCheckpoint = false,
      _disposed = false;
  int _resumeRequest = 0;
  Completer<void>? _writeDone;
  String? error;
  String? notificationError;
  Json notificationState = {'enabled': false, 'exact': false, 'sound': false};
  Future<bool> Function()? retry;
  Timer? _timer;
  AppController(this.port);
  void _beginWrite() {
    busy = true;
    _writeDone = Completer<void>();
  }

  void _finishWrite() {
    busy = false;
    _writeDone?.complete();
    _writeDone = null;
    if (!_disposed) notifyListeners();
  }

  void _publish() {
    if (_foreground && !_needsRecovery && !corrupt && !_disposed) {
      simulator.update(state.session, now);
    }
  }

  Future<void> initialize({bool startTicker = true}) async {
    now = await port.clock();
    try {
      final data = await port.load();
      state = data == null
          ? AppState.fresh(now)
          : AppState.fromJson(Map<String, dynamic>.from(jsonDecode(data)));
      await NativeDisplayFonts.initialize(port);
      await NativeDisplayFonts.prepareState(state);
      for (final t in state.templates) {
        validateTimelinePixels(t);
      }
      if (state.session.timeline != null)
        validateTimelinePixels(state.session.timeline!);
      if (state.session.alert != null) validateLayout(state.session.alert!);
      for (final cue in state.stageCues) {
        validateLayout(cue);
      }
      final previous = state.session;
      state.session = recover(state.session, now);
      // Persist recovery holds before the first possible display publication.
      await port.save(jsonEncode(state.toJson()));
      await syncPhoneWarnings(previous: previous);
    } catch (e) {
      state = AppState.fresh(now);
      state.session.held = true;
      corrupt = true;
      error = 'Saved state could not be recovered. Output is held. $e';
    }
    ready = true;
    if (_foreground && _needsRecovery) await resume();
    _publish();
    notifyListeners();
    if (startTicker)
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => tick());
  }

  Future<void> tick() async {
    if (_ticking || !ready || _disposed || !_foreground || _needsRecovery)
      return;
    _ticking = true;
    try {
      now = await port.clock();
      if (!_foreground || _needsRecovery || _disposed) return;
      if (!corrupt) {
        if (!busy &&
            retry == null &&
            dueWarnings(state.session, now).isNotEmpty) {
          await act('warnings');
        }
        _publish();
        if (!busy &&
            !storageUncertain &&
            now.since(state.session.checkpoint) >= 55000 &&
            (state.session.active || state.session.phase == 'ended'))
          await checkpoint();
      }
      if (!_disposed) notifyListeners();
    } catch (e) {
      error = 'Clock or activity checkpoint unavailable: $e';
    } finally {
      _ticking = false;
    }
  }

  Future<bool> commit(
    void Function(AppState draft, Stamp at) mutation, {
    int? revision,
  }) async {
    if (busy || corrupt || _needsRecovery || !_foreground || _disposed)
      return false;
    _beginWrite();
    notifyListeners();
    final baseRevision = revision ?? state.session.revision;
    try {
      final at = await port.clock();
      now = at;
      require(
        baseRevision == state.session.revision,
        'The service changed. Review this action again.',
      );
      final draft = state.copy();
      final previous = state.session;
      mutation(draft, at);
      await NativeDisplayFonts.prepareState(draft);
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
      await syncPhoneWarnings(previous: previous);
      error = null;
      retry = null;
      _retryIsCheckpoint = false;
      storageUncertain = false;
      _publish();
      return true;
    } catch (e) {
      error = 'Action was not saved: $e';
      _retryIsCheckpoint = false;
      retry = e is RuleError
          ? null
          : () => commit(mutation, revision: baseRevision);
      return false;
    } finally {
      _finishWrite();
    }
  }

  Future<bool> act(String action, {dynamic value, int? revision}) =>
      commit((draft, at) {
        if (action == 'cue') validateLayout(value as TextLayout);
        draft.session = transition(
          draft.session,
          action,
          at,
          value: value,
          expectedRevision: revision,
        );
        if (action == 'end') {
          draft.reports.add(ServiceReport.fromSession(draft.session, at));
        }
      }, revision: revision);

  Future<void> reloadFonts() async {
    corrupt = false;
    error = null;
    await initialize(startTicker: false);
  }

  Future<void> syncPhoneWarnings({Session? previous}) async {
    try {
      final s = state.session;
      final newlySeen =
          previous != null &&
              previous.id == s.id &&
              previous.index == s.index &&
              s.warningNotice != null &&
              s.warningNotice != previous.warningNotice
          ? s.warningSeen.toSet().difference(previous.warningSeen.toSet())
          : <int>{};
      await port.syncWarnings(
        warningNotificationPlan(s, now, newlySeen: newlySeen),
      );
      notificationState = await port.notificationStatus();
      notificationError = null;
    } catch (e) {
      notificationError = 'Phone warnings could not be scheduled: $e';
    }
  }

  Future<void> enablePhoneWarnings() async {
    try {
      await port.enableNotifications();
      await syncPhoneWarnings();
    } catch (e) {
      notificationError = 'Could not enable notifications: $e';
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> setLiveWarnings(List<WarningRule> rules) => commit((draft, at) {
    final s = draft.session;
    require(
      s.timeline != null && (s.active || s.phase == 'ready'),
      'Load a service first.',
    );
    final old = s.timeline!;
    final consumed = s.warningSeen
        .map((i) => old.display.warnings[i].seconds)
        .toSet();
    s.warningSeen = rules
        .asMap()
        .entries
        .where(
          (e) =>
              consumed.contains(e.value.seconds) ||
              (s.active && e.value.seconds * 1000 > s.remaining(at)),
        )
        .map((e) => e.key)
        .toList();
    s.automaticCue = null;
    s.warningNotice = null;
    // The previous segment's warning indexes refer to the old rule set.
    if (s.undo != null) {
      final u = s.undo!.toJson();
      final thresholds = s.undo!.warningSeen
          .map((i) => old.display.warnings[i].seconds)
          .toSet();
      u['warningSeen'] = rules
          .asMap()
          .entries
          .where((e) => thresholds.contains(e.value.seconds))
          .map((e) => e.key)
          .toList();
      s.undo = UndoPoint.fromJson(u);
    }
    s.timeline = Timeline(
      old.name,
      old.segments,
      old.display.withWarnings(rules),
    );
    final i = draft.templates.indexWhere((t) => t.name == old.name);
    if (i >= 0) {
      final t = draft.templates[i];
      draft.templates[i] = Timeline(
        t.name,
        t.segments,
        t.display.withWarnings(rules),
      );
    }
    s.revision++;
  });

  Future<bool> sendAndSaveCue(TextLayout layout, {int? index, int? revision}) =>
      commit((draft, at) {
        validateLayout(layout);
        if (index != null) {
          require(
            index >= 0 && index < draft.stageCues.length,
            'This cue no longer exists.',
          );
          draft.stageCues[index] = layout;
        } else {
          draft.stageCues.add(layout);
        }
        draft.session = transition(
          draft.session,
          'cue',
          at,
          value: layout,
          expectedRevision: revision,
        );
      }, revision: revision);

  Future<bool> clearReports(Set<String> ids) => commit((draft, _) {
    draft.reports.removeWhere((r) => ids.contains(r.id));
  });

  Future<void> checkpoint() async {
    if (busy || corrupt || !ready) return;
    _beginWrite();
    try {
      final at = await port.clock();
      now = at;
      final draft = state.copy();
      draft.session.checkpoint = at;
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
      storageUncertain = false;
      if (_retryIsCheckpoint) {
        error = null;
        retry = null;
        _retryIsCheckpoint = false;
      }
    } catch (e) {
      storageUncertain = true;
      if (retry == null || _retryIsCheckpoint) {
        error =
            'Activity could not be saved. Timing continues; recovery evidence is uncertain. $e';
        _retryIsCheckpoint = true;
        retry = () async {
          await checkpoint();
          return !storageUncertain;
        };
      }
    } finally {
      _finishWrite();
    }
  }

  Future<void> suspend() async {
    _foreground = false;
    _needsRecovery = true;
    _resumeRequest++;
    await checkpoint();
  }

  Future<void> resume() async {
    _foreground = true;
    _needsRecovery = true;
    final request = ++_resumeRequest;
    if (!ready || corrupt || _disposed) return;
    // A lifecycle event may arrive while a durable action is still being saved.
    // Wait for it, then recover its committed result before publishing any frame.
    while (busy) {
      await _writeDone!.future;
    }
    if (!_foreground || request != _resumeRequest || _disposed) return;
    _beginWrite();
    try {
      now = await port.clock();
      final draft = state.copy();
      draft.session = recover(draft.session, now);
      final previous = state.session;
      if (storageUncertain) {
        draft.session.held = true;
        draft.session.uncertain = true;
      }
      draft.session.checkpoint = now;
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
      await syncPhoneWarnings(previous: previous);
      storageUncertain = false;
      error = null;
      retry = null;
      _retryIsCheckpoint = false;
      if (_foreground && request == _resumeRequest) _needsRecovery = false;
      _publish();
    } catch (e) {
      storageUncertain = true;
      error = 'Recovery could not be saved. Output remains held. $e';
      _retryIsCheckpoint = false;
      retry = () async {
        await resume();
        return !_needsRecovery;
      };
    } finally {
      _finishWrite();
    }
  }

  Future<void> resetCorrupt() async {
    if (busy || !corrupt || _disposed) return;
    _beginWrite();
    try {
      final at = await port.clock();
      final fresh = AppState.fresh(at);
      await port.save(jsonEncode(fresh.toJson()));
      state = fresh;
      await syncPhoneWarnings();
      corrupt = false;
      error = null;
      retry = null;
      storageUncertain = false;
      _needsRecovery = !_foreground;
    } catch (e) {
      error = 'Could not create a new local state: $e';
    } finally {
      _finishWrite();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
