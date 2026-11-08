import 'dart:async';

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/domain/domain.dart';

/// A fixed boot clock and a quick three-segment program for timing tests.

const start = Stamp(100000, 10000000, 'boot-1');
Stamp after(int seconds, {int wallShift = 0, String boot = 'boot-1'}) => Stamp(
  start.mono + seconds * 1000,
  start.wall + seconds * 1000 + wallShift,
  boot,
);
Timeline timeline() => Timeline('Sunday', const [
  Segment('First', 10),
  Segment('Second', 5),
  Segment('Last', 1),
], DisplaySettings());
Session loaded() => transition(
  Session(id: 'idle', anchor: start),
  'load',
  start,
  value: timeline(),
);
Session running() => transition(loaded(), 'start', start);

class FakePort extends DevicePort {
  Stamp at = start;
  String? data;
  bool fail = false;
  Completer<void>? saveGate;
  @override
  Future<Stamp> clock() async => at;
  // A fixed installed version keeps screenshots stable across releases.
  @override
  Future<String> installedVersion() async => '0.0.0 (test)';
  @override
  Future<String?> load() async => data;
  @override
  Future<void> save(String state) async {
    await saveGate?.future;
    if (fail) throw Exception('Disk full');
    data = state;
  }

  @override
  Future<Map<String, dynamic>?> pickFile() async => null;
  @override
  Future<void> exportFile(String filename, String content) async {}
}
