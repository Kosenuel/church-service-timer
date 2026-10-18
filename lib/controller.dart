import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'domain.dart' as branding show appVersion;
import 'pixels.dart';
import 'church_banner.dart';
import 'platform.dart';
import 'native_fonts.dart';
import 'warning_notifications.dart';
import 'display_connection.dart';
import 'hardware_display.dart';

/// The simulator is an output adapter, not a fake Huidu protocol implementation.
class Simulator {
  TextLayout? delivered;
  String owner = '', signature = '';
  int revision = -1, deliveredAt = 0;
  List<bool> pixels = List.filled(512, false);
  void clear() {
    delivered = null;
    owner = signature = '';
    revision = -1;
    deliveredAt = 0;
    pixels = List.filled(512, false);
  }

  void update(Session s, Stamp now) {
    if (s.disconnected || s.held) return;
    if (s.outputBlank) {
      if (owner != s.id || signature != 'blank') deliveredAt = now.mono;
      owner = s.id;
      signature = 'blank';
      revision = s.revision;
      delivered = null;
      pixels = List.filled(512, false);
      return;
    }
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
  late final HardwareDisplay hardware;
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
  String? deviceSettingsError;
  bool backgroundActive = false;
  ({String session, int segment, int trigger, Stamp acceptedAt})?
  _warningAccepted;
  String? backgroundError;
  final List<({String session, ServiceEvent event})> _events = [];
  List<({String session, ServiceEvent event})> _mergeEvents(AppState draft) {
    final batch = List.of(_events);
    for (final item in batch) {
      if (draft.session.id == item.session)
        addServiceEvent(draft.session.events, item.event);
      for (final report in draft.reports.where((r) => r.id == item.session)) {
        addServiceEvent(report.events, item.event);
      }
    }
    return batch;
  }

  Future<void> syncActiveService() async {
    final desired =
        state.session.active &&
        hardware.enabled &&
        hardware.connected &&
        !hardware.held;
    if (desired == backgroundActive) return;
    try {
      backgroundActive = await port.setActiveService(desired);
      backgroundError = desired && !backgroundActive
          ? 'Keep this app open: background operation is unavailable.'
          : null;
    } catch (_) {
      backgroundActive = false;
      backgroundError =
          'Keep this app open: background operation could not start.';
    }
  }

  String loadingChurchName = '';
  String appVersion = branding.appVersion;
  final themeSelection = ValueNotifier<String>('midnight_lime');
  String? _previewTheme;
  void previewTheme(String? id) {
    _previewTheme = id;
    themeSelection.value = id ?? (ready ? state.themeId : 'midnight_lime');
  }

  Future<void> syncDeviceSettings() async {
    themeSelection.value = _previewTheme ?? state.themeId;
    try {
      await port.setKeepScreenAwake(state.keepScreenAwake);
      deviceSettingsError = null;
    } catch (e) {
      deviceSettingsError =
          'Screen-awake preference is saved but could not be applied: $e';
    }
  }

  Json notificationState = {'enabled': false, 'exact': false, 'sound': false};
  Future<bool> Function()? retry;
  Timer? _timer;
  AppController(this.port) {
    hardware = HardwareDisplay(port)..addListener(_hardwareChanged);
    hardware.onEvent = (session, kind, message) {
      if (_events.length < 2000)
        _events.add((
          session: session,
          event: ServiceEvent(now.wall, kind, message),
        ));
    };
    hardware.onWarningAccepted = (session, segment, trigger, acceptedAt) {
      _warningAccepted = (
        session: session,
        segment: segment,
        trigger: trigger,
        acceptedAt: acceptedAt,
      );
    };
    port.setBackgroundHandler(() async {
      if (backgroundActive && !await port.activeServiceRunning()) {
        backgroundActive = false;
        await suspend();
      } else {
        await tick();
      }
    });
  }
  void _hardwareChanged() {
    if (backgroundActive && (!hardware.connected || hardware.held)) {
      backgroundActive = false;
      if (!_foreground) _needsRecovery = true;
      unawaited(port.setActiveService(false));
      if (ready && !busy) unawaited(checkpoint());
    }
    if (!_disposed) notifyListeners();
  }

  DisplayConnection get displayConnection => DisplayConnection.fromAdapter(
    simulated: !hardware.enabled,
    connected: hardware.enabled
        ? hardware.connected
        : !state.session.disconnected,
  );
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
    if ((_foreground || backgroundActive) &&
        !_needsRecovery &&
        !corrupt &&
        !_disposed) {
      simulator.update(state.session, now);
      if (!storageUncertain) hardware.reconcile(state.session, now);
    }
  }

