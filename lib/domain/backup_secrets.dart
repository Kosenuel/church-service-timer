import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Saved passwords optionally sealed inside a backup with a passphrase the
/// person chooses. Without the passphrase the rest of the backup still
/// restores; the passwords are simply skipped.
const backupSecretsIterations = 120000;
const minimumBackupPassphrase = 8;

final _cipher = AesGcm.with256bits();

Future<SecretKey> _key(String passphrase, List<int> salt, int iterations) =>
    Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);

Future<Map<String, dynamic>> sealBackupSecrets(
  Map<String, dynamic> secrets,
  String passphrase, {
  int iterations = backupSecretsIterations,
}) async {
  if (passphrase.length < minimumBackupPassphrase)
    throw ArgumentError('Use a passphrase of at least 8 characters.');
  final r = Random.secure();
  final salt = List.generate(16, (_) => r.nextInt(256));
  final box = await _cipher.encrypt(
    utf8.encode(jsonEncode(secrets)),
    secretKey: await _key(passphrase, salt, iterations),
  );
  return {
    'v': 1,
    'kdf': 'pbkdf2-sha256',
    'iterations': iterations,
    'cipher': 'aes-256-gcm',
    'salt': base64Encode(salt),
    'nonce': base64Encode(box.nonce),
    'data': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };
}

/// Returns the secrets, or null when the passphrase is wrong or the sealed
/// block was altered.
Future<Map<String, dynamic>?> openBackupSecrets(
  Map<String, dynamic> sealed,
  String passphrase,
) async {
  if (sealed['v'] != 1 ||
      sealed['kdf'] != 'pbkdf2-sha256' ||
      sealed['cipher'] != 'aes-256-gcm')
    throw const FormatException('Unsupported saved-password format.');
  final iterations = sealed['iterations'];
  if (iterations is! int || iterations < 10000 || iterations > 2000000)
    throw const FormatException('Unsupported saved-password format.');
  try {
    final clear = await _cipher.decrypt(
      SecretBox(
        base64Decode(sealed['data'] as String),
        nonce: base64Decode(sealed['nonce'] as String),
        mac: Mac(base64Decode(sealed['mac'] as String)),
      ),
      secretKey: await _key(
        passphrase,
        base64Decode(sealed['salt'] as String),
        iterations,
      ),
    );
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)));
  } on SecretBoxAuthenticationError {
    return null;
  }
}
