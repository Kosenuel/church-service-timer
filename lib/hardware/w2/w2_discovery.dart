import 'dart:convert';
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';

/// Strict decoder for the parameter selection physically verified on W2:
/// a Dart port of `W2Discovery.java`. Unknown controllers are recognised
/// as unsupported and are never written to.
class W2Discovery {
  W2Discovery._();
  static const port = 6101;
  static const _query = [0, 12, 255, 13, 236, 169, 97, 0, 0, 198, 0, 1];

  static Uint8List query(int sequence) {
    final wire = Uint8List(42);
    final b = ByteData.sublistView(wire);
    wire.setAll(0, [0x48, 0x54, 0, 27]); // "HT", 0, 27
    b.setUint16(4, 42);
    wire[6] = 27;
    b.setUint32(23, sequence & 0xffffffff);
    wire.setAll(27, _query);
    var sum = 0;
    for (var i = 0; i < 39; i++) {
      sum += wire[i];
    }
    b.setUint16(39, sum & 0xffff);
    wire[41] = 0xaa;
    return wire;
  }

  /// Throws [FormatException] for anything but the one reply layout that
  /// was read from a real sign.
  static Json decode(Uint8List wire, int sequence, String address) {
    if (wire.length != 224)
      throw const FormatException('Unsupported discovery length');
    final b = ByteData.sublistView(wire);
    var sum = 0;
    for (var i = 0; i < wire.length - 3; i++) {
      sum += wire[i];
    }
    if (wire[0] != 0x48 ||
        wire[1] != 0x52 ||
        b.getInt16(18) != 28 ||
        wire[20] != 27 ||
        wire[21] != 0 ||
        b.getUint16(22) != 193 ||
        b.getUint32(24) != (sequence & 0xffffffff) ||
        b.getUint16(221) != (sum & 0xffff) ||
        wire[223] != 0xaa)
      throw const FormatException('Invalid discovery reply');
    // Other presence masks change all offsets: never guess at their layout.
    for (var i = 0; i < _query.length; i++) {
      if (wire[28 + i] != _query[i])
        throw const FormatException('Unsupported parameter selection');
    }
    final id = [
      for (var i = 2; i < 18; i++) wire[i].toRadixString(16).padLeft(2, '0'),
    ].join();
    final nameUnits = [
      for (var i = 0; i < 36; i++) b.getUint16(53 + i * 2, Endian.little),
    ];
    final name = String.fromCharCodes(nameUnits).split('\u0000').first.trim();
    final firmware = ascii
        .decode(wire.sublist(177, 209), allowInvalid: true)
        .split('\u0000')
        .first;
    final width = b.getUint16(40), height = b.getUint16(42), color = wire[44];
    final model = b.getUint16(174),
        protocol = b.getUint16(214),
        chunk = b.getUint16(219);
    final supported =
        width == 32 &&
        height == 16 &&
        color == 0 &&
        model == 145 &&
        protocol == 1 &&
        wire[217] == 1 &&
        chunk >= 393 &&
        chunk <= 4096 &&
        firmware == 'HD_W2 V6.02.232';
    return {
      'id': id,
      'name': name.isEmpty ? 'W2 display' : name,
      'address': address,
      'firmware': firmware,
      'width': width,
      'height': height,
      'color': color,
      'model': model,
      'chunk': chunk,
      'supported': supported,
      'pwdComplexity': wire[218],
    };
  }
}
