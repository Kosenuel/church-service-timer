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
import 'w2_program.dart';
import 'pairing.dart';

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
    pixels = s.outputMode(now) == 'Clock'
        ? W2Program.clockPixels(
            DateTime.fromMillisecondsSinceEpoch(now.wall),
            format12Hour: s.clockFormat == '12h',
          )
        : renderPixels(delivered, now.mono - deliveredAt);
  }
}

class AppController extends ChangeNotifier {
  final Map<String, Json?> _draftWrites = {};
  Timer? _draftTimer;
  String? draftError;
  void queueEditDraft(String key, Json? value) {
    _draftWrites[key] = value;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), flushEditDrafts);
  }

  Future<void>? _draftFlush;
  Future<void> flushEditDrafts() {
    _draftTimer?.cancel();
    return _draftFlush ??= _flushDrafts().whenComplete(
      () => _draftFlush = null,
    );
  }

  Future<void> _flushDrafts() async {
    while (_draftWrites.isNotEmpty && !_disposed && ready) {
      if (busy) await _writeDone?.future;
      if (_disposed) return;
      if (reportSavePending) {
        _draftTimer = Timer(const Duration(milliseconds: 600), flushEditDrafts);
        return;
      }
      final pending = Map<String, Json?>.from(_draftWrites);
      final ok = await commit((draft, _) {
        for (final entry in pending.entries) {
          if (entry.value == null) {
            draft.editDrafts.remove(entry.key);
          } else {
            draft.editDrafts[entry.key] = entry.value!;
          }
        }
        readEditDrafts(draft.editDrafts);
      });
      if (!ok) {
        draftError =
            'Draft could not be saved. Keep this screen open and retry.';
        if (!_disposed) notifyListeners();
        return;
      }
      for (final entry in pending.entries) {
        if (identical(_draftWrites[entry.key], entry.value))
          _draftWrites.remove(entry.key);
      }
      draftError = null;
      if (!_disposed) notifyListeners();
    }
  }

  Session? _pendingEnd;
  int? _pendingEndRevision;
  bool _preparingEnd = false;
  bool get reportSavePending => _pendingEnd != null;
  Session get liveSession => _pendingEnd ?? state.session;
  String get destination =>
      state.outputDestination ?? (hardware.enabled ? 'led' : 'simulator');
  bool get stageConnected =>
      destination == 'mobile' &&
      pairing.hosting &&
      pairing.syncedStagePeers.isNotEmpty;
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
  QuickMessage? _quickMessage;
  String? quickMessageId;
  final Set<String> _quickRecipients = {}, quickSeen = {};
  final Map<String, String> quickRecipientNames = {};
  Set<String> get quickRecipients => Set.unmodifiable(_quickRecipients);

  Json decoratePairedSnapshot(PairPeer peer, Json data) {
    final profile = pairing.savedDevices
        .where((d) => d.id == peer.id)
        .firstOrNull;
    data['stageLayout'] = profile?.layout ?? 'timer';
    if (!peer.viewingStage || !_quickRecipients.contains(peer.id)) {
      data.remove('quickMessage');
      data['blank'] = state.session.outputBlank;
    } else if (data['quickMessage'] != null) {
      data['messageId'] = quickMessageId;
      data['messageSeen'] = quickSeen.contains(peer.id);
    }
    return data;
  }

  void receiveMessageSeen(PairPeer peer, String id) {
    if (!peer.connected ||
        !peer.viewingStage ||
        currentQuickMessage?.requestSeen != true ||
        id != quickMessageId ||
        !_quickRecipients.contains(peer.id) ||
        peer.acknowledgedSnapshot?['messageId'] != id ||
        !pairing.syncedStagePeers.contains(peer))
      return;
    if (quickSeen.add(peer.id)) {
      unawaited(pairing.publish());
      notifyListeners();
    }
  }

  int? _quickUntil;
  String? _quickSession;
  int? _quickSegment;
  QuickMessage? get currentQuickMessage =>
      _quickMessage != null &&
          stageConnected &&
          (state.session.active || state.session.phase == 'ended') &&
          state.session.id == _quickSession &&
          state.session.index == _quickSegment &&
          (_quickUntil == null || now.mono < _quickUntil!)
      ? _quickMessage
      : null;
  void clearQuickMessage() {
    _quickMessage = null;
    quickMessageId = null;
    _quickRecipients.clear();
    quickSeen.clear();
    quickRecipientNames.clear();
    _quickUntil = null;
    _quickSession = null;
    _quickSegment = null;
  }

  Future<bool> sendQuickMessage(
    QuickMessage message, {
    bool test = false,
    String? confirmedEndedSession,
    Set<String>? recipientIds,
  }) async {
    final ended = state.session.phase == 'ended';
    if (busy ||
        corrupt ||
        reportSavePending ||
        !pairing.localControl ||
        !stageConnected ||
        (!test &&
            !state.session.active &&
            !(ended && confirmedEndedSession == state.session.id))) {
      error =
          'Connect an approved stage screen. After a service ends, confirm before sending.';
      notifyListeners();
      return false;
    }
    final eligible = pairing.syncedStagePeers.map((p) => p.id).toSet();
    final recipients = Set<String>.from(recipientIds ?? eligible);
    final sessionId = state.session.id,
        segmentIndex = state.session.index,
        epoch = pairing.epoch;
    try {
      require(
        recipients.isNotEmpty && eligible.containsAll(recipients),
        'Selected screens are unavailable. Review the recipients.',
      );
      message.validate();
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    }
    if (!test &&
        !ended &&
        !await commit((draft, at) {
          require(
            stageConnected && pairing.localControl,
            'Stage screen disconnected or control changed.',
          );
          draft.session.revision++;
          addServiceEvent(
            draft.session.events,
            ServiceEvent(
              at.wall,
              'message',
              'Quick message sent to stage screen',
            ),
          );
        }))
      return false;
    if (state.session.id != sessionId ||
        state.session.index != segmentIndex ||
        pairing.epoch != epoch ||
        !pairing.localControl ||
        !pairing.syncedStagePeers
            .map((p) => p.id)
            .toSet()
            .containsAll(recipients)) {
      error =
          'Service, control or selected screens changed. Review the message again.';
      notifyListeners();
      return false;
    }
    clearQuickMessage();
    _quickRecipients.addAll(recipients);
    quickRecipientNames.addAll({
      for (final peer in pairing.syncedStagePeers.where(
        (p) => recipients.contains(p.id),
      ))
        peer.id: peer.name,
    });
    quickMessageId = pairRandom(16);
    if (test) {
      _testMessage = message;
      _testUntil = now.mono + 5000;
    } else {
      _testMessage = null;
      _quickMessage = message;
      _quickSession = state.session.id;
      _quickSegment = state.session.index;
      _quickUntil = message.seconds == 0
          ? null
          : now.mono + message.seconds * 1000;
    }
    error = null;
    await pairing.publish();
    notifyListeners();
    return true;
  }

  Future<void> dismissQuickMessage() async {
    if (!pairing.localControl || busy || reportSavePending) return;
    clearQuickMessage();
    await pairing.publish();
    notifyListeners();
  }

  QuickMessage? _testMessage;
  int _testUntil = 0;
  Future<bool> saveQuickPreset(QuickMessage message, {int? index}) =>
      commit((draft, _) {
        message.validate();
        if (index == null) {
          require(draft.quickMessages.length < 50, 'Keep at most 50 presets.');
          draft.quickMessages.add(message);
        } else {
          require(
            index >= 0 && index < draft.quickMessages.length,
            'This preset changed.',
          );
          draft.quickMessages[index] = message;
        }
      });
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
    clearQuickMessage();
    _testMessage = null;
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

  Future<bool> stopStageSharing() async {
    clearQuickMessage();
    _testMessage = null;
    pairing.setStageSharing(false);
    await pairing.publish();
    return true;
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

  Json pairedSnapshot(bool privateNotes) {
    if (!ready) return {};
    final s = state.session, t = state.session.timeline;
    final display = s.intended(now);
    final quick =
        _testMessage != null && stageConnected && now.mono < _testUntil
        ? _testMessage
        : currentQuickMessage;
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

  Future<void> syncDeviceSettings() async {
    themeSelection.value = _previewTheme ?? state.themeId;
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

  Json notificationState = {'enabled': false, 'exact': false, 'sound': false};
  Future<bool> Function()? retry;
  Timer? _timer;
  AppController(this.port) {
    pairing.readMemory = port.loadPairing;
    pairing.writeMemory = port.savePairing;
    pairing.discoverHosts = port.discoverPairHosts;
    pairing.currentAddress = port.localNetworkAddress;
    pairing.advertise = (portNumber) =>
        port.advertisePairHost(portNumber, hostId: pairing.hostId);
    pairing.unadvertise = port.stopPairAdvertisement;
    pairing.addListener(() {
      if (ready) {
        final available = pairing.syncedStagePeers.map((p) => p.id).toSet();
        _quickRecipients.removeWhere((id) => !available.contains(id));
      }
      if (ready && !stageConnected) {
        clearQuickMessage();
        _testMessage = null;
      }
      if (!_disposed) notifyListeners();
    });
    pairing.snapshotFor = pairedSnapshot;
    pairing.decorateSnapshot = decoratePairedSnapshot;
    pairing.onMessageSeen = receiveMessageSeen;
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
    pairing.command = (action, value, revision) async {
      if (!{
            'pause',
            'adjust',
            'advance',
            'jump',
            'clock',
            'clearCue',
            'endScreen',
            'cue',
            'timer',
            'blank',
            'end',
          }.contains(action) ||
          busy) {
        error = busy
            ? 'Host is saving another action. Try again.'
            : 'This action is unavailable.';
        return false;
      }
      if (action == 'adjust' && (value is! int || value.abs() > 3600))
        return false;
      if (action == 'cue') {
        if (value is Map) {
          if (value['session'] != state.session.id ||
              value['segment'] != state.session.index) {
            error =
                'The service or segment changed. Review the current service.';
            return false;
          }
          final i = value['index'];
          if (i is! int ||
              i < 0 ||
              i >= state.stageCues.length ||
              value['version'] != jsonEncode(state.stageCues[i].toJson())) {
            error = 'This prepared cue changed. Select its updated button.';
            return false;
          }
          value = i;
          revision = state.session.revision;
        }
        if (value is! int || value < 0 || value >= state.stageCues.length)
          return false;
        value = state.stageCues[value];
      }
      return await act(action, value: value, revision: revision, remote: true);
    };
    pairing.commandMessage = (ok, action) => !ok
        ? (error ?? 'Action unavailable. Review the host service.')
        : action == 'cue' &&
              hardware.enabled &&
              (!hardware.connected || hardware.held || hardware.interrupted)
        ? 'Cue applied to the service and paired screens · LED sign unavailable or held'
        : 'Command applied';
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
            : pairing.stagePeers.isNotEmpty
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
      if (!corrupt && !reportSavePending) {
        if (_quickMessage != null && currentQuickMessage == null)
          clearQuickMessage();
        if (_testMessage != null && (!stageConnected || now.mono >= _testUntil))
          _testMessage = null;
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
      if (clearMessage) {
        clearQuickMessage();
        _testMessage = null;
      }
      if (ending) {
        _pendingEnd = null;
        _pendingEndRevision = null;
        clearQuickMessage();
        _testMessage = null;
      }
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
    if (action == 'end') return _finishService(revision: revision);
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
        if (action == 'warnings' &&
            currentQuickMessage != null &&
            pairing.syncedStagePeers.every(
              (peer) => _quickRecipients.contains(peer.id),
            )) {
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
        if (action == 'load') draft.session.churchName = draft.churchName;
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
        if (action == 'end') {
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
        }.contains(action)) {
      clearQuickMessage();
      _testMessage = null;
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
      draft.quickMessages = restored.quickMessages;
      draft.clockFormat = restored.clockFormat;
      draft.pixelShape = restored.pixelShape;
      draft.groupTemplates = restored.groupTemplates;
      draft.churchName = restored.churchName;
      draft.churchBanner = restored.churchBanner;
      draft.themeId = restored.themeId;
      draft.keepScreenAwake = restored.keepScreenAwake;
      draft.notificationClearSeconds = restored.notificationClearSeconds;
      draft.printPreferences = restored.printPreferences;
      draft.editDrafts.clear();
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
        warningNotificationPlan(
          s,
          now,
          newlySeen: newlySeen,
          clearSeconds: state.notificationClearSeconds,
        ),
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
    _draftTimer?.cancel();
    liveClock.dispose();
    previewClock.dispose();
    _disposed = true;
    pairing.dispose();
    port.setBackgroundHandler(null);
    unawaited(port.setActiveService(false));
    _timer?.cancel();
    hardware.removeListener(_hardwareChanged);
    hardware.dispose();
    themeSelection.dispose();
    super.dispose();
  }
}
