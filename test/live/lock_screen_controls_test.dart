import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import '../support/fake_port.dart';

class NotifyPort extends FakePort {
  final cards = <Json>[];
  Future<void> Function(String)? action;
  @override
  Future<void> updateServiceNotification(Json card) async => cards.add(card);
  @override
  void setNotificationActionHandler(
    Future<void> Function(String action)? handler,
  ) => action = handler;
}

void main() {
  Future<(AppController, NotifyPort)> running() async {
    final p = NotifyPort();
    final c = AppController(p);
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline());
    await c.act('start');
    return (c, p);
  }

  test(
    'An active service shows the card without starting the foreground service',
    () async {
      final (c, p) = await running();
      expect(c.backgroundActive, isFalse);
      final card = p.cards.last;
      expect(card['active'], isTrue);
      expect(card['segment'], c.state.session.timeline!.segments.first.name);
      expect(card['deadlineWall'], isA<int>());
      expect(card['canPause'], isTrue);
      expect(card['canNext'], isTrue);
    },
  );

  test('The card is only sent when something visible changes', () async {
    final (c, p) = await running();
    final sent = p.cards.length;
    p.at = after(5);
    await c.tick();
    await c.tick();
    expect(p.cards.length, sent);
    await c.act('pause');
    expect(p.cards.last['paused'], isTrue);
    expect(p.cards.last.containsKey('deadlineWall'), isFalse);
  });

  test('Notification Pause and Next act like the Live buttons', () async {
    final (c, p) = await running();
    await p.action!('pause');
    expect(c.state.session.paused, isTrue);
    await p.action!('pause');
    expect(c.state.session.paused, isFalse);
    await p.action!('next');
    expect(c.state.session.index, 1);
  });

  test('Locked controls ignore notification actions', () async {
    final (c, p) = await running();
    c.uiLocked = true;
    await p.action!('pause');
    expect(c.state.session.paused, isFalse);
    expect(c.serviceCard()['canPause'], isFalse);
    c.uiLocked = false;
    await p.action!('pause');
    expect(c.state.session.paused, isTrue);
  });

  test('Turning lock-screen controls off clears the card', () async {
    final (c, p) = await running();
    await c.commit((draft, _) => draft.lockScreenControls = false);
    await c.syncActiveService();
    expect(p.cards.last['active'], isFalse);
  });

  test('Ending the service clears the card', () async {
    final (c, p) = await running();
    await c.act('end');
    await c.syncActiveService();
    expect(p.cards.last['active'], isFalse);
  });

  test('The preference is saved but not part of portable backups', () async {
    final (c, _) = await running();
    await c.commit((draft, _) => draft.lockScreenControls = false);
    final saved = AppState.fromJson(c.state.toJson(), now: c.now);
    expect(saved.lockScreenControls, isFalse);
    expect(exportBackup(c.state, c.now), isNot(contains('lockScreenControls')));
  });
}
