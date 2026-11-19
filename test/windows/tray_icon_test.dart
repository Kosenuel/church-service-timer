import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/windows/tray_countdown.dart';
import 'package:church_service_timer/windows/win32_api.dart' as win32;
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import 'desktop_clock_and_storage_test.dart' show FakeProtector;
import 'windows_port_test.dart' show FakeDialogs, FakeSystem, tinosFace;

/// The app on a PC, with the notification-area icon decided by the same
/// [TrayCountdown] the Windows port uses and a fake Windows behind it.
class TrayPort extends FakePort {
  final FakeSystem system;
  late final TrayCountdown tray = TrayCountdown(system.tray);
  TrayPort(this.system);
  @override
  bool get isDesktop => true;
  @override
  Future<void> showTrayCountdown(String? text) async => tray.show(text);
  @override
  Future<void> setTrayCountdown(bool on) async => tray.enabled = on;
  @override
  Future<void> windowClosing() async => tray.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSystem system;
  setUp(() => system = FakeSystem());

  group('during a service', () {
    late TrayPort port;
    late AppController c;

    /// Moves the clock to [seconds] after the start and lets the app see it.
    Future<void> at(int seconds) async {
      port.at = after(seconds);
      await c.tick();
      await c.syncServiceNotification();
    }

    setUp(() async {
      port = TrayPort(system);
      c = AppController(port);
      await c.initialize(startTicker: false);
    });
    tearDown(() => c.dispose());

    test(
      'the icon appears when a service starts and goes when it ends',
      () async {
        await c.syncServiceNotification();
        expect(system.trayCalls, isEmpty, reason: 'nothing is running');
        await c.act('load', value: timeline());
        await c.syncServiceNotification();
        expect(system.trayCalls, isEmpty, reason: 'loaded is not running');
        await c.act('start');
        await at(0);
        expect(system.trayShown, 'First · 10:00 left');
        await c.act('end');
        await c.syncServiceNotification();
        expect(system.trayShown, isNull);
        expect(system.trayCalls.last, isNull);
      },
    );

    test('the tooltip follows the countdown, overtime and pause', () async {
      await c.act('load', value: timeline());
      await c.act('start');
      await at(0);
      expect(system.trayShown, 'First · 10:00 left');
      await at(1);
      expect(system.trayShown, 'First · 09:59 left');
      await at(446);
      expect(system.trayShown, 'First · 02:34 left');
      await at(670);
      expect(system.trayShown, 'First · 01:10 over');
      await c.act('pause');
      await c.syncServiceNotification();
      expect(system.trayShown, 'Paused · First · 01:10 over');
      await c.act('pause');
      await c.act('advance');
      await at(700);
      expect(system.trayShown, 'Second · 04:30 left');
      await c.act('pause');
      await c.syncServiceNotification();
      expect(system.trayShown, 'Paused · Second · 04:30');
      // Time passes; a paused countdown stays as it is.
      final calls = system.trayCalls.length;
      await at(760);
      expect(system.trayShown, 'Paused · Second · 04:30');
      expect(system.trayCalls.length, calls);
    });

    test('Windows is told only when the text changes', () async {
      await c.act('load', value: timeline());
      await c.act('start');
      await at(0);
      expect(system.trayCalls, ['First · 10:00 left']);
      // The app looks at the clock ten times a second.
      for (var i = 0; i < 9; i++) {
        port.at = Stamp(start.mono + 100 * i, start.wall + 100 * i, 'boot-1');
        await c.tick();
        await c.syncServiceNotification();
      }
      expect(system.trayCalls, ['First · 10:00 left']);
      await at(1);
      await at(1);
      await at(2);
      expect(system.trayCalls, [
        'First · 10:00 left',
        'First · 09:59 left',
        'First · 09:58 left',
      ]);
    });

    test('a quick timer shows too, by its name', () async {
      await c.startQuickTimer(const QuickTimerChoice('Offering', 90));
      await at(0);
      expect(system.trayShown, 'Offering · 01:30 left');
    });

    test('the longest name still fits a Windows tooltip', () async {
      await c.act(
        'load',
        value: Timeline('Sunday', [Segment('W' * 80, 10)], DisplaySettings()),
      );
      await c.act('start');
      await at(700);
      await c.act('pause');
      await c.syncServiceNotification();
      final tip = system.trayShown!;
      expect(tip, 'Paused · ${'W' * 80} · 01:40 over');
      expect(tip.length, lessThanOrEqualTo(127));
    });

    test('turned off, nothing shows; turned on again, it comes back', () async {
      await port.setTrayCountdown(false);
      await c.act('load', value: timeline());
      await c.act('start');
      await at(0);
      await at(5);
      expect(system.trayCalls, isEmpty);
      await port.setTrayCountdown(true);
      expect(system.trayShown, 'First · 09:55 left');
      await port.setTrayCountdown(false);
      expect(system.trayShown, isNull);
    });

    test('a system call that fails does not disturb the service', () async {
      system.trayThrows = true;
      await c.act('load', value: timeline());
      expect(await c.act('start'), isTrue);
      await at(0);
      await at(3);
      expect(c.error, isNull);
      expect(c.state.session.active, isTrue);
      expect(system.trayShown, isNull);
      await c.act('end');
      await c.syncServiceNotification();
      expect(c.state.session.active, isFalse);
    });

    test('closing the window takes the icon away for good', () async {
      await c.act('load', value: timeline());
      await c.act('start');
      await at(0);
      await port.windowClosing();
      expect(system.trayShown, isNull);
      await at(1);
      await at(2);
      expect(system.trayShown, isNull);
      expect(system.trayCalls.last, isNull);
    });

    test('a phone is never asked to show it', () async {
      final phoneSystem = FakeSystem();
      final phone = _PhoneWithTray(phoneSystem);
      final pc = AppController(phone);
      await pc.initialize(startTicker: false);
      await pc.act('load', value: timeline());
      await pc.act('start');
      await pc.syncServiceNotification();
      expect(phoneSystem.trayCalls, isEmpty);
      pc.dispose();
    });
  });

