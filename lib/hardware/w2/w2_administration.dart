import 'dart:convert';
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';
import 'package:pointycastle/export.dart' as pc;

/// Pure codecs for the sign's own settings: a Dart port of
/// `W2Administration.kt`. See docs/DEVICE-ADMIN-0.13.md. The caller wipes
/// returned bodies after use.
class W2Administration {
  W2Administration._();
  static const wifiCommand = 39;
  static const devicePasswordCommand = 49;
  static const _keySuffix = '64ACFEB8B6FE4EF082DB8F3CD428EB20';

  /// Deliberately limited to the exact firmware and capability physically
  /// read.
  static bool supported(Json device) =>
      device['supported'] == true &&
      device['firmware'] == 'HD_W2 V6.02.232' &&
      (device['pwdComplexity'] as num?)?.toInt() == 1;

  static Uint8List ssidBody(String newSsid) {
    require(
      RegExp(r'^[A-Za-z0-9_-]{4,16}$').hasMatch(newSsid),
      'Use 4–16 letters, digits, underscores or hyphens for the Wi-Fi name.',
    );
    return _wifiParameter(4, Uint8List.fromList(utf8.encode(newSsid)));
  }

  static Uint8List wifiPasswordBody(String password) {
    validateNewPassword(password);
    final bytes = Uint8List.fromList(utf8.encode(password));
    try {
      return _wifiParameter(5, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Uint8List devicePasswordBody(String password) {
    validateNewPassword(password);
    final joined = Uint8List.fromList(utf8.encode(password + _keySuffix));
    try {
      final digest = pc.MD5Digest().process(joined);
      final body = Uint8List(20);
      body[0] = 4;
      body[1] = 2;
      ByteData.sublistView(body).setUint16(2, 16);
      body.setAll(4, digest);
      digest.fillRange(0, digest.length, 0);
      return body;
    } finally {
      joined.fillRange(0, joined.length, 0);
    }
  }

  /// Conservative subset of LedArt's 8–16 character validation.
  static void validateNewPassword(String password) {
    final codes = password.codeUnits;
    require(
      codes.length >= 8 &&
          codes.length <= 16 &&
          codes.every((c) => c >= 0x21 && c <= 0x7e),
      'Use 8–16 visible English characters without spaces.',
    );
    require(codes.any((c) => c != codes[0]), 'Use a varied password.');
    final step = codes[1] - codes[0];
    require(
      Iterable.generate(
        codes.length - 2,
        (i) => i + 2,
      ).any((i) => codes[i] - codes[i - 1] != step),
      'Avoid a simple sequence of characters.',
    );
  }

  static Uint8List _wifiParameter(int parameter, Uint8List bytes) {
    final body = Uint8List(8 + bytes.length);
    final b = ByteData.sublistView(body);
    body[0] = 8;
    body[1] = 0;
    b.setUint16(2, parameter);
    b.setUint32(4, bytes.length);
    body.setAll(8, bytes);
    return body;
  }
}
