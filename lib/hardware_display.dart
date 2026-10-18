import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'hardware_output.dart';
import 'pixels.dart';
import 'platform.dart';
import 'w2_program.dart';

/// Foreground-only first hardware milestone. Never retries a whole stale job.
class HardwareDisplay extends ChangeNotifier {
  final DevicePort port;
  bool enabled = false, connected = false, held = true;
  bool busy = false, sending = false, _checking = false, _disposed = false;
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
  HardwareDisplay(this.port);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    final p = await port.displayPreferences();
    enabled = p['hardware'] == true;
    rememberedId = p['id'] as String? ?? '';
    rememberedName = p['name'] as String? ?? '';
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

  Future<bool> connect(String id, String password) async {
    if (busy || sending) return false;
    busy = true;
    connected = false;
    held = true;
    _confirmed = null;
    accepted = null;
    timingApprovedSession = null;
    final epoch = ++_epoch;
    status = 'Connecting…';
    changed();
    try {
      final p = await port.connectDisplay(id, password);
      if (epoch != _epoch || _disposed) {
        await port.disconnectDisplay();
        return false;
      }
      profile = p;
      generation = p['generation'] as int;
      enabled = connected = true;
      rememberedId = id;
      rememberedName = p['name'] as String;
      status = 'Connected · output held for review';
      _lastCheck = -10000;
      return true;
    } catch (e) {
      status = 'Connection failed: $e';
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> disconnect({bool simulator = false}) async {
    ++_epoch;
    connected = false;
    held = true;
    _confirmed = null;
    timingApprovedSession = null;
    status = 'Disconnected · the sign may retain its last accepted output';
    changed();
    try {
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
    status = reason;
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
    if (!enabled ||
        !connected ||
        busy ||
        sending ||
        _checking ||
        at.mono - _lastCheck < 5000)
      return;
    _checking = true;
    _lastCheck = at.mono;
    final epoch = _epoch;
    try {
      final result = await port.checkDisplay();
      if (epoch != _epoch || _disposed) return;
      if (result['connected'] != true || result['generation'] != generation) {
        connected = false;
        hold(
          'Connection lost · the sign may still show its last accepted output. Reconnect and restore the timer.',
        );
      }
    } catch (_) {
      if (epoch == _epoch && !_disposed) {
        connected = false;
        hold('Display unreachable · reconnect and review output');
      }
    } finally {
      _checking = false;
      changed();
    }
  }

  HardwareOutputPlan _plan(Session s, Stamp at) {
    // Automatic stage warnings and effects are intentionally not enabled yet.
    final copy = s.copy()..automaticCue = null;
    return planHardwareOutput(
      copy,
      at,
      connectionGeneration: generation,
      automaticCues: false,
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
        staticLayout(cue),
        'Use a static cue that fits 32 pixels for this hardware milestone. Scrolling and flashing sign cues are not enabled yet.',
      );
  }

  static bool staticLayout(TextLayout l) =>
      l.effect != 'flash' && textWidth(l) <= 32;
  bool _fallback(HardwareOutputPlan p) =>
      p.kind == HardwareOutputKind.text && !staticLayout(p.layout!);
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
    if (p.kind == HardwareOutputKind.blank ||
        (_fallback(p) && p.reason == HardwareOutputReason.endScreen))
      return List.filled(512, false);
    if (_fallback(p))
      return renderPixels(
        const TextLayout('00:00', effect: 'static', height: 2),
        0,
      );
    return renderPixels(p.layout, 0);
  }

  List<bool> preview(Stamp at) =>
      accepted == null ? List.filled(512, false) : _pixels(accepted!, at);
  String get acceptedLabel {
    final p = accepted;
    if (p == null) return 'No current output acknowledgement';
    if (p.kind == HardwareOutputKind.countdown)
      return 'Native countdown · phone preview estimates remaining time';
    if (p.kind == HardwareOutputKind.blank ||
        (_fallback(p) && p.reason == HardwareOutputReason.endScreen))
      return 'Blank';
    return _fallback(p) ? '00:00' : p.layout?.text ?? 'Blank';
  }

  void reconcile(Session s, Stamp at) {
    _latest = s;
    _now = at;
    if (!enabled || !connected || held || busy || sending || _disposed) return;
    final p = _plan(s, at);
    if (p.kind == HardwareOutputKind.blocked) {
      hold(
        'Output held: ${p.reason.name}. Review and restore the current timer.',
      );
      return;
    }
    if (!p.canPublish || _confirmed == p.fingerprint) return;
    if (p.kind == HardwareOutputKind.text &&
        !staticLayout(p.layout!) &&
        p.reason != HardwareOutputReason.endScreen &&
        p.reason != HardwareOutputReason.atZero) {
      hold(
        'This cue needs animation. Choose a static cue or restore the timer.',
      );
      return;
    }
    // The controller already stops at 00:00; do not cause a needless blink there.
    if (p.reason == HardwareOutputReason.atZero &&
        accepted?.kind == HardwareOutputKind.countdown &&
        accepted!.sessionId == p.sessionId &&
        accepted!.segmentIndex == p.segmentIndex &&
        at.wall >= accepted!.deadlineWallMs! &&
        (_fallback(p) ||
            jsonEncode(p.layout!.toJson()) ==
                jsonEncode(
                  const TextLayout(
                    '00:00',
                    effect: 'static',
                    height: 2,
                  ).toJson(),
                ))) {
      _confirmed = p.fingerprint;
      status = 'Native countdown reached 00:00';
      changed();
      return;
    }
    unawaited(_send(p, at));
  }

  Future<void> _send(HardwareOutputPlan plan, Stamp at) async {
    final epoch = _epoch;
    sending = true;
    status = 'Sending…';
    changed();
    try {
      final Uint8List bytes = plan.kind == HardwareOutputKind.countdown
          ? W2Program.countdown(0)
          : W2Program.frames([_pixels(plan, at)]);
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
      accepted = plan;
      _confirmed = null;
      final current = _plan(_latest!, _now!);
      if (current.fingerprint == plan.fingerprint && current.canPublish)
        _confirmed = plan.fingerprint;
      status = _fallback(plan)
          ? plan.reason == HardwareOutputReason.endScreen
                ? 'Controller accepted blank · animated end screen is deferred'
                : 'Controller accepted 00:00 · animated At Zero is deferred'
          : 'Controller accepted · check the sign to confirm appearance';
    } catch (e) {
      if (epoch == _epoch && !_disposed) {
        _confirmed = null;
        connected = false;
        held = true;
        ++_epoch;
        status = 'Update not confirmed: $e';
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
    ++_epoch;
    unawaited(port.disconnectDisplay().catchError((_) {}));
    super.dispose();
  }
}
