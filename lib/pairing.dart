import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'domain.dart';
import 'pairing_pin.dart';

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
  bool approved = false, requestedControl = false;
  int lastSeen = DateTime.now().millisecondsSinceEpoch;
  PairPeer(this.id, this.name, this.role, this.wire);
}

/// Local encrypted links. The host remains the single timer/output authority.
class PairHub extends ChangeNotifier {
  ServerSocket? _server;
  PairWire? _client;
  final peers = <PairPeer>[];
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
  Future<bool> Function(String action, dynamic value, int revision)? command;
  void Function()? onOwnershipChanged;
  void Function(String message)? onControlChanged;
  bool get hosting => _server != null;
  bool get joined => mode == 'viewer' || mode == 'stage' || mode == 'operator';
  bool get stale =>
      lastSnapshot == 0 ||
      DateTime.now().millisecondsSinceEpoch - lastSnapshot > 3500;
  bool get canControl =>
      joined && mode == 'operator' && !stale && owner == clientId;
  bool get localControl => !hosting || owner.isEmpty;
  void showStage(bool stage) {
    if (!joined || mode == 'operator') return;
    mode = stage ? 'stage' : 'viewer';
    onOwnershipChanged?.call();
    changed();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> host(String address) async {
    require(localPairAddress(address), 'Connect to a local Wi-Fi network.');
    await stop();
    _server = await ServerSocket.bind(address, 0);
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
    final invitation = code;
    final pinInvitation = _pinInvitation;
    if (invitation == null ||
        invitation.expires < DateTime.now().millisecondsSinceEpoch ||
        _sockets.length >= 8) {
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
      if (input.current.startsWith('{')) {
        require(
          pinAvailable && identical(code, invitation),
          'Generate a new code.',
        );
        pinAttempts++;
        changed();
        final request = jsonDecode(input.current) as Map;
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
          SecretKey(base64Url.decode(invitation.secret)),
          challenge,
        );
        hello = await helloWire.decode(input.current);
        final shared = await exchange.sharedSecretKey(
          keyPair: kp,
          remotePublicKey: SimplePublicKey(
            base64Decode(hello['public']),
            type: KeyPairType.x25519,
          ),
        );
        final key = await pairSessionKey(
          shared,
          invitation.secret,
          challenge,
          base64Encode(public.bytes),
          hello['public'] as String,
        );
        wire = PairWire(socket, key, challenge);
      }
      require(
        identical(code, invitation) &&
            invitation.expires > DateTime.now().millisecondsSinceEpoch,
        'This invitation expired or was replaced.',
      );
      require(
        hello['type'] == 'hello' &&
            ['viewer', 'stage', 'operator'].contains(hello['role']) &&
            hello['name'] is String &&
            (hello['name'] as String).length <= 60,
        'Invalid pairing hello.',
      );
      peer = PairPeer(
        pairRandom(12),
        nameValue(hello['name'], 'Device name'),
        hello['role'],
        wire,
      );
      peers.add(peer);
      changed();
      await wire.send({'type': 'pending', 'id': peer.id});
      while (await input.moveNext().timeout(const Duration(seconds: 10))) {
        final message = await wire.decode(input.current);
        peer.lastSeen = DateTime.now().millisecondsSinceEpoch;
        if (message['type'] == 'heartbeat') continue;
        if (!peer.approved) {
          await peer.wire.send({'type': 'pending', 'id': peer.id});
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
          await wire.send({'type': 'result', 'ok': ok});
          await publish();
        }
      }
    } catch (_) {
      /* Invalid/unavailable peers lose their lease. No secrets logged. */
    } finally {
      _sockets.remove(socket);
      socket.destroy();
      if (peer != null) {
        peers.remove(peer);
        if (owner == peer.id) {
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

  void approve(PairPeer peer) {
    if (!peers.contains(peer) || peer.wire.closed) return;
    peer.approved = true;
    changed();
    unawaited(publish());
  }

  void remove(PairPeer peer) {
    peer.wire.close();
    peers.remove(peer);
    if (owner == peer.id) reclaim();
    changed();
  }

  void grant(PairPeer peer) {
    if (!peers.contains(peer) || peer.wire.closed) return;
    require(
      peer.approved && peer.role == 'operator',
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
          remove(peer);
          continue;
        }
        try {
          if (!peer.approved) {
            await peer.wire.send({'type': 'pending', 'id': peer.id});
            continue;
          }
          await peer.wire.send({
            'type': 'state',
            'id': peer.id,
            'owner': owner,
            'epoch': epoch,
            'snapshot':
                snapshotFor?.call(
                  peer.role == 'operator' && peer.id == owner,
                ) ??
                {},
          });
        } catch (_) {
          remove(peer);
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
  }) async {
    require(
      ['viewer', 'stage', 'operator'].contains(role),
      'Choose a device role.',
    );
    name = nameValue(name, 'Device name');
    await stop();
    mode = role;
    status = 'Connecting…';
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
        _client = PairWire(socket, key, challenge['challenge']);
        await _client!.send({'type': 'hello', 'name': name, 'role': role});
      } else {
        final exchange = X25519();
        final kp = await exchange.newKeyPair();
        final public = await kp.extractPublicKey();
        final hello = PairWire(
          socket,
          SecretKey(base64Url.decode(invitation.secret)),
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
        _client = PairWire(socket, key, challenge['challenge']);
      }
      // Do not show a successful join until the host accepts the handshake.
      require(
        await input.moveNext().timeout(const Duration(seconds: 8)),
        'Invitation unavailable.',
      );
      final pending = await _client!.decode(input.current);
      require(pending['type'] == 'pending', 'Invalid pairing acknowledgement.');
      clientId = pending['id'];
      status = 'Waiting for host approval';
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(
          _client?.send({'type': 'heartbeat'}).catchError((_) {}) ??
              Future<void>.value(),
        );
        changed();
      });
      unawaited(_receive(input));
      onOwnershipChanged?.call();
      changed();
    } catch (_) {
      connecting?.destroy();
      await stop();
      status =
          'Could not pair. Check the code and that Wi-Fi allows devices to reach each other.';
      changed();
      rethrow;
    }
  }

  Future<void> _receive(StreamIterator<String> input) async {
    final wire = _client;
    try {
      while (wire != null &&
          await input.moveNext().timeout(const Duration(seconds: 12))) {
        final msg = await wire.decode(input.current);
        if (msg['type'] == 'pending') {
          clientId = msg['id'];
        }
        if (msg['type'] == 'state') {
          clientId = msg['id'];
          owner = msg['owner'];
          epoch = msg['epoch'];
          snapshot = Map<String, dynamic>.from(msg['snapshot']);
          lastSnapshot = DateTime.now().millisecondsSinceEpoch;
          status = 'Connected';
        }
        if (msg['type'] == 'result')
          requestResult = msg['ok'] == true
              ? 'Command applied'
              : 'Command not applied. Review the current service.';
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
        status = 'Disconnected · last received state';
        changed();
      }
    }
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

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    try {
      await unadvertise?.call();
    } catch (_) {}
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
    mode = 'off';
    status = 'Not paired';
    epoch++;
    onOwnershipChanged?.call();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
