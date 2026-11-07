import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing_pin.dart';
import 'package:church_service_timer/shared/best_effort.dart';

// pairing_memory.dart stays a part: it extends PairHub and needs its
// private trust state (approvals, saved client, resume codes), which must
// not become public API.
part 'pairing_memory.dart';

Future<SecretKey> pairSessionKey(
  SecretKey shared,
  String invitationSecret,
  String challenge,
  String hostPublic,
  String clientPublic,
) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
  secretKey: shared,
  nonce: base64Url.decode(invitationSecret),
  info: utf8.encode(
    jsonEncode(['CST1 session', challenge, hostPublic, clientPublic]),
  ),
);

String pairRandom(int bytes) =>
    base64UrlEncode(List.generate(bytes, (_) => Random.secure().nextInt(256)));

void _observePairSocket(Socket socket) {
  // Socket sink failures also complete done with an error, independently of
  // the reader and individual writes. Close the transport so the normal
  // receive-loop cleanup can revoke control and schedule recovery.
  unawaited(
    socket.done.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) => socket.destroy(),
    ),
  );
}

bool localPairAddress(String host) {
  final a = InternetAddress.tryParse(host);
  if (a == null || a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

class PairCode {
  final String address, secret;
  final int port, expires;
  PairCode(this.address, this.port, this.secret, this.expires);
  String encode() =>
      'CST1:${base64UrlEncode(utf8.encode(jsonEncode({'a': address, 'p': port, 'k': secret, 'e': expires})))}';
  factory PairCode.parse(String value) {
    require(
      value.length < 1000 && value.startsWith('CST1:'),
      'Paste a Church Service Timer pairing code.',
    );
    final j =
        jsonDecode(utf8.decode(base64Url.decode(value.substring(5)))) as Map;
    require(
      j['a'] is String &&
          localPairAddress(j['a']) &&
          j['p'] is int &&
          j['p'] > 0 &&
          j['p'] <= 65535 &&
          j['e'] is int &&
          j['k'] is String,
      'Invalid pairing address.',
    );
    require(base64Url.decode(j['k']).length == 32, 'Invalid pairing key.');
    require(
      j['e'] > DateTime.now().millisecondsSinceEpoch,
      'This code expired. Generate a new code on the host.',
    );
    return PairCode(j['a'], j['p'], j['k'], j['e']);
  }
}

class PairWire {
  final Socket socket;
  SecretKey key;
  final String binding;
  final aes = AesGcm.with256bits();
  int sent = 0, received = 0;
  bool closed = false;
  Future<void> _out = Future.value();
  PairWire(this.socket, this.key, this.binding);
  Future<void> send(Json body) {
    _out = _out.then((_) async {
      if (closed) return;
      final bytes = utf8.encode(
        jsonEncode({'b': binding, 'q': ++sent, 'd': body}),
      );
      require(bytes.length <= 512000, 'Pairing message too large.');
      final encrypted = await aes.encrypt(bytes, secretKey: key);
      if (!closed) socket.write('${base64Encode(encrypted.concatenation())}\n');
    });
    return _out;
  }

  Future<Json> decode(String line) async {
    final encrypted = SecretBox.fromConcatenation(
      base64Decode(line),
      nonceLength: 12,
      macLength: 16,
    );
    final bytes = await aes.decrypt(encrypted, secretKey: key);
    final j = jsonDecode(utf8.decode(bytes)) as Map;
    require(
      j['b'] == binding &&
          j['q'] is int &&
          j['q'] == received + 1 &&
          j['d'] is Map,
      'Invalid or replayed pairing message.',
    );
    received = j['q'];
    return Map<String, dynamic>.from(j['d']);
  }

  void close() {
    closed = true;
    socket.destroy();
  }
}

Stream<String> pairLines(Socket socket) async* {
  var pending = <int>[];
  await for (final chunk in socket) {
    for (final byte in chunk) {
      if (byte == 10) {
        yield utf8.decode(pending);
        pending = [];
      } else {
        pending.add(byte);
        if (pending.length > 700000)
          throw RuleError('Pairing message too large.');
      }
    }
  }
}

class PairPeer {
  final String id, name, role;
  final PairWire wire;
  bool approved = false, requestedControl = false, suspended = false;
  bool get connected => approved && !suspended && !wire.closed;
  bool viewingStage;
  int lastAck = 0, lastAckId = 0;
  final Map<int, Json> pendingSnapshots = {};
  Json? acknowledgedSnapshot;
  int lastSeen = DateTime.now().millisecondsSinceEpoch;
  PairPeer(this.id, this.name, this.role, this.wire)
    : viewingStage = role == 'stage';
}

/// Local encrypted links. The host remains the single timer/output authority.
class PairHub extends ChangeNotifier {
  bool stageSharingEnabled = true;
  int _snapshotSequence = 0;
  List<PairPeer> get stagePeers =>
      peers.where((p) => p.connected && p.viewingStage).toList();
  List<PairPeer> get syncedStagePeers => stageSharingEnabled
      ? stagePeers
            .where(
              (p) =>
                  p.lastAck > 0 &&
                  DateTime.now().millisecondsSinceEpoch - p.lastAck < 3500,
            )
            .toList()
      : [];
  Future<void> acknowledgeMessage() async {
    final data = snapshot;
    require(
      mode == 'stage' &&
          !stale &&
          data != null &&
          data['stageSharing'] == true &&
          data['blank'] != true &&
          data['quickMessage'] is Map &&
          data['quickMessage']['requestSeen'] == true &&
          data['messageId'] is String,
      'This message is no longer available.',
    );
    await _client?.send({'type': 'seen', 'messageId': data!['messageId']});
  }

  void setStageSharing(bool enabled) {
    stageSharingEnabled = enabled;
    changed();
    unawaited(publish());
  }

  ServerSocket? _server;
  PairWire? _client;
  final peers = <PairPeer>[];

  /// Receives a program the host sent, already validated and without an ID.
  void Function(Timeline program, String from)? onProgramReceived;
  final changingDevices = <String>{};
  PairCode? code;
  String pin = '';
  PairPinInvitation? _pinInvitation;
  int pinAttempts = 0;
  bool get pinAvailable =>
      code != null &&
      pinAttempts < 5 &&
      code!.expires > DateTime.now().millisecondsSinceEpoch;
  Future<void> Function(int port)? advertise;
  Future<void> Function()? unadvertise;
  String discoveryNotice = '';
  Timer? _timer;
  bool _busy = false, _disposed = false;
  final _sockets = <Socket>{};
  String mode = 'off',
      status = 'Not paired',
      clientId = '',
      owner = '',
      requestResult = '';
  int epoch = 0, lastSnapshot = 0;
  Json? snapshot;
  Json Function(bool privateNotes)? snapshotFor;
  Json Function(PairPeer peer, Json data)? decorateSnapshot;
  void Function(PairPeer peer, String messageId)? onMessageSeen;

  /// A stage screen asked the operator for something (one of a fixed set).
  bool Function(PairPeer peer, String kind)? onStageRequest;
  Future<bool> Function(String action, dynamic value, int revision)? command;
  String Function(bool ok, String action)? commandMessage;
  final _approvals = <String, SavedPairDevice>{};
  Future<String?> Function()? readMemory;
  Future<void> Function(String)? writeMemory;
  Future<List<Json>> Function()? discoverHosts;
  Future<String> Function()? currentAddress;

  /// Rejoins the one Wi-Fi network remembered for this host (never others).
  Future<bool> Function()? rejoinWifi;
  Future<String> Function()? currentSsid;
  Future<void> Function()? cancelWifi;

  /// The network this phone joined the host on; empty when not remembered.
  String rejoinSsid = '';
  bool rejoiningWifi = false;
  String get remoteHostId => _remoteHostId;
  Future<void> _memoryWrites = Future.value();
  Future<void>? _restoringMemory;
  bool pausedByHost = false;
  String hostId = pairRandom(16), _remoteHostId = '', memoryNotice = '';
  int _savedPort = 0;
  Json? _savedClient;
  PairCode? _resumeCode;
  String? _resumeId, _sourceAddress;
  String _joinName = '', _joinRole = '';
  Timer? _retry;
  int _lifecycle = 0, _retryCount = 0;
  bool get reconnecting =>
      joined && !pausedByHost && _client == null && _resumeCode != null;

  /// Attempts since the host was lost, and when the loss began.
  int get reconnectAttempt => reconnecting ? _retryCount : 0;
  DateTime? reconnectingSince;

  void Function()? onOwnershipChanged;
  void Function(String message)? onControlChanged;
  bool get hosting => _server != null;

  /// Approved phones connected now that can review a program; stage
  /// screens cannot.
  List<PairPeer> get programRecipients => [
    for (final p in peers)
      if (p.connected && !p.viewingStage) p,
  ];

  /// Sends [program] (portable JSON, without this phone's ID) to the
  /// connected phones in [peerIds]. Returns how many it reached.
  Future<int> sendProgram(
    Json program,
    Set<String> peerIds,
    String from,
  ) async {
    require(hosting, 'Share to screens first, then send.');
    var sent = 0;
    for (final peer in programRecipients) {
      if (!peerIds.contains(peer.id)) continue;
      try {
        await peer.wire.send({
          'type': 'program',
          'program': program,
          'from': from,
        });
        sent++;
      } catch (_) {
        /* A dropped phone just misses this program. */
      }
    }
    return sent;
  }

  void _receiveProgram(Json msg) {
    try {
      final raw = msg['program'];
      if (raw is! Map || jsonEncode(raw).length > 300000) return;
      final program = Timeline.fromJson(
        Map<String, dynamic>.from(raw),
      ).withId('');
      final from = msg['from'] is String ? (msg['from'] as String).trim() : '';
      onProgramReceived?.call(
        program,
        from.isEmpty ? 'the host' : String.fromCharCodes(from.runes.take(60)),
      );
    } catch (_) {
      /* An invalid program is ignored, as a file import would refuse it. */
    }
  }

  bool get joined => mode == 'viewer' || mode == 'stage' || mode == 'operator';
  bool get stale =>
      lastSnapshot == 0 ||
      DateTime.now().millisecondsSinceEpoch - lastSnapshot > 3500;
  bool get canControl =>
      joined &&
      !pausedByHost &&
      mode == 'operator' &&
      !stale &&
      owner == clientId;
  bool get localControl => !hosting || owner.isEmpty;
  void showStage(bool stage) {
    if (!joined || mode == 'operator') return;
    mode = stage ? 'stage' : 'viewer';
    if (_savedClient != null) {
      _savedClient!['viewMode'] = mode;
      _saveMemoryQuietly();
    }
    unawaited(
      _client?.send({'type': 'viewMode', 'stage': stage}).catchError((_) {}) ??
          Future.value(),
    );
    onOwnershipChanged?.call();
    changed();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> host(String address) async {
    require(localPairAddress(address), 'Connect to a local Wi-Fi network.');
    await restoreMemory();
    await stop();
    try {
      _server = await ServerSocket.bind(address, _savedPort);
    } on SocketException {
      _server = await ServerSocket.bind(address, 0);
    }
    _savedPort = _server!.port;
    _saveMemoryQuietly();
    mode = 'host';
    status = 'Sharing this service';
    owner = '';
    epoch++;
    newCode();
    _server!.listen((s) {
      unawaited(_accept(s));
    });
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(publish()),
    );
    onOwnershipChanged?.call();
    changed();
    try {
      await advertise?.call(_server!.port);
    } catch (_) {
      discoveryNotice =
          'Nearby discovery is unavailable. Use the QR code instead.';
    }
    changed();
  }

  void newCode() {
    if (_server == null) return;
    pin = createPairPin();
    _pinInvitation = PairPinInvitation(pin);
    pinAttempts = 0;
    code = PairCode(
      _server!.address.address,
      _server!.port,
      pairRandom(32),
      DateTime.now().millisecondsSinceEpoch + 600000,
    );
    changed();
  }

  Future<void> _accept(Socket socket) async {
    _observePairSocket(socket);
    final lifecycle = _lifecycle;
    final invitation = code;
    final pinInvitation = _pinInvitation;
    if (invitation == null || _sockets.length >= 8) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    PairPeer? peer;
    try {
      final exchange = X25519();
      final kp = await exchange.newKeyPair();
      final public = await kp.extractPublicKey();
      final challenge = pairRandom(24);
      socket.write(
        '${jsonEncode({'challenge': challenge, 'public': base64Encode(public.bytes), 'salt': base64Encode(pinInvitation!.salt)})}\n',
      );
      final input = StreamIterator(pairLines(socket));
      require(
        await input.moveNext().timeout(const Duration(seconds: 8)),
        'Missing pairing hello.',
      );
      late final PairWire wire;
      late final Json hello;
      String? resumedId;
      var secret = invitation.secret;
      var first = input.current;
      if (first.startsWith('{')) {
        final request = jsonDecode(first) as Map;
        if (request['type'] == 'resume') {
          resumedId = request['id'] as String?;
          final approval = _approvals[resumedId];
          require(approval != null, 'Approval expired. Pair again.');
          secret = approval!.secret;
          require(
            await input.moveNext().timeout(const Duration(seconds: 8)),
            'Missing resume proof.',
          );
          first = input.current;
        }
      }
      if (first.startsWith('{')) {
        require(
          pinAvailable && identical(code, invitation),
          'Generate a new code.',
        );
        pinAttempts++;
        changed();
        final request = jsonDecode(first) as Map;
        require(request['type'] == 'pin', 'Invalid pairing method.');
        final a = pairNumber(request['a']);
        final srp = pinInvitation.server();
        final b = srp.generateServerCredentials()!;
        srp.calculateSecret(a);
        socket.write('${jsonEncode({'b': b.toRadixString(16)})}\n');
        require(
          await input.moveNext().timeout(const Duration(seconds: 12)),
          'Missing proof.',
        );
        final proof = jsonDecode(input.current) as Map;
        require(
          srp.verifyClientEvidenceMessage(
            pairNumber(proof['proof'], proof: true),
          ),
          'Incorrect pairing code.',
        );
        final m2 = srp.calculateServerEvidenceMessage()!;
        final key = await pinInvitation.sessionKey(srp, challenge);
        socket.write('${jsonEncode({'proof': m2.toRadixString(16)})}\n');
        wire = PairWire(socket, key, challenge);
        require(
          await input.moveNext().timeout(const Duration(seconds: 8)),
          'Missing hello.',
        );
        hello = await wire.decode(input.current);
      } else {
        final helloWire = PairWire(
          socket,
          SecretKey(base64Url.decode(secret)),
          challenge,
        );
        hello = await helloWire.decode(first);
        final shared = await exchange.sharedSecretKey(
          keyPair: kp,
          remotePublicKey: SimplePublicKey(
            base64Decode(hello['public']),
            type: KeyPairType.x25519,
          ),
        );
        final key = await pairSessionKey(
          shared,
          secret,
          challenge,
          base64Encode(public.bytes),
          hello['public'] as String,
        );
        wire = PairWire(socket, key, challenge);
      }
      require(
        (resumedId != null && _approvals[resumedId]?.secret == secret) ||
            (identical(code, invitation) &&
                invitation.expires > DateTime.now().millisecondsSinceEpoch),
        'This invitation expired or was replaced.',
      );
      require(
        hello['type'] == 'hello' &&
            ['viewer', 'stage', 'operator'].contains(hello['role']) &&
            hello['name'] is String &&
            (hello['name'] as String).length <= 60,
        'Invalid pairing hello.',
      );
      final approval = _approvals[resumedId];
      require(
        lifecycle == _lifecycle && hosting && !_disposed,
        'Sharing stopped.',
      );
      if (resumedId != null) {
        require(
          approval != null &&
              approval.name == hello['name'] &&
              approval.role == hello['role'],
          'Approval changed.',
        );
        for (final old in peers.where((p) => p.id == resumedId).toList()) {
          _drop(old);
        }
      }
      peer = PairPeer(
        resumedId ?? pairRandom(12),
        nameValue(hello['name'], 'Device name'),
        hello['role'],
        wire,
      );
      peer.approved = approval != null;
      peer.suspended = approval?.suspended ?? false;
      peers.add(peer);
      changed();
      await wire.send({'type': 'pending', 'id': peer.id});
      while (await input.moveNext().timeout(const Duration(seconds: 10))) {
        final message = await wire.decode(input.current);
        peer.lastSeen = DateTime.now().millisecondsSinceEpoch;
        if (message['type'] == 'leave') {
          if (peer.approved) await disconnectDevice(peer.id);
          break;
        }
        if (message['type'] == 'heartbeat') continue;
        if (!peer.approved) {
          await peer.wire.send({'type': 'pending', 'id': peer.id});
          continue;
        }
        if (peer.suspended) continue;
        if (message['type'] == 'viewMode' && peer.role != 'operator') {
          final stage = message['stage'] == true;
          if (peer.viewingStage != stage) {
            peer.viewingStage = stage;
            changed();
          }
          continue;
        }
        if (message['type'] == 'ack' && message['id'] is int) {
          final id = message['id'] as int;
          final accepted = peer.pendingSnapshots.remove(id);
          if (accepted != null && id > peer.lastAckId) {
            final wasStale =
                peer.lastAck == 0 ||
                DateTime.now().millisecondsSinceEpoch - peer.lastAck >= 3500;
            peer.lastAckId = id;
            peer.lastAck = DateTime.now().millisecondsSinceEpoch;
            peer.acknowledgedSnapshot = accepted;
            peer.pendingSnapshots.removeWhere((key, _) => key < id);
            if (wasStale) changed();
          }
          continue;
        }
        if (message['type'] == 'seen' &&
            peer.viewingStage &&
            message['messageId'] is String) {
          onMessageSeen?.call(peer, message['messageId']);
          continue;
        }
        if (message['type'] == 'stageRequest' &&
            peer.role != 'operator' &&
            peer.viewingStage &&
            message['kind'] is String) {
          onStageRequest?.call(peer, message['kind'] as String);
          continue;
        }
        if (message['type'] == 'requestControl' && peer.role == 'operator') {
          peer.requestedControl = true;
          changed();
          continue;
        }
        if (message['type'] == 'command') {
          final permitted =
              peer.id == owner &&
              message['epoch'] == epoch &&
              message['revision'] is int &&
              command != null;
          var ok = false;
          if (permitted) {
            try {
              ok = await command!(
                message['action'] as String,
                message['value'],
                message['revision'],
              );
            } catch (_) {
              ok = false;
            }
          }
          await wire.send({
            'type': 'result',
            'ok': ok,
            'message': permitted
                ? commandMessage?.call(ok, message['action'] as String) ??
                      (ok
                          ? 'Command applied'
                          : 'Action unavailable. Review the host service.')
                : 'Control changed. Request control from the host.',
          });
          await publish();
        }
      }
    } catch (_) {
      /* Invalid/unavailable peers lose their lease. No secrets logged. */
    } finally {
      _sockets.remove(socket);
      socket.destroy();
      if (peer != null) {
        peer.wire.close();
        peers.remove(peer);
        final saved = _approvals[peer.id];
        if (saved != null) {
          saved.lastSeen = peer.lastSeen;
          _saveMemoryQuietly();
        }
        if (owner == peer.id && !peers.any((p) => p.id == peer!.id)) {
          owner = '';
          epoch++;
          onControlChanged?.call(
            'Control returned to host after operator disconnected',
          );
          onOwnershipChanged?.call();
        }
      }
      changed();
    }
  }

  Future<void> approve(PairPeer peer) async {
    if (!peers.contains(peer) || peer.wire.closed) return;
    if (peer.approved) return;
    require(
      _approvals.length < 32,
      'Forget an unused device before pairing another.',
    );
    _approvals[peer.id] = SavedPairDevice(
      peer.id,
      peer.name,
      peer.role,
      pairRandom(32),
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await _saveMemory();
    } catch (_) {
      _approvals.remove(peer.id);
      rethrow;
    }
    if (!peers.contains(peer) || peer.wire.closed) return;
    peer.approved = true;
    changed();
    unawaited(publish());
  }

  void remove(PairPeer peer) {
    unawaited(
      forgetDevice(peer.id).catchError((_) {
        memoryNotice = 'Could not forget this device. Try again.';
        changed();
      }),
    );
  }

  void _drop(PairPeer peer) {
    peer.wire.close();
    peers.remove(peer);
    if (owner == peer.id) reclaim();
    changed();
  }

  void grant(PairPeer peer) {
    if (!peers.contains(peer) || peer.wire.closed) return;
    require(
      peer.connected && peer.role == 'operator',
      'Approve an operator first.',
    );
    owner = peer.id;
    epoch++;
    peer.requestedControl = false;
    onControlChanged?.call('Control given to ${peer.name}');
    onOwnershipChanged?.call();
    changed();
    unawaited(publish());
  }

  void reclaim() {
    owner = '';
    epoch++;
    onControlChanged?.call('Host took back control');
    onOwnershipChanged?.call();
    changed();
    unawaited(publish());
  }

  Future<void> publish() async {
    if (!hosting || _busy) return;
    _busy = true;
    try {
      for (final peer in List.of(peers)) {
        if (DateTime.now().millisecondsSinceEpoch - peer.lastSeen > 10000) {
          _drop(peer);
          continue;
        }
        try {
          if (!peer.approved) {
            await peer.wire.send({'type': 'pending', 'id': peer.id});
            continue;
          }
          if (peer.suspended) {
            // Keep only an authenticated availability channel. No service data
            // or control commands flow until the host explicitly reconnects.
            await peer.wire.send({
              'type': 'paused',
              'id': peer.id,
              'hostId': hostId,
              'resume': _approvals[peer.id]?.secret,
            });
            continue;
          }
          final snapshotId = ++_snapshotSequence;
          var data =
              snapshotFor?.call(peer.role == 'operator' && peer.id == owner) ??
              <String, dynamic>{};
          data = decorateSnapshot?.call(peer, data) ?? data;
          // Older viewers do not understand stageSharing; explicitly blank their output.
          if (peer.viewingStage && data['stageSharing'] == false) {
            data['blank'] = true;
            data['displayText'] = '';
            data.remove('quickMessage');
          }
          peer.pendingSnapshots[snapshotId] = data;
          while (peer.pendingSnapshots.length > 12) {
            peer.pendingSnapshots.remove(peer.pendingSnapshots.keys.first);
          }
          await peer.wire.send({
            'type': 'state',
            'snapshotId': snapshotId,
            'id': peer.id,
            'owner': owner,
            'epoch': epoch,
            'resume': _approvals[peer.id]?.secret,
            'hostId': hostId,
            'snapshot': data,
          });
        } catch (_) {
          _drop(peer);
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> join(
    String encoded,
    String name,
    String role, {
    String? sourceAddress,
  }) =>
      _join(PairCode.parse(encoded), name, role, sourceAddress: sourceAddress);

  Future<void> joinPin(
    String address,
    int port,
    String pin,
    String name,
    String role, {
    String? sourceAddress,
  }) {
    require(
      localPairAddress(address) &&
          port > 0 &&
          port <= 65535 &&
          validPairPin(pin),
      'Choose a nearby host and enter its six-digit code.',
    );
    return _join(
      PairCode(address, port, '', 0),
      name,
      role,
      pin: pin,
      sourceAddress: sourceAddress,
    );
  }

  Future<void> _join(
    PairCode invitation,
    String name,
    String role, {
    String? sourceAddress,
    String? pin,
    String? resumeId,
  }) async {
    require(
      ['viewer', 'stage', 'operator'].contains(role),
      'Choose a device role.',
    );
    name = nameValue(name, 'Device name');
    if (resumeId == null) {
      await restoreMemory();
      await stop();
    }
    final lifecycle = _lifecycle;
    final secret = invitation.secret;
    _joinName = name;
    _joinRole = role;
    _sourceAddress = sourceAddress;
    if (resumeId == null) mode = role;
    status = resumeId == null
        ? 'Connecting…'
        : 'Reconnecting to the host device…';
    changed();
    Socket? connecting;
    try {
      final socket = await Socket.connect(
        invitation.address,
        invitation.port,
        timeout: const Duration(seconds: 8),
        sourceAddress: sourceAddress,
      );
      connecting = socket;
      _observePairSocket(socket);
      if (lifecycle != _lifecycle || _disposed) {
        socket.destroy();
        return;
      }
      final input = StreamIterator(pairLines(socket));
      require(
        await input.moveNext().timeout(const Duration(seconds: 8)),
        'No pairing challenge.',
      );
      final challenge = jsonDecode(input.current) as Map;
      require(
        challenge['challenge'] is String &&
            (challenge['challenge'] as String).length <= 100,
        'Invalid host.',
      );
      if (resumeId != null)
        socket.write('${jsonEncode({'type': 'resume', 'id': resumeId})}\n');
      if (pin != null) {
        final srp = PairPinClient();
        final a = srp.start(challenge['salt'], pin);
        socket.write('${jsonEncode({'type': 'pin', 'a': a})}\n');
        require(
          await input.moveNext().timeout(const Duration(seconds: 12)),
          'Code unavailable.',
        );
        final response = jsonDecode(input.current) as Map;
        final proof = srp.prove(response['b']);
        socket.write('${jsonEncode({'proof': proof})}\n');
        require(
          await input.moveNext().timeout(const Duration(seconds: 12)),
          'Incorrect code.',
        );
        final verified = jsonDecode(input.current) as Map;
        final key = await srp.finish(verified['proof'], challenge['challenge']);
        require(lifecycle == _lifecycle && !_disposed, 'Pairing cancelled.');
        _client = PairWire(socket, key, challenge['challenge']);
        await _client!.send({'type': 'hello', 'name': name, 'role': role});
      } else {
        final exchange = X25519();
        final kp = await exchange.newKeyPair();
        final public = await kp.extractPublicKey();
        final hello = PairWire(
          socket,
          SecretKey(base64Url.decode(secret)),
          challenge['challenge'],
        );
        await hello.send({
          'type': 'hello',
          'name': name,
          'role': role,
          'public': base64Encode(public.bytes),
        });
        final shared = await exchange.sharedSecretKey(
          keyPair: kp,
          remotePublicKey: SimplePublicKey(
            base64Decode(challenge['public']),
            type: KeyPairType.x25519,
          ),
        );
        final key = await pairSessionKey(
          shared,
          invitation.secret,
          challenge['challenge'] as String,
          challenge['public'] as String,
          base64Encode(public.bytes),
        );
        require(lifecycle == _lifecycle && !_disposed, 'Pairing cancelled.');
        _client = PairWire(socket, key, challenge['challenge']);
      }
      // Do not show a successful join until the host accepts the handshake.
      require(
        await input.moveNext().timeout(const Duration(seconds: 8)),
        'Invitation unavailable.',
      );
      final pending = await _client!.decode(input.current);
      require(pending['type'] == 'pending', 'Invalid pairing acknowledgement.');
      if (lifecycle != _lifecycle || _disposed) {
        socket.destroy();
        return;
      }
      clientId = pending['id'];
      _retryCount = 0;
      reconnectingSince = null;
      _retry?.cancel();
      _timer?.cancel();
      status = resumeId == null
          ? 'Waiting for host approval'
          : 'Reconnected · waiting for current state';
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(
          _client?.send({'type': 'heartbeat'}).catchError((_) {}) ??
              Future<void>.value(),
        );
        changed();
      });
      unawaited(_receive(input, invitation));
      onOwnershipChanged?.call();
      changed();
    } catch (_) {
      connecting?.destroy();
      if (lifecycle != _lifecycle || _disposed) return;
      _client?.close();
      _client = null;
      if (resumeId != null) {
        _scheduleReconnect();
        return;
      }
      await stop();
      status =
          'Could not pair. Check the code and that Wi-Fi allows devices to reach each other.';
      changed();
      rethrow;
    }
  }

  Future<void> _receive(
    StreamIterator<String> input,
    PairCode invitation,
  ) async {
    final wire = _client;
    try {
      while (wire != null &&
          await input.moveNext().timeout(const Duration(seconds: 12))) {
        final msg = await wire.decode(input.current);
        if (msg['type'] == 'removed') {
          _resumeCode = null;
          _resumeId = null;
          _savedClient = null;
          pausedByHost = false;
          snapshot = null;
          _saveMemoryQuietly();
          requestResult = 'Host removed this device. Pair again for approval.';
          break;
        }
        if (msg['type'] == 'pending') {
          clientId = msg['id'];
        }
        if (msg['type'] == 'paused') {
          clientId = msg['id'];
          pausedByHost = true;
          owner = '';
          snapshot = null;
          lastSnapshot = 0;
          status = 'Disconnected by host · waiting for Reconnect';
          _rememberHost(msg, invitation);
        }
        if (msg['type'] == 'state') {
          pausedByHost = false;
          clientId = msg['id'];
          owner = msg['owner'];
          epoch = msg['epoch'];
          snapshot = Map<String, dynamic>.from(msg['snapshot']);
          lastSnapshot = DateTime.now().millisecondsSinceEpoch;
          if (msg['snapshotId'] is int) {
            await wire.send({'type': 'ack', 'id': msg['snapshotId']});
            await wire.send({'type': 'viewMode', 'stage': mode == 'stage'});
          }
          status = 'Connected';
          _rememberHost(msg, invitation);
        }
        if (msg['type'] == 'program') _receiveProgram(msg);
        if (msg['type'] == 'result')
          requestResult =
              msg['message'] as String? ??
              (msg['ok'] == true
                  ? 'Command applied'
                  : 'Command not applied. Review the current service.');
        changed();
      }
    } catch (_) {
      /* Keep the last snapshot visibly stale; never become host. */
    } finally {
      if (_client == wire) {
        wire?.close();
        _client = null;
        lastSnapshot = 0;
        owner = '';
        // Never retain private notes or a control grant after a lost link.
        if (snapshot != null) {
          snapshot = Map<String, dynamic>.from(snapshot!)
            ..remove('cues')
            ..remove('cueVersions');
          snapshot!['rundown'] = [
            for (final row in (snapshot!['rundown'] as List? ?? []))
              Map<String, dynamic>.from(row)..remove('notes'),
          ];
        }
        status = 'Disconnected · last received state';
        _scheduleReconnect();
        changed();
      }
    }
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_disposed || !joined || _resumeCode == null || _resumeId == null)
      return;
    reconnectingSince ??= DateTime.now();
    _retry?.cancel();
    _timer?.cancel();
    _retryCount = (_retryCount + 1).clamp(1, 5);
    status = pausedByHost
        ? 'Disconnected by host · waiting for Reconnect'
        : 'Host disconnected · reconnecting…';
    final lifecycle = _lifecycle;
    _retry = Timer(
      Duration(seconds: immediate ? 0 : [0, 2, 4, 8, 16, 30][_retryCount]),
      () async {
        if (lifecycle == _lifecycle && joined && !_disposed) {
          await _rejoinRememberedWifi(lifecycle);
          try {
            _sourceAddress = await currentAddress?.call();
          } catch (_) {
            _sourceAddress = null;
          }
          if (_retryCount > 1 && _remoteHostId.isNotEmpty) {
            try {
              final hosts = await discoverHosts?.call() ?? [];
              for (final host in hosts) {
                if (host['id'] == _remoteHostId &&
                    localPairAddress(host['address']) &&
                    host['port'] is int &&
                    host['port'] > 0 &&
                    host['port'] <= 65535) {
                  _resumeCode = PairCode(
                    host['address'],
                    host['port'],
                    _resumeCode!.secret,
                    0,
                  );
                  break;
                }
              }
            } catch (_) {
              /* Retry the last authenticated host address. */
            }
          }
          if (lifecycle != _lifecycle ||
              !joined ||
              _disposed ||
              _resumeCode == null)
            return;
          unawaited(
            _join(
              _resumeCode!,
              _joinName,
              _joinRole,
              sourceAddress: _sourceAddress,
              resumeId: _resumeId,
            ),
          );
        }
      },
    );
    changed();
  }

  /// After a second failed attempt, rejoin the remembered network if this
  /// phone is now on a different one (or none).
  Future<void> _rejoinRememberedWifi(int lifecycle) async {
    if (_retryCount < 2 || rejoinSsid.isEmpty || rejoinWifi == null) return;
    try {
      final current = await currentSsid?.call() ?? '';
      if (current == rejoinSsid || lifecycle != _lifecycle) return;
      rejoiningWifi = true;
      changed();
      await rejoinWifi!();
    } catch (_) {
      /* Keep retrying the host; the banner offers Wi-Fi settings. */
    } finally {
      if (rejoiningWifi) {
        rejoiningWifi = false;
        changed();
      }
    }
  }

  /// Sends one of the fixed stage requests from this stage screen.
  Future<void> sendStageRequest(String kind) async {
    require(
      mode == 'stage' && !stale && snapshot?['stageRequests'] == true,
      'Requests are not available right now.',
    );
    await _client?.send({'type': 'stageRequest', 'kind': kind});
  }

  Future<void> requestControl() async {
    await _client?.send({'type': 'requestControl'});
  }

  Future<void> sendCommand(
    String action,
    dynamic value, {
    int? expectedRevision,
  }) async {
    require(canControl, 'Control is unavailable. Request it from the host.');
    requestResult = 'Sending…';
    changed();
    await _client!.send({
      'type': 'command',
      'action': action,
      'value': value,
      'epoch': epoch,
      'revision': expectedRevision ?? snapshot?['revision'],
    });
  }

  Future<void> stop({bool preserveClient = false}) async {
    _lifecycle++;
    _retry?.cancel();
    _retry = null;
    reconnectingSince = null;
    _resumeCode = null;
    _resumeId = null;
    if (rejoinSsid.isNotEmpty) {
      rejoinSsid = '';
      await bestEffort('release Wi-Fi rejoin', () async => cancelWifi?.call());
    }
    if (!preserveClient && _savedClient != null) {
      _savedClient!['autoResume'] = false;
      _saveMemoryQuietly();
    }
    if (!preserveClient)
      await bestEffort(
        'notify host of leave',
        () async => _client
            ?.send({'type': 'leave'})
            .timeout(const Duration(milliseconds: 250)),
      );
    _timer?.cancel();
    _timer = null;
    await bestEffort('stop advertising', () async => unadvertise?.call());
    discoveryNotice = '';
    await _server?.close();
    _server = null;
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
    for (final p in List.of(peers)) {
      p.wire.close();
    }
    peers.clear();
    _client?.close();
    _client = null;
    code = null;
    pin = '';
    _pinInvitation = null;
    pinAttempts = 0;
    owner = '';
    snapshot = null;
    lastSnapshot = 0;
    pausedByHost = false;
    mode = 'off';
    status = 'Not paired';
    epoch++;
    onOwnershipChanged?.call();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop(preserveClient: true));
    super.dispose();
  }
}
