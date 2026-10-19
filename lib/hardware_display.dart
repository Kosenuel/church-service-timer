import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'hardware_output.dart';
import 'pixels.dart';
import 'platform.dart';
import 'w2_program.dart';

/// Serialized display updates, including the active Android foreground service.
/// Never retries a whole stale job.
class HardwareDisplay extends ChangeNotifier {
  final DevicePort port;
  bool enabled = false, connected = false, held = true;
  bool busy = false, sending = false, _checking = false, _disposed = false;
  bool autoReconnect = true, interrupted = false, credentialsNeeded = false;
  int _failures = 0, _attempt = 0, _nextRetry = 0, _intent = 0;
  String? _sessionPassword, _restoreSession;
  Stamp? _lostAt;
  final List<String> diagnostics = [];
  bool get retryEnabled =>
      enabled && autoReconnect && !credentialsNeeded && rememberedId.isNotEmpty;
  void record(String message) {
    diagnostics.insert(
      0,
      '${DateTime.now().toIso8601String().substring(11, 19)} · $message',
    );
    if (diagnostics.length > 20) diagnostics.removeLast();
  }

  int generation = 0, _epoch = 0, _lastCheck = -10000;
  String rememberedId = '',
      rememberedName = '',
      status = 'No physical display selected';
  String? timingApprovedSession;
  Json? profile;
  HardwareOutputPlan? accepted;
  String? _confirmed;
  Session? _latest;
  Stamp? _now;
  List<Json> devices = [];
  void Function(String session, String kind, String message)? onEvent;
  Stamp? _acceptedAt;
  String? _warningToken;
  int _warningUntil = 0;
  void Function(String session, int segment, int trigger, Stamp acceptedAt)?
  onWarningAccepted;
  String cueToken(Session s) => '${s.id}/${s.index}/${s.automaticCueAt?.mono}';
  HardwareDisplay(this.port);
  void event(String kind, String message, {String? session}) {
    final id = session ?? _latest?.id;
    if (id != null) onEvent?.call(id, kind, message);
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    final p = await port.displayPreferences();
    enabled = p['hardware'] == true;
    rememberedId = p['id'] as String? ?? '';
    rememberedName = p['name'] as String? ?? '';
    autoReconnect = p['autoReconnect'] != false;
    if (enabled) status = 'Reconnect and review before restoring output';
    changed();
  }