  Future<void> initialize({bool startTicker = true}) async {
    now = await port.clock();
    try {
      final data = await port.load();
      state = data == null
          ? AppState.fresh(now)
          : AppState.fromJson(
              Map<String, dynamic>.from(jsonDecode(data)),
              now: now,
            );
      loadingChurchName = state.churchName;
      themeSelection.value = state.themeId;
      notifyListeners();
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
    try {
      await hardware.initialize();
    } catch (_) {
      hardware.status = 'Display preferences unavailable · scan to connect';
    }
    try {
      appVersion = await port.installedVersion();
    } catch (_) {
      /* Source build fallback. */
    }
    await syncDeviceSettings();
    if (_foreground && _needsRecovery) await resume();
    _publish();
    notifyListeners();
    if (startTicker)
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => tick());
  }

  Future<void> tick() async {
    if (_ticking ||
        !ready ||
        _disposed ||
        (!_foreground && !backgroundActive) ||
        _needsRecovery)
      return;
    _ticking = true;
    try {
      now = await port.clock();
      if ((!_foreground && !backgroundActive) || _needsRecovery || _disposed)
        return;
      if (!corrupt) {
        if (!busy && _warningAccepted != null && retry == null) {
          final accepted = _warningAccepted!;
          final saved = await commit((draft, _) {
            final s = draft.session;
            if (s.id == accepted.session &&
                s.index == accepted.segment &&
                s.active &&
                s.automaticCueAt?.mono == accepted.trigger &&
                s.automaticCue != null &&
                !s.outputBlank) {
              s.automaticCueAt = accepted.acceptedAt;
            }
          });
          if (saved && _warningAccepted == accepted) _warningAccepted = null;
        }
        if (!busy &&
            retry == null &&
            dueWarnings(state.session, now).isNotEmpty) {
          await act('warnings');
        }
        _publish();
        unawaited(hardware.check(now));
        if (!busy &&
            !storageUncertain &&
            (now.since(state.session.checkpoint) >= 55000 ||
                _events.isNotEmpty) &&
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
    if (busy ||
        corrupt ||
        _needsRecovery ||
        (!_foreground && !backgroundActive) ||
        _disposed)
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
      final previousAwake = state.keepScreenAwake;
      mutation(draft, at);
      draft.churchName = churchNameValue(draft.churchName);
      if (draft.churchBanner != state.churchBanner)
        await validateBannerPixels(draft.churchBanner);
      themeIdValue(draft.themeId);
      draft.applySharedZero();
      draft.applySharedWarnings(at);
      await NativeDisplayFonts.prepareState(draft);
      if (draft.session.automaticCue != null &&
          draft.session.automaticCueAt != null &&
          draft.session.automaticCueAt!.mono != previous.automaticCueAt?.mono) {
        final rule = draft.session.timeline!.display.warnings.firstWhere(
          (w) =>
              jsonEncode(w.cue.toJson()) ==
              jsonEncode(draft.session.automaticCue!.toJson()),
        );
        draft.session.automaticCueDurationMs = warningDurationMs(rule);
      }
      final logged = _mergeEvents(draft);
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
      _events.removeRange(0, logged.length);
      if (state.session.phase == 'idle' && state.session.id != previous.id)
        simulator.clear();
      themeSelection.value = _previewTheme ?? state.themeId;
      if (previousAwake != state.keepScreenAwake) await syncDeviceSettings();
      await syncPhoneWarnings(previous: previous);
      error = null;
      retry = null;
      _retryIsCheckpoint = false;
      storageUncertain = false;
      if (previous.phase == 'ready' &&
          state.session.active &&
          hardware.connected) {
        hardware.release(state.session);
      }
      await syncActiveService();
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

  Future<bool> act(String action, {dynamic value, int? revision}) async {
    final saved = await commit((draft, at) {
      if (action == 'cue') validateLayout(value as TextLayout);
      draft.session = transition(
        draft.session,
        action,
        at,
        value: value,
        expectedRevision: revision,
      );
      if ([
        'start',
        'pause',
        'adjust',
        'advance',
        'undo',
        'rate',
        'cue',
      ].contains(action)) {
        hardware.validateAction(
          draft.session,
          at,
          cue: action == 'cue' ? value as TextLayout : null,
        );
      }
      if (action == 'load') draft.session.churchName = draft.churchName;
      if ((action == 'start' || action == 'advance') && hardware.connected)
        draft.session.disconnected = false;
      if (action == 'end') {
        draft.reports.add(ServiceReport.fromSession(draft.session, at));
      }
    }, revision: revision);
    if (saved && action == 'advance' && hardware.connected) {
      hardware.release(state.session, timingVerified: true);
      await syncActiveService();
      _publish();
    }
    return saved;
  }

  Future<bool> restoreHardware({int? verifiedSeconds, int? revision}) async {
    if (!hardware.connected) return false;
    final saved = await commit((draft, at) {
      final s = draft.session;
      if (verifiedSeconds != null)
        require(
          verifiedSeconds >= 0 && verifiedSeconds <= 3599,
          'Enter a verified time from 00:00 to 59:59.',
        );
      require(
        s.active || s.phase == 'ended',
        'Start a service before restoring its output.',
      );
      if (s.uncertain && s.active)
        require(
          verifiedSeconds != null,
          'Verify the remaining time before restoring.',
        );
      if (s.active) {
        s.baseMs = verifiedSeconds == null
            ? s.balance(at)
            : verifiedSeconds * 1000;
        s.anchor = at;
        s.undo = null;
      }
      s.alert = null;
      s.automaticCue = null;
      s.outputBlank = false;
      s.held = false;
      s.disconnected = false;
      s.outage = null;
      s.checkpoint = at;
      s.revision++;
      hardware.validateAction(s, at);
    }, revision: revision);
    if (!saved || !hardware.connected) return false;
    hardware.release(state.session, timingVerified: true);
    await syncActiveService();
    _publish();
    return true;
  }

  Future<bool> restoreBackup(AppState restored) async {
    try {
      await NativeDisplayFonts.prepareState(restored);
    } catch (e) {
      error = 'Backup not restored: $e';
      notifyListeners();
      return false;
    }
    final saved = await commit((draft, at) {
      require(
        !draft.session.active && draft.session.phase != 'ready',
        'End or cancel the loaded service before restoring a backup.',
      );
      for (final t in restored.templates) {
        validateTimelinePixels(t);
      }
      for (final cue in restored.stageCues) {
        validateLayout(cue);
      }
      validateLayout(restored.defaults.end);
      for (final cue in restored.defaults.cues) {
        validateLayout(cue);
      }
      for (final warning in restored.defaults.warnings) {
        validateLayout(warning.cue);
      }
      if (restored.defaults.zero != null)
        validateLayout(restored.defaults.zero!);
      draft.templates = restored.templates;
      draft.defaults = restored.defaults;
      draft.reports = restored.reports;
      draft.stageCues = restored.stageCues;
      draft.pixelShape = restored.pixelShape;
      draft.groupTemplates = restored.groupTemplates;
      draft.churchName = restored.churchName;
      draft.churchBanner = restored.churchBanner;
      draft.themeId = restored.themeId;
      draft.keepScreenAwake = restored.keepScreenAwake;
      draft.session = Session(
        id: 'restored-${at.wall}',
        anchor: at,
        revision: draft.session.revision + 1,
      );
    });
    if (saved) {
      simulator.clear();
      notifyListeners();
    }
    return saved;
  }

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

  Future<bool> setSharedWarnings(List<WarningRule> rules) =>
      commit((draft, at) {
        final checked = readWarnings(rules.map((w) => w.toJson()).toList());
        draft.defaults = draft.defaults.withWarnings(checked);
        draft.applySharedWarnings(at);
        draft.session.revision++;
      });

  /// Deliberately excludes names, cue text, notes, paths and raw exceptions.
  String get feedbackDiagnostics {
    final categories = [
      if (corrupt) 'state recovery',
      if (storageUncertain || retry != null) 'storage',
      if (error != null) 'app action',
      if (notificationError != null) 'notifications',
      if (deviceSettingsError != null) 'screen preference',
    ];
    return [
      'Output adapter: ${hardware.enabled ? 'W2 Wi-Fi' : 'Simulator'}',
      'Connection: ${displayConnection.label}',
      'Physical controller: ${hardware.enabled ? 'W2 hardware milestone' : 'not configured'}',
      'Notifications: ${notificationState['enabled'] == true ? 'enabled' : 'disabled'}',
      'Notification sound: ${notificationState['sound'] == true ? 'enabled' : 'disabled'}',
      'Precise alarms: ${notificationState['exact'] == true ? 'allowed' : 'not allowed'}',
      'Current error categories: ${categories.isEmpty ? 'none' : categories.join(', ')}',
    ].join('\n');
  }

  Future<bool> sendAndSaveCue(TextLayout layout, {int? index, int? revision}) =>
      commit((draft, at) {
        validateLayout(layout);
        hardware.validateAction(draft.session, at, cue: layout);
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

  Future<bool> setSharedZero(TextLayout? layout) => commit((draft, _) {
    if (layout != null) validateLayout(layout);
    draft.defaults = draft.defaults.withZero(layout);
  });

  Future<bool> deleteStageCue(int index, TextLayout expected) =>
      commit((draft, _) {
        require(
          index >= 0 &&
              index < draft.stageCues.length &&
              jsonEncode(draft.stageCues[index].toJson()) ==
                  jsonEncode(expected.toJson()),
          'This cue changed. Open it again before deleting.',
        );
        draft.stageCues.removeAt(index);
      });

  Future<void> checkpoint() async {
    if (busy || corrupt || !ready) return;
    _beginWrite();
    try {
      final at = await port.clock();
      now = at;
      final draft = state.copy();
      draft.session.checkpoint = at;
      final logged = _mergeEvents(draft);
      await port.save(jsonEncode(draft.toJson()));
      state = draft;
      _events.removeRange(0, logged.length);
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
    if (backgroundActive && await port.activeServiceRunning()) {
      _foreground = false;
      await checkpoint();
      return;
    }
    backgroundActive = false;
    if (hardware.enabled)
      hardware.hold(
        'App was in the background · review and restore output. The sign may retain a cue or continue its countdown.',
      );
    _foreground = false;
    _needsRecovery = true;
    _resumeRequest++;
    await checkpoint();
  }

  Future<void> resume() async {
    if (backgroundActive && await port.activeServiceRunning()) {
      _foreground = true;
      await tick();
      return;
    }
    backgroundActive = false;
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
      simulator.clear();
      await syncDeviceSettings();
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
    port.setBackgroundHandler(null);
    unawaited(port.setActiveService(false));
    _timer?.cancel();
    hardware.removeListener(_hardwareChanged);
    hardware.dispose();
    themeSelection.dispose();
    super.dispose();
  }
}
