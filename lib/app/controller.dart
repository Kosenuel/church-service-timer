import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:church_service_timer/diagnostics/service_metrics.dart';
import 'package:church_service_timer/diagnostics/performance_report.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:church_service_timer/web_stage/mdns_responder.dart';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/domain/domain.dart'
    as branding
    show appVersion;
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/shared/church_banner.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/hardware/hardware_display.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/app/appearance_preview.dart';
import 'package:church_service_timer/app/edit_draft_queue.dart';
import 'package:church_service_timer/app/practice_controller.dart';
import 'package:church_service_timer/app/quick_message_controller.dart';
import 'package:church_service_timer/app/stage_request_controller.dart';
import 'package:church_service_timer/app/paired_command_bridge.dart';
import 'package:church_service_timer/app/phone_warning_scheduler.dart';
import 'package:church_service_timer/app/simulator.dart';
import 'package:church_service_timer/app/web_stage_coordinator.dart';
import 'package:church_service_timer/app/metrics_tracker.dart';
import 'package:church_service_timer/app/backup_controller.dart';
import 'package:church_service_timer/app/settings_pin_controller.dart';
import 'package:church_service_timer/app/service_notification_controller.dart';

export 'package:church_service_timer/app/simulator.dart';

class AppController extends ChangeNotifier {
  final liveNavigation = ValueNotifier<int>(0);
  int? get messageReturnSeconds {
    final s = liveSession;
    int? ms;
    final until = quickMessages.untilMono;
    if (until != null)
      ms = until - now.mono;
    else if (s.hasAutomaticCue(now))
      ms = s.automaticCueDurationMs - now.since(s.automaticCueAt!);
    else if (s.hasManualCue(now) && s.alertDurationSeconds > 0)
      ms = s.alertDurationSeconds * 1000 - now.since(s.alertAt!);
    return ms == null ? null : (ms / 1000).ceil().clamp(0, 86400);
  }

  late final editDrafts = EditDraftQueue(this);
  String? get draftError => editDrafts.error;
  void queueEditDraft(String key, Json? value) => editDrafts.queue(key, value);
  Future<void> flushEditDrafts() => editDrafts.flush();

  Session? _pendingEnd;
  int? _pendingEndRevision;
  bool _preparingEnd = false;
  bool get reportSavePending => _pendingEnd != null;
  Session get liveSession => _pendingEnd ?? state.session;
  String get destination =>
      state.outputDestination ?? (hardware.enabled ? 'led' : 'simulator');

  /// Every stage screen showing the output now: paired phones and web
  /// Stage displays (ids `web:<token>`), for quick-message recipients.
  List<({String id, String name})> get stageScreens => [
    for (final p in pairing.syncedStagePeers) (id: p.id, name: p.name),
    for (final d in webStage.syncedStageDevices)
      (id: 'web:${d.token}', name: '${d.label} (web)'),
  ];

  /// A paired stage screen or a web Stage display is showing the output.
  bool get stageConnected =>
      destination == 'mobile' &&
      pairing.hosting &&
      (pairing.syncedStagePeers.isNotEmpty ||
          webStage.syncedStageDevices.isNotEmpty);
  bool get destinationConnected => destination == 'mobile'
      ? stageConnected
      : destination == 'led'
      ? hardware.connected
      : !state.session.disconnected;
  String get destinationName => destination == 'mobile'
      ? 'Stage screen'
      : destination == 'led'
      ? (hardware.rememberedName.isEmpty ? 'LED sign' : hardware.rememberedName)
      : 'Simulator';
  late final quickMessages = QuickMessageController(this);
  late final practice = PracticeController(this);
  late final stageRequests = StageRequestController(this);
  late final pairedCommands = PairedCommandBridge(this);
  String? get quickMessageId => quickMessages.messageId;
  Set<String> get quickSeen => quickMessages.seen;
  Map<String, String> get quickRecipientNames => quickMessages.recipientNames;
  Set<String> get quickRecipients => quickMessages.recipients;
  QuickMessage? get currentQuickMessage => quickMessages.current;
  Json decoratePairedSnapshot(PairPeer peer, Json data) {
    quickMessages.decorateSnapshot(peer, data);
    // A stage screen offers Request only while requests are on, and sees
    // the state of the one it sent.
    if (stageRequests.enabled && state.session.active) {
      data['stageRequests'] = true;
      final status = stageRequests.statusFor(peer.id);
      if (status != null) data['stageRequest'] = status;
    }
    return data;
  }

