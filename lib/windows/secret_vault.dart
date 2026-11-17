import 'dart:convert';
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/windows/atomic_store.dart';

/// Turns a secret into bytes only this user on this PC can turn back.
/// On Windows that is DPAPI; tests use a reversible fake.
abstract class SecretProtector {
  Uint8List protect(Uint8List plain, Uint8List entropy);
  Uint8List unprotect(Uint8List cipher, Uint8List entropy);
}

/// Opt-in local storage for LED sign passwords and pairings: the desktop
/// counterpart of DisplayCredentialVault.kt. Each entry is bound to its id,
/// so a value copied under another id does not open. Never part of a plain
/// backup or of diagnostics.
class SecretVault {
  final JsonPrefs _store;
  final SecretProtector _protector;
  final int maxLength;
  SecretVault(this._store, this._protector, {this.maxLength = 128});

  Future<void> save(String id, String secret) async {
    require(
      id.trim().isNotEmpty &&
          id.length <= 200 &&
          secret.isNotEmpty &&
          secret.length <= maxLength,
      'This value cannot be saved.',
    );
    final plain = Uint8List.fromList(utf8.encode(secret));
    try {
      final sealed = _protector.protect(
        plain,
        Uint8List.fromList(utf8.encode(id)),
      );
      await _store.set(id, base64Encode(sealed));
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<bool> contains(String id) => _store.contains(id);

  Future<String?> read(String id) async {
    final value = await _store.get(id);
    if (value == null) return null;
    try {
      final plain = _protector.unprotect(
        base64Decode(value as String),
        Uint8List.fromList(utf8.encode(id)),
      );
      try {
        return utf8.decode(plain);
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
    } catch (_) {
      throw RuleError(
        'Saved credential unavailable. Forget it and enter the password again.',
      );
    }
  }

  Future<void> forget(String id) => _store.remove(id);
}
