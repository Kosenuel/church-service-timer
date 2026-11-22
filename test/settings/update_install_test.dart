import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/update_checker.dart';
import 'package:church_service_timer/app/update_installer.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:church_service_timer/windows/windows_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../windows/desktop_clock_and_storage_test.dart' show FakeProtector;
import '../windows/windows_port_test.dart' show FakeDialogs, FakeSystem;
import 'update_notice_test.dart' show UpdatePort;

const _download = releaseDownloadPrefix;
const _setup = 'Church-Service-Timer-0.33.0-windows-setup.exe';
const _zip = 'Church-Service-Timer-0.33.0-windows-x64.zip';

/// A stand-in installer: 2.5 MB of a repeating pattern.
final installerBytes = Uint8List.fromList(
  List.generate(2621440, (i) => (i * 7 + i ~/ 256) & 0xff),
);

String sha256Hex(List<int> bytes) {
  final digest = SHA256Digest();
  final input = Uint8List.fromList(bytes);
  final out = Uint8List(32);
  digest
    ..update(input, 0, input.length)
    ..doFinal(out, 0);
  return [for (final b in out) b.toRadixString(16).padLeft(2, '0')].join();
}

Map<String, Object?> asset(
  String name,
  int size, {
  String? url,
  String? digest,
}) => {
  'name': name,
  'size': size,
  'browser_download_url': url ?? '${_download}v0.33.0/$name',
  'digest': ?digest,
};

/// A release as GitHub's API describes it, with [assets].
String releaseWith(
  List<Map<String, Object?>> assets, {
  String tag = 'v0.33.0',
}) => jsonEncode({
  'tag_name': tag,
  'html_url':
      'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/tag/$tag',
  'assets': assets,
});

/// The installer, its checksum file and the zip, as Package-Windows.ps1
/// and the release workflow publish them.
String fullRelease({String tag = 'v0.33.0', int? size, String? digest}) =>
    releaseWith([
      asset('Church-Service-Timer-0.33.0.apk', 1000),
      asset(_zip, 5000),
      asset(_setup, size ?? installerBytes.length, digest: digest),
      asset('$_setup.sha256', '${sha256Hex(installerBytes)}  $_setup\n'.length),
    ], tag: tag);

class FakeFile implements UpdateFile {
  @override
  final String path;
  final bytes = BytesBuilder();
  bool closed = false, deleted = false;
  FakeFile(this.path);
  @override
  Future<void> add(List<int> chunk) async => bytes.add(chunk);
  @override
  Future<void> close() async => closed = true;
  @override
  Future<void> delete() async => deleted = true;
}

/// The network, disk and Windows, faked. Each address answers with the
/// bytes in [served], in 64 KB pieces, unless [gate] holds the installer
/// back so a test can watch it arrive.
class FakeUpdateFiles implements UpdateFiles {
  final served = <String, List<int>>{};
  StreamController<List<int>>? gate;
  final asked = <String>[];
  final files = <FakeFile>[];
  final launched = <String>[];
  bool launches = true;

  FakeUpdateFiles({List<int>? installer, String? checksum}) {
    served['${_download}v0.33.0/$_setup'] = installer ?? installerBytes;
    served['${_download}v0.33.0/$_setup.sha256'] = utf8.encode(
      checksum ?? '${sha256Hex(installerBytes)}  $_setup\n',
    );
  }

  @override
  Stream<List<int>> download(String url) {
    asked.add(url);
    if (gate != null && url.endsWith('.exe')) return gate!.stream;
    final bytes = served[url];
    if (bytes == null) return Stream.error(Exception('Not found'));
    return Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += 65536)
        bytes.sublist(i, i + 65536 > bytes.length ? bytes.length : i + 65536),
    ]);
  }

  @override
  Future<UpdateFile> create(String name) async {
    final file = FakeFile('C:\\Temp\\church-service-timer-update-1\\$name');
    files.add(file);
    return file;
  }

  @override
  Future<bool> launch(String path) async {
    launched.add(path);
    return launches;
  }
}

