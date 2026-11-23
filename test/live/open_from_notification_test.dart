import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';

class OpenPort extends FakePort {
  Future<void> Function(String)? action;
  @override
  void setNotificationActionHandler(
    Future<void> Function(String action)? handler,
  ) => action = handler;
}

/// Tapping a notification brings Live forward. Android's side (the pending
/// intent) sends `notificationAction` with "open" through the device channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android passes a notification tap through the device channel',
    () async {
      final port = AndroidPort();
      final seen = <String>[];
      port.setNotificationActionHandler((a) async => seen.add(a));
      addTearDown(() => port.setNotificationActionHandler(null));
      Future<void> send(String method, Object? arguments) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              AndroidPort.channel.name,
              AndroidPort.channel.codec.encodeMethodCall(
                MethodCall(method, arguments),
              ),
              (_) {},
            );
      }

      await send('notificationAction', 'open');
      await send('notificationAction', 'pause');
      expect(seen, ['open', 'pause']);
    },
  );

  test('a tap shows Live whatever the service or controls are doing', () async {
    final p = OpenPort();
    final c = AppController(p);
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline());
    await c.act('start');
    expect(c.liveNavigation.value, 0);
    await p.action!('open');
    expect(c.liveNavigation.value, 1);
    // Locked controls and a phone that is only watching still come to Live.
    c.uiLocked = true;
    await p.action!('open');
    expect(c.liveNavigation.value, 2);
    // It only navigates: the running service is untouched.
    final s = c.state.session;
    expect(s.active, isTrue);
    expect(s.paused, isFalse);
    expect(s.index, 0);
    expect(s.revision, c.state.session.revision);
  });
}
