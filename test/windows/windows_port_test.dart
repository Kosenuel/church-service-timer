import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/w2_program.dart';
import 'package:church_service_timer/windows/desktop_files.dart';
import 'package:church_service_timer/windows/desktop_images.dart';
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_w2_controller.dart';
import 'desktop_clock_and_storage_test.dart' show FakeProtector;

class FakeDialogs implements FileDialogs {
  String? openResult, saveResult, folderResult;
  final asked = <String>[];
  @override
  Future<String?> open({
    required String label,
    required List<String> extensions,
  }) async {
    asked.add('open ${extensions.join(',')}');
    return openResult;
  }

  @override
  Future<String?> save({
    required String suggestedName,
    required String label,
    required List<String> extensions,
  }) async {
    asked.add('save $suggestedName ${extensions.join(',')}');
    return saveResult;
  }

  @override
  Future<String?> folder() async {
    asked.add('folder');
    return folderResult;
  }
}

class FakeSystem implements DesktopSystem {
  final opened = <String>[];
  final awake = <String>[];
  int flashes = 0, raises = 0;
  final notices = <String>[];
  @override
  void notify(
    String title,
    String body, {
    int clearSeconds = 30,
    bool sound = false,
  }) => notices.add('$title | $body | $clearSeconds${sound ? ' | sound' : ''}');
  bool canOpen = true;
  @override
  bool open(String target) {
    opened.add(target);
    return canOpen;
  }

  @override
  void keepAwake({required bool system, required bool display}) =>
      awake.add('${system ? 'system' : '-'}/${display ? 'display' : '-'}');
  @override
  Json power() => {'level': 81, 'charging': true};
  @override
  void flash() => flashes++;
  @override
  void raise() => raises++;

  /// Every call to the notification-area icon: the tooltip, or null for
  /// "remove". [trayShown] is what Windows would be showing now.
  final trayCalls = <String?>[];
  String? trayShown;
  bool trayRefuses = false, trayThrows = false;
  @override
  bool tray(String? tip) {
    trayCalls.add(tip);
    if (trayThrows) throw StateError('Shell_NotifyIconW is not there');
    if (trayRefuses) return false;
    trayShown = tip;
    return true;
  }

  @override
  String description() => 'Windows PC · test';
}

