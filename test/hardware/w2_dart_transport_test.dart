import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/w2/w2_transport.dart';
import 'package:church_service_timer/hardware/w2_program.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_w2_controller.dart';

// The Dart sign transport against a synthetic W2 on the loopback
// interface: real UDP packets, no hardware.

class MemoryPrefs implements W2Preferences {
  final Json values = {};
  @override
  Future<Json> read() async => Map<String, dynamic>.from(values);
  @override
  Future<void> write(Json changes) async {
    for (final e in changes.entries) {
      if (e.value == null) {
        values.remove(e.key);
      } else {
        values[e.key] = e.value;
      }
    }
  }
}

void main() {
  late FakeW2Controller sign;
  late MemoryPrefs prefs;
  late W2Transport w2;

  setUp(() async {
    sign = await FakeW2Controller.start();
    prefs = MemoryPrefs();
    w2 = W2Transport(
      prefs: prefs,
      port: sign.port,
      routes: () async => [
        (
          local: InternetAddress.loopbackIPv4,
          target: InternetAddress.loopbackIPv4,
        ),
      ],
    );
  });
  tearDown(() async {
    await w2.disconnect();
    sign.close();
  });

  Future<Json> connected() async {
    await w2.discover();
    return w2.connect(FakeW2Controller.idHex, 'Sign1234');
  }

  test('finds the sign and reads its details', () async {
    final found = await w2.discover();
    expect(found, hasLength(1));
    expect(found.single['id'], FakeW2Controller.idHex);
    expect(found.single['name'], 'Hall sign');
    expect(found.single['firmware'], 'HD_W2 V6.02.232');
    expect(found.single['supported'], isTrue);
    expect(found.single['address'], '127.0.0.1');
  });

  test('connects with the password and remembers which sign', () async {
    final profile = await connected();
    expect(profile['generation'], isA<int>());
    expect(sign.logins.single, endsWith('_ChurchServiceTimer_Windows'));
    expect(prefs.values['hardware'], isTrue);
    expect(prefs.values['id'], FakeW2Controller.idHex);
    expect(prefs.values['name'], 'Hall sign');
    expect(prefs.values.values, isNot(contains('Sign1234')));
    expect((await w2.preferences())['autoReconnect'], isTrue);
    // The same installation id is used for every later login.
    final installation = prefs.values['installation'];
    await connected();
    expect(prefs.values['installation'], installation);
    expect(sign.logins.last, startsWith('${installation}__'));
  });

  test('a wrong password is reported as such and nothing is kept', () async {
    await w2.discover();
    await expectLater(
      w2.connect(FakeW2Controller.idHex, 'wrong-password'),
      throwsA(
        isA<RuleError>().having(
          (e) => e.message,
          'message',
          'Display password was rejected.',
        ),
      ),
    );
    expect(prefs.values['hardware'], isNot(true));
    expect((await w2.status())['connected'], isFalse);
  });

  test('never logs in to firmware that was not verified', () async {
    sign.firmware = 'HD_W2 V6.02.233';
    final found = await w2.discover();
    expect(found.single['supported'], isFalse);
    await expectLater(
      w2.connect(FakeW2Controller.idHex, 'Sign1234'),
      throwsA(isA<RuleError>()),
    );
    expect(sign.logins, isEmpty);
    expect(sign.commands, isEmpty);
  });

  test('never logs in to a sign of another size', () async {
    sign.width = 64;
    await w2.discover();
    await expectLater(
      w2.connect(FakeW2Controller.idHex, 'Sign1234'),
      throwsA(isA<RuleError>()),
    );
    expect(sign.logins, isEmpty);
  });

  test('connecting needs a scan first', () async {
    await expectLater(
      w2.connect(FakeW2Controller.idHex, 'Sign1234'),
      throwsA(isA<RuleError>()),
    );
  });

  test('sends a frame program in order and whole', () async {
    final generation = (await connected())['generation'] as int;
    final program = W2Program.frames([List.filled(512, false)]);
    final result = await w2.send(program, null, generation);
    expect(result['accepted'], isTrue);
    expect(result['generation'], generation);
    expect(sign.programs.single, program);
    expect(sign.commands.map((c) => c.command), [2, 3, 4]);
  });

  test('a large program is split into 4096-byte packets', () async {
    final generation = (await connected())['generation'] as int;
    final frame = List.generate(512, (i) => i.isEven);
    final program = W2Program.frames(List.filled(150, frame));
    expect(program.length, greaterThan(8192));
    await w2.send(program, null, generation);
    expect(sign.programs.single, program);
    final chunks = sign.commands.where((c) => c.command == 3).toList();
    expect(chunks.length, (program.length + 4095) ~/ 4096);
    for (var i = 0; i < chunks.length; i++) {
      expect(ByteData.sublistView(chunks[i].body).getUint16(3), i);
    }
  });

  test('a countdown sets the sign clock, then its deadline', () async {
    final generation = (await connected())['generation'] as int;
    final target = DateTime.now().millisecondsSinceEpoch + 600000;
    await w2.send(W2Program.countdown(0), target, generation);
    expect(sign.commands.first.command, 20);
    expect(sign.commands.first.body.length, 14);
    final offset = DateTime.fromMillisecondsSinceEpoch(
      target,
    ).timeZoneOffset.inMilliseconds;
    expect(
      ByteData.sublistView(sign.programs.single).getUint32(144),
      (target + offset) ~/ 1000,
    );
    final rtc = ByteData.sublistView(sign.commands.first.body).getUint32(1);
    final localNow = (DateTime.now().millisecondsSinceEpoch + offset) ~/ 1000;
    expect((rtc - localNow).abs(), lessThan(5));
  });

  test('a countdown outside 00:01–59:59 is refused before sending', () async {
    final generation = (await connected())['generation'] as int;
    final now = DateTime.now().millisecondsSinceEpoch;
    await expectLater(
      w2.send(W2Program.countdown(0), now + 3600000, generation),
      throwsA(isA<RuleError>()),
    );
    expect(sign.commands, isEmpty);
  });

  test('the clock program is checked and sets the sign clock', () async {
    final generation = (await connected())['generation'] as int;
    for (final twelve in [false, true]) {
      sign.commands.clear();
      final g = twelve ? (await connected())['generation'] as int : generation;
      sign.commands.clear();
      final program = W2Program.clock(format12Hour: twelve);
      await w2.send(program, null, g);
      expect(sign.commands.first.command, 20);
      expect(sign.programs.last, program);
    }
    final g = (await connected())['generation'] as int;
    sign.commands.clear();
    final damaged = W2Program.clock()..[150] ^= 1;
    await expectLater(w2.send(damaged, null, g), throwsA(isA<RuleError>()));
    expect(sign.commands, isEmpty);
  });

  test('anything that is not one of the app\'s programs is refused', () async {
    var generation = (await connected())['generation'] as int;
    await expectLater(
      w2.send(Uint8List(300), null, generation),
      throwsA(isA<RuleError>()),
    );
    final wrongKind = W2Program.frames([List.filled(512, false)])..[142] = 0x31;
    await expectLater(
      w2.send(wrongKind, null, generation),
      throwsA(isA<RuleError>()),
    );
    generation = (await connected())['generation'] as int;
    sign.commands.clear();
    // A timer deadline with a program that is not the countdown.
    await expectLater(
      w2.send(
        W2Program.clock(),
        DateTime.now().millisecondsSinceEpoch + 60000,
        generation,
      ),
      throwsA(isA<RuleError>()),
    );
    expect(sign.commands, isEmpty);
  });

  test('one lost acknowledgement is retried without sending twice', () async {
    final generation = (await connected())['generation'] as int;
    sign.dropNext = 1;
    final program = W2Program.frames([List.filled(512, true)]);
    final result = await w2.send(program, null, generation);
    expect(result['accepted'], isTrue);
    expect(sign.programs.single, program);
    expect(sign.commands.map((c) => c.command), [2, 3, 4]);
  });

  test('no acknowledgement fails the send and closes the session', () async {
    final generation = (await connected())['generation'] as int;
    sign.acknowledge = false;
    await expectLater(
      w2.send(W2Program.frames([List.filled(512, false)]), null, generation),
      throwsA(
        isA<RuleError>().having(
          (e) => e.message,
          'message',
          contains('No acknowledgement'),
        ),
      ),
    );
    sign.acknowledge = true;
    // The old connection is gone: its generation no longer sends.
    await expectLater(
      w2.send(W2Program.frames([List.filled(512, false)]), null, generation),
      throwsA(isA<RuleError>()),
    );
  });

  test('a rejected command is reported with its status', () async {
    final generation = (await connected())['generation'] as int;
    sign.rejectWith = -3;
    await expectLater(
      w2.send(W2Program.frames([List.filled(512, false)]), null, generation),
      throwsA(
        isA<RuleError>().having((e) => e.message, 'message', contains('(-3)')),
      ),
    );
  });

  test('status follows the sign coming and going', () async {
    expect(await w2.status(), {'connected': false});
    final generation = (await connected())['generation'] as int;
    expect(await w2.status(), {'connected': true, 'generation': generation});
    sign.answerDiscovery = false;
    final missing = await w2.status();
    expect(missing['connected'], isFalse);
    expect(missing['generation'], generation);
    expect(missing['reason'], isNotEmpty);
    // A missed health reply alone does not close the session.
    sign.answerDiscovery = true;
    expect((await w2.status())['connected'], isTrue);
  });

  test('disconnecting, the simulator and forgetting', () async {
    final generation = (await connected())['generation'] as int;
    await w2.simulator();
    expect(prefs.values['hardware'], isFalse);
    expect(prefs.values['id'], FakeW2Controller.idHex);
    await expectLater(
      w2.send(W2Program.frames([List.filled(512, false)]), null, generation),
      throwsA(isA<RuleError>()),
    );
    await connected();
    await w2.autoReconnect(false);
    expect((await w2.preferences())['autoReconnect'], isFalse);
    await w2.forget();
    expect(await w2.preferences(), {
      'hardware': false,
      'id': '',
      'autoReconnect': false,
      'name': '',
    });
  });

  test('device settings are sent once and close the session', () async {
    final generation = (await connected())['generation'] as int;
    sign.commands.clear();
    final outcome = await w2.administer('ssid', 'Hall_Sign', generation);
    expect(outcome, {'acknowledged': true});
    expect(sign.commands.single.command, 39);
    expect((await w2.status())['connected'], isFalse);

    // Never retried: a lost reply may still mean the setting changed.
    final next = (await connected())['generation'] as int;
    sign.commands.clear();
    sign.acknowledge = false;
    expect(await w2.administer('devicePassword', 'Str0ng!pass', next), {
      'acknowledged': false,
    });
    expect(sign.commands.single.command, 49);
  });

  test(
    'device settings need the verified firmware and a live session',
    () async {
      final generation = (await connected())['generation'] as int;
      await expectLater(
        w2.administer('ssid', 'Hall_Sign', generation + 1),
        throwsA(isA<RuleError>()),
      );
      sign.pwdComplexity = 0;
      final next = (await connected())['generation'] as int;
      sign.commands.clear();
      await expectLater(
        w2.administer('ssid', 'Hall_Sign', next),
        throwsA(isA<RuleError>()),
      );
      expect(sign.commands, isEmpty);
    },
  );

  test('the search goes out on every network and skips a dead one', () async {
    final both = W2Transport(
      prefs: prefs,
      port: sign.port,
      routes: () async => [
        // TEST-NET-1: not an address of this machine, so binding fails.
        (
          local: InternetAddress('192.0.2.1'),
          target: InternetAddress('192.0.2.255'),
        ),
        (
          local: InternetAddress.loopbackIPv4,
          target: InternetAddress.loopbackIPv4,
        ),
      ],
    );
    expect((await both.discover()).single['id'], FakeW2Controller.idHex);
    expect(
      (await both.connect(FakeW2Controller.idHex, 'Sign1234'))['name'],
      'Hall sign',
    );
    expect(both.localAddress, '127.0.0.1');
    await both.disconnect();
    expect(both.localAddress, isNull);
  });

  test('no network at all is explained', () async {
    final none = W2Transport(prefs: prefs, routes: () async => []);
    await expectLater(none.discover(), throwsA(isA<RuleError>()));
  });
}