  Future<void> discover() async {
    if (busy || sending) return;
    busy = true;
    status = 'Looking for displays on Wi-Fi…';
    changed();
    try {
      devices = await port.discoverDisplays();
      status = devices.isEmpty
          ? 'No supported parameter replies. Check the sign’s Wi-Fi and scan again.'
          : 'Select the display to connect';
    } catch (e) {
      status = 'Scan failed: $e';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> connect(
    String id,
    String password, {
    bool recovering = false,
  }) async {
    if (busy || sending) return false;
    busy = true;
    connected = false;
    held = true;
    _confirmed = null;
    accepted = null;
    timingApprovedSession = null;
    final epoch = ++_epoch;
    final intent = _intent;
    status = 'Connecting…';
    changed();
    try {
      final p = await port.connectDisplay(id, password);
      if (epoch != _epoch || intent != _intent || _disposed) {
        await port.disconnectDisplay();
        return false;
      }
      profile = p;
      generation = p['generation'] as int;
      enabled = connected = true;
      rememberedId = id;
      rememberedName = p['name'] as String;
      _sessionPassword = password;
      autoReconnect = true;
      credentialsNeeded = interrupted = false;
      _failures = _attempt = 0;
      await port.setDisplayAutoReconnect(true);
      if (intent != _intent || _disposed) return false;
      status = 'Connected · output held for review';
      final latest = _latest;
      if (recovering &&
          latest != null &&
          latest.active &&
          latest.id == _restoreSession &&
          !latest.held &&
          !latest.uncertain &&
          _lostAt != null &&
          _now != null &&
          _now!.sameBoot(_lostAt!) &&
          _now!.since(_lostAt!) < recoveryLimitMs) {
        held = false;
        status = 'Reconnected · restoring current output';
      }
      _restoreSession = null;
      _lostAt = null;
      record(recovering ? 'LED sign reconnected' : 'LED sign connected');
      event('connection', status);
      _lastCheck = -10000;
      return true;
    } catch (e) {
      if (intent != _intent || _disposed) return false;
      final rejected = e.toString().toLowerCase().contains('password');
      if (rejected) {
        credentialsNeeded = true;
        _sessionPassword = null;
      }
      status = rejected
          ? 'Password rejected · enter the current device password'
          : 'LED sign unavailable · retrying connection';
      record(
        rejected
            ? 'Authentication rejected; automatic retries stopped'
            : 'LED sign connection attempt failed',
      );
      return false;
    } finally {
      busy = false;
      changed();
      if (!_disposed && _latest != null && _now != null)
        reconcile(_latest!, _now!);
    }
  }

  Future<void> disconnect({bool simulator = false}) async {
    _intent++;
    autoReconnect = false;
    credentialsNeeded = interrupted = false;
    _sessionPassword = _restoreSession = null;
    _lostAt = null;
    ++_epoch;
    connected = false;
    held = true;
    _confirmed = null;
    timingApprovedSession = null;
    status = 'Disconnected · the sign may retain its last accepted output';
    event('connection', 'Display disconnected · last output may remain');
    record('Disconnected by operator · automatic retries stopped');
    changed();
    try {
      await port.setDisplayAutoReconnect(false);
      if (simulator) {
        await port.useSimulator();
        enabled = false;
        accepted = null;
      } else {
        await port.disconnectDisplay();
      }
    } catch (e) {
      status = 'Could not close display connection: $e';
    }
    changed();
  }

  void hold(String reason) {
    ++_epoch;
    held = true;
    _confirmed = null;
    timingApprovedSession = null;
    _restoreSession = null;
    status = reason;
    event('hold', reason);
    changed();
  }

  void release(Session s, {bool timingVerified = false}) {
    require(connected, 'Connect the display first.');
    if (timingVerified) timingApprovedSession = s.id;
    held = false;
    _confirmed = null;
    status = 'Ready to send the reviewed output';
    changed();
  }

  Future<void> check(Stamp at) async {
    _now = at;
    if (!connected) {
      if (retryEnabled &&
          !busy &&
          !sending &&
          !_checking &&
          at.mono >= _nextRetry) {
        await reconnectSaved(automatic: true);
      }
      return;
    }
    if (!enabled ||
        !connected ||
        busy ||
        sending ||
        _checking ||
        at.mono - _lastCheck < (interrupted ? 2000 : 5000))
      return;
    _checking = true;
    _lastCheck = at.mono;
    final epoch = _epoch;
    try {
      final result = await port.checkDisplay();
      if (epoch != _epoch || _disposed) return;
      if (result['connected'] != true || result['generation'] != generation) {
        await _missedCheck(
          result['reason'] as String? ?? 'Controller reply missing',
        );
      } else if (interrupted) {
        interrupted = false;
        _failures = 0;
        status = 'Display connected';
        record('LED sign responded during connection grace period');
        changed();
      }
    } catch (_) {
      if (epoch == _epoch && !_disposed) {
        await _missedCheck('Controller health check failed');
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _missedCheck(String reason) async {
    interrupted = true;
    _failures++;
    status = 'Connection interrupted · checking display…';
    if (_failures == 1) record(reason);
    if (_failures >= 3) {
      _loseConnection('LED sign unreachable');
      await port.disconnectDisplay();
    }
    changed();
  }

  void _loseConnection(String reason) {
    if (!held && _latest?.active == true) _restoreSession = _latest!.id;
    _lostAt ??= _now;
    connected = false;
    held = true;
    interrupted = false;
    _confirmed = null;
    ++_epoch;
    _nextRetry = (_now?.mono ?? 0) + 2000;
    status = autoReconnect ? '$reason · retrying…' : reason;
    record(status);
    event('connection', reason);
  }

  /// Re-authenticate only the remembered controller. Never replay a saved upload.
  Future<bool> reconnectSaved({bool automatic = false}) async {
    if (_disposed || busy || sending || _checking || rememberedId.isEmpty)
      return false;
    if (automatic && !retryEnabled) return false;
    if (!automatic) {
      _intent++;
      autoReconnect = true;
      credentialsNeeded = false;
    }
    final intent = _intent;
    _checking = true;
    status = 'Reconnecting display…';
    changed();
    try {
      // Reserve the operation before persistence can yield to a clock tick.
      // Otherwise a background retry can race a manual reconnection.
      if (!automatic) await port.setDisplayAutoReconnect(true);
      if (intent != _intent || _disposed) return false;
      final secret =
          _sessionPassword ?? await port.savedDisplayPassword(rememberedId);
      if (intent != _intent || _disposed) return false;
      if (secret == null) {
        credentialsNeeded = true;
        status = 'Enter the device password to reconnect';
        return false;
      }
      final found = await port.discoverDisplays();
      if (intent != _intent || _disposed) return false;
      if (!found.any(
        (d) => d['id'] == rememberedId && d['supported'] == true,
      )) {
        status = 'Remembered display unavailable · retrying…';
        return false;
      }
      devices = found;
      return await connect(rememberedId, secret, recovering: true);
    } catch (_) {
      if (intent == _intent) status = 'LED sign unavailable · retrying…';
      return false;
    } finally {
      _checking = false;
      _attempt = (_attempt + 1).clamp(1, 5);
      _nextRetry =
          (_now?.mono ?? 0) + [0, 2000, 4000, 8000, 16000, 30000][_attempt];
      changed();
      if (!_disposed && _latest != null && _now != null)
        reconcile(_latest!, _now!);
    }
  }

  HardwareOutputPlan _plan(Session s, Stamp at) {
    final current = s.copy();
    if (cueToken(s) == _warningToken &&
        s.automaticCueAt != null &&
        s.automaticCue != null) {
      current.automaticCueDurationMs = _warningUntil - s.automaticCueAt!.mono;
    }
    return planHardwareOutput(
      current,
      at,
      connectionGeneration: generation,
      allowUncertainTiming: timingApprovedSession == s.id,
    );
  }

  void validateAction(Session s, Stamp at, {TextLayout? cue}) {
    if (!enabled) return;
    require(
      s.rate == 1,
      'Use normal speed with a physical sign. Fast rehearsal is simulator-only.',
    );
    if (s.active)
      require(
        s.remaining(at) <= observedW2CountdownLimitMs,
        'This hardware milestone supports up to 59:59 remaining. Use Simulator for longer countdowns.',
      );
    if (cue != null)
      require(
        textWidth(cue) + 6 <= 2048,
        'This cue is too long for the display animation buffer.',
      );
  }

  static bool staticLayout(TextLayout l) =>
      l.effect != 'flash' && textWidth(l) <= 32;
  List<bool> _pixels(HardwareOutputPlan p, Stamp at) {
    if (p.kind == HardwareOutputKind.countdown) {
      final left = ((p.deadlineWallMs! - at.wall).clamp(
        0,
        maxRemainingMs,
      )).toInt();
      return renderPixels(
        TextLayout(formatTime(left), effect: 'static', height: 2),
        0,
      );
    }
    if (p.kind == HardwareOutputKind.blank) return List.filled(512, false);
    return renderPixels(
      p.layout,
      _acceptedAt == null ? 0 : at.since(_acceptedAt!),
    );
  }

  List<bool> preview(Stamp at) =>
      accepted == null ? List.filled(512, false) : _pixels(accepted!, at);
  String get acceptedLabel {
    final p = accepted;
    if (p == null) return 'No current output acknowledgement';
    if (p.kind == HardwareOutputKind.countdown)
      return 'Native countdown · phone preview estimates remaining time';
    if (p.kind == HardwareOutputKind.blank) return 'Blank';
    return p.layout?.text ?? 'Blank';
  }

  void reconcile(Session s, Stamp at) {
    _latest = s;
    _now = at;
    if (!enabled ||
        !connected ||
        interrupted ||
        held ||
        busy ||
        sending ||
        _disposed)
      return;
    final p = _plan(s, at);
    if (p.kind == HardwareOutputKind.blocked) {
      hold(
        'Output held: ${p.reason.name}. Review and restore the current timer.',
      );
      return;
    }
    if (!p.canPublish || _confirmed == p.fingerprint) return;
    // The controller already stops at 00:00; do not cause a needless blink there.
    if (p.reason == HardwareOutputReason.atZero &&
        accepted?.kind == HardwareOutputKind.countdown &&
        accepted!.sessionId == p.sessionId &&
        accepted!.segmentIndex == p.segmentIndex &&
        at.wall >= accepted!.deadlineWallMs! &&
        (jsonEncode(p.layout!.toJson()) ==
            jsonEncode(
              const TextLayout('00:00', effect: 'static', height: 2).toJson(),
            ))) {
      _confirmed = p.fingerprint;
      status = 'Native countdown reached 00:00';
      changed();
      return;
    }
    unawaited(_send(p, at));
  }

  Uint8List _program(HardwareOutputPlan p, Stamp at) {
    final l = p.layout;
    if (l == null) return W2Program.frames([List.filled(512, false)]);
    if (l.effect == 'flash')
      return W2Program.frames([
        renderPixels(l, 0),
        List.filled(512, false),
      ], frameIntervalMs: 500);
    if (l.effect == 'scroll' && textWidth(l) > 32) {
      final interval = 2 * (500 / l.speed).round();
      return W2Program.frames(
        List.generate(
          textWidth(l) + 6,
          (i) => renderPixels(l, (i * 1000 / l.speed).ceil()),
        ),
        frameIntervalMs: interval,
      );
    }
    return W2Program.frames([renderPixels(l, 0)]);
  }

  Future<void> _send(HardwareOutputPlan plan, Stamp at) async {
    final epoch = _epoch;
    final warningSession = _latest?.copy();
    sending = true;
    status = 'Sending…';
    event('sending', 'Sending ${plan.reason.name}', session: plan.sessionId);
    changed();
    try {
      final Uint8List bytes = plan.kind == HardwareOutputKind.countdown
          ? W2Program.countdown(0)
          : _program(plan, at);
      final result = await port.sendDisplay(
        bytes,
        generation,
        plan.deadlineWallMs,
      );
      if (_disposed || epoch != _epoch) {
        _confirmed = null;
        return;
      }
      require(
        result['accepted'] == true && result['generation'] == generation,
        'No valid final acknowledgement.',
      );
      // Even a stale successful write reached the sign. Invalidate the cache,
      // then reconcile the newest desired output rather than suppressing it.
      final acceptedAt = await port.clock();
      if (_disposed || epoch != _epoch) return;
      accepted = plan;
      _acceptedAt = acceptedAt;
      if (plan.reason == HardwareOutputReason.automaticCue &&
          warningSession != null &&
          _latest != null &&
          cueToken(_latest!) == cueToken(warningSession) &&
          _latest!.active &&
          !_latest!.outputBlank &&
          _latest!.automaticCue != null) {
        _warningToken = cueToken(warningSession);
        _warningUntil =
            _acceptedAt!.mono + warningSession.automaticCueDurationMs;
        onWarningAccepted?.call(
          plan.sessionId,
          plan.segmentIndex,
          warningSession.automaticCueAt!.mono,
          _acceptedAt!,
        );
      }
      event(
        'accepted',
        'Controller accepted ${plan.reason.name} · appearance is not optically verified',
        session: plan.sessionId,
      );
      _confirmed = null;
      final current = _plan(_latest!, _now!);
      if (current.fingerprint == plan.fingerprint && current.canPublish)
        _confirmed = plan.fingerprint;
      status = 'Controller accepted · check the sign to confirm appearance';
    } catch (e) {
      if (epoch == _epoch && !_disposed) {
        _confirmed = null;
        _loseConnection('Display update not confirmed');
        event(
          'failed',
          'Display update not confirmed · reconnect and review',
          session: plan.sessionId,
        );
        try {
          await port.disconnectDisplay();
        } catch (_) {}
      }
    } finally {
      sending = false;
      changed();
      if (!_disposed && _latest != null && _now != null)
        reconcile(_latest!, _now!);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _intent++;
    _sessionPassword = null;
    ++_epoch;
    unawaited(port.disconnectDisplay().catchError((_) {}));
    super.dispose();
  }
}
