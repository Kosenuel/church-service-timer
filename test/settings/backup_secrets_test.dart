import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/settings/backup_secret_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort, start;

class SecretPort extends FakePort {
  final saved = <String, String>{};
  Map<String, dynamic>? wifi;
  @override
  Future<void> saveDisplayPassword(String id, String password) async =>
      saved[id] = password;
  @override
  Future<void> saveSignWifiProfile(Map<String, dynamic> profile) async =>
      wifi = profile;
}

void main() {
  final secrets = {
    'display': {
      'id': 'sign-1',
      'name': 'Hall sign',
      'devicePassword': 'device-pass',
      'wifi': {
        'ssid': 'HallSign-W2',
        'security': 'wpa2',
        'bssid': '',
        'password': 'wifi-pass-1',
      },
    },
  };

  test('Sealed passwords open only with the right passphrase', () async {
    final sealed = await sealBackupSecrets(
      secrets,
      'correct horse',
      iterations: 10000,
    );
    expect(jsonEncode(sealed), isNot(contains('device-pass')));
    expect(await openBackupSecrets(sealed, 'correct horse'), secrets);
    expect(await openBackupSecrets(sealed, 'wrong horse!'), isNull);
    final tampered = Map<String, dynamic>.from(sealed);
    final data = base64Decode(sealed['data'] as String)..[0] ^= 1;
    tampered['data'] = base64Encode(data);
    expect(await openBackupSecrets(tampered, 'correct horse'), isNull);
    expect(
      () => sealBackupSecrets(secrets, 'short'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'Only backups with passwords use schema 8; plain ones stay at 7',
    () async {
      final state = AppState.fresh(start);
      final plain = exportBackup(state, start);
      expect(jsonDecode(plain)['schemaVersion'], 7);
      expect(backupSavedPasswords(plain), isNull);
      final sealed = await sealBackupSecrets(
        secrets,
        'correct horse',
        iterations: 10000,
      );
      final withPasswords = exportBackup(state, start, savedPasswords: sealed);
      expect(jsonDecode(withPasswords)['schemaVersion'], 8);
      expect(importBackup(withPasswords, start).templates, isNotEmpty);
      expect(backupSavedPasswords(withPasswords), sealed);
      final forged = jsonDecode(plain)..['savedPasswords'] = sealed;
      expect(
        () => importBackup(jsonEncode(forged), start),
        throwsA(anything),
        reason: 'Version 7 backups never carry passwords',
      );
    },
  );

  test('Restored passwords go to encrypted storage on this phone', () async {
    final port = SecretPort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    expect(await c.backupSecrets(), isEmpty, reason: 'No sign remembered');
    expect(await c.restoreBackupSecrets(secrets), 2);
    expect(port.saved, {'sign-1': 'device-pass'});
    expect(port.wifi, {
      'id': 'sign-1',
      'ssid': 'HallSign-W2',
      'security': 'wpa2',
      'bssid': '',
      'password': 'wifi-pass-1',
    });
  });

  testWidgets('Export dialog needs a matching passphrase of 8+ characters', (
    t,
  ) async {
    BackupExportChoice? choice;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showDialog(
              context: context,
              builder: (_) => const BackupExportDialog(hasPasswords: true),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('include-passwords')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('backup-passphrase')), 'short');
    await t.tap(find.text('Export'));
    await t.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('backup-passphrase')),
      'correct horse',
    );
    await t.enterText(
      find.byKey(const ValueKey('backup-passphrase-repeat')),
      'correct horse',
    );
    await t.tap(find.text('Export'));
    await t.pumpAndSettle();
    expect(choice?.includePasswords, isTrue);
    expect(choice?.passphrase, 'correct horse');
  });
}
