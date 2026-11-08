import 'dart:async';
import 'dart:typed_data';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_port.dart';

/// A synthetic W2 LED sign, and an app connected to it.

class W2Port extends FakePort {
  final sent = <({Uint8List bytes, int? deadline})>[];
  Completer<Json>? sendGate;
  bool acknowledged = true, reachable = true, hardwarePreference = false;
  int nativeGeneration = 4;
  final profile = <String, dynamic>{
    'id': 'synthetic-w2',
    'name': 'Test sign',
    'firmware': 'HD_W2 V6.02.232',
    'width': 32,
    'height': 16,
    'address': '192.0.2.1',
    'supported': true,
  };
  @override
  Future<Json> displayPreferences() async => {
    'hardware': hardwarePreference,
    'id': 'synthetic-w2',
    'name': 'Test sign',
  };
  @override
  Future<List<Json>> discoverDisplays() async => [profile];
  @override
  Future<Json> connectDisplay(String id, String password) async => {
    ...profile,
    'generation': nativeGeneration,
  };
  @override
  Future<Json> checkDisplay() async => {
    'connected': reachable,
    'generation': nativeGeneration,
  };
  @override
  Future<Json> sendDisplay(
    Uint8List bytes,
    int generation,
    int? deadline,
  ) async {
    sent.add((bytes: bytes, deadline: deadline));
    return sendGate?.future ??
        Future.value({
          'accepted': acknowledged,
          'generation': nativeGeneration,
        });
  }
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<AppController> setup(W2Port port, {bool started = true}) async {
  final c = AppController(port);
  await c.initialize(startTicker: false);
  await c.hardware.discover();
  expect(await c.hardware.connect('synthetic-w2', 'synthetic'), true);
  await c.act('load', value: timeline());
  if (started) {
    await c.act('start');
    await flush();
  }
  return c;
}

class RecoveryPort extends W2Port {
  int connects = 0;
  bool auto = true, found = true;
  String? saved;
  Completer<List<Json>>? discoveryGate;
  Completer<void>? preferenceGate;
  @override
  Future<void> setDisplayAutoReconnect(bool value) async {
    auto = value;
    if (value) await preferenceGate?.future;
  }

  @override
  Future<Json> displayPreferences() async => {
    ...await super.displayPreferences(),
    'autoReconnect': auto,
  };
  @override
  Future<String?> savedDisplayPassword(String id) async => saved;
  @override
  Future<List<Json>> discoverDisplays() async =>
      discoveryGate?.future ?? (found ? [profile] : []);
  @override
  Future<Json> connectDisplay(String id, String password) async {
    connects++;
    nativeGeneration++;
    return super.connectDisplay(id, password);
  }
}

Future<void> outage(AppController c, RecoveryPort p) async {
  p.reachable = false;
  for (final second in [10, 12, 14]) {
    p.at = after(second);
    await c.hardware.check(p.at);
  }
}
