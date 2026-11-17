import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// A W2 controller on the loopback interface, written from the protocol
/// notes rather than from the app's own codec, so the two check each other.
/// It answers discovery, checks the login password, and records every
/// authenticated command and each program uploaded to it.

Uint8List fakeMd5(List<int> bytes) =>
    pc.MD5Digest().process(Uint8List.fromList(bytes));
Uint8List fakeHmac(Uint8List key, List<int> bytes) {
  final mac = pc.HMac(pc.MD5Digest(), 64)..init(pc.KeyParameter(key));
  return mac.process(Uint8List.fromList(bytes));
}

Uint8List fakeAes(bool encrypt, Uint8List key, Uint8List input) =>
    (pc.PaddedBlockCipherImpl(
          pc.PKCS7Padding(),
          pc.ECBBlockCipher(pc.AESEngine()),
        )..init(
          encrypt,
          pc.PaddedBlockCipherParameters(pc.KeyParameter(key), null),
        ))
        .process(input);

Uint8List fakePasswordKey(String password) => password.isEmpty
    ? fakeMd5(Uint8List(32))
    : fakeMd5(utf8.encode('${password}64ACFEB8B6FE4EF082DB8F3CD428EB20'));

/// The parts of a request packet, after its checks passed with [key].
({int command, int messageId, Uint8List session, int salt, Uint8List plain})?
parseHd7Request(Uint8List wire, Uint8List key) {
  final b = ByteData.sublistView(wire);
  if (wire.length < 40 ||
      wire[0] != 0x48 ||
      wire[1] != 0x44 ||
      b.getUint16(2, Endian.little) != wire.length ||
      wire[4] != 23 ||
      wire.last != 0xaa)
    return null;
  final tag = wire.sublist(wire.length - 17, wire.length - 1);
  final expected = fakeHmac(key, wire.sublist(0, wire.length - 17));
  for (var i = 0; i < 16; i++) {
    if (tag[i] != expected[i]) return null;
  }
  final body = Uint8List.fromList(wire.sublist(23, wire.length - 17));
  final encrypted = wire[17] & 1 != 0;
  return (
    command: wire[22],
    messageId: b.getUint32(18, Endian.little),
    session: Uint8List.fromList(wire.sublist(5, 13)),
    salt: b.getUint32(13, Endian.little),
    plain: encrypted ? fakeAes(false, key, body) : body,
  );
}

class FakeW2Controller {
  final RawDatagramSocket _socket;
  FakeW2Controller._(this._socket) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (var d = _socket.receive(); d != null; d = _socket.receive()) {
        _handle(d);
      }
    });
  }

  static Future<FakeW2Controller> start() async => FakeW2Controller._(
    await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  int get port => _socket.port;
  String password = 'Sign1234';
  String firmware = 'HD_W2 V6.02.232';
  String name = 'Hall sign';
  int width = 32, height = 16, pwdComplexity = 1;
  bool answerDiscovery = true, acknowledge = true;

  /// A status other than 0 to answer commands with.
  int rejectWith = 0;

  /// Acknowledgements to drop before answering again (tests the retry).
  int dropNext = 0;

  final commands = <({int command, Uint8List body})>[];
  final programs = <Uint8List>[];
  final logins = <String>[];
  final _sessionId = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3, 2]);
  final _sessionKey = Uint8List.fromList(List.generate(16, (i) => 200 - i * 3));
  final _salts = <int>{};
  BytesBuilder? _upload;
  int _packets = 0;

  static const idHex = '0a0b0c0d0e0f101112131415161718ff';

  void _handle(Datagram d) {
    final wire = d.data;
    if (wire.length == 42 && wire[0] == 0x48 && wire[1] == 0x54) {
      if (answerDiscovery) {
        _socket.send(_discovery(wire.sublist(23, 27)), d.address, d.port);
      }
      return;
    }
    if (wire.length < 40 || wire[0] != 0x48 || wire[1] != 0x44) return;
    final command = wire[22];
    if (command == 0) {
      final key = fakePasswordKey(password);
      final request = parseHd7Request(wire, key);
      if (request == null) {
        _reply(d, wire, -125, Uint8List(32), null);
        return;
      }
      logins.add(utf8.decode(request.plain.sublist(4)));
      _salts.clear();
      _reply(
        d,
        wire,
        0,
        key,
        Uint8List.fromList([..._sessionId, ..._sessionKey]),
      );
      return;
    }
    final request = parseHd7Request(wire, _sessionKey);
    if (request == null) return;
    for (var i = 0; i < 8; i++) {
      if (request.session[i] != _sessionId[i]) return;
    }
    // A retried packet repeats its salt and must not be applied twice.
    final repeat = !_salts.add(request.salt);
    if (!repeat) {
      commands.add((command: command, body: request.plain));
      final b = ByteData.sublistView(request.plain);
      if (command == 2) {
        _upload = BytesBuilder();
        _packets = b.getUint16(3);
      } else if (command == 3) {
        _upload?.add(request.plain.sublist(5));
      } else if (command == 4 && _upload != null) {
        programs.add(_upload!.toBytes());
        _upload = null;
        _packets = 0;
      }
    }
    if (dropNext > 0) {
      dropNext--;
      return;
    }
    if (!acknowledge) return;
    if (rejectWith != 0) {
      _reply(d, wire, rejectWith, Uint8List(32), null);
    } else {
      _reply(d, wire, 0, _sessionKey, null);
    }
  }

  int get pendingPackets => _packets;

  void _reply(
    Datagram d,
    Uint8List request,
    int status,
    Uint8List key,
    Uint8List? plain,
  ) {
    final body = plain == null ? Uint8List(0) : fakeAes(true, key, plain);
    final wire = Uint8List(41 + body.length);
    final b = ByteData.sublistView(wire);
    wire[0] = 0x44;
    wire[1] = 0x48;
    b.setUint16(2, wire.length, Endian.little);
    wire[4] = 24;
    wire[17] = 0xc1;
    wire.setRange(18, 22, request, 18);
    wire[22] = request[22];
    b.setInt8(23, status);
    wire.setAll(24, body);
    wire.setAll(
      wire.length - 17,
      fakeHmac(key, wire.sublist(0, wire.length - 17)),
    );
    wire[wire.length - 1] = 0xaa;
    _socket.send(wire, d.address, d.port);
  }

  Uint8List _discovery(List<int> sequence) {
    final wire = Uint8List(224);
    final b = ByteData.sublistView(wire);
    wire[0] = 0x48;
    wire[1] = 0x52;
    for (var i = 0; i < 16; i++) {
      wire[2 + i] = int.parse(idHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    b.setUint16(18, 28);
    wire[20] = 27;
    b.setUint16(22, 193);
    wire.setAll(24, sequence);
    wire.setAll(28, [0, 12, 255, 13, 236, 169, 97, 0, 0, 198, 0, 1]);
    b.setUint16(40, width);
    b.setUint16(42, height);
    wire[44] = 0;
    final units = name.codeUnits;
    for (var i = 0; i < units.length && i < 36; i++) {
      b.setUint16(53 + i * 2, units[i], Endian.little);
    }
    b.setUint16(174, 145);
    wire.setAll(177, ascii.encode(firmware));
    b.setUint16(214, 1);
    wire[217] = 1;
    wire[218] = pwdComplexity;
    b.setUint16(219, 4096);
    var sum = 0;
    for (var i = 0; i < 221; i++) {
      sum += wire[i];
    }
    b.setUint16(221, sum & 0xffff);
    wire[223] = 0xaa;
    return wire;
  }

  void close() => _socket.close();
}
