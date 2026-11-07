import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';

/// The fixed requests a presenter can send. No free text reaches the
/// operator, so nothing unexpected can appear on the host phone.
const stageRequestKinds = {
  'time': 'Need 2 minutes',
  'finish': 'Ready to finish',
  'mic': 'Microphone issue',
};

class StageRequest {
  final String id, kind, screenId, screenName;
  final int atMono, atWall;

  /// 'sent' until the operator answers: 'seen', 'added' or 'dismissed'.
  String state;
  StageRequest(
    this.id,
    this.kind,
    this.screenId,
    this.screenName,
    this.atMono,
    this.atWall, {
    this.state = 'sent',
  });
  String get label => stageRequestKinds[kind]!;
  bool get open => state == 'sent';
}

/// Requests from approved stage screens to the operator, one per screen.
/// Answering never changes the timing; only "Add 2 min" does, through the
/// normal time adjustment with Undo.
class StageRequestController {
  final AppController app;
  StageRequestController(this.app);

  static const expireMs = 120000, gapMs = 5000;

  /// Newest last; one entry per screen.
  final requests = <StageRequest>[];
  final _lastFrom = <String, int>{};

  /// Called for each new request, so the UI can vibrate.
  void Function(StageRequest request)? onRequest;

  bool get enabled => app.state.stageRequests;
  List<StageRequest> get open => [
    for (final r in requests.reversed)
      if (r.open) r,
  ];

  /// What a screen should show for its own request, or null.
  Json? statusFor(String screenId) {
    final r = requests.where((r) => r.screenId == screenId).lastOrNull;
    if (r == null) return null;
    return {'id': r.id, 'kind': r.kind, 'label': r.label, 'state': r.state};
  }

  /// A request arrived from [screenId]. Returns false when it is not
  /// accepted: requests are off, no service is running, the kind is
  /// unknown, or the screen sent one less than 5 seconds ago.
  bool receive(String screenId, String screenName, String kind) {
    final now = app.now;
    if (!enabled ||
        !app.ready ||
        !app.state.session.active ||
        !stageRequestKinds.containsKey(kind))
      return false;
    final last = _lastFrom[screenId];
    if (last != null && now.mono - last < gapMs) return false;
    _lastFrom[screenId] = now.mono;
    requests.removeWhere((r) => r.screenId == screenId);
    final request = StageRequest(
      pairRandom(12),
      kind,
      screenId,
      screenName,
      now.mono,
      now.wall,
    );
    requests.add(request);
    unawaited(_log('Stage request · ${request.label} · $screenName'));
    onRequest?.call(request);
    _publish();
    return true;
  }

  Future<void> acknowledge(String id) => _answer(id, 'seen');
  Future<void> dismiss(String id) => _answer(id, 'dismissed');

  /// Adds two minutes to the current segment for a "Need 2 minutes"
  /// request, using the normal adjustment (with Undo).
  Future<bool> addTime(String id) async {
    final r = requests.where((r) => r.id == id && r.open).firstOrNull;
    if (r == null || r.kind != 'time') return false;
    if (!await app.act('adjust', value: 120)) return false;
    await _answer(id, 'added');
    return true;
  }

  Future<void> _answer(String id, String state) async {
    final r = requests.where((r) => r.id == id && r.open).firstOrNull;
    if (r == null) return;
    r.state = state;
    await _log(
      'Stage request · ${r.label} · ${switch (state) {
        'added' => '2 minutes added',
        'seen' => 'acknowledged',
        _ => 'dismissed',
      }}',
    );
    _publish();
  }

  /// Drops requests older than two minutes and all of them when no
  /// service is running. Returns whether anything changed.
  bool prune() {
    final before = requests.length;
    if (!app.ready || !app.state.session.active || !enabled) {
      requests.clear();
    } else {
      requests.removeWhere((r) => app.now.mono - r.atMono > expireMs);
    }
    if (requests.length == before) return false;
    _publish();
    return true;
  }

  void clear() {
    if (requests.isEmpty) return;
    requests.clear();
    _publish();
  }

  Future<void> _log(String message) async {
    if (!app.ready || !app.state.session.active) return;
    await app.commit((draft, at) {
      addServiceEvent(
        draft.session.events,
        ServiceEvent(at.wall, 'request', message),
      );
    });
  }

  void _publish() {
    unawaited(app.pairing.publish());
    app.notifyChanged();
  }
}
