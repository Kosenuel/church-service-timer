import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Answers multicast DNS questions for `<name>.local` with the host phone's
/// Wi-Fi address, so browsers can open an easy name that keeps working when
/// the address changes. Works offline, on the church router or a hotspot.
/// Devices that do not support `.local` names use the QR or the address.
class MdnsResponder {
  static final group = InternetAddress('224.0.0.251');
  static const port = 5353;
  static const ttlSeconds = 120;

  RawDatagramSocket? _socket;
  String _name = '';
  InternetAddress? _address;
  Timer? _announce;

  bool get running => _socket != null;
  String get hostname => '$_name.local';

  /// Starts answering for [name] (without `.local`) with [address]. Returns
  /// false when this phone does not allow it, for example when the port is
  /// held by the system.
  Future<bool> start(String name, String address) async {
    await stop();
    _name = name.toLowerCase();
    _address = InternetAddress(address);
    try {
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
          reusePort: true,
        );
      } on Object {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
        );
      }
      NetworkInterface? wifi;
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        if (i.addresses.any((a) => a.address == address)) wifi = i;
      }
      socket
        ..multicastLoopback = false
        ..joinMulticast(group, wifi)
        ..listen((event) {
          if (event == RawSocketEvent.read) _read();
        });
      _socket = socket;
    } on Object {
      await stop();
      return false;
    }
    // Announce twice, as the protocol asks, so caches learn the name.
    _send(answer(_name, _address!), group, port);
    _announce = Timer(const Duration(seconds: 1), () {
      if (_socket != null) _send(answer(_name, _address!), group, port);
    });
    return true;
  }

  Future<void> stop() async {
    _announce?.cancel();
    final s = _socket;
    _socket = null;
    if (s != null && _address != null) {
      // A goodbye (TTL 0) so devices forget the address promptly.
      try {
        s.send(answer(_name, _address!, ttl: 0), group, port);
      } on Object {
        /* Best effort. */
      }
    }
    s?.close();
  }

  void _read() {
    final s = _socket;
    if (s == null) return;
    Datagram? d;
    while ((d = s.receive()) != null) {
      final q = parseQuery(d!.data);
      if (q == null || !q.asks(hostname)) continue;
      // A one-shot query from another port wants a direct reply that
      // echoes its id and question; others get the multicast answer.
      if (d.port != port) {
        _send(
          answer(_name, _address!, id: q.id, echoQuestion: true),
          d.address,
          d.port,
        );
      } else if (q.unicast) {
        _send(answer(_name, _address!), d.address, d.port);
      } else {
        _send(answer(_name, _address!), group, port);
      }
    }
  }

  void _send(List<int> bytes, InternetAddress to, int toPort) {
    try {
      _socket?.send(bytes, to, toPort);
    } on Object {
      /* A missed reply is retried by the asking device. */
    }
  }
}

class MdnsQuery {
  final int id;
  final List<({String name, int type, bool unicast})> questions;
  const MdnsQuery(this.id, this.questions);
  bool get unicast => questions.any((q) => q.unicast);

  /// Asks for the IPv4 address (or anything) of [hostname].
  bool asks(String hostname) => questions.any(
    (q) => q.name.toLowerCase() == hostname && (q.type == 1 || q.type == 255),
  );
}

/// Reads the questions of a DNS query; null for anything else.
MdnsQuery? parseQuery(Uint8List b) {
  try {
    if (b.length < 12) return null;
    final flags = (b[2] << 8) | b[3];
    if (flags & 0x8000 != 0) return null; // A response, not a question.
    final count = (b[4] << 8) | b[5];
    var offset = 12;
    final questions = <({String name, int type, bool unicast})>[];
    for (var i = 0; i < count && i < 32; i++) {
      final (name, next) = readName(b, offset);
      if (next + 4 > b.length) return null;
      final type = (b[next] << 8) | b[next + 1];
      final cls = (b[next + 2] << 8) | b[next + 3];
      questions.add((name: name, type: type, unicast: cls & 0x8000 != 0));
      offset = next + 4;
    }
    return MdnsQuery((b[0] << 8) | b[1], questions);
  } on Object {
    return null;
  }
}

/// A DNS name at [offset], following compression pointers; returns the
/// name and the offset just after it.
(String, int) readName(Uint8List b, int offset) {
  final labels = <String>[];
  var i = offset, end = -1, jumps = 0;
  while (true) {
    if (i >= b.length) throw const FormatException('Short name');
    final len = b[i];
    if (len == 0) {
      i++;
      break;
    }
    if (len & 0xC0 == 0xC0) {
      if (i + 1 >= b.length || ++jumps > 16)
        throw const FormatException('Bad pointer');
      if (end < 0) end = i + 2;
      i = ((len & 0x3F) << 8) | b[i + 1];
      continue;
    }
    if (i + 1 + len > b.length) throw const FormatException('Short label');
    labels.add(String.fromCharCodes(b.sublist(i + 1, i + 1 + len)));
    i += 1 + len;
  }
  return (labels.join('.'), end >= 0 ? end : i);
}

List<int> _name(String name) => [
  for (final label in name.split('.')) ...[label.length, ...label.codeUnits],
  0,
];

/// An authoritative answer: `<name>.local` is at [address].
Uint8List answer(
  String name,
  InternetAddress address, {
  int id = 0,
  bool echoQuestion = false,
  int ttl = MdnsResponder.ttlSeconds,
}) {
  final host = _name('$name.local');
  final out = BytesBuilder()
    ..add([id >> 8, id & 0xFF, 0x84, 0x00])
    ..add([0, echoQuestion ? 1 : 0, 0, 1, 0, 0, 0, 0]);
  if (echoQuestion) out.add([...host, 0, 1, 0, 1]);
  out
    ..add(host)
    // Type A; class IN, with the cache-flush bit unless replying directly.
    ..add([0, 1, echoQuestion ? 0x00 : 0x80, 1])
    ..add([ttl >> 24 & 0xFF, ttl >> 16 & 0xFF, ttl >> 8 & 0xFF, ttl & 0xFF])
    ..add([0, 4, ...address.rawAddress]);
  return out.toBytes();
}
