import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// HD7 wire codec for the W2 controller: a line-for-line Dart port of
/// `Hd7Auth.java`, used where the app talks to the sign from Dart
/// (Windows). No network I/O, logging or credential persistence.
///
/// Thrown for a reply that is malformed, unmatched or fails authentication.
class Hd7SecurityError implements Exception {
  final String message;
  Hd7SecurityError(this.message);
  @override
  String toString() => message;
}

const _passwordSuffix = '64ACFEB8B6FE4EF082DB8F3CD428EB20';

Uint8List _md5(Uint8List bytes) => pc.MD5Digest().process(bytes);

Uint8List _hmac(Uint8List key, Uint8List bytes, int count) {
  final mac = pc.HMac(pc.MD5Digest(), 64)..init(pc.KeyParameter(key));
  mac.update(bytes, 0, count);
  final out = Uint8List(16);
  mac.doFinal(out, 0);
  return out;
}

Uint8List _aes(bool encrypt, Uint8List key, Uint8List input) {
  final cipher = pc.PaddedBlockCipherImpl(
    pc.PKCS7Padding(),
    pc.ECBBlockCipher(pc.AESEngine()),
  )..init(encrypt, pc.PaddedBlockCipherParameters(pc.KeyParameter(key), null));
  return cipher.process(input);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

void _wipe(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);

class Hd7Request {
  final Uint8List _wire, _key;
  final int command, messageId;
  bool _closed = false;
  Hd7Request._(this._wire, Uint8List key, this.command, this.messageId)
    : _key = Uint8List.fromList(key);
  Uint8List bytes() {
    _checkOpen();
    return Uint8List.fromList(_wire);
  }

  void _checkOpen() {
    if (_closed) throw StateError('Request closed');
  }

  void close() {
    _wipe(_key);
    _wipe(_wire);
    _closed = true;
  }
}

class Hd7Reply {
  final int status, flags;
  final Uint8List _plaintext;
  Hd7Reply._(this.status, this.flags, this._plaintext);
  Uint8List body() => Uint8List.fromList(_plaintext);
  Hd7Session loginSession() {
    if (status != 0)
      throw Hd7SecurityError('Controller rejected login: $status');
    if (flags & 1 == 0 || _plaintext.length != 24)
      throw Hd7SecurityError('Invalid login result');
    return Hd7Session._(
      Uint8List.fromList(_plaintext.sublist(0, 8)),
      Uint8List.fromList(_plaintext.sublist(8, 24)),
    );
  }

  void close() => _wipe(_plaintext);
}

class Hd7Session {
  final Uint8List _id, _key;
  int _salt = 0;
  bool _closed = false;
  Hd7Session._(this._id, this._key);
  Hd7Request command(int command, Uint8List plaintext) {
    if (_closed) throw StateError('Session closed');
    if (command <= 0 || command > 127) throw ArgumentError('Invalid command');
    if (_salt == 0x7fffffff)
      throw Hd7SecurityError('Session sequence exhausted');
    return Hd7Auth._packet(command, plaintext, _id, _key, ++_salt);
  }

  void close() {
    _wipe(_id);
    _wipe(_key);
    _closed = true;
  }
}

class Hd7Auth {
  Hd7Auth._();
  static final _random = math.Random.secure();

  /// Replaced in tests so a packet can be compared byte for byte.
  static int Function() nextMessageId = _randomId;
  static int _randomId() => _random.nextInt(1 << 32);

  static Uint8List passwordKey(String password) {
    if (password.isEmpty) return _md5(Uint8List(32));
    final input = Uint8List.fromList(utf8.encode(password + _passwordSuffix));
    try {
      return _md5(input);
    } finally {
      _wipe(input);
    }
  }

  static Hd7Request login(
    String password,
    String installationId,
    String applicationName, {
    DateTime? now,
  }) {
    final key = passwordKey(password);
    try {
      return loginWithDerivedKey(
        key,
        installationId,
        applicationName,
        now: now,
      );
    } finally {
      _wipe(key);
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static Hd7Request loginWithDerivedKey(
    Uint8List key,
    String installationId,
    String applicationName, {
    DateTime? now,
  }) {
    if (key.length != 16 ||
        !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(installationId) ||
        !RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(applicationName))
      throw ArgumentError('Invalid login arguments');
    final t = now ?? DateTime.now();
    final timestamp =
        '${t.year.toString().padLeft(4, '0')}/${_two(t.month)}/${_two(t.day)} '
        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    final log = Uint8List.fromList(
      utf8.encode('${installationId}__${timestamp}_$applicationName'),
    );
    final identity = _md5(Uint8List.fromList(utf8.encode(installationId)));
    final plaintext = Uint8List(4 + log.length);
    try {
      for (var group = 0; group < 4; group++) {
        var sum = 0;
        for (var i = 0; i < 4; i++) {
          sum += identity[group * 4 + i];
        }
        plaintext[group] = sum & 255;
      }
      plaintext.setAll(4, log);
      return _packet(0, plaintext, Uint8List(8), key, 0);
    } finally {
      _wipe(log);
      _wipe(identity);
      _wipe(plaintext);
    }
  }

  static Hd7Request _packet(
    int command,
    Uint8List plaintext,
    Uint8List session,
    Uint8List key,
    int salt,
  ) {
    if (session.length != 8 || key.length != 16)
      throw ArgumentError('Invalid packet arguments');
    final encrypt = command != 3 && command != 25;
    final body = encrypt
        ? _aes(true, key, plaintext)
        : Uint8List.fromList(plaintext);
    Uint8List? tag;
    try {
      final length = body.length + 40;
      if (length > 32767) throw ArgumentError('Packet too large');
      final messageId = nextMessageId() & 0xffffffff;
      final wire = Uint8List(length);
      final b = ByteData.sublistView(wire);
      wire[0] = 0x48; // H
      wire[1] = 0x44; // D
      b.setUint16(2, length, Endian.little);
      wire[4] = 23;
      wire.setAll(5, session);
      b.setUint32(13, salt, Endian.little);
      wire[17] = encrypt ? 0xc1 : 0xc0;
      b.setUint32(18, messageId, Endian.little);
      wire[22] = command;
      wire.setAll(23, body);
      tag = _hmac(key, wire, length - 17);
      wire.setAll(length - 17, tag);
      wire[length - 1] = 0xaa;
      return Hd7Request._(wire, key, command, messageId);
    } finally {
      _wipe(body);
      _wipe(tag);
    }
  }

  /// Verify the UDP peer separately; pass the exact datagram bytes.
  static Hd7Reply decode(
    Hd7Request request,
    Uint8List wire,
    int maxPacketLength,
  ) {
    request._checkOpen();
    if (wire.length < 41 ||
        wire.length > maxPacketLength ||
        wire.length > 32767)
      throw Hd7SecurityError('Invalid response length');
    final b = ByteData.sublistView(wire);
    if (wire[0] != 0x44 ||
        wire[1] != 0x48 ||
        b.getUint16(2, Endian.little) != wire.length ||
        wire[4] != 24 ||
        wire[wire.length - 1] != 0xaa)
      throw Hd7SecurityError('Invalid response framing');
    if (wire[22] != request.command ||
        b.getUint32(18, Endian.little) != request.messageId)
      throw Hd7SecurityError('Unmatched response');
    final status = b.getInt8(23), flags = wire[17];
    final verificationKey = status == 0 ? request._key : Uint8List(32);
    Uint8List? expected, supplied, body;
    try {
      expected = _hmac(verificationKey, wire, wire.length - 17);
      supplied = Uint8List.fromList(
        wire.sublist(wire.length - 17, wire.length - 1),
      );
      if (!_equal(expected, supplied))
        throw Hd7SecurityError('Response authentication failed');
      if (status != 0) return Hd7Reply._(status, flags, Uint8List(0));
      body = Uint8List.fromList(wire.sublist(24, wire.length - 17));
      // W2 acknowledgements can have an empty body with the encryption bit
      // set. Their status and entire header have already passed HMAC
      // verification.
      if (flags & 1 != 0 && body.length % 16 != 0)
        throw Hd7SecurityError('Invalid encrypted body');
      final Uint8List plain;
      try {
        plain = flags & 1 != 0 && body.isNotEmpty
            ? _aes(false, request._key, body)
            : Uint8List.fromList(body);
      } on Hd7SecurityError {
        rethrow;
      } catch (_) {
        throw Hd7SecurityError('Invalid encrypted body');
      }
      if (request.command == 0 && (flags & 1 == 0 || plain.length != 24)) {
        _wipe(plain);
        throw Hd7SecurityError('Invalid login result');
      }
      return Hd7Reply._(status, flags, plain);
    } finally {
      _wipe(expected);
      _wipe(supplied);
      _wipe(body);
    }
  }
}
