import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/w2/hd7_auth.dart';
import 'package:church_service_timer/hardware/w2/w2_administration.dart';
import 'package:church_service_timer/hardware/w2/w2_discovery.dart';

/// Where to look for a sign: a local address to send from and the address
/// to send the search to (the broadcast address of that network).
typedef W2Route = ({InternetAddress local, InternetAddress target});

/// Every IPv4 network this computer is on. A PC is often on Ethernet and
/// on the sign's Wi-Fi at once, so the search goes out on each of them,
/// from that network's own address.
Future<List<W2Route>> allIpv4Routes() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  return [
    for (final interface in interfaces)
      for (final address in interface.addresses)
        (local: address, target: InternetAddress('255.255.255.255')),
  ];
}

/// The small saved facts about the sign (which one, whether to reconnect).
/// Never holds a password.
abstract class W2Preferences {
  Future<Json> read();
  Future<void> write(Json changes);
}

class _Udp {
  final RawDatagramSocket socket;
  final _queue = <Datagram>[];
  Completer<void>? _waiting;
  late final StreamSubscription<RawSocketEvent> _events;
  _Udp(this.socket) {
    _events = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (Datagram? d = socket.receive(); d != null; d = socket.receive()) {
        _queue.add(d);
      }
      _waiting?.complete();
      _waiting = null;
    }, onError: (_) {});
  }

  static Future<_Udp> bind(InternetAddress local) async {
    final socket = await RawDatagramSocket.bind(local, 0);
    socket.broadcastEnabled = true;
    return _Udp(socket);
  }

  /// The next datagram, or null when [until] passes first.
  Future<Datagram?> receive(DateTime until) async {
    while (_queue.isEmpty) {
      final left = until.difference(DateTime.now());
      if (left <= Duration.zero) return null;
      final waiting = _waiting ??= Completer<void>();
      await waiting.future.timeout(left, onTimeout: () {});
    }
    return _queue.removeAt(0);
  }

  void close() {
    unawaited(_events.cancel());
    socket.close();
  }
}

/// Talks to a Huidu W2 sign over the local network: a Dart port of
/// `W2Display.kt`, with the same checks in the same order.
///
/// It only ever writes to a controller that reported firmware V6.02.232,
/// 32 × 16, single colour, and it only sends the three program shapes the
/// app builds (frames, countdown, clock). It never changes scan settings,
/// polarity or firmware. No password is kept here.
///
/// Operations run strictly one after another.
class W2Transport {
  final W2Preferences prefs;
  final Future<List<W2Route>> Function() routes;
  final int port;
  final String applicationName;
  final math.Random _random;
  W2Transport({
    required this.prefs,
    Future<List<W2Route>> Function()? routes,
    this.port = W2Discovery.port,
    this.applicationName = 'ChurchServiceTimer_Windows',
    math.Random? random,
  }) : routes = routes ?? allIpv4Routes,
       _random = random ?? math.Random.secure();

  InternetAddress? _local;
  InternetAddress? _peer;
  _Udp? _socket;
  Hd7Session? _session;
  Json? _device;
  int _generation = 0;
  final _candidates = <String, ({InternetAddress local, Json device})>{};

  /// This computer's address on the network the sign was found on, while
  /// connected.
  String? get localAddress => _local?.address;

  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.catchError((_) {}).then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Json> preferences() => _serial(() async {
    final p = await prefs.read();
    return {
      'hardware': p['hardware'] == true,
      'id': p['id'] as String? ?? '',
      'autoReconnect': p['autoReconnect'] != false,
      'name': p['name'] as String? ?? '',
    };
  });

  Future<void> autoReconnect(bool enabled) =>
      _serial(() => prefs.write({'autoReconnect': enabled}));

  Future<void> forget() => _serial(() async {
    _disconnect();
    await prefs.write({'id': null, 'name': null, 'hardware': false});
  });

  Future<void> simulator() => _serial(() async {
    _disconnect();
    await prefs.write({'hardware': false});
  });

  Future<void> disconnect() => _serial(() async => _disconnect());

  void _disconnect() {
    _generation++;
    _socket?.close();
    _socket = null;
    _session?.close();
    _session = null;
    _device = null;
    _local = null;
    _peer = null;
  }

