import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/desktop_clock.dart';
import 'package:church_service_timer/windows/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';

/// A reversible stand-in for Windows' DPAPI that still binds each value
/// to its entropy, as the real one does.
class FakeProtector implements SecretProtector {
  @override
  Uint8List protect(Uint8List plain, Uint8List entropy) => Uint8List.fromList([
    entropy.length,
    ...entropy,
    for (final b in plain) b ^ 0x5a,
  ]);
  @override
  Uint8List unprotect(Uint8List cipher, Uint8List entropy) {
    final n = cipher[0];
    final bound = cipher.sublist(1, 1 + n);
    if (bound.length != entropy.length ||
        Iterable.generate(n).any((i) => bound[i] != entropy[i]))
      throw StateError('wrong entropy');
    return Uint8List.fromList([
      for (final b in cipher.sublist(1 + n)) b ^ 0x5a,
    ]);
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cst-desktop'));
  tearDown(() => dir.deleteSync(recursive: true));
  File at(String name) => File('${dir.path}/$name');

  group('which run of Windows this is', () {
    // A PC that started at wall-clock 1,000,000 ms: counter = wall - 1e6.
    const started = 1000000;
    var ids = 0;
    BootTracker tracker() =>
        BootTracker(at('boot.json'), newId: () => 'run-${++ids}');
    setUp(() => ids = 0);

    test('the same run keeps its id across app restarts', () {
      final first = tracker().id(5000, started + 5000);
      expect(tracker().id(90000, started + 90000), first);
      expect(tracker().id(90000000, started + 90000000), first);
    });

    test('sleep and hibernation do not change the id', () {
      final t = tracker();
      final before = t.id(60000, started + 60000);
      // Eight hours asleep: the counter and the date both moved on.
      const slept = 8 * 3600 * 1000;
      expect(t.id(60000 + slept, started + 60000 + slept), before);
      expect(tracker().id(61000 + slept, started + 61000 + slept), before);
    });

    test('a restart gets a new id even when it has been up longer', () {
      final first = tracker().id(5000, started + 5000);
      // Restarted an hour later; now up for longer than last time.
      const restarted = started + 3600000;
      final second = tracker().id(20000, restarted + 20000);
      expect(second, isNot(first));
      expect(tracker().id(30000, restarted + 30000), second);
    });

    test('a counter that went backwards is a new run', () {
      final t = tracker();
      final first = t.id(500000, started + 500000);
      expect(t.id(4000, started + 4000), isNot(first));
      expect(tracker().id(100, started + 600000), isNot(first));
    });

    test('a changed date while the app was closed is treated as a new run', () {
      final first = tracker().id(5000, started + 5000);
      // Same boot, but the PC's date was moved a day forward.
      expect(tracker().id(8000, started + 8000 + 86400000), isNot(first));
    });

    test('small clock corrections keep the id, and are followed', () {
      final t = tracker();
      final first = t.id(5000, started + 5000);
      // Network time nudged the clock by 4 s, then another 4 s a minute
      // on: each within tolerance of the last anchor.
      expect(t.id(70000, started + 70000 + 4000), first);
      expect(t.id(140000, started + 140000 + 8000), first);
      expect(tracker().id(150000, started + 150000 + 8000), first);
    });

    test('a date changed while the app is open keeps the id', () {
      final t = tracker();
      final first = t.id(5000, started + 5000);
      expect(t.id(70000, started + 70000 + 86400000), first);
      // And the next launch agrees, because the marker was re-anchored.
      expect(tracker().id(80000, started + 80000 + 86400000), first);
    });

    test('a damaged or missing marker starts a new id without failing', () {
      at('boot.json').writeAsStringSync('{not json');
      expect(tracker().id(5000, started + 5000), 'run-1');
      at('boot.json').writeAsStringSync('{"id":"","mono":1,"wall":2}');
      expect(tracker().id(5000, started + 5000), 'run-2');
      final missing = BootTracker(
        File('${dir.path}/no/such/folder/boot.json'),
        newId: () => 'made',
      );
      expect(missing.id(1, 2), 'made');
    });

    test('ids are random and unlike Android\'s unknown markers', () {
      final a = BootTracker(at('a.json')).id(1, 2);
      final b = BootTracker(at('b.json')).id(1, 2);
      expect(a, isNot(b));
      expect(a.length, 32);
      expect(a, isNot(anyOf('unknown', '-1')));
    });
  });

  group('a running service across sleep and restart', () {
    late int mono, wall;
    DesktopClock clock() => DesktopClock(
      monotonicMs: () => mono,
      wallMs: () => wall,
      boot: BootTracker(at('boot.json')),
    );
    setUp(() {
      mono = 400000;
      wall = 1700000000000;
    });

    test('time asleep counts, by the counter rather than the date', () {
      final c = clock();
      final begun = c.read();
      final s = transition(
        transition(
          Session(id: 'idle', anchor: begun),
          'load',
          begun,
          value: timeline(),
        ),
        'start',
        begun,
      );
      // Lid closed for four minutes; meanwhile the date was set back.
      mono += 240000;
      wall += 240000 - 3600000;
      final now = c.read();
      expect(now.sameBoot(begun), isTrue);
      expect(now.since(begun), 240000);
      expect(s.remaining(now), 10 * 60000 - 240000);
      final recovered = recover(s, now);
      expect(recovered.uncertain, isFalse);
    });

    test(
      'after a restart the date is used and the service asks for review',
      () {
        final begun = clock().read();
        var s = transition(
          transition(
            Session(id: 'idle', anchor: begun),
            'load',
            begun,
            value: timeline(),
          ),
          'start',
          begun,
        );
        s.checkpoint = begun;
        // PC restarted: counter starts again, three minutes passed.
        mono = 20000;
        wall += 180000;
        final now = clock().read();
        expect(now.sameBoot(begun), isFalse);
        expect(now.since(begun), 180000);
        s = recover(s, now);
        expect(s.uncertain, isTrue);
        expect(s.held, isTrue);
      },
    );
  });

  group('atomic saves', () {
    test('reads back what was written, and null before anything is', () async {
      final f = AtomicTextFile.json(at('state.json'));
      expect(await f.read(), isNull);
      await f.write('{"a":1}');
      expect(await f.read(), '{"a":1}');
      await f.write('{"a":2}');
      expect(await f.read(), '{"a":2}');
      expect(at('state.json.bak').readAsStringSync(), '{"a":1}');
      expect(at('state.json.tmp').existsSync(), isFalse);
    });

    test('an interrupted save leaves the previous version in place', () async {
      final f = AtomicTextFile.json(at('state.json'));
      await f.write('{"a":1}');
      // A crash while writing: a partial temporary file is left behind.
      at('state.json.tmp').writeAsStringSync('{"a":');
      expect(await f.read(), '{"a":1}');
      await f.write('{"a":3}');
      expect(await f.read(), '{"a":3}');
    });

    test('a damaged or missing main file falls back to the backup', () async {
      final f = AtomicTextFile.json(at('state.json'));
      await f.write('{"a":1}');
      await f.write('{"a":2}');
      at('state.json').writeAsStringSync('');
      expect(await f.read(), '{"a":1}');
      // The damaged file is not promoted to be the next backup.
      await f.write('{"a":4}');
      expect(at('state.json.bak').readAsStringSync(), '{"a":1}');
      at('state.json').deleteSync();
      expect(await f.read(), '{"a":1}');
    });

    test('saves asked for together land in order', () async {
      final f = AtomicTextFile.json(at('state.json'));
      await Future.wait([for (var i = 0; i < 20; i++) f.write('{"n":$i}')]);
      expect(await f.read(), '{"n":19}');
    });

    test(
      'a failed save reports the error and later saves still work',
      () async {
        final blocked = Directory('${dir.path}/blocked')..createSync();
        // A folder where the temporary file should go makes the write fail.
        Directory('${blocked.path}/s.json.tmp').createSync();
        final f = AtomicTextFile.json(File('${blocked.path}/s.json'));
        await expectLater(f.write('{"a":1}'), throwsA(anything));
        Directory('${blocked.path}/s.json.tmp').deleteSync();
        await f.write('{"a":2}');
        expect(await f.read(), '{"a":2}');
      },
    );

    test('creates its folder on first save', () async {
      final f = AtomicTextFile.json(File('${dir.path}/new/deeper/s.json'));
      await f.write('{}');
      expect(await f.read(), '{}');
    });
  });

  group('preferences', () {
    test('keep values across reloads and remove on null', () async {
      final prefs = JsonPrefs(at('p.json'));
      await prefs.update({'a': 1, 'b': 'two'});
      await prefs.set('c', [1, 2]);
      await prefs.remove('a');
      final again = JsonPrefs(at('p.json'));
      expect(await again.all(), {
        'b': 'two',
        'c': [1, 2],
      });
      expect(await again.contains('a'), isFalse);
      expect(await again.get('b'), 'two');
    });

    test('an unreadable file starts empty', () async {
      at('p.json').writeAsStringSync('[1,2');
      final prefs = JsonPrefs(at('p.json'));
      expect(await prefs.all(), isEmpty);
      await prefs.set('x', true);
      expect(jsonDecode(at('p.json').readAsStringSync()), {'x': true});
    });
  });

  group('saved passwords', () {
    SecretVault vault({int max = 128}) => SecretVault(
      JsonPrefs(at('vault.json')),
      FakeProtector(),
      maxLength: max,
    );

    test('round-trip, and are not stored as plain text', () async {
      await vault().save('sign-1', 'Pässw0rd ✓');
      expect(await vault().read('sign-1'), 'Pässw0rd ✓');
      expect(await vault().contains('sign-1'), isTrue);
      final raw = at('vault.json').readAsStringSync();
      expect(raw, isNot(contains('Pässw0rd')));
      expect(raw, isNot(contains(base64Encode(utf8.encode('Pässw0rd ✓')))));
    });

    test('a missing entry is null and forgetting removes it', () async {
      final v = vault();
      expect(await v.read('nothing'), isNull);
      await v.save('wifi:sign-1', 'wifi-password');
      await v.forget('wifi:sign-1');
      expect(await v.read('wifi:sign-1'), isNull);
      expect(await v.contains('wifi:sign-1'), isFalse);
    });

    test('a value moved to another entry does not open', () async {
      final v = vault();
      await v.save('sign-1', 'secret-one');
      final stored = jsonDecode(at('vault.json').readAsStringSync()) as Map;
      at(
        'vault.json',
      ).writeAsStringSync(jsonEncode({'sign-2': stored['sign-1']}));
      await expectLater(
        vault().read('sign-2'),
        throwsA(
          isA<RuleError>().having(
            (e) => e.message,
            'message',
            contains('Forget it and enter the password again'),
          ),
        ),
      );
    });

    test('limits match Android', () async {
      await expectLater(vault().save('', 'x'), throwsA(isA<RuleError>()));
      await expectLater(vault().save('id', ''), throwsA(isA<RuleError>()));
      await expectLater(
        vault().save('id', 'x' * 129),
        throwsA(isA<RuleError>()),
      );
      await vault(max: 65536).save('registry', 'x' * 60000);
      expect((await vault(max: 65536).read('registry'))!.length, 60000);
    });
  });
}