  group('TrayCountdown', () {
    test('adds, changes and removes, once each', () {
      final tray = TrayCountdown(system.tray);
      tray.show(null);
      expect(system.trayCalls, isEmpty);
      tray.show('Sermon · 12:34 left');
      tray.show('Sermon · 12:34 left');
      tray.show('Sermon · 12:33 left');
      tray.show(null);
      tray.show(null);
      expect(system.trayCalls, [
        'Sermon · 12:34 left',
        'Sermon · 12:33 left',
        null,
      ]);
    });

    test('after a refusal it waits, then tries again', () {
      final tray = TrayCountdown(system.tray);
      system.trayRefuses = true;
      tray.show('Sermon · 00:00 left');
      expect(system.trayCalls.length, 1);
      for (var i = 1; i <= TrayCountdown.refusedPause; i++) {
        tray.show('Sermon · $i');
      }
      expect(system.trayCalls.length, 1, reason: 'not once a second');
      system.trayRefuses = false;
      tray.show('Sermon · 12:00 left');
      expect(system.trayShown, 'Sermon · 12:00 left');
    });

    test('a call that throws is swallowed, also when removing', () {
      final tray = TrayCountdown(system.tray);
      tray.show('Sermon · 12:34 left');
      system.trayThrows = true;
      expect(() => tray.show('Sermon · 12:33 left'), returnsNormally);
      expect(() => tray.show(null), returnsNormally);
      expect(tray.close, returnsNormally);
      expect(() => tray.enabled = false, returnsNormally);
    });
  });