  Future<bool> _present(InternetAddress local) async {
    if (local.isLoopback) return true;
    try {
      return (await routes()).any((r) => r.local.address == local.address);
    } catch (_) {
      return false;
    }
  }

  Future<List<Json>> _scan(
    InternetAddress local,
    InternetAddress target,
    int timeoutMs, {
    required bool broadcast,
  }) async {
    final found = <String, Json>{};
    final socket = await _Udp.bind(local);
    try {
      final sequence = _random.nextInt(1 << 32);
      socket.socket.send(W2Discovery.query(sequence), target, port);
      final until = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (true) {
        final reply = await socket.receive(until);
        if (reply == null) break;
        if (reply.port != port) continue;
        try {
          final d = W2Discovery.decode(
            reply.data,
            sequence,
            reply.address.address,
          );
          found[d['id'] as String] = d;
          if (!broadcast) break;
        } on FormatException {
          // Unknown controllers are never written to.
        }
      }
    } finally {
      socket.close();
    }
    return found.values.toList();
  }

  Future<List<Json>> discover() => _serial(() async {
    final all = await routes();
    require(
      all.isNotEmpty,
      'Connect this computer to the sign’s Wi-Fi, then scan again.',
    );
    _candidates.clear();
    // Every network is searched at the same time; a network that cannot
    // be searched (an adapter that just went away) is skipped.
    final results = await Future.wait([
      for (final route in all)
        _scan(route.local, route.target, 2200, broadcast: true).then(
          (found) => (local: route.local, found: found),
          onError: (_) => (local: route.local, found: <Json>[]),
        ),
    ]);
    for (final result in results) {
      for (final device in result.found) {
        _candidates.putIfAbsent(
          device['id'] as String,
          () => (local: result.local, device: device),
        );
      }
    }
    return [for (final c in _candidates.values) c.device];
  });