Future<Uint8List> tinosFace(String style) => File(
  'android/app/src/main/assets/display_fonts/tinos/Tinos-$style.ttf',
).readAsBytes();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeDialogs dialogs;
  late FakeSystem system;
  late int mono;
  WindowsPort port() => WindowsPort(
    dataDir: Directory('${dir.path}/data'),
    monotonicMs: () => mono,
    wallMs: () => 1700000000000 + mono,
    protector: FakeProtector(),
    dialogs: dialogs,
    system: system,
    loadTinosFace: tinosFace,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cst-port');
    dialogs = FakeDialogs();
    system = FakeSystem();
    mono = 50000;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('is a desktop, and Android is not', () {
    expect(port().isDesktop, isTrue);
    expect(AndroidPort().isDesktop, isFalse);
  });

  test('state survives an app restart and the clock keeps its run', () async {
    final first = port();
    expect(await first.load(), isNull);
    final at = await first.clock();
    await first.save('{"session":{"phase":"idle"}}');
    mono += 5000;
    final second = port();
    expect(await second.load(), '{"session":{"phase":"idle"}}');
    final later = await second.clock();
    expect(later.sameBoot(at), isTrue);
    expect(later.since(at), 5000);
    expect(File('${dir.path}/data/service-state.json').existsSync(), isTrue);
  });

  test(
    'import reads the chosen file; closing the dialog is not an error',
    () async {
      final p = port();
      expect(await p.pickFile(), isNull);
      expect(await p.pickBackup(), isNull);
      final file = File('${dir.path}/Sunday.json')
        ..writeAsStringSync('{"n":1}');
      dialogs.openResult = file.path;
      expect(await p.pickFile(), {'name': 'Sunday.json', 'content': '{"n":1}'});
      expect(dialogs.asked.last, 'open csv,json');
    },
  );

  test(
    'export writes where the person chose, adding a missing extension',
    () async {
      final p = port();
      await p.exportFile('Sunday.json', '{"a":1}');
      expect(dir.listSync().whereType<File>(), isEmpty);
      dialogs.saveResult = '${dir.path}/out.json';
      await p.exportFile('Sunday.json', '{"a":1}');
      expect(File('${dir.path}/out.json').readAsStringSync(), '{"a":1}');
      dialogs.saveResult = '${dir.path}/typed-name';
      await p.exportFile('plan.csv', 'a,b');
      expect(File('${dir.path}/typed-name.csv').readAsStringSync(), 'a,b');
      expect(dialogs.asked.last, 'save plan.csv csv');
      expect(File('${dir.path}/typed-name.csv.part').existsSync(), isFalse);
    },
  );

  test('sharing saves one file by name and several into a folder', () async {
    final p = port();
    final pdf = SharedFile(
      'Report.pdf',
      Uint8List.fromList([1, 2, 3]),
      'application/pdf',
    );
    expect(await p.shareFiles([pdf]), isFalse);
    dialogs.saveResult = '${dir.path}/Report.pdf';
    expect(await p.shareFiles([pdf]), isTrue);
    expect(File('${dir.path}/Report.pdf').readAsBytesSync(), [1, 2, 3]);

    final two = [
      SharedFile.text('a.csv', 'one', 'text/csv'),
      SharedFile.text('Report.pdf', 'new', 'application/pdf'),
    ];
    expect(await p.shareFiles(two), isFalse);
    dialogs.folderResult = dir.path;
    expect(await p.shareFiles(two), isTrue);
    expect(File('${dir.path}/a.csv').readAsStringSync(), 'one');
    // The earlier Report.pdf is kept; the new one gets its own name.
    expect(File('${dir.path}/Report.pdf').readAsBytesSync(), [1, 2, 3]);
    expect(File('${dir.path}/Report (2).pdf').readAsStringSync(), 'new');
    expect(await p.shareFiles([]), isFalse);
  });

  test(
    'a file opened with the app is offered once and raises the window',
    () async {
      final p = port();
      var calls = 0;
      p.setIncomingFileHandler(() async => calls++);
      expect(await p.takeIncomingFile(), isNull);
      final file = File('${dir.path}/plan.csv')..writeAsStringSync('a,b');
      p.offerIncomingFile(file.path);
      expect(calls, 1);
      expect(system.raises, 1);
      expect(await p.takeIncomingFile(), {
        'name': 'plan.csv',
        'content': 'a,b',
      });
      expect(await p.takeIncomingFile(), isNull);
      p.offerIncomingFile('${dir.path}/photo.png');
      await expectLater(p.takeIncomingFile(), throwsA(isA<RuleError>()));
    },
  );

  test(
    'sign passwords and pairings are sealed and survive a restart',
    () async {
      await port().saveDisplayPassword('sign-1', 'Sign1234');
      await port().savePairing('{"hosts":[]}');
      expect(await port().savedDisplayPassword('sign-1'), 'Sign1234');
      expect(await port().loadPairing(), '{"hosts":[]}');
      for (final f in Directory(
        '${dir.path}/data',
      ).listSync().whereType<File>()) {
        expect(
          f.readAsStringSync(),
          isNot(contains('Sign1234')),
          reason: f.path,
        );
      }
      await port().forgetDisplayPassword('sign-1');
      expect(await port().savedDisplayPassword('sign-1'), isNull);
      expect(await port().loadPairing(), '{"hosts":[]}');
    },
  );

  test('sign Wi-Fi details are kept for backups but never joined', () async {
    final p = port();
    expect(await p.signWifiProfile('sign-1'), {
      'ssid': '',
      'security': 'wpa2',
      'bssid': '',
      'passwordSaved': false,
      'supported': false,
      'wifiEnabled': true,
    });
    await p.saveSignWifiProfile({
      'id': 'sign-1',
      'ssid': 'HD-W2-1234',
      'security': 'wpa2',
      'password': 'wifi-pass-1',
      'bssid': '',
    });
    final saved = await port().signWifiProfile('sign-1');
    expect(saved['ssid'], 'HD-W2-1234');
    expect(saved['passwordSaved'], isTrue);
    expect(await port().savedDisplayPassword('wifi:sign-1'), 'wifi-pass-1');
    expect(await p.joinSignWifi('sign-1'), isFalse);
    // Keeping the same network keeps its password; a new one needs it.
    await p.saveSignWifiProfile({
      'id': 'sign-1',
      'ssid': 'HD-W2-1234',
      'security': 'wpa2',
      'bssid': 'aa:bb:cc:dd:ee:ff',
    });
    await expectLater(
      p.saveSignWifiProfile({
        'id': 'sign-1',
        'ssid': 'Other',
        'security': 'wpa2',
      }),
      throwsA(isA<RuleError>()),
    );
    await expectLater(
      p.saveSignWifiProfile({
        'id': 'sign-1',
        'ssid': 'HD-W2-1234',
        'security': 'wep',
      }),
      throwsA(isA<RuleError>()),
    );
    await p.saveSignWifiProfile({
      'id': 'sign-1',
      'ssid': 'Open',
      'security': 'open',
    });
    expect((await p.signWifiProfile('sign-1'))['passwordSaved'], isFalse);
    await p.openWifiSettings();
    expect(system.opened.last, 'ms-settings:network-wifi');
  });

  test('a joined host\'s Wi-Fi is remembered the same way', () async {
    final p = port();
    await p.savePairWifi({
      'host': 'host-1',
      'ssid': 'Church',
      'security': 'wpa2',
      'kind': 'church',
      'password': 'church-pass',
      'store': true,
    });
    expect((await port().pairWifiProfile('host-1'))['passwordSaved'], isTrue);
    await p.savePairWifi({
      'host': 'host-2',
      'ssid': 'Hotspot',
      'security': 'wpa2',
      'kind': 'hotspot',
      'password': 'not-stored-1',
      'store': false,
    });
    expect((await p.pairWifiProfile('host-2'))['passwordSaved'], isFalse);
    expect((await p.pairWifiProfile('host-2'))['kind'], 'hotspot');
    await p.forgetPairWifi('host-1');
    expect((await p.pairWifiProfile('host-1'))['ssid'], '');
    expect(await p.joinPairWifi('host-1'), isFalse);
  });

  test('the PC never sleeps while a service runs or screens are shared, and '
      'the monitor follows the app', () async {
    final p = port();
    // Idle: nothing is held.
    await p.setKeepScreenAwake(false);
    expect(system.awake.last, '-/-');
    // The app asks for the monitor (a service, a stage screen).
    await p.setKeepScreenAwake(true);
    expect(system.awake.last, '-/display');
    await p.updateServiceNotification({'active': true, 'title': 'Welcome'});
    expect(system.awake.last, 'system/display');
    // The operator chose Never: the PC stays up, the monitor may sleep.
    await p.setKeepScreenAwake(false);
    expect(system.awake.last, 'system/-');
    await p.updateServiceNotification({'active': false});
    expect(system.awake.last, '-/-');
    // Sharing alone holds the PC but not the monitor.
    expect(await p.setActiveService(true), isTrue);
    expect(await p.activeServiceRunning(), isTrue);
    expect(system.awake.last, 'system/-');
    await p.setKeepScreenAwake(true);
    expect(system.awake.last, 'system/display');
    await p.setKeepScreenAwake(false);
    expect(await p.setActiveService(false), isFalse);
    expect(system.awake.last, '-/-');
    // The card is updated every second; Windows is only told on a change.
    final before = system.awake.length;
    await p.updateServiceNotification({'active': false});
    expect(system.awake.length, before);
  });

  test('warnings notify, flash the taskbar and never make a sound', () async {
    final p = port();
    expect(await p.notificationStatus(), {
      'enabled': true,
      'exact': true,
      'sound': false,
      'tray': true,
    });
    await p.testNotification();
    expect(system.flashes, 1);
    expect(
      system.notices.single,
      startsWith('Church Service Timer test warning'),
    );
    await p.syncWarnings({
      'session': 's',
      'clearSeconds': 60,
      'alarms': [],
      'notice': {'id': 'n', 'title': 'Wrap up', 'body': 'Sermon · 02:00'},
    });
    expect(system.flashes, 2);
    expect(system.notices.last, 'Wrap up | Sermon · 02:00 | 60');
    // The same warning is not shown twice, and "until dismissed" is kept.
    await p.syncWarnings({
      'session': 's',
      'clearSeconds': 0,
      'alarms': [],
      'notice': {'id': 'n', 'title': 'Wrap up', 'body': 'Sermon'},
    });
    expect(system.notices, hasLength(2));
    await p.syncWarnings({
      'session': 's',
      'clearSeconds': 0,
      'alarms': [],
      'notice': {'id': 'm', 'title': 'Time', 'body': 'Sermon'},
    });
    expect(system.notices.last, 'Time | Sermon | 0');
    p.dispose();
  });

  test(
    'the warning sound is a setting, off until turned on, and kept',
    () async {
      final p = port();
      await p.testNotification();
      expect(system.notices.last, isNot(endsWith('| sound')));
      await p.setWarningSound(true);
      expect((await p.notificationStatus())['sound'], true);
      await p.testNotification();
      expect(system.notices.last, endsWith('| sound'));
      p.dispose();
      // It is remembered on this computer.
      final again = port();
      expect((await again.notificationStatus())['sound'], true);
      await again.setWarningSound(false);
      await again.testNotification();
      expect(system.notices.last, isNot(endsWith('| sound')));
      again.dispose();
    },
  );

  test('only https pages open, and feedback goes to the one address', () async {
    final p = port();
    expect(await p.openWebPage('http://example.com'), isFalse);
    expect(await p.openWebPage('file:///C:/Windows'), isFalse);
    expect(system.opened, isEmpty);
    expect(await p.openWebPage('https://example.com/guide'), isTrue);
    expect(system.opened.single, 'https://example.com/guide');

    expect(await p.composeFeedback('Idea & more', 'Line 1\nLine 2'), isTrue);
    expect(
      system.opened.last,
      'mailto:immanuelproton@gmail.com?subject=Idea%20%26%20more&body=Line%201%0ALine%202',
    );
    await expectLater(p.composeFeedback('', 'x'), throwsA(isA<RuleError>()));
    await expectLater(
      p.composeFeedback('a\nb', 'x'),
      throwsA(isA<RuleError>()),
    );
    system.canOpen = false;
    expect(await p.composeFeedback('Idea', 'text'), isFalse);
  });

  test('a long feedback message goes through the clipboard', () async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        });
    final body = 'A long report. ' * 300;
    expect(await port().composeFeedback('Problem', body), isTrue);
    expect(copied, body);
    expect(system.opened.last.length, lessThan(2000));
    expect(system.opened.last, contains('Ctrl%2BV'));
  });

  test('diagnostics describe a Windows PC', () async {
    final p = port();
    expect(await p.deviceDescription(), 'Windows PC · test');
    expect(await p.batteryStatus(), {'level': 81, 'charging': true});
    expect(await p.batteryUnrestricted(), isNull);
  });

  group('with a sign on the network', () {
    late FakeW2Controller sign;
    setUp(() async => sign = await FakeW2Controller.start());
    tearDown(() => sign.close());

    test('device settings are refused while a service is running', () async {
      final p = port();
      await p.save('{"session":{"phase":"active"}}');
      await expectLater(
        p.administerDisplay('ssid', 'Hall_Sign', 0),
        throwsA(
          isA<RuleError>().having(
            (e) => e.message,
            'message',
            'End the service before changing device settings.',
          ),
        ),
      );
      expect(sign.commands, isEmpty);
    });

    test('forgetting the sign forgets its passwords too', () async {
      final p = port();
      await p.sign.prefs.write({
        'id': 'sign-1',
        'name': 'Hall',
        'hardware': true,
      });
      await p.saveDisplayPassword('sign-1', 'Sign1234');
      await p.saveSignWifiProfile({
        'id': 'sign-1',
        'ssid': 'HD-W2',
        'security': 'wpa2',
        'password': 'wifi-pass-1',
      });
      await p.forgetDisplay();
      expect(await p.savedDisplayPassword('sign-1'), isNull);
      expect(await p.savedDisplayPassword('wifi:sign-1'), isNull);
      expect((await p.signWifiProfile('sign-1'))['ssid'], '');
      expect(await p.displayPreferences(), {
        'hardware': false,
        'id': '',
        'autoReconnect': true,
        'name': '',
      });
    });
  });

  group('Tinos on the LED display', () {
    testWidgets('renders at 7 and 14 rows in every face', (tester) async {
      await tester.runAsync(() async {
        final p = port();
        expect(await p.hasTinosFont(), isTrue);
        for (final height in [1, 2]) {
          for (final (bold, italic) in [
            (false, false),
            (true, false),
            (false, true),
            (true, true),
          ]) {
            final raster = TextRaster.fromJson(
              await p.rasterizeTinos(
                TextLayout(
                  'Amen 12',
                  font: 'tinos',
                  height: height,
                  bold: bold,
                  italic: italic,
                ),
              ),
            );
            final limit = height * 7;
            expect(raster.height, lessThanOrEqualTo(limit));
            // The fit is tight: the ink fills the rows it was given.
            expect(raster.height, greaterThanOrEqualTo(limit - 1));
            expect(raster.rows.join(), contains('1'));
          }
        }
      });
    });

    testWidgets('bold is heavier than regular and 14 rows wider than 7', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final p = port();
        Future<TextRaster> render(int height, {bool bold = false}) async =>
            TextRaster.fromJson(
              await p.rasterizeTinos(
                TextLayout(
                  'WRAP UP',
                  font: 'tinos',
                  height: height,
                  bold: bold,
                ),
              ),
            );
        int lit(TextRaster r) => '1'.allMatches(r.rows.join()).length;
        final small = await render(1), large = await render(2);
        expect(large.width, greaterThan(small.width));
        expect(lit(await render(2, bold: true)), greaterThan(lit(large)));
        // Each letter keeps solid strokes: no row of the capitals is empty.
        expect(large.rows.every((r) => r.contains('1')), isTrue);
      });
    });

    testWidgets('keeps the Android input rules', (tester) async {
      await tester.runAsync(() async {
        final p = port();
        for (final bad in ['   ', 'two\nlines', 'tab\there', 'x' * 161]) {
          await expectLater(
            p.rasterizeTinos(TextLayout(bad, font: 'tinos')),
            throwsA(isA<RuleError>()),
            reason: jsonEncode(bad),
          );
        }
      });
    });

    testWidgets('a missing font file is reported, not thrown', (tester) async {
      await tester.runAsync(() async {
        final p = WindowsPort(
          dataDir: Directory('${dir.path}/data'),
          monotonicMs: () => mono,
          protector: FakeProtector(),
          dialogs: dialogs,
          system: system,
          loadTinosFace: (style) => File('${dir.path}/none.ttf').readAsBytes(),
        );
        expect(await p.hasTinosFont(), isFalse);
      });
    });
  });

  group('church pictures', () {
    Future<Uint8List> picture(int w, int h, {bool clear = false}) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (!clear)
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..color = const ui.Color(0xff204080),
        );
      canvas.drawCircle(
        ui.Offset(w / 2, h / 2),
        h / 4,
        ui.Paint()..color = const ui.Color(0xffffcc00),
      );
      final image = await recorder.endRecording().toImage(w, h);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    }

    Future<ui.Image> decode(String base64) async {
      final codec = await ui.instantiateImageCodec(base64Decode(base64));
      return (await codec.getNextFrame()).image;
    }

    testWidgets('the banner is always 600 × 200', (tester) async {
      await tester.runAsync(() async {
        final p = port();
        expect(await p.pickChurchBanner(), isNull);
        final file = File('${dir.path}/tall.png')
          ..writeAsBytesSync(await picture(300, 900));
        dialogs.openResult = file.path;
        final banner = await decode((await p.pickChurchBanner())!);
        expect((banner.width, banner.height), (600, 200));
        expect(dialogs.asked.last, 'open jpg,jpeg,png,webp');
      });
    });

    testWidgets('the logo photo is shrunk, JPEG when opaque, PNG when clear', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final big = await churchPhotoFrom(await picture(2000, 1000));
        final bytes = base64Decode(big);
        expect(bytes.sublist(0, 3), [0xff, 0xd8, 0xff]);
        final image = await decode(big);
        expect((image.width, image.height), (1600, 800));

        final clear = base64Decode(
          await churchPhotoFrom(await picture(400, 400, clear: true)),
        );
        expect(clear.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
        final small = await decode(base64Encode(clear));
        expect((small.width, small.height), (400, 400));
      });
    });

    testWidgets('files that are not pictures, or too large, are refused', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await expectLater(
          churchBannerFrom(Uint8List.fromList(utf8.encode('GIF89a not ok'))),
          throwsA(
            isA<RuleError>().having(
              (e) => e.message,
              'message',
              'Choose a JPEG, PNG or WebP image.',
            ),
          ),
        );
        await expectLater(
          churchPhotoFrom(Uint8List(5000001)),
          throwsA(isA<RuleError>()),
        );
        // A PNG signature with nothing behind it.
        await expectLater(
          churchBannerFrom(
            Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]),
          ),
          throwsA(isA<RuleError>()),
        );
      });
    });

    test('the banner frame crops without stretching', () {
      expect(bannerFrame(600, 200), const ui.Rect.fromLTRB(0, 0, 600, 200));
      expect(bannerFrame(300, 900), const ui.Rect.fromLTRB(0, -800, 600, 1000));
      expect(bannerFrame(1200, 200), const ui.Rect.fromLTRB(-300, 0, 900, 200));
    });
  });

  test('the app\'s programs pass the sign checks the transport applies', () {
    // Guards against the Dart checks drifting from what W2Program builds.
    expect(W2Program.countdown(0).length, 393);
    expect(W2Program.clock().length, 444);
    expect(W2Program.clock(format12Hour: true).length, 500);
  });
}