  group('the Windows port', () {
    late Directory dir;
    WindowsPort port() => WindowsPort(
      dataDir: Directory('${dir.path}/data'),
      monotonicMs: () => 50000,
      wallMs: () => 1700000050000,
      protector: FakeProtector(),
      dialogs: FakeDialogs(),
      system: system,
      loadTinosFace: tinosFace,
    );
    setUp(() => dir = Directory.systemTemp.createTempSync('cst-tray'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('shows the countdown unless turned off, and remembers', () async {
      var p = port();
      expect((await p.notificationStatus())['tray'], isTrue);
      await p.showTrayCountdown('Sermon · 12:34 left');
      expect(system.trayShown, 'Sermon · 12:34 left');
      await p.setTrayCountdown(false);
      expect(system.trayShown, isNull);
      expect((await p.notificationStatus())['tray'], isFalse);
      await p.showTrayCountdown('Sermon · 12:33 left');
      expect(system.trayShown, isNull);
      p.dispose();

      // The app is started again on the same computer.
      system = FakeSystem();
      p = port();
      await p.showTrayCountdown('Sermon · 12:32 left');
      expect(system.trayCalls, isEmpty);
      expect((await p.notificationStatus())['tray'], isFalse);
      await p.setTrayCountdown(true);
      expect(system.trayShown, 'Sermon · 12:32 left');
      p.dispose();

      system = FakeSystem();
      p = port();
      await p.showTrayCountdown('Sermon · 12:31 left');
      expect(system.trayShown, 'Sermon · 12:31 left');
      p.dispose();
    });

    test(
      'the icon is there from the start, and says when nothing runs',
      () async {
        final p = port();
        // Asking for the status is the first thing the app does.
        expect((await p.notificationStatus())['trayState'], 'showing');
        expect(system.trayShown, 'Church Service Timer · no service running');
        await p.showTrayCountdown('Sermon · 12:34 left');
        expect(system.trayShown, 'Sermon · 12:34 left');
        // The service ends: the icon stays, with the idle text.
        await p.showTrayCountdown(null);
        expect(system.trayShown, 'Church Service Timer · no service running');
        await p.setTrayCountdown(false);
        expect(system.trayShown, isNull);
        expect((await p.notificationStatus())['trayState'], 'off');
        p.dispose();
      },
    );

    test('a refusal by Windows is reported, not hidden', () async {
      system.trayRefuses = true;
      final p = port();
      expect((await p.notificationStatus())['trayState'], 'refused');
      expect(system.trayShown, isNull);
      // It keeps trying as the countdown changes, and says when it works.
      system.trayRefuses = false;
      for (var i = 0; i <= TrayCountdown.refusedPause; i++) {
        await p.showTrayCountdown('Sermon · 12:${59 - i} left');
      }
      expect((await p.notificationStatus())['trayState'], 'showing');
      p.dispose();
    });

    test('the icon is removed when the app closes', () async {
      final p = port();
      await p.showTrayCountdown('Sermon · 12:34 left');
      await p.windowClosing();
      expect(system.trayShown, isNull);
      await p.showTrayCountdown('Sermon · 12:33 left');
      expect(system.trayShown, isNull);

      final other = port();
      await other.showTrayCountdown('Sermon · 12:34 left');
      other.dispose();
      expect(system.trayShown, isNull);
    });

    test('a failing system call does not throw', () async {
      final p = port();
      system.trayThrows = true;
      await p.showTrayCountdown('Sermon · 12:34 left');
      await p.showTrayCountdown(null);
      await p.setTrayCountdown(false);
      await p.windowClosing();
      p.dispose();
    });

    test('a phone does nothing with any of it', () async {
      final phone = FakePort();
      await phone.showTrayCountdown('Sermon · 12:34 left');
      await phone.setTrayCountdown(true);
      await phone.windowClosing();
    });
  });

  group('NOTIFYICONDATAW for 64-bit Windows', () {
    int u32(Uint8List b, int at) =>
        ByteData.sublistView(b).getUint32(at, Endian.little);
    int u64(Uint8List b, int at) =>
        ByteData.sublistView(b).getUint64(at, Endian.little);
    String tipOf(Uint8List b) {
      final units = <int>[];
      for (var at = 40; at < 296; at += 2) {
        final unit = ByteData.sublistView(b).getUint16(at, Endian.little);
        if (unit == 0) break;
        units.add(unit);
      }
      return String.fromCharCodes(units);
    }

    test('every field is where Windows reads it', () {
      final data = win32.notifyIconData(
        window: 0x1122334455,
        flags: 0x7,
        icon: 0x66778899AA,
        tip: 'Sermon · 12:34 left',
      );
      expect(data.length, 976);
      expect(u32(data, 0), 976, reason: 'cbSize');
      expect(u32(data, 4), 0, reason: 'padding');
      expect(u64(data, 8), 0x1122334455, reason: 'hWnd');
      expect(u32(data, 16), 1, reason: 'uID');
      expect(u32(data, 20), 0x7, reason: 'uFlags');
      expect(u32(data, 24), 0x8000 + 0x3C7, reason: 'uCallbackMessage');
      expect(u32(data, 28), 0, reason: 'padding');
      expect(u64(data, 32), 0x66778899AA, reason: 'hIcon');
      expect(tipOf(data), 'Sermon · 12:34 left');
      // "·" is one UTF-16 unit, 0x00B7, low byte first.
      expect(data.sublist(40 + 14, 40 + 16), [0xB7, 0x00]);
      expect(
        data.sublist(296).every((byte) => byte == 0),
        isTrue,
        reason: 'no balloon, state or GUID',
      );
    });

    test('a long tooltip is cut to 127 units and still ends with zero', () {
      final data = win32.notifyIconData(window: 1, flags: 4, tip: 'x' * 300);
      expect(tipOf(data), 'x' * 127);
      expect(data.sublist(294, 296), [0, 0]);
      // A character of two units is not cut in half.
      final split = win32.notifyIconData(
        window: 1,
        flags: 4,
        tip: '${'x' * 126}\u{1F600}',
      );
      expect(tipOf(split), 'x' * 126);
    });

    test('the callback message is the one the runner answers', () {
      final runner = File('windows/runner/win32_window.cpp').readAsStringSync();
      expect(win32.trayCallbackMessage, 0x8000 + 0x3C7);
      expect(runner, contains('case WM_APP + 0x3C7:'));
    });
  });
}

/// A phone that would record a call if one were made.
class _PhoneWithTray extends FakePort {
  final FakeSystem system;
  _PhoneWithTray(this.system);
  @override
  Future<void> showTrayCountdown(String? text) async => system.tray(text);
}
