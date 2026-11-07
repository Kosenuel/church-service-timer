import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';

/// Quick messages for phone and tablet stage screens: the current message,
/// its recipients and Seen acknowledgements, the short test preview and
/// saved presets. Owned by [AppController], which forwards its public API.
class QuickMessageController {
  final AppController app;
  QuickMessageController(this.app);

  QuickMessage? _message;
  String? messageId;
  final Set<String> _recipients = {}, seen = {};
  final Map<String, String> recipientNames = {};
  int? _until;
  String? _session;
  int? _segment;
  QuickMessage? _testMessage;
  int _testUntil = 0;

  Set<String> get recipients => Set.unmodifiable(_recipients);

  /// The monotonic deadline of a timed message, for its return countdown.
  int? get untilMono => current == null ? null : _until;

  QuickMessage? get current {
    final s = app.state.session;
    return _message != null &&
            app.stageConnected &&
            (s.active || s.phase == 'ended') &&
            s.id == _session &&
            s.index == _segment &&
            (_until == null || app.now.mono < _until!)
        ? _message
        : null;
  }

  /// What stage screens should show: a live test preview, else the message.
  QuickMessage? get forStage =>
      _testMessage != null && app.stageConnected && app.now.mono < _testUntil
      ? _testMessage
      : current;

  /// Whether every synced stage screen receives the current message.
  bool get coversEveryStage =>
      current != null &&
      app.pairing.syncedStagePeers.every((p) => _recipients.contains(p.id));

  Json decorateSnapshot(PairPeer peer, Json data) {
    final profile = app.pairing.savedDevices
        .where((d) => d.id == peer.id)
        .firstOrNull;
    data['stageLayout'] = profile?.layout ?? 'timer';
    if (!peer.viewingStage || !_recipients.contains(peer.id)) {
      data.remove('quickMessage');
      data['blank'] = app.state.session.outputBlank;
    } else if (data['quickMessage'] != null) {
      data['messageId'] = messageId;
      data['messageSeen'] = seen.contains(peer.id);
    }
    return data;
  }

  void receiveSeen(PairPeer peer, String id) {
    if (!peer.connected ||
        !peer.viewingStage ||
        current?.requestSeen != true ||
        id != messageId ||
        !_recipients.contains(peer.id) ||
        peer.acknowledgedSnapshot?['messageId'] != id ||
        !app.pairing.syncedStagePeers.contains(peer))
      return;
    if (seen.add(peer.id)) {
      unawaited(app.pairing.publish());
      app.notifyChanged();
    }
  }

  void clear() {
    _message = null;
    messageId = null;
    _recipients.clear();
    seen.clear();
    recipientNames.clear();
    _until = null;
    _session = null;
    _segment = null;
  }

  /// Clears the message and any test preview.
  void reset() {
    clear();
    _testMessage = null;
  }

  /// Drops recipients that are no longer synced stage screens.
  void keepRecipients(Set<String> available) =>
      _recipients.removeWhere((id) => !available.contains(id));

  /// Expires a timed message or test preview whose time has passed.
  void expire() {
    if (_message != null && current == null) clear();
    if (_testMessage != null &&
        (!app.stageConnected || app.now.mono >= _testUntil))
      _testMessage = null;
  }

  Future<bool> send(
    QuickMessage message, {
    bool test = false,
    String? confirmedEndedSession,
    Set<String>? recipientIds,
  }) async {
    final state = app.state, pairing = app.pairing;
    final ended = state.session.phase == 'ended';
    if (app.busy ||
        app.corrupt ||
        app.reportSavePending ||
        !pairing.localControl ||
        !app.stageConnected ||
        (!test &&
            !state.session.active &&
            !(ended && confirmedEndedSession == state.session.id))) {
      app.error =
          'Connect an approved stage screen. After a service ends, confirm before sending.';
      app.notifyChanged();
      return false;
    }
    final eligible = {for (final s in app.stageScreens) s.id};
    final chosen = Set<String>.from(recipientIds ?? eligible);
    final sessionId = state.session.id,
        segmentIndex = state.session.index,
        epoch = pairing.epoch;
    try {
      require(
        chosen.isNotEmpty && eligible.containsAll(chosen),
        'Selected screens are unavailable. Review the recipients.',
      );
      message.validate();
    } catch (e) {
      app.error = '$e';
      app.notifyChanged();
      return false;
    }
    if (!test &&
        !ended &&
        !await app.commit((draft, at) {
          require(
            app.stageConnected && pairing.localControl,
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
    final latest = app.state.session;
    if (latest.id != sessionId ||
        latest.index != segmentIndex ||
        pairing.epoch != epoch ||
        !pairing.localControl ||
        !{for (final s in app.stageScreens) s.id}.containsAll(chosen)) {
      app.error =
          'Service, control or selected screens changed. Review the message again.';
      app.notifyChanged();
      return false;
    }
    clear();
    _recipients.addAll(chosen);
    recipientNames.addAll({
      for (final s in app.stageScreens.where((s) => chosen.contains(s.id)))
        s.id: s.name,
    });
    messageId = pairRandom(16);
    if (test) {
      _testMessage = message;
      _testUntil = app.now.mono + 5000;
    } else {
      _testMessage = null;
      _message = message;
      _session = app.state.session.id;
      _segment = app.state.session.index;
      _until = message.seconds == 0
          ? null
          : app.now.mono + message.seconds * 1000;
    }
    app.error = null;
    await pairing.publish();
    app.notifyChanged();
    return true;
  }

  Future<void> dismiss() async {
    if (!app.pairing.localControl || app.busy || app.reportSavePending) return;
    clear();
    await app.pairing.publish();
    app.notifyChanged();
  }

  Future<bool> savePreset(QuickMessage message, {int? index}) =>
      app.commit((draft, _) {
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
}
