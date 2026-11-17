import 'dart:io';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/desktop_files.dart';
import 'package:church_service_timer/windows/desktop_network.dart';
import 'package:church_service_timer/windows/desktop_warnings.dart';
import 'package:church_service_timer/windows/single_instance.dart';
import 'package:church_service_timer/windows/window_memory.dart';
import 'package:church_service_timer/windows/windows_app.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWindow implements WindowHandle {
  WindowPlace? place;
  bool onScreen = true;
  final restored = <WindowPlace>[];
  @override
  WindowPlace? read() => place;
  @override
  bool restore(WindowPlace p) {
    if (!onScreen) return false;
    restored.add(p);
    place = p;
    return true;
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cst-desktop'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('reading a program or backup file', () {
    test('returns the name and text of CSV and JSON files', () async {
      final f = File('${dir.path}/Sunday.JSON')..writeAsStringSync('{"é":1}');
      expect(await readImportFile(f.path, 1048576), {
        'name': 'Sunday.JSON',
        'content': '{"é":1}',
      });
      final csv = File('${dir.path}/plan.csv')..writeAsStringSync('a,b\n1,2');
      expect((await readImportFile(csv.path, 1048576))['name'], 'plan.csv');
    });

    test('refuses other kinds, oversize files and non-UTF-8 text', () async {
      final xlsx = File('${dir.path}/plan.xlsx')..writeAsStringSync('x');
      await expectLater(
        readImportFile(xlsx.path, 1048576),
        throwsA(
          isA<RuleError>().having(
            (e) => e.message,
            'message',
            'Choose CSV or JSON. Export Excel as CSV first.',
          ),
        ),
      );
      final big = File('${dir.path}/big.csv')
        ..writeAsBytesSync(List.filled(2000, 65));
      await expectLater(
        readImportFile(big.path, 1000),
        throwsA(isA<RuleError>()),
      );
      final latin = File('${dir.path}/latin.csv')
        ..writeAsBytesSync([0x63, 0x61, 0x66, 0xe9]);
      await expectLater(
        readImportFile(latin.path, 1048576),
        throwsA(
          isA<RuleError>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
    });

    test('names from Windows paths and unsafe names', () {
      expect(fileName(r'C:\Users\me\Documents\Sunday.json'), 'Sunday.json');
      expect(fileName('/tmp/a/b.csv'), 'b.csv');
      expect(safeFileName('Report: 9/11 "AM"?.pdf'), 'Report_ 9_11 _AM__.pdf');
      expect(safeFileName('trailing. '), 'trailing');
      expect(safeFileName('CON.json'), '_CON.json');
      expect(safeFileName(''), 'file');
    });

    test('saving into a folder never replaces a file', () async {
      final sep = Platform.pathSeparator;
      expect(await freePath(dir.path, 'r.pdf'), '${dir.path}${sep}r.pdf');
      File('${dir.path}/r.pdf').writeAsStringSync('old');
      expect(await freePath(dir.path, 'r.pdf'), '${dir.path}${sep}r (2).pdf');
      File('${dir.path}/r (2).pdf').writeAsStringSync('old');
      expect(await freePath(dir.path, 'r.pdf'), '${dir.path}${sep}r (3).pdf');
    });

    test('the file named on the command line', () {
      expect(fileArgument([]), isNull);
      expect(
        fileArgument(['--flag', r'C:\x\Sunday.JSON']),
        r'C:\x\Sunday.JSON',
      );
      expect(fileArgument([r'C:\x\plan.csv']), r'C:\x\plan.csv');
      expect(fileArgument([r'C:\x\photo.png']), isNull);
    });
  });

  group('which address to share', () {
    test('a single network is used', () {
      expect(
        pickLanAddress([(adapter: 'Wi-Fi', address: '192.168.1.20')]),
        '192.168.1.20',
      );
    });

    test('adapters phones cannot reach come last', () {
      expect(
        pickLanAddress([
          (adapter: 'vEthernet (WSL)', address: '172.20.0.1'),
          (adapter: 'VirtualBox Host-Only Network', address: '192.168.56.1'),
          (adapter: 'Wi-Fi', address: '192.168.1.20'),
        ]),
        '192.168.1.20',
      );
      // But they are still better than nothing.
      expect(
        pickLanAddress([(adapter: 'vEthernet (WSL)', address: '172.20.0.1')]),
        '172.20.0.1',
      );
    });

    test('the sign\'s own network is avoided when there is another', () {
      const both = [
        (adapter: 'Wi-Fi', address: '192.168.43.2'),
        (adapter: 'Ethernet', address: '10.0.0.15'),
      ];
      expect(pickLanAddress(both, avoid: '10.0.0.15'), '192.168.43.2');
      expect(pickLanAddress(both, avoid: '192.168.43.2'), '10.0.0.15');
      expect(
        pickLanAddress([both.first], avoid: '192.168.43.2'),
        '192.168.43.2',
      );
    });

    test('wired comes before Wi-Fi, and the choice is stable', () {
      const a = (adapter: 'Wi-Fi', address: '192.168.1.20');
      const b = (adapter: 'Ethernet', address: '192.168.1.30');
      expect(pickLanAddress([a, b]), '192.168.1.30');
      expect(pickLanAddress([b, a]), '192.168.1.30');
      const c = (adapter: 'Ethernet 2', address: '192.168.1.5');
      expect(pickLanAddress([b, c]), pickLanAddress([c, b]));
    });

    test('public and unusable addresses are never shared', () {
      expect(
        pickLanAddress([
          (adapter: 'Mobile broadband', address: '100.72.3.9'),
          (adapter: 'Ethernet', address: '8.8.8.8'),
        ]),
        isNull,
      );
      expect(pickLanAddress([]), isNull);
    });

    test('the Wi-Fi name is read from netsh, not the BSSID', () {
      const output = '''

There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6 AX201 160MHz
    GUID                   : 11111111-2222-3333-4444-555555555555
    Physical address       : aa:bb:cc:dd:ee:ff
    State                  : connected
    SSID                   : Church Hall 5G
    BSSID                  : 11:22:33:44:55:66
    Network type           : Infrastructure
''';
      expect(parseNetshSsid(output), 'Church Hall 5G');
      expect(parseNetshSsid(output.replaceAll('\n', '\r\n')), 'Church Hall 5G');
      expect(
        parseNetshSsid('    State : disconnected\r\n    BSSID : 11:22\r\n'),
        '',
      );
      expect(parseNetshSsid(''), '');
    });
  });

  group('operator warnings', () {
    Json plan(String session, List<(String, int)> alarms, {String? notice}) => {
      'session': session,
      'scope': session,
      'clearSeconds': 30,
      'alarms': [
        for (final (id, at) in alarms)
          {'id': id, 'at': at, 'title': 'T $id', 'body': 'B $id'},
      ],
      'notice': notice == null
          ? null
          : {'id': notice, 'title': 'T $notice', 'body': 'B $notice'},
    };

    test('each fires once at its moment on the counter', () {
      fakeAsync((async) {
        var mono = 1000;
        final fired = <String>[];
        final warnings = DesktopWarnings(
          monoMs: () => mono + async.elapsed.inMilliseconds,
          deliver: (title, body) => fired.add('$title/$body'),
        );
        warnings.sync(plan('s1', [('a', 6000), ('b', 11000)]));
        async.elapse(const Duration(milliseconds: 4999));
        expect(fired, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(fired, ['T a/B a']);
        // The same plan again (every save re-sends it): no repeat.
        warnings.sync(plan('s1', [('a', 6000), ('b', 11000)]));
        async.elapse(const Duration(seconds: 6));
        expect(fired, ['T a/B a', 'T b/B b']);
        mono = 0;
        warnings.dispose();
      });
    });

    test('a changed plan cancels what it no longer contains', () {
      fakeAsync((async) {
        final fired = <String>[];
        final warnings = DesktopWarnings(
          monoMs: () => async.elapsed.inMilliseconds,
          deliver: (title, _) => fired.add(title),
        );
        warnings.sync(plan('s1', [('a', 5000)]));
        warnings.sync(plan('s1', []));
        async.elapse(const Duration(seconds: 10));
        expect(fired, isEmpty);
      });
    });

    test('a warning that just triggered is shown at once, once', () {
      final fired = <String>[];
      final warnings = DesktopWarnings(
        monoMs: () => 0,
        deliver: (title, _) => fired.add(title),
      );
      warnings.sync(plan('s1', [], notice: 'n'));
      warnings.sync(plan('s1', [], notice: 'n'));
      expect(fired, ['T n']);
      // A new service starts with a clean slate.
      warnings.sync(plan('s2', [], notice: 'n'));
      expect(fired, ['T n', 'T n']);
    });

    test('a PC that slept past a warning delivers it on waking', () {
      fakeAsync((async) {
        var slept = 0;
        final fired = <String>[];
        final warnings = DesktopWarnings(
          monoMs: () => async.elapsed.inMilliseconds + slept,
          deliver: (title, _) => fired.add(title),
        );
        warnings.sync(plan('s1', [('a', 60000)]));
        async.elapse(const Duration(seconds: 10));
        // Asleep for ten minutes: timers did not run, the counter did.
        slept = 600000;
        async.elapse(const Duration(seconds: 50));
        expect(fired, ['T a']);
      });
    });

    test('a timer that runs early waits for the counter', () {
      fakeAsync((async) {
        var behind = 0;
        final fired = <String>[];
        final warnings = DesktopWarnings(
          monoMs: () => async.elapsed.inMilliseconds - behind,
          deliver: (title, _) => fired.add(title),
        );
        warnings.sync(plan('s1', [('a', 5000)]));
        behind = 2000;
        async.elapse(const Duration(seconds: 5));
        expect(fired, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(fired, ['T a']);
      });
    });
  });

  group('window place', () {
    JsonPrefs prefs() => JsonPrefs(File('${dir.path}/window.json'));

    test('is saved when it changes and restored next time', () async {
      final window = FakeWindow()
        ..place = (frame: [100, 80, 1380, 880], maximised: false);
      final memory = WindowMemory(prefs(), window);
      await memory.restore();
      expect(window.restored, isEmpty);
      await memory.save();
      window.place = (frame: [100, 80, 1380, 880], maximised: true);
      await memory.save();

      final next = FakeWindow();
      await WindowMemory(prefs(), next).restore();
      expect(next.restored.single.frame, [100, 80, 1380, 880]);
      expect(next.restored.single.maximised, isTrue);
    });

    test('a place that is off every screen is ignored', () async {
      await prefs().set('window', {
        'frame': [5000, 80, 6280, 880],
        'maximised': false,
      });
      final window = FakeWindow()..onScreen = false;
      await WindowMemory(prefs(), window).restore();
      expect(window.restored, isEmpty);
    });

    test('nonsense in the file is ignored, and never saved', () async {
      for (final bad in [
        'text',
        {
          'frame': [1, 2, 3],
        },
        {
          'frame': [0, 0, 50, 50],
        },
        {
          'frame': ['a', 0, 900, 900],
        },
      ]) {
        await prefs().set('window', bad);
        final window = FakeWindow();
        await WindowMemory(prefs(), window).restore();
        expect(window.restored, isEmpty, reason: '$bad');
      }
      await prefs().remove('window');
      final minimised = FakeWindow()
        ..place = (frame: [0, 0, 10, 10], maximised: false);
      await WindowMemory(prefs(), minimised).save();
      expect(await prefs().get('window'), isNull);
    });

    test('an unchanged place is written only once', () async {
      final window = FakeWindow()
        ..place = (frame: [1, 2, 900, 700], maximised: false);
      final memory = WindowMemory(prefs(), window);
      await memory.save();
      final written = File('${dir.path}/window.json').lastModifiedSync();
      File('${dir.path}/window.json').deleteSync();
      await memory.save();
      expect(File('${dir.path}/window.json').existsSync(), isFalse);
      expect(written, isNotNull);
    });
  });

  group('one copy of the app', () {
    test('the first copy holds the lock until it lets go', () {
      final first = SingleInstance(dir);
      expect(first.acquire(), isTrue);
      first.dispose();
      final again = SingleInstance(dir);
      expect(again.acquire(), isTrue);
      again.dispose();
    });

    test('a later copy hands over its file and a plain start', () async {
      final first = SingleInstance(dir)..acquire();
      final requests = <String?>[];
      first.listen(requests.add);
      SingleInstance(dir).handOver(r'C:\Users\me\Sunday.json');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      SingleInstance(dir).handOver(null);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(requests, [r'C:\Users\me\Sunday.json', null]);
      expect(Directory('${dir.path}/handoff').listSync(), isEmpty);
      first.dispose();
    });

    test('notes left while the app was closed are discarded', () async {
      SingleInstance(dir).handOver('stale.json');
      final first = SingleInstance(dir)..acquire();
      final requests = <String?>[];
      first.listen(requests.add);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(requests, isEmpty);
      first.dispose();
    });
  });
}