  void receiveMessageSeen(PairPeer peer, String id) =>
      quickMessages.receiveSeen(peer, id);
  void clearQuickMessage() => quickMessages.clear();
  Future<bool> sendQuickMessage(
    QuickMessage message, {
    bool test = false,
    String? confirmedEndedSession,
    Set<String>? recipientIds,
  }) => quickMessages.send(
    message,
    test: test,
    confirmedEndedSession: confirmedEndedSession,
    recipientIds: recipientIds,
  );
  Future<void> dismissQuickMessage() => quickMessages.dismiss();
  Future<bool> saveQuickPreset(QuickMessage message, {int? index}) =>
      quickMessages.savePreset(message, index: index);

  Future<bool> selectDestination(String target) async {
    if (!{'led', 'mobile', 'simulator'}.contains(target) ||
        !pairing.localControl ||
        pairing.joined ||
        busy ||
        reportSavePending)
      return false;
    if (!await commit((draft, _) {
      draft.outputDestination = target;
    }))
      return false;
    quickMessages.reset();
    pairing.setStageSharing(target == 'mobile');
    if (target != 'led') await hardware.disconnect(simulator: true);
    await syncActiveService();
    _publish();
    notifyListeners();
    return true;
  }

  Future<bool> blankBeforeSwitch() async {
    if (destination != 'led' ||
        !hardware.connected ||
        hardware.held ||
        hardware.sending)
      return false;
    final wasBlank = state.session.outputBlank;
    if (!wasBlank && !await act('blank')) return false;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) && hardware.connected) {
      if (!hardware.sending && hardware.accepted?.kind.name == 'blank')
        return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    error =
        'Blanking was not acknowledged. The previous sign may still show its last output.';
    return false;
  }

  Future<void> stopSharing() async {
    quickMessages.reset();
    pairing.setStageSharing(false);
    await pairing.stop();
  }

  Future<bool> _finishService({int? revision}) async {
    if (busy || reportSavePending || _preparingEnd) return false;
    _preparingEnd = true;
    final controlEpoch = pairing.epoch;
    try {
      final at = await port.clock();
      require(
        controlEpoch == pairing.epoch,
        'Operator control changed. Review the action again.',
      );
      _pendingEnd = transition(
        state.session,
        'end',
        at,
        expectedRevision: revision,
      );
      _pendingEndRevision = state.session.revision;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    } finally {
      _preparingEnd = false;
    }
    return _saveEndedService();
  }

  Future<bool> _saveEndedService() async {
    final ended = _pendingEnd;
    if (ended == null) return false;
    final saved = await commit(
      (draft, _) {
        draft.session = ended.copy();
        draft.reports.removeWhere((r) => r.id == ended.id);
        if (!ended.noReport)
          draft.reports.add(ServiceReport.fromSession(ended, ended.anchor));
      },
      revision: _pendingEndRevision,
      ending: true,
    );
    if (!saved) {
      error =
          'The service has finished, but its report could not be saved. Retry saving to return to Standing by.';
      retry = _saveEndedService;
      notifyListeners();
    }
    return saved;
  }

  final DevicePort port;
  final pairing = PairHub();
  late AppState state;
  Stamp now = const Stamp(0, 0, 'unknown');
  final simulator = Simulator();
  final liveClock = ChangeNotifier();
  final previewClock = ChangeNotifier();
  int _lastVisibleSecond = -1;
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

  /// Mirrors the Live screen's Lock controls, so notification actions obey it.
  bool uiLocked = false;

  /// The active-service notification; these delegates keep callers
  /// unchanged.
  late final serviceNotification = ServiceNotificationController(this);
  Json serviceCard() => serviceNotification.build();
  Future<void> syncServiceNotification() => serviceNotification.sync();
  Future<void> handleNotificationAction(String action) =>
      serviceNotification.handleAction(action);

  /// Hooks for the feature controllers this class owns.
  bool get disposed => _disposed;
  Future<void>? get pendingWrite => _writeDone?.future;
  void notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  String? error;
  late final phoneWarnings = PhoneWarningScheduler(this);
  String? get notificationError => phoneWarnings.error;
  set notificationError(String? value) => phoneWarnings.error = value;
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
        pairing.hosting ||
        pairing.joined ||
        ((state.session.active ||
                (state.session.phase == 'ended' &&
                    ((state.session.hasManualCue(now) &&
                            state.session.alertDurationSeconds > 0) ||
                        hardware.sending))) &&
            hardware.enabled &&
            ((hardware.connected && !hardware.held) ||
                (!hardware.connected &&
                    hardware.retryEnabled &&
                    !state.session.held &&
                    !_needsRecovery)));
    if (desired == backgroundActive) {
      await syncServiceNotification();
      return;
    }
    try {
      backgroundActive = await port.setActiveService(desired);
      serviceNotification.forget();
      await syncServiceNotification();
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
  final appearancePreview = AppearancePreview();
  ValueNotifier<String> get themeSelection => appearancePreview.themeSelection;
  ValueNotifier<AppearancePreferences> get appearanceSelection =>
      appearancePreview.appearanceSelection;
  void previewAppearance(AppearancePreferences? value) =>
      appearancePreview.previewAppearance(
        value,
        ready ? state.appearance : const AppearancePreferences(),
      );
  void previewTheme(String? id) => appearancePreview.previewTheme(
    id,
    ready ? state.themeId : 'midnight_lime',
  );

  Json pairedSnapshot(bool privateNotes) {
    if (!ready) return {};
    final s = state.session, t = state.session.timeline;
    final display = s.intended(now);
    final quick = quickMessages.forStage;
    return {
      'revision': s.revision,
      'session': s.id,
      'service': t?.name ?? 'Standing by',
      'church': state.churchName,
      'segment': t == null ? '' : t.segments[s.index].name,
      'nextSegment': t != null && s.index + 1 < t.segments.length
          ? t.segments[s.index + 1].name
          : '',
      'displayIsTimer':
          s.active &&
          !s.showClock &&
          !s.outputBlank &&
          !s.hasManualCue(now) &&
          !s.hasAutomaticCue(now) &&
          (s.remaining(now) > 0 || s.timeline?.display.zero == null),
      'index': s.index,
      'phase': s.phase,
      'paused': s.paused,
      'remaining': s.overtime(now) > 0
          ? '+${formatTime(s.overtime(now))}'
          : s.formatted(now),
      'overtime': s.overtime(now) > 0,
      'blank': s.outputBlank && quick == null,
      'stageSharing': destination == 'mobile' && pairing.stageSharingEnabled,
      if (quick != null) 'quickMessage': quick.toJson(),
      'displayText': s.outputBlank ? '' : display?.text ?? '',
      'outputMode': s.outputMode(now),
      'clockBlink': s.clockBlink,
      'effect': display?.effect ?? 'static',
      'speed': display?.speed ?? 12,
      'bold': display?.bold ?? false,
      'italic': display?.italic ?? false,
      'connection': displayConnection.label,
      'rundown': [
        for (final e in t?.segments ?? <Segment>[])
          {
            'name': e.name,
            'minutes': e.minutes,
            'seconds': e.seconds,
            'speaker': e.speaker,
            if (privateNotes) 'notes': e.notes,
          },
      ],
      if (privateNotes) 'cues': [for (final cue in state.stageCues) cue.text],
      if (privateNotes)
        'cueVersions': [
          for (final cue in state.stageCues) jsonEncode(cue.toJson()),
        ],
    };
  }

  /// Whether Android exempts the app from battery optimisation; null when
  /// unknown. Restricted apps can have warnings stopped with the screen off.
  bool? batteryUnrestricted;
  Future<void> refreshBatteryStatus() async {
    bool? next;
    try {
      next = await port.batteryUnrestricted();
    } catch (_) {
      next = null;
    }
    if (next != batteryUnrestricted) {
      batteryUnrestricted = next;
      notifyChanged();
    }
  }

  Future<void> syncDeviceSettings() async {
    unawaited(refreshBatteryStatus());
    appearancePreview.sync(state);
    try {
      await port.setKeepScreenAwake(
        state.keepScreenAwake || pairing.mode == 'stage',
      );
      deviceSettingsError = null;
    } catch (e) {
      deviceSettingsError =
          'Screen-awake preference is saved but could not be applied: $e';
    }
  }

  Json get notificationState => phoneWarnings.status;
  Future<bool> Function()? retry;
  Timer? _timer;

  /// Records performance during a service when Diagnostics asks for it.
  final ServiceMetricsRecorder metrics;

  /// What the last finished recording found, until the app restarts.
  MetricsSummary? lastMetrics;

  /// The marked report of the last finished recording.
  PerformanceReport? lastReport;

  AppController(this.port, {MetricsStore? metricsStore})
    : metrics = ServiceMetricsRecorder(store: metricsStore) {
    pairing.readMemory = port.loadPairing;
    pairing.writeMemory = port.savePairing;
    pairing.discoverHosts = port.discoverPairHosts;
    pairing.currentAddress = port.localNetworkAddress;
    pairing.rejoinWifi = () => port.joinPairWifi(pairing.remoteHostId);
    pairing.currentSsid = () async =>
        (await port.displayNetworkInfo())['ssid'] as String? ?? '';
    pairing.cancelWifi = port.cancelPairWifi;
    pairing.advertise = (portNumber) =>
        port.advertisePairHost(portNumber, hostId: pairing.hostId);
    pairing.unadvertise = port.stopPairAdvertisement;
    pairing.addListener(() {
      unawaited(web.sync());
      if (ready) {
        quickMessages.keepRecipients({for (final s in stageScreens) s.id});
      }
      if (ready && !stageConnected) quickMessages.reset();
      if (!_disposed) notifyListeners();
    });
    pairing.snapshotFor = pairedSnapshot;
    pairing.decorateSnapshot = decoratePairedSnapshot;
    pairing.onMessageSeen = receiveMessageSeen;
    pairing.onStageRequest = (peer, kind) =>
        stageRequests.receive(peer.id, peer.name, kind);
    // Saved at once, so a received program waits for review even after
    // leaving the pairing or closing the app.
    pairing.onProgramReceived = (program, from) => unawaited(
      commit((draft, at) => draft.receiveProgram(program, from, at.wall)),
    );
    pairing.onControlChanged = (message) {
      if (ready && state.session.active && _events.length < 2000) {
        _events.add((
          session: state.session.id,
          event: ServiceEvent(now.wall, 'operator', message),
        ));
      }
    };
    pairing.onOwnershipChanged = () {
      if (ready && !_disposed) {
        unawaited(syncActiveService());
        unawaited(syncDeviceSettings());
      }
    };
    pairing.command = pairedCommands.handle;
    pairing.commandMessage = pairedCommands.message;
    hardware = HardwareDisplay(port)..addListener(_hardwareChanged);
    hardware.onEvent = (session, kind, message) {
      // Output changes after the service must not rewrite its completed report.
      if (!ready || !state.session.active) return;
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
    port.setNotificationActionHandler(handleNotificationAction);
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
    if (ready) unawaited(syncActiveService());
    if (!_disposed) notifyListeners();
  }

  DisplayConnection get displayConnection => destination == 'mobile'
      ? stageConnected
            ? DisplayConnection.stageConnected
            : pairing.stagePeers.isNotEmpty ||
                  webStage.activeDevices.any((d) => d.role == WebRole.stage)
            ? DisplayConnection.stageDisconnected
            : DisplayConnection.stageWaiting
      : DisplayConnection.fromAdapter(
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
      if (reportSavePending) return;
      if (destination == 'simulator') simulator.update(state.session, now);
      if (!storageUncertain && destination == 'led')
        hardware.reconcile(state.session, now);
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
      appearanceSelection.value = state.appearance;
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
    // Create the order-of-service code and easy name once, so they stay the
    // same week after week (and slides stay valid).
    final web = webStageSettings;
    if (state.webStage['orderCode'] != web.orderCode ||
        state.webStage['localName'] != web.localName)
      await commit((draft, _) => draft.webStage = web.toJson());
    // Replace any card left by an earlier process with the restored state.
    unawaited(syncServiceNotification());
    await pairing.restoreMemory();
    try {
      await hardware.initialize();
      if (state.outputDestination != null && destination != 'led')
        await hardware.disconnect(simulator: true);
      pairing.stageSharingEnabled = destination == 'mobile';
    } catch (_) {
      hardware.status = 'Display preferences unavailable · scan to connect';
    }
    try {
      appVersion = await port.installedVersion();
    } catch (_) {
      /* Source build fallback. */
    }
    await syncDeviceSettings();
    if (!corrupt && !state.session.active) {
      unawaited(
        pairing.resumeSavedHost(automatic: true).catchError((_) {
          pairing.memoryNotice =
              'Could not restore the saved connection. Open Paired devices to retry.';
          pairing.changed();
        }),
      );
    }
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
      unawaited(syncServiceNotification());
      if (!corrupt && !reportSavePending) {
        quickMessages.expire();
        practice.checkOvertime();
        stageRequests.prune();
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
          final s = state.session;
          final remaining = s.remaining(now);
          final late = dueWarnings(s, now)
              .map(
                (i) =>
                    s.timeline!.display.warnings[i].seconds * 1000 - remaining,
              )
              .fold(0, math.max);
          await act('warnings');
          unawaited(metrics.warning(now, late));
        }
        await metricsTracker.track();
        unawaited(web.followNetworkChange());
        web.checkSynced();
        _publish();
        await syncActiveService();
        if (destination == 'led') unawaited(hardware.check(now));
        if (!busy &&
            !storageUncertain &&
            (now.since(state.session.checkpoint) >= 55000 ||
                _events.isNotEmpty) &&
            (state.session.active || state.session.phase == 'ended'))
          await checkpoint();
      }
      if (!_disposed) {
        previewClock.notifyListeners();
        final second = now.mono ~/ 1000;
        if (second != _lastVisibleSecond) {
          _lastVisibleSecond = second;
          liveClock.notifyListeners();
        }
      }
    } catch (e) {
      error = 'Clock or activity checkpoint unavailable: $e';
    } finally {
      _ticking = false;
    }
  }

  Future<bool> commit(
    void Function(AppState draft, Stamp at) mutation, {
    int? revision,
    bool ending = false,
    bool clearMessage = false,
  }) async {
    if (busy ||
        (reportSavePending && !ending) ||
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
      draft.clockFormat = readClockFormat(draft.clockFormat);
      draft.session.clockFormat = draft.clockFormat;
      draft.clockBlink = boolSetting(draft.clockBlink);
      draft.session.clockBlink = draft.clockBlink;
      AppearancePreferences.fromJson(draft.appearance.toJson());
      draft.churchName = churchNameValue(draft.churchName);
      if (draft.churchBanner != state.churchBanner)
        await validateBannerPixels(draft.churchBanner);
      themeIdValue(draft.themeId);
      draft.applySharedZero();
      draft.applySharedWarnings(at);
      await NativeDisplayFonts.prepareState(draft);
      if (draft.session.automaticCue != null &&
          draft.session.automaticCueAt != null &&
          draft.session.automaticCueAt!.mono != previous.automaticCueAt?.mono &&
          draft.session.timeline!.display.warnings.any(
            (w) =>
                jsonEncode(w.cue.toJson()) ==
                jsonEncode(draft.session.automaticCue!.toJson()),
          )) {
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
      if (clearMessage) quickMessages.reset();
      if (ending) {
        _pendingEnd = null;
        _pendingEndRevision = null;
        quickMessages.reset();
      }
      _events.removeRange(0, logged.length);
      if (state.session.phase == 'idle' && state.session.id != previous.id)
        simulator.clear();
      appearancePreview.sync(state);
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
      // Scheduling a start is a deliberate "show this on the display": the
      // sign's own hold is released so the pre-service output can be sent.
      if (state.session.phase == 'ready' &&
          state.session.startsAtWall != null &&
          state.session.startsAtWall != previous.startsAtWall &&
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
          : () => commit(
              mutation,
              revision: baseRevision,
              ending: ending,
              clearMessage: clearMessage,
            );
      return false;
    } finally {
      _finishWrite();
    }
  }

  Future<bool> act(
    String action, {
    dynamic value,
    int? revision,
    bool remote = false,
  }) async {
    if ((!pairing.localControl && !remote) || pairing.joined) {
      error = 'This device does not currently control the service.';
      notifyListeners();
      return false;
    }
    if (action == 'end') {
      final ended = await _finishService(revision: revision);
      if (ended) await practice.observe('end', null);
      return ended;
    }
    final controlEpoch = pairing.epoch;
    final saved = await commit(
      (draft, at) {
        require(
          controlEpoch == pairing.epoch &&
              (remote
                  ? pairing.hosting && !pairing.localControl
                  : pairing.localControl),
          'Operator control changed. Review the action again.',
        );
        if (action == 'cue') validateLayout(value as TextLayout);
        if (action == 'message')
          validateLayout((value as StageOutputMessage).layout);
        draft.session = transition(
          draft.session,
          action,
          at,
          value: value,
          expectedRevision: revision,
        );
        // A message already covering every stage screen consumes an automatic
        // cue, as before. Targeted messages must not suppress other screens.
        if (action == 'warnings' && quickMessages.coversEveryStage) {
          draft.session.automaticCue = null;
        }
        if ([
          'start',
          'pause',
          'adjust',
          'advance',
          'jump',
          'clock',
          'message',
          'clearCue',
          'endScreen',
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
        if (action == 'load') {
          draft.session.churchName = draft.churchName;
          // A program handed over without its ID is matched by its name.
          final loaded = draft.session.timeline;
          final saved = loaded == null
              ? null
              : loaded.id.isNotEmpty
              ? draft.programById(loaded.id)
              : draft.templates.where((p) => p.name == loaded.name).firstOrNull;
          if (loaded != null && saved != null) {
            if (loaded.id.isEmpty)
              draft.session.timeline = loaded.withId(saved.id);
            draft.programLibrary.recent[saved.id] = at.wall;
          }
        }
        if ({
              'start',
              'advance',
              'jump',
              'clock',
              'message',
              'clearCue',
              'endScreen',
              'timer',
            }.contains(action) &&
            hardware.connected)
          draft.session.disconnected = false;
        if (action == 'end' && !draft.session.noReport) {
          draft.reports.add(ServiceReport.fromSession(draft.session, at));
        }
      },
      revision: revision,
      clearMessage: {
        'load',
        'start',
        'advance',
        'jump',
        'clock',
        'message',
        'clearCue',
        'endScreen',
        'undo',
        'cue',
        'timer',
        'blank',
        'cancelReady',
        'unstart',
      }.contains(action),
    );
    if (saved &&
        {
          'load',
          'start',
          'advance',
          'jump',
          'clock',
          'message',
          'clearCue',
          'endScreen',
          'cue',
          'timer',
          'blank',
          'cancelReady',
          'unstart',
        }.contains(action)) {
      quickMessages.reset();
      unawaited(pairing.publish());
    }
    if (saved &&
        {
          'advance',
          'jump',
          'clock',
          'message',
          'clearCue',
          'endScreen',
          'timer',
          'blank',
        }.contains(action) &&
        hardware.connected) {
      hardware.release(state.session, timingVerified: true);
      await syncActiveService();
      _publish();
    }
    if (saved) await practice.observe(action, value);
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

  /// Backups; these delegates keep callers unchanged.
  late final backups = BackupController(this);
  Future<bool> restoreBackup(AppState restored) => backups.restore(restored);
  Future<Map<String, dynamic>> backupSecrets() => backups.secrets();
  bool hasBackupSecrets(Map<String, dynamic> secrets) =>
      backups.hasSecrets(secrets);
  Future<int> restoreBackupSecrets(Map<String, dynamic> secrets) =>
      backups.restoreSecrets(secrets);

  /// Clears a shown error that has nothing to retry (the card's Dismiss).
  void dismissError() {
    if (error == null || retry != null || corrupt) return;
    error = null;
    notifyListeners();
  }

  /// Releases a held display so the scheduled pre-service output shows.
  Future<bool> showPreService() async {
    if (state.session.phase != 'ready' || state.session.startsAtWall == null)
      return false;
    if (state.session.held && !await act('release')) return false;
    if (hardware.connected) {
      hardware.release(state.session);
      hardware.reconcile(state.session, now);
    }
    _publish();
    notifyListeners();
    return true;
  }

  Future<void> reloadFonts() async {
    corrupt = false;
    error = null;
    await initialize(startTicker: false);
  }

  // Settings PIN; these delegates keep callers unchanged.
  late final settingsPin = SettingsPinController(this);
  bool get settingsLocked => settingsPin.locked;
  DateTime? get pinRetryAfter => settingsPin.retryAfter;
  void lockSettings() => settingsPin.lock();
  Future<bool> unlockSettings(String pin) => settingsPin.unlock(pin);
  Future<String?> setSettingsPin(String pin) => settingsPin.setPin(pin);
  Future<bool> removeSettingsPin() => settingsPin.removePin();
  Future<bool> recoverSettings(String code) => settingsPin.recover(code);

  Future<void> syncPhoneWarnings({Session? previous}) =>
      phoneWarnings.sync(previous: previous);
  Future<void> enablePhoneWarnings() => phoneWarnings.enable();

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

  /// Sets or, with empty text, removes a report's review note. Recorded
  /// timings are never changed.
  Future<bool> setReviewNote(String reportId, String text) =>
      commit((draft, at) => draft.setReviewNote(reportId, text, at.wall));

  /// Deletes the named saved programs atomically; null when nothing saved.
  Future<List<DeletedProgram>?> deletePrograms(Set<String> ids) async {
    List<DeletedProgram>? removed;
    final ok = await commit((draft, _) => removed = draft.deletePrograms(ids));
    return ok ? removed : null;
  }

  Future<bool> restorePrograms(List<DeletedProgram> removed) =>
      commit((draft, _) => draft.restorePrograms(removed));

  Future<List<DeletedReport>?> deleteReports(Set<String> ids) async {
    List<DeletedReport>? removed;
    final ok = await commit((draft, _) => removed = draft.deleteReports(ids));
    return ok ? removed : null;
  }

  Future<bool> restoreReports(List<DeletedReport> removed) =>
      commit((draft, _) => draft.restoreReports(removed));

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

  /// Web screens; these delegates keep callers unchanged.
  late final web = WebStageCoordinator(this);
  WebStageServer get webStage => web.server;
  MdnsResponder get mdns => web.mdns;
  void Function(String message)? get onWebJoined => web.onJoined;
  set onWebJoined(void Function(String message)? f) => web.onJoined = f;
  String? get webStageError => web.error;
  set webStageError(String? v) => web.error = v;
  String? get joinSlideAddress => web.joinSlideAddress;
  set joinSlideAddress(String? v) => web.joinSlideAddress = v;
  bool get localNameActive => web.localNameActive;
  WebStageSettings get webStageSettings => web.settings;
  String? get webStageUrl => web.url;
  String? get webStageLocalUrl => web.localUrl;
  Future<bool> setWebStageSettings(WebStageSettings next) =>
      web.setSettings(next);
  Json webStageSnapshot() => web.snapshot();

  late final metricsTracker = MetricsTracker(this);
  Future<bool> setRecordMetrics(bool on) => metricsTracker.setRecord(on);

  /// Loads and starts a 2-hour generated service that saves no report,
  /// with metrics recording on.
  Future<bool> startTestService() async {
    if (state.session.active || state.session.phase == 'ready') {
      error = 'End or cancel the current service before a test service.';
      notifyListeners();
      return false;
    }
    if (!await act('load', value: testServiceProgram())) return false;
    if (!await commit((draft, _) {
      draft.session.noReport = true;
      draft.recordMetrics = true;
    }))
      return false;
    return act('start');
  }

  Future<void> suspend() async {
    unawaited(metrics.event(now, 'background'));
    await flushEditDrafts();
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
    unawaited(refreshBatteryStatus());
    if (metrics.recording)
      unawaited(port.clock().then((at) => metrics.event(at, 'foreground')));
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
    metricsTracker.frameTimings(false);
    web.stop();
    editDrafts.dispose();
    liveClock.dispose();
    previewClock.dispose();
    _disposed = true;
    pairing.dispose();
    port.setBackgroundHandler(null);
    port.setNotificationActionHandler(null);
    unawaited(port.setActiveService(false));
    _timer?.cancel();
    hardware.removeListener(_hardwareChanged);
    hardware.dispose();
    appearancePreview.dispose();
    liveNavigation.dispose();
    super.dispose();
  }
}
