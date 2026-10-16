import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'pixels.dart';
import 'platform.dart';

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
      for (final t in state.templates) {
        validateTimelinePixels(t);
      }
      if (state.session.timeline != null)
        validateTimelinePixels(state.session.timeline!);
      if (state.session.alert != null) validateLayout(state.session.alert!);
      for (final cue in state.savedCues) {
        validateLayout(cue.layout);
      }
      state.session = recover(state.session, now);
      // Persist recovery holds before the first possible display publication.
      await port.save(jsonEncode(state.toJson()));
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
      mutation(draft, at);
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
      error = null;
      retry = null;
      _retryIsCheckpoint = false;
      storageUncertain = false;
      _publish();
      return true;
    } catch (e) {
      error = 'Action was not saved: $e';
      _retryIsCheckpoint = false;
      retry = () => commit(mutation, revision: baseRevision);
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
      if (storageUncertain) {
        draft.session.held = true;
        draft.session.uncertain = true;
      }
      draft.session.checkpoint = now;
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
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
