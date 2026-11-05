import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Optional PIN that guards Settings, deletion and sign administration.
/// Only salted PBKDF2 hashes are stored; the one-time recovery code can clear
/// the PIN once if it is forgotten.
class SettingsLock {
  final String salt, pinHash;
  final String? recoveryHash;
  const SettingsLock(this.salt, this.pinHash, this.recoveryHash);

  factory SettingsLock.fromJson(Map<String, dynamic> j) {
    final salt = j['salt'], pin = j['pinHash'], recovery = j['recoveryHash'];
    if (salt is! String ||
        pin is! String ||
        (recovery != null && recovery is! String))
      throw const FormatException('Invalid Settings PIN.');
    return SettingsLock(salt, pin, recovery as String?);
  }
  Map<String, dynamic> toJson() => {
    'salt': salt,
    'pinHash': pinHash,
    'recoveryHash': recoveryHash,
  };

  static bool validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  /// Eight characters without look-alikes, shown as XXXX-XXXX.
  static String newRecoveryCode([Random? random]) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = random ?? Random.secure();
    final raw = List.generate(8, (_) => alphabet[r.nextInt(alphabet.length)]);
    return '${raw.take(4).join()}-${raw.skip(4).join()}';
  }

  static String normaliseRecovery(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static Future<SettingsLock> create(String pin, String recovery) async {
    final r = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => r.nextInt(256)));
    return SettingsLock(
      salt,
      await _hash(pin, salt),
      await _hash(normaliseRecovery(recovery), salt),
    );
  }

  Future<bool> checkPin(String pin) async =>
      _same(await _hash(pin, salt), pinHash);
  Future<bool> checkRecovery(String code) async =>
      recoveryHash != null &&
      _same(await _hash(normaliseRecovery(code), salt), recoveryHash!);

  static Future<String> _hash(String secret, String salt) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 20000,
      bits: 256,
    ).deriveKeyFromPassword(password: secret, nonce: base64Decode(salt));
    return base64Encode(await key.extractBytes());
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
