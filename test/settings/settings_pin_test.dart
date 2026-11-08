import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  test('PIN and recovery are stored only as salted hashes', () async {
    final lock = await SettingsLock.create('2468', 'ABCD-EFGH');
    expect(lock.toJson().toString(), isNot(contains('2468')));
    expect(await lock.checkPin('2468'), isTrue);
    expect(await lock.checkPin('2469'), isFalse);
    expect(await lock.checkRecovery('abcd efgh'), isTrue);
    expect(SettingsLock.validPin('123'), isFalse);
    expect(SettingsLock.validPin('123456789'), isFalse);
    expect(
      SettingsLock.newRecoveryCode(),
      matches(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$'),
    );
    final restored = SettingsLock.fromJson(lock.toJson());
    expect(await restored.checkPin('2468'), isTrue);
  });

  test('Backups never carry the Settings PIN', () async {
    final s = AppState.fresh(start)
      ..settingsLock = await SettingsLock.create('2468', 'ABCD-EFGH');
    expect(exportBackup(s, start), isNot(contains('settingsLock')));
    final again = AppState.fromJson(s.toJson());
    expect(again.settingsLock, isNotNull);
  });

  test('Wrong PINs throttle; the recovery code works once', () async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final recovery = (await c.setSettingsPin('2468'))!;
    expect(c.settingsLocked, isFalse);
    c.lockSettings();
    expect(c.settingsLocked, isTrue);
    for (var i = 0; i < 5; i++) {
      expect(await c.unlockSettings('0000'), isFalse);
    }
    expect(c.pinRetryAfter, isNotNull);
    expect(await c.unlockSettings('2468'), isFalse, reason: 'still waiting');
    expect(await c.recoverSettings('WRONG-CODE'), isFalse);
    expect(await c.recoverSettings(recovery), isTrue);
    expect(c.state.settingsLock, isNull);
    expect(c.settingsLocked, isFalse);
    expect(await c.recoverSettings(recovery), isFalse);
  });

  testWidgets(
    'A locked phone asks for the PIN for Settings and deleting only',
    (t) async {
      t.view.physicalSize = const Size(430, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.runAsync(() => c.setSettingsPin('2468'));
      c.lockSettings();
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(find.text('Settings are locked'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('pin-field')), '1111');
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('Unlock'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await t.pumpAndSettle();
      expect(find.text('That PIN is not correct.'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Display settings'), findsNothing);
      // Programs stay open, but deleting asks for the PIN.
      await t.tap(find.text('Programs'));
      await t.pumpAndSettle();
      final name = c.state.templates.first.name;
      await t.longPress(find.byKey(ValueKey('template-row:$name')));
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.byKey(const ValueKey('delete-selected-programs')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('delete-selected-programs')));
      await t.pumpAndSettle();
      expect(find.text('Settings are locked'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('pin-field')), '2468');
      await t.pump();
      await t.runAsync(() async {
        await t.tap(find.text('Unlock'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await t.pumpAndSettle();
      expect(find.text('Delete 1 program?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.templates.any((p) => p.name == name), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
}
