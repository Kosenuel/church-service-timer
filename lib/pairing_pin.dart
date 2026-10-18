import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:pointycastle/srp/srp6_client.dart';
import 'package:pointycastle/srp/srp6_server.dart';
import 'package:pointycastle/srp/srp6_standard_groups.dart';
import 'package:pointycastle/srp/srp6_verifier_generator.dart';
import 'domain.dart';

// SRP-6a authenticates the short code without transmitting it or using it as
// an encryption key. The only accepted group is RFC 5054's 3072-bit group.
final pairPinGroup = SRP6StandardGroups.rfc5054_3072;
final _identity = Uint8List.fromList(utf8.encode('CST2 pairing'));
Uint8List _bytes(int count) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
}

pc.SecureRandom _random() =>
    pc.FortunaRandom()..seed(pc.KeyParameter(_bytes(32)));
String createPairPin() =>
    Random.secure().nextInt(1000000).toString().padLeft(6, '0');
bool validPairPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

BigInt pairNumber(dynamic value, {bool proof = false}) {
  require(
    value is String &&
        value.isNotEmpty &&
        value.length <= (proof ? 64 : 768) &&
        RegExp(r'^[0-9a-f]+$').hasMatch(value),
    'Invalid pairing proof.',
  );
  final number = BigInt.parse(value as String, radix: 16);
  require(
    proof || (number > BigInt.zero && number < pairPinGroup.N),
    'Invalid pairing public value.',
  );
  return number;
}

Future<SecretKey> _key(BigInt value, String challenge) {
  final hex = value.toRadixString(16).padLeft(64, '0');
  final bytes = List.generate(
    32,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  );
  return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(bytes),
    nonce: utf8.encode(challenge),
    info: utf8.encode('CST2 SRP-6a session'),
  );
}

class PairPinInvitation {
  final Uint8List salt = _bytes(32);
  late final BigInt verifier;
  PairPinInvitation(String pin) {
    require(validPairPin(pin), 'Enter the six-digit code.');
    verifier = SRP6VerifierGenerator(
      group: pairPinGroup,
      digest: pc.SHA256Digest(),
    ).generateVerifier(salt, _identity, Uint8List.fromList(utf8.encode(pin)));
  }
  SRP6Server server() => SRP6Server(
    group: pairPinGroup,
    v: verifier,
    digest: pc.SHA256Digest(),
    random: _random(),
  );
  Future<SecretKey> sessionKey(SRP6Server server, String challenge) =>
      _key(server.calculateSessionKey()!, challenge);
}

class PairPinClient {
  final client = SRP6Client(
    group: pairPinGroup,
    digest: pc.SHA256Digest(),
    random: _random(),
  );
  String start(dynamic salt, String pin) {
    require(
      validPairPin(pin) && salt is String && salt.length <= 48,
      'Enter the six-digit code.',
    );
    final bytes = base64Decode(salt as String);
    require(bytes.length == 32, 'Invalid pairing salt.');
    return client
        .generateClientCredentials(
          bytes,
          _identity,
          Uint8List.fromList(utf8.encode(pin)),
        )!
        .toRadixString(16);
  }

  String prove(dynamic serverB) {
    client.calculateSecret(pairNumber(serverB));
    return client.calculateClientEvidenceMessage()!.toRadixString(16);
  }

  Future<SecretKey> finish(dynamic proof, String challenge) {
    require(
      client.verifyServerEvidenceMessage(pairNumber(proof, proof: true)),
      'The host could not verify this code.',
    );
    return _key(client.calculateSessionKey()!, challenge);
  }
}
