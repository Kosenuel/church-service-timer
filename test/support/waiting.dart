import 'package:flutter_test/flutter_test.dart';

/// Polls real-time state (sockets, servers) until it holds.

Future<void> eventually(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  expect(condition(), true);
}

Future<void> until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsedMilliseconds > 8000)
      fail('Timed out waiting for paired state');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