/// A PC whose update check answers [reply] and whose downloads are fake.
class PcUpdatePort extends DesktopFakePort {
  String? reply;
  final FakeUpdateFiles io;
  int quits = 0;
  final opened = <String>[];
  PcUpdatePort(this.reply, [FakeUpdateFiles? files])
    : io = files ?? FakeUpdateFiles();
  @override
  Future<String> installedVersion() async => '0.32.0 (37)';
  @override
  UpdateChecker get updateChecker => UpdateChecker((url) async => reply);
  @override
  late final UpdateInstaller updateInstaller = UpdateInstaller(
    io,
    quit: () async => quits++,
  );
  @override
  Future<bool> openWebPage(String url) async {
    opened.add(url);
    return true;
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('reading the release', () {
    Future<UpdateAvailable> found(String reply) async =>
        await UpdateChecker((_) async => reply).check('0.32.0 (37)')
            as UpdateAvailable;

    test(
      'lists files on the guide repository with their size and hash',
      () async {
        final hash = sha256Hex(installerBytes);
        final update = await found(fullRelease(digest: 'sha256:$hash'));
        expect(update.assets.map((a) => a.name), [
          'Church-Service-Timer-0.33.0.apk',
          _zip,
          _setup,
          '$_setup.sha256',
        ]);
        final setup = update.assets[2];
        expect(setup.size, installerBytes.length);
        expect(setup.sha256, hash);
        expect(setup.url, '${_download}v0.33.0/$_setup');
        expect(update.assets[0].sha256, isNull);
      },
    );

    test(
      'a beta install is offered the stable release and its files',
      () async {
        final update =
            await UpdateChecker(
                  (_) async => fullRelease(),
                ).check('0.33.0-beta.1 (41)')
                as UpdateAvailable;
        expect(update.version, '0.33.0');
        expect(update.assets.map((a) => a.name), contains(_setup));
        // The same release is no update for the same beta's own stable number
        // or above, and a beta tag is never an update.
        expect(
          await UpdateChecker(
            (_) async => fullRelease(tag: 'v0.33.0-beta.2'),
          ).check('0.32.0 (37)'),
          isA<UpToDate>(),
        );
      },
    );

    test('files from anywhere else, or without a size, are left out', () async {
      final update = await found(
        releaseWith([
          asset(_setup, 10, url: 'https://example.com/$_setup'),
          asset(_setup, 10, url: '${_download}v0.33.0/other.exe'),
          asset(_setup, 0),
          {
            'name': _setup,
            'browser_download_url': '${_download}v0.33.0/$_setup',
          },
          asset(_setup, 10, digest: 'md5:abc'),
        ]),
      );
      expect(update.assets, hasLength(1));
      expect(update.assets.single.sha256, isNull);
    });

    test('the installer must carry the version being offered', () async {
      final offered = windowsUpdateIn(await found(fullRelease()));
      expect(offered, isA<InstallerOffered>());
      offered as InstallerOffered;
      expect(offered.installer.name, _setup);
      expect(offered.checksum!.name, '$_setup.sha256');

      final older = windowsUpdateIn(
        await found(
          releaseWith([
            asset('Church-Service-Timer-0.32.0-windows-setup.exe', 10),
          ]),
        ),
      );
      expect(older, isA<InstallerNotOffered>());
      expect((older as InstallerNotOffered).zip, isFalse);
    });

    test('a zip alone is not something the app can run', () async {
      final only = windowsUpdateIn(await found(releaseWith([asset(_zip, 10)])));
      expect((only as InstallerNotOffered).zip, isTrue);
      final none = windowsUpdateIn(await found(releaseWith([])));
      expect((none as InstallerNotOffered).zip, isFalse);
    });
  });

  group('downloading', () {
    Future<(InstallerOffered, FakeUpdateFiles, UpdateInstaller)> setUpDownload(
      String release, [
      FakeUpdateFiles? files,
    ]) async {
      final update =
          await UpdateChecker((_) async => release).check('0.32.0 (37)')
              as UpdateAvailable;
      final io = files ?? FakeUpdateFiles();
      return (
        windowsUpdateIn(update) as InstallerOffered,
        io,
        UpdateInstaller(io, quit: () async {}),
      );
    }

    test('checks the size and the published checksum', () async {
      final (offer, io, installer) = await setUpDownload(fullRelease());
      final seen = <int>[];
      final done = await installer.download(
        offer,
        '0.33.0',
        progress: (got, of) {
          expect(of, installerBytes.length);
          seen.add(got);
        },
        cancel: Completer<void>().future,
      );
      expect(done.hashChecked, isTrue);
      expect(done.path, endsWith(_setup));
      expect(io.asked, [
        '${_download}v0.33.0/$_setup.sha256',
        '${_download}v0.33.0/$_setup',
      ]);
      expect(seen.first, 0);
      expect(seen.last, installerBytes.length);
      expect(seen.length, greaterThan(10));
      expect(io.files.single.bytes.length, installerBytes.length);
      expect(io.files.single.deleted, isFalse);
      expect(io.launched, isEmpty);
    });

    test('a short download is rejected and deleted', () async {
      final (offer, io, installer) = await setUpDownload(
        fullRelease(),
        FakeUpdateFiles(installer: installerBytes.sublist(0, 100000)),
      );
      await expectLater(
        installer.download(
          offer,
          '0.33.0',
          progress: (_, _) {},
          cancel: Completer<void>().future,
        ),
        throwsA(
          isA<DownloadFailed>().having(
            (e) => e.message,
            'message',
            contains('size does not match'),
          ),
        ),
      );
      expect(io.files.single.deleted, isTrue);
    });

    test('a download larger than listed is stopped and deleted', () async {
      final (offer, io, installer) = await setUpDownload(
        fullRelease(size: 1000),
      );
      await expectLater(
        installer.download(
          offer,
          '0.33.0',
          progress: (_, _) {},
          cancel: Completer<void>().future,
        ),
        throwsA(
          isA<DownloadFailed>().having(
            (e) => e.message,
            'message',
            contains('larger than GitHub said'),
          ),
        ),
      );
      expect(io.files.single.deleted, isTrue);
    });

    test('a file that does not match the checksum is rejected', () async {
      final changed = Uint8List.fromList(installerBytes)..[5000] ^= 1;
      final (offer, io, installer) = await setUpDownload(
        fullRelease(),
        FakeUpdateFiles(installer: changed),
      );
      await expectLater(
        installer.download(
          offer,
          '0.33.0',
          progress: (_, _) {},
          cancel: Completer<void>().future,
        ),
        throwsA(
          isA<DownloadFailed>().having(
            (e) => e.message,
            'message',
            contains('does not match the checksum'),
          ),
        ),
      );
      expect(io.files.single.deleted, isTrue);
    });

    test(
      'an unreadable or disagreeing checksum stops before downloading',
      () async {
        for (final (checksum, digest) in [
          ('not a checksum', null),
          ('${sha256Hex(installerBytes)}  some-other-file.exe', null),
          ('${sha256Hex(installerBytes)}  $_setup', 'sha256:${'0' * 64}'),
        ]) {
          final (offer, io, installer) = await setUpDownload(
            fullRelease(digest: digest),
            FakeUpdateFiles(checksum: checksum),
          );
          await expectLater(
            installer.download(
              offer,
              '0.33.0',
              progress: (_, _) {},
              cancel: Completer<void>().future,
            ),
            throwsA(isA<DownloadFailed>()),
          );
          expect(io.files, isEmpty, reason: checksum);
        }
      },
    );

    test('GitHub’s own hash is used when there is no checksum file', () async {
      final (offer, _, installer) = await setUpDownload(
        releaseWith([
          asset(
            _setup,
            installerBytes.length,
            digest: 'sha256:${sha256Hex(installerBytes)}',
          ),
        ]),
      );
      final done = await installer.download(
        offer,
        '0.33.0',
        progress: (_, _) {},
        cancel: Completer<void>().future,
      );
      expect(done.hashChecked, isTrue);
    });

    test('with no checksum at all only the size is checked', () async {
      final (offer, _, installer) = await setUpDownload(
        releaseWith([asset(_setup, installerBytes.length)]),
      );
      final done = await installer.download(
        offer,
        '0.33.0',
        progress: (_, _) {},
        cancel: Completer<void>().future,
      );
      expect(done.hashChecked, isFalse);
    });

    test('Cancel stops at once and deletes the part downloaded', () async {
      final gate = StreamController<List<int>>();
      final (offer, io, installer) = await setUpDownload(
        fullRelease(),
        FakeUpdateFiles()..gate = gate,
      );
      final cancel = Completer<void>();
      var got = 0;
      final done = installer.download(
        offer,
        '0.33.0',
        progress: (received, _) => got = received,
        cancel: cancel.future,
      );
      await pumpEventQueue();
      gate.add(installerBytes.sublist(0, 1000));
      await pumpEventQueue();
      expect(got, 1000);
      cancel.complete();
      await expectLater(done, throwsA(isA<DownloadCancelled>()));
      expect(io.files.single.deleted, isTrue);
      expect(gate.hasListener, isFalse);
    });

    test('a failed connection is a plain sentence', () async {
      final (offer, io, installer) = await setUpDownload(fullRelease());
      io.served.remove('${_download}v0.33.0/$_setup');
      await expectLater(
        installer.download(
          offer,
          '0.33.0',
          progress: (_, _) {},
          cancel: Completer<void>().future,
        ),
        throwsA(
          isA<DownloadFailed>().having(
            (e) => e.message,
            'message',
            contains('Check the internet connection'),
          ),
        ),
      );
    });

    test('install starts the installer, then closes the app', () async {
      final io = FakeUpdateFiles();
      var quit = 0;
      final installer = UpdateInstaller(io, quit: () async => quit++);
      await installer.install(
        const DownloadedInstaller(
          'C:\\x\\setup.exe',
          '0.33.0',
          hashChecked: true,
        ),
      );
      expect(io.launched, ['C:\\x\\setup.exe']);
      expect(quit, 1);
      io.launches = false;
      await expectLater(
        installer.install(
          const DownloadedInstaller(
            'C:\\x\\setup.exe',
            '0.33.0',
            hashChecked: true,
          ),
        ),
        throwsA(isA<DownloadFailed>()),
      );
      expect(quit, 1);
    });
  });

  group('on a PC', () {
    setUp(() => desktopWording = true);
    tearDown(() => desktopWording = false);

    Future<(AppController, PcUpdatePort)> openCheck(
      WidgetTester t,
      String? reply, {
      FakeUpdateFiles? files,
      bool service = false,
    }) async {
      setScreen(t, const Size(1366, 768));
      final port = PcUpdatePort(reply, files);
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit(
        (draft, _) => draft.appearance = draft.appearance.copyWith(
          desktopLayout: 'three_panes',
        ),
      );
      if (service) {
        await c.act('load', value: timeline());
        await c.act('start');
      }
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('About'));
      await t.pumpAndSettle();
      await t.tap(find.text('About'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('about-check-updates')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('about-check-updates')));
      await t.pumpAndSettle();
      return (c, port);
    }

    Future<void> shot(WidgetTester t, String name) async {
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(TimerApp),
        matchesGoldenFile('../goldens/desktop-update-$name.png'),
      );
    }

    Finder install() => find.byKey(const ValueKey('update-install'));
    Finder problem() => find.byKey(const ValueKey('update-problem'));

    testWidgets('a newer version offers Download and install', (t) async {
      final (_, port) = await openCheck(t, fullRelease());
      expect(find.text('Version 0.33.0 is available'), findsOneWidget);
      expect(find.text('Download and install'), findsOneWidget);
      expect(find.text('Open release page'), findsOneWidget);
      // Nothing is downloaded until it is pressed.
      expect(port.io.asked, isEmpty);
      await shot(t, 'available');
      await t.tap(find.text('Open release page'));
      await t.pumpAndSettle();
      expect(port.opened, [
        'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/tag/v0.33.0',
      ]);
      expect(port.io.asked, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the same or an older version offers nothing to install', (
      t,
    ) async {
      for (final tag in ['v0.32.0', 'v0.31.4']) {
        final (_, port) = await openCheck(t, fullRelease(tag: tag));
        expect(
          find.text('You have the latest version (0.32.0)'),
          findsOneWidget,
        );
        expect(install(), findsNothing);
        expect(find.text('Open release page'), findsNothing);
        expect(port.io.asked, isEmpty);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the download shows progress and can be cancelled', (t) async {
      final gate = StreamController<List<int>>();
      final (_, port) = await openCheck(
        t,
        fullRelease(),
        files: FakeUpdateFiles()..gate = gate,
      );
      await t.tap(install());
      await t.pump();
      gate.add(installerBytes.sublist(0, 1048576));
      await t.pump();
      await t.pump();
      expect(find.text('Downloading… 1.0 MB of 2.5 MB'), findsOneWidget);
      final bar = t.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('update-progress')),
      );
      expect(bar.value, closeTo(0.4, 0.001));
      expect(install(), findsNothing);
      await shot(t, 'downloading');
      await t.tap(find.text('Cancel download'));
      await t.pumpAndSettle();
      expect(
        find.text('Download cancelled. Nothing was installed.'),
        findsOneWidget,
      );
      expect(port.io.files.single.deleted, isTrue);
      expect(port.io.launched, isEmpty);
      expect(find.text('Download and install'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a checked download asks before the app closes', (t) async {
      final (_, port) = await openCheck(t, fullRelease());
      await t.tap(install());
      await t.pumpAndSettle();
      expect(find.text('Install version 0.33.0?'), findsOneWidget);
      expect(
        find.textContaining('The app will close to install version 0.33.0.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('matches the size and checksum'),
        findsOneWidget,
      );
      await shot(t, 'confirm');
      // Cancel keeps the download and installs nothing.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(port.io.launched, isEmpty);
      expect(port.quits, 0);
      expect(find.text('Install now'), findsOneWidget);
      expect(port.io.files, hasLength(1));

      await t.tap(find.text('Install now'));
      await t.pumpAndSettle();
      expect(port.io.files, hasLength(1), reason: 'not downloaded again');
      await t.tap(find.text('Close and install'));
      await t.pumpAndSettle();
      expect(port.io.launched, [
        'C:\\Temp\\church-service-timer-update-1\\$_setup',
      ]);
      expect(port.quits, 1);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a download of the wrong size is not offered to install', (
      t,
    ) async {
      final (_, port) = await openCheck(
        t,
        fullRelease(),
        files: FakeUpdateFiles(installer: installerBytes.sublist(0, 5000)),
      );
      await t.tap(install());
      await t.pumpAndSettle();
      expect(find.text('Install version 0.33.0?'), findsNothing);
      expect(
        t.widget<Text>(problem()).data,
        contains('its size does not match the release'),
      );
      expect(port.io.files.single.deleted, isTrue);
      expect(port.io.launched, isEmpty);
      await shot(t, 'failed');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a running service blocks installing', (t) async {
      final (c, port) = await openCheck(t, fullRelease(), service: true);
      expect(c.liveSession.active, isTrue);
      await t.tap(install());
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(problem()).data,
        startsWith('Finish or end the service first.'),
      );
      expect(port.io.asked, isEmpty);
      expect(port.io.launched, isEmpty);
      await shot(t, 'service-running');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a service started while the question is open still blocks', (
      t,
    ) async {
      final (c, port) = await openCheck(t, fullRelease());
      await t.tap(install());
      await t.pumpAndSettle();
      expect(find.text('Install version 0.33.0?'), findsOneWidget);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.tap(find.text('Close and install'));
      await t.pumpAndSettle();
      expect(port.io.launched, isEmpty);
      expect(port.quits, 0);
      expect(
        t.widget<Text>(problem()).data,
        startsWith('Finish or end the service first.'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('only a zip falls back to the release page', (t) async {
      final (_, port) = await openCheck(t, releaseWith([asset(_zip, 5000)]));
      expect(install(), findsNothing);
      expect(
        find.textContaining('published for Windows only as a zip file'),
        findsOneWidget,
      );
      await shot(t, 'zip-only');
      await t.tap(find.text('Open release page'));
      await t.pumpAndSettle();
      expect(port.opened, hasLength(1));
      expect(port.io.asked, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('no Windows file at all also falls back', (t) async {
      await openCheck(
        t,
        releaseWith([asset('Church-Service-Timer-0.33.0.apk', 1000)]),
      );
      expect(install(), findsNothing);
      expect(
        find.textContaining('no Windows installer the app can use'),
        findsOneWidget,
      );
      expect(find.text('Open release page'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('the Windows port', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cst-update'));
    tearDown(() => dir.deleteSync(recursive: true));

    WindowsPort port({UpdateFiles? files, void Function()? exitApp}) =>
        WindowsPort(
          dataDir: Directory('${dir.path}/data'),
          monotonicMs: () => 1000,
          protector: FakeProtector(),
          dialogs: FakeDialogs(),
          system: FakeSystem(),
          loadTinosFace: (_) async => Uint8List(0),
          updateFiles: files,
          exitApp: exitApp,
        );

    test('installs only with update files, and closes the app after', () async {
      expect(port().updateInstaller, isNull);
      var exits = 0;
      final io = FakeUpdateFiles();
      final p = port(files: io, exitApp: () => exits++);
      await p.updateInstaller!.install(
        const DownloadedInstaller(
          'C:\\x\\setup.exe',
          '0.33.0',
          hashChecked: true,
        ),
      );
      expect(io.launched, ['C:\\x\\setup.exe']);
      expect(exits, 1);
    });

    test('the real files use a new temporary folder and https only', () async {
      const files = WindowsUpdateFiles();
      final file = await files.create(_setup);
      expect(file.path, endsWith(_setup));
      expect(file.path, contains('church-service-timer-update-'));
      await file.add([1, 2, 3]);
      await file.close();
      expect(File(file.path).readAsBytesSync(), [1, 2, 3]);
      await file.delete();
      expect(File(file.path).parent.existsSync(), isFalse);
      await expectLater(
        files.download('http://example.com/$_setup').toList(),
        throwsA(isA<DownloadFailed>()),
      );
    });
  });

  testWidgets('A phone is unchanged: only the download page is offered', (
    t,
  ) async {
    setScreen(t, const Size(430, 1000));
    final port = UpdatePort(fullRelease());
    expect(port.updateInstaller, isNull);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('About', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('About'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('about-check-updates')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('about-check-updates')));
    await t.pumpAndSettle();
    expect(find.text('Version 0.33.0 is available'), findsOneWidget);
    expect(find.text('Open the download page'), findsOneWidget);
    expect(find.text('Download and install'), findsNothing);
    expect(find.text('Open release page'), findsNothing);
    expect(find.textContaining('zip'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
