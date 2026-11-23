import 'dart:async';

import 'package:flutter/services.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/format_labels.dart';
import 'package:church_service_timer/web_stage/mdns_responder.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';

/// Web screens: the browser server and the .local name, started and
/// stopped with sharing, and moved to a new address when the network
/// changes.
class WebStageCoordinator {
  final AppController app;
  WebStageCoordinator(this.app);

  /// Browsers following the service: started and stopped with sharing.
  late final server =
      WebStageServer(settings: () => settings, snapshot: snapshot)
        ..onChanged = app.notifyChanged
        // A web display shows a quick message only if it was a recipient.
        ..showsMessage = ((d) =>
            app.quickMessages.recipients.contains('web:${d.token}'))
        ..onJoined = ((d) =>
            onJoined?.call('${d.label} joined · ${d.role.label}'))
        // Team Stage displays may send requests while they are on.
        ..requestsOpen = (() =>
            app.stageRequests.enabled && app.state.session.active)
        ..onRequest = ((d, kind) => app.stageRequests.receive(
          'web:${d.token}',
          '${d.label} (web)',
          kind,
        ))
        ..requestFor = ((d) => app.stageRequests.statusFor('web:${d.token}'))
        // Each Stage display shows what its group shows.
        ..stageFor = ((d, s) =>
            app.screens.decorate(Map.of(s), 'web:${d.token}', LyricTarget.web))
        ..groupFor = ((d) {
          final g = app.screens.groupOf('web:${d.token}');
          return (id: g.id, name: g.name);
        })
        ..lyricImage = _lyricImage;

  /// A bundled photo by id, or Your picture when its name is the one in
  /// use, for web screens showing a slide.
  Future<Uint8List?> _lyricImage(String kind, String id) async {
    if (kind == 'photo') {
      final photo = lyricPhotoById(id);
      if (photo == null) return null;
      try {
        return (await rootBundle.load(photo.asset)).buffer.asUint8List();
      } catch (_) {
        return null;
      }
    }
    return app.lyrics.look.background == 'custom:$id'
        ? app.lyrics.pictureBytes
        : null;
  }

  final mdns = MdnsResponder();

  /// Shown by the home screen as a short note when a team browser joins.
  void Function(String message)? onJoined;

  /// Why web screens are not available, shown in their panel only.
  String? error;

  /// The address on the last exported join slide, to spot a stale slide.
  String? joinSlideAddress;

  /// Whether the easy .local name is being answered on this Wi-Fi.
  bool localNameActive = false;

  bool _rehosting = false, _syncing = false;
  int _lastAddressCheck = 0, _synced = 0;

  WebStageSettings get settings => WebStageSettings.fromJson(
    app.state.webStage,
    churchName: app.state.churchName,
  );

  /// The address browsers open, e.g. `http://192.168.1.23:8080`.
  String? get url =>
      server.running ? 'http://${server.address}:${server.port}' : null;
  String? get localUrl => localNameActive
      ? 'http://${settings.localName}.local:${server.port}'
      : null;

  /// While sharing, a change of network (another Wi-Fi, the hotspot turned
  /// on or off) gives this device a new address and leaves the old one
  /// advertised but dead. Share again on the new address, keeping approved
  /// devices, the team code and joined browsers.
  Future<void> followNetworkChange() async {
    final pairing = app.pairing;
    if (!pairing.hosting ||
        _rehosting ||
        app.now.mono - _lastAddressCheck < 10000)
      return;
    _lastAddressCheck = app.now.mono;
    final old = pairing.code?.address;
    String next;
    try {
      next = await app.port.localNetworkAddress();
    } catch (_) {
      return;
    }
    if (old == null || next == old || !localPairAddress(next)) return;
    if (next == '127.0.0.1') return;
    _rehosting = true;
    try {
      await pairing.host(next);
      // The listener restarts web screens; wait for them to move over.
      await sync();
      onJoined?.call('Network changed · sharing again at $next');
    } catch (_) {
      error = 'The network changed and sharing could not restart.';
    } finally {
      _rehosting = false;
      app.notifyChanged();
    }
  }

  /// A web display that stops fetching drops out like a paired screen.
  void checkSynced() {
    final synced = server.syncedStageDevices.length;
    if (synced == _synced) return;
    _synced = synced;
    app.notifyChanged();
  }

  /// Starts, moves or stops the server to match sharing.
  Future<void> sync() async {
    if (_syncing || app.disposed) return;
    _syncing = true;
    try {
      final address = app.pairing.hosting ? app.pairing.code?.address : null;
      if (address == null) {
        // Sharing pauses for a moment while it moves to a new network;
        // keep the web page and its browsers through that.
        if (_rehosting) return;
        if (server.running) {
          await server.stop();
          await mdns.stop();
          localNameActive = false;
          unawaited(app.port.setMulticastLock(false).catchError((_) {}));
          app.notifyChanged();
        }
        return;
      }
      if (server.running && server.address == address) return;
      final saved = settings;
      error = null;
      await server.start(address, keepSession: _rehosting);
      try {
        await app.port.setMulticastLock(true);
      } catch (_) {
        /* The name may still work; the QR and address always do. */
      }
      localNameActive = await mdns.start(saved.localName, address);
      app.notifyChanged();
    } catch (e) {
      // Paired phones and the service carry on; only the panel says so.
      error = 'Web screens could not start on this network.';
      app.notifyChanged();
    } finally {
      _syncing = false;
    }
  }

  Future<bool> setSettings(WebStageSettings next) async {
    final before = settings;
    if (!await app.commit((draft, _) => draft.webStage = next.toJson()))
      return false;
    if (next.orderCode.toLowerCase() != before.orderCode.toLowerCase())
      server.forgetOrderViewers();
    if (next.localName != before.localName && server.running) {
      localNameActive = await mdns.start(next.localName, server.address!);
    }
    app.notifyChanged();
    return true;
  }

  /// The paired-screen snapshot without private notes, plus timing for
  /// Service overview. Each Stage display adds what its group shows (see
  /// [ScreensController.decorate]).
  Json snapshot() {
    final base = app.pairedSnapshot(false);
    final s = app.state.session;
    final now = app.now;
    if (!app.ready || !s.active || s.timeline == null) return base;
    final projected = s.projectedTotal(now);
    final eta = now.wall + ((projected - s.totalElapsed(now)) / s.rate).round();
    return {
      ...base,
      'variance': varianceLabel(projected - s.plannedMs),
      'behind': projected > s.plannedMs + 999,
      'finish': clockLabel(eta),
    };
  }

  void stop() {
    unawaited(server.stop());
    unawaited(mdns.stop());
  }
}