  Future<Json> connect(String id, String password) => _serial(() async {
    try {
      _disconnect();
      final candidate = _candidates[id];
      require(candidate != null, 'Scan again and select the display.');
      final local = candidate!.local;
      final address = InternetAddress(candidate.device['address'] as String);
      final current = (await _scan(
        local,
        address,
        1200,
        broadcast: false,
      )).where((d) => d['id'] == id).firstOrNull;
      require(
        current != null,
        'Selected display is no longer reachable. Scan again.',
      );
      require(
        current!['supported'] == true,
        'This milestone supports W2 V6.02.232, 32 × 16 red monochrome only.',
      );
      _socket = await _Udp.bind(local);
      _local = local;
      _peer = InternetAddress(current['address'] as String);
      final saved = await prefs.read();
      final installId =
          saved['installation'] as String? ??
          List.generate(
            16,
            (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
      final request = Hd7Auth.login(password, installId, applicationName);
      try {
        final reply = await _exchange(request);
        try {
          _session = reply.loginSession();
        } finally {
          reply.close();
        }
      } finally {
        request.close();
      }
      _device = current;
      await prefs.write({
        'installation': installId,
        'id': id,
        'name': current['name'],
        'hardware': true,
      });
      return {...current, 'generation': _generation};
    } catch (e) {
      _disconnect();
      if (e is Hd7SecurityError) throw RuleError(e.message);
      rethrow;
    }
  });

  Future<Hd7Reply> _exchange(Hd7Request request, {int attempts = 2}) async {
    final socket = _socket, peer = _peer;
    require(socket != null && peer != null, 'Display disconnected');
    final wire = request.bytes();
    try {
      // A retry is exactly the same authenticated request, including salt
      // and ID.
      for (var attempt = 0; attempt < attempts; attempt++) {
        socket!.socket.send(wire, peer!, port);
        final until = DateTime.now().add(const Duration(milliseconds: 1200));
        while (true) {
          final packet = await socket.receive(until);
          if (packet == null) break;
          if (packet.address.address != peer.address || packet.port != port)
            continue;
          final Hd7Reply reply;
          try {
            reply = Hd7Auth.decode(request, packet.data, 8192);
          } on Hd7SecurityError {
            continue;
          }
          if (reply.status != 0) {
            final status = reply.status;
            reply.close();
            throw RuleError(
              status == -125
                  ? 'Display password was rejected.'
                  : 'Controller rejected the request ($status). Reconnect before retrying.',
            );
          }
          return reply;
        }
      }
      throw RuleError(
        'No acknowledgement from the display. Its last accepted output may still be showing.',
      );
    } finally {
      wire.fillRange(0, wire.length, 0);
    }
  }

  Future<void> _command(int code, Uint8List body, {int attempts = 2}) async {
    final session = _session;
    require(session != null, 'Reconnect to the display.');
    final request = session!.command(code, body);
    try {
      (await _exchange(request, attempts: attempts)).close();
    } finally {
      request.close();
    }
  }

  /// Administration never retries: a lost ACK may still mean the setting
  /// changed.
  Future<Json> administer(String kind, String value, int expectedGeneration) =>
      _serial(() async {
        Uint8List? body;
        try {
          require(
            expectedGeneration == _generation && _session != null,
            'Reconnect before changing device settings.',
          );
          require(
            W2Administration.supported(_device ?? const {}),
            'Administration is not verified for this display.',
          );
          final code = kind == 'devicePassword'
              ? W2Administration.devicePasswordCommand
              : W2Administration.wifiCommand;
          body = switch (kind) {
            'ssid' => W2Administration.ssidBody(value),
            'wifiPassword' => W2Administration.wifiPasswordBody(value),
            'devicePassword' => W2Administration.devicePasswordBody(value),
            _ => throw RuleError('Unknown device setting'),
          };
          bool accepted;
          try {
            await _command(code, body, attempts: 1);
            accepted = true;
          } catch (_) {
            accepted = false;
          }
          _disconnect();
          return {'acknowledged': accepted};
        } finally {
          body?.fillRange(0, body.length, 0);
        }
      });

  Future<Json> status() => _serial(() async {
    final d = _device;
    if (d == null) return {'connected': false};
    try {
      final local = _local;
      if (local == null || !await _present(local)) throw StateError('gone');
      final current = (await _scan(
        local,
        InternetAddress(d['address'] as String),
        1000,
        broadcast: false,
      )).where((c) => c['id'] == d['id']).firstOrNull;
      if (current == null || current['supported'] != true)
        throw StateError('missing');
      return {'connected': true, 'generation': _generation};
    } catch (_) {
      // A missed discovery reply is not proof that the authenticated
      // session died. The caller applies a grace period before closing and
      // re-authenticating it.
      return {
        'connected': false,
        'generation': _generation,
        'reason': 'Controller health reply missing',
      };
    }
  });

  Future<void> _calibrateRtc(int now) async {
    final offset = DateTime.fromMillisecondsSinceEpoch(
      now,
    ).timeZoneOffset.inMilliseconds;
    final localSeconds = (now + offset) ~/ 1000;
    require(
      localSeconds >= 0 && localSeconds <= 0xffffffff,
      'This computer’s time is outside the controller range.',
    );
    final body = Uint8List(14);
    body[0] = 14;
    ByteData.sublistView(body).setUint32(1, localSeconds);
    await _command(20, body);
  }

  /// Only the compact numeric clock layouts produced by W2Program.clock.
  static void validateClock(Uint8List bytes) {
    require(
      bytes.length == 444 || bytes.length == 500,
      'Invalid clock program length',
    );
    final twelve = bytes[148] == 6;
    require(bytes[148] == 1 || twelve, 'Invalid clock time format');
    final suffixBytes = twelve ? 56 : 0;
    require(bytes.length == 444 + suffixBytes, 'Invalid clock glyph data');
    final header = Uint8List(94);
    final h = ByteData.sublistView(header);
    h.setUint16(0, 94);
    header[2] = 0x32;
    header[6] = 0xff;
    header[7] = 0xff;
    header[8] = twelve ? 6 : 1;
    h.setUint16(29, 14);
    h.setUint16(31, twelve ? 4 : 6);
    h.setUint32(35, 135);
    h.setUint32(41, 135);
    h.setUint16(47, twelve ? 12 : 0);
    h.setUint32(49, 135);
    h.setUint32(53, 1);
    h.setUint32(65, 135 + suffixBytes);
    h.setUint32(69, bytes.length - 99);
    h.setUint32(73, bytes.length - 99);
    h.setUint32(86, 1);
    var same = true;
    for (var i = 0; i < 94; i++) {
      if (bytes[140 + i] != header[i]) same = false;
    }
    require(same, 'Invalid clock layout');
    final data = ByteData.sublistView(bytes);
    require(
      data.getUint32(19) == 0 &&
          data.getUint32(27) == 31 &&
          bytes[99] == 0x48 &&
          bytes[100] == 0x41 &&
          data.getUint16(107) == 32 &&
          data.getUint16(109) == 16 &&
          data.getUint16(111) == 1 &&
          data.getUint32(136) == 41,
      'Invalid clock display area',
    );
  }

  /// Checks [bytes] is one of the three program shapes the app builds.
  /// Returns which: 'timer', 'clock' or 'frames'.
  static String validateProgram(Uint8List bytes, {required bool timer}) {
    require(
      bytes.length >= 233 &&
          bytes.length <= 135335 &&
          bytes[0] == 0x48 &&
          bytes[1] == 0x43,
      'Unsupported display program',
    );
    if (timer) {
      require(
        bytes.length == 393 && bytes[142] == 0x34,
        'Invalid timer program',
      );
      return 'timer';
    }
    if (bytes[142] == 0x32) {
      validateClock(bytes);
      return 'clock';
    }
    final data = ByteData.sublistView(bytes);
    final frames = data.getUint16(143);
    require(
      bytes[142] == 0x30 &&
          frames >= 1 &&
          frames <= 2048 &&
          bytes.length == 167 + 66 * frames &&
          data.getUint32(155) == 27 + 2 * frames,
      'Invalid display frame sequence',
    );
    return 'frames';
  }

  Future<Json> send(
    Uint8List program,
    int? targetWall,
    int expectedGeneration,
  ) => _serial(() async {
    require(
      expectedGeneration == _generation && _session != null,
      'Connection changed. Reconnect before sending.',
    );
    final bytes = Uint8List.fromList(program);
    require(
      bytes.length >= 233 &&
          bytes.length <= 135335 &&
          bytes[0] == 0x48 &&
          bytes[1] == 0x43,
      'Unsupported display program',
    );
    try {
      final shape = validateProgram(bytes, timer: targetWall != null);
      final local = _local;
      require(local != null && await _present(local), 'Network disconnected');
      final now = DateTime.now().millisecondsSinceEpoch;
      if (shape == 'timer') {
        final left = targetWall! - now;
        require(
          left >= 1 && left <= 3599000,
          'Remaining time must be between 00:01 and 59:59.',
        );
        final offset = DateTime.fromMillisecondsSinceEpoch(
          now,
        ).timeZoneOffset.inMilliseconds;
        await _calibrateRtc(now);
        // The countdown deadline stays fixed even if an acknowledgement
        // is retried.
        ByteData.sublistView(
          bytes,
        ).setUint32(144, ((targetWall + offset) ~/ 1000) & 0xffffffff);
      } else if (shape == 'clock') {
        // This program reads the RTC locally; no per-second uploads.
        await _calibrateRtc(now);
      }
      final transfer = _random.nextInt(65536);
      final packets = (bytes.length + 4095) ~/ 4096;
      final begin = Uint8List(5);
      begin[0] = 5;
      ByteData.sublistView(begin)
        ..setUint16(1, transfer)
        ..setUint16(3, packets);
      await _command(2, begin);
      for (var index = 0; index < packets; index++) {
        final offset = index * 4096;
        final length = math.min(4096, bytes.length - offset);
        final chunk = Uint8List(5 + length);
        chunk[0] = 5;
        ByteData.sublistView(chunk)
          ..setUint16(1, transfer)
          ..setUint16(3, index);
        chunk.setRange(5, 5 + length, bytes, offset);
        await _command(3, chunk);
      }
      final end = Uint8List(3);
      end[0] = 3;
      ByteData.sublistView(end).setUint16(1, transfer);
      await _command(4, end);
      return {
        'accepted': true,
        'generation': _generation,
        'acceptedAt': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      _disconnect();
      if (e is Hd7SecurityError) throw RuleError(e.message);
      rethrow;
    }
  });
}
