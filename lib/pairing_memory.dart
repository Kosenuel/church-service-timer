part of 'pairing.dart';

/// Local trust, separate from a socket and never included in portable backups.
class SavedPairDevice {
  final String id, name, role, secret;
  bool suspended;
  int lastSeen;
  SavedPairDevice(
    this.id,
    this.name,
    this.role,
    this.secret, {
    this.suspended = false,
    required this.lastSeen,
  });

  Json toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'secret': secret,
    'suspended': suspended,
    'lastSeen': lastSeen,
  };

  factory SavedPairDevice.fromJson(Json j) {
    require(
      j['id'] is String &&
          (j['id'] as String).length <= 80 &&
          ['stage', 'viewer', 'operator'].contains(j['role']) &&
          j['secret'] is String &&
          base64Url.decode(j['secret']).length == 32 &&
          j['lastSeen'] is int,
      'Invalid saved pairing.',
    );
    return SavedPairDevice(
      j['id'],
      nameValue(j['name'], 'Device name'),
      j['role'],
      j['secret'],
      suspended: j['suspended'] == true,
      lastSeen: j['lastSeen'],
    );
  }
}

extension PairMemory on PairHub {
  Future<void> retrySavingDevices() async {
    await _saveMemory();
    memoryNotice = '';
    changed();
  }

  List<SavedPairDevice> get savedDevices =>
      List.unmodifiable(_approvals.values);
  PairPeer? peerFor(String id) {
    for (final peer in peers.reversed) {
      if (peer.id == id && !peer.wire.closed) return peer;
    }
    return null;
  }

  bool connectedDevice(String id) => peerFor(id)?.connected == true;
  bool get hasSavedHost => _savedClient != null;
  bool get canResumeAsStage =>
      hasSavedHost && _savedClient!['role'] != 'operator';

  Future<void> _saveMemory() {
    final encoded = jsonEncode({
      'version': 1,
      'hostId': hostId,
      'port': _savedPort,
      'devices': [for (final d in _approvals.values) d.toJson()],
      'client': _savedClient,
    });
    final write = _memoryWrites.catchError((_) {}).then((_) async {
      await writeMemory?.call(encoded);
    });
    _memoryWrites = write;
    return write;
  }

  void _saveMemoryQuietly() {
    unawaited(
      _saveMemory().catchError((_) {
        memoryNotice =
            'Could not save paired devices. Try again before closing the app.';
        changed();
      }),
    );
  }

  Future<void> restoreMemory() => _restoringMemory ??= _restoreMemory();

  Future<void> _restoreMemory() async {
    try {
      final raw = await readMemory?.call();
      if (raw == null) return;
      require(raw.length <= 65536, 'Saved pairing is too large.');
      final j = jsonDecode(raw) as Map;
      require(
        j['version'] == 1 &&
            j['devices'] is List &&
            (j['devices'] as List).length <= 32 &&
            j['hostId'] is String,
        'Invalid saved devices.',
      );
      final devices = <String, SavedPairDevice>{};
      for (final value in j['devices']) {
        final d = SavedPairDevice.fromJson(Map<String, dynamic>.from(value));
        devices[d.id] = d;
      }
      final client = j['client'] == null
          ? null
          : Map<String, dynamic>.from(j['client']);
      if (client != null) {
        require(
          client['address'] is String &&
              localPairAddress(client['address']) &&
              client['port'] is int &&
              client['port'] > 0 &&
              client['port'] <= 65535 &&
              client['id'] is String &&
              client['hostId'] is String &&
              client['secret'] is String &&
              base64Url.decode(client['secret']).length == 32 &&
              ['stage', 'viewer', 'operator'].contains(client['role']),
          'Invalid saved host.',
        );
        nameValue(client['name'], 'Device name');
      }
      hostId = j['hostId'];
      _savedPort = j['port'] is int && j['port'] > 0 && j['port'] <= 65535
          ? j['port']
          : 0;
      _approvals.addAll(devices);
      _savedClient = client;
      changed();
    } catch (_) {
      memoryNotice =
          'Saved pairing could not be opened. Pair your devices again.';
      changed();
    }
  }

  Future<void> resumeSavedHost({bool automatic = false}) async {
    final saved = _savedClient;
    if (saved == null ||
        hosting ||
        joined ||
        (automatic && saved['autoResume'] != true))
      return;
    _resumeId = saved['id'];
    _resumeCode = PairCode(saved['address'], saved['port'], saved['secret'], 0);
    _joinName = saved['name'];
    _joinRole = saved['role'];
    _remoteHostId = saved['hostId'];
    mode = saved['viewMode'] == 'stage' && _joinRole != 'operator'
        ? 'stage'
        : _joinRole;
    pausedByHost = saved['paused'] == true;
    saved['autoResume'] = true;
    await _saveMemory();
    _scheduleReconnect(immediate: true);
  }

  void _rememberHost(Json msg, PairCode invitation) {
    if (msg['resume'] is! String ||
        base64Url.decode(msg['resume']).length != 32)
      return;
    _resumeId = clientId;
    _resumeCode = PairCode(
      invitation.address,
      invitation.port,
      msg['resume'],
      0,
    );
    _remoteHostId = msg['hostId'] as String? ?? '';
    final next = <String, dynamic>{
      'id': clientId,
      'hostId': _remoteHostId,
      'address': invitation.address,
      'port': invitation.port,
      'secret': msg['resume'],
      'name': _joinName,
      'role': _joinRole,
      'viewMode': mode,
      'autoResume': true,
      'paused': pausedByHost,
    };
    if (jsonEncode(next) != jsonEncode(_savedClient)) {
      _savedClient = next;
      _saveMemoryQuietly();
    }
  }

  Future<void> disconnectDevice(String id) async {
    final device = _approvals[id];
    if (device == null) return;
    device.suspended = true;
    final peer = peerFor(id);
    device.lastSeen = peer?.lastSeen ?? device.lastSeen;
    if (peer != null) {
      peer.suspended = true;
      peer.requestedControl = false;
      peer.pendingSnapshots.clear();
      peer.acknowledgedSnapshot = null;
      peer.lastAck = 0;
    }
    if (owner == id) reclaim();
    changed();
    try {
      await _saveMemory();
    } catch (_) {
      memoryNotice =
          'Disconnect could not be saved. Retry before closing the app.';
      changed();
      rethrow;
    }
    await publish();
  }

  Future<bool> reconnectDevice(String id) async {
    require(hosting, 'Start sharing on this phone first.');
    final device = _approvals[id];
    require(device != null, 'Pair this device again.');
    device!.suspended = false;
    try {
      await _saveMemory();
    } catch (_) {
      device.suspended = true;
      rethrow;
    }
    final peer = peerFor(id);
    if (peer != null) {
      peer.suspended = false;
      peer.requestedControl = false;
      peer.lastAck = 0;
      peer.pendingSnapshots.clear();
    }
    changed();
    await publish();
    return peer?.connected == true;
  }

  Future<void> forgetDevice(String id) async {
    final device = _approvals.remove(id);
    final peer = peerFor(id);
    if (peer != null) peer.suspended = true;
    if (owner == id) reclaim();
    try {
      await _saveMemory();
    } catch (_) {
      if (device != null) _approvals[id] = device;
      if (peer != null) peer.suspended = device?.suspended ?? false;
      rethrow;
    }
    if (peer != null) {
      peer.approved = false;
      try {
        await peer.wire.send({'type': 'removed'});
      } catch (_) {}
      _drop(peer);
    }
    changed();
  }
}
