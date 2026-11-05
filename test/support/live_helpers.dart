import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';

/// Opens the Live ⋮ menu in the header and selects [item].
Future<void> openLiveMenu(WidgetTester t, String item) async {
  await t.tap(find.byKey(const ValueKey('live-menu')));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

/// Taps the current segment title, which opens Jump to segment.
Future<void> tapJump(WidgetTester t) async {
  final target = find.byKey(const ValueKey('jump-to-segment'));
  await Scrollable.ensureVisible(t.element(target), alignment: 0.5);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

/// Waits past the Show timer double-tap guard.
Future<void> passShowTimerGuard(WidgetTester t) async {
  await t.pump(ShowTimerButton.guard + const Duration(milliseconds: 50));
  await t.pumpAndSettle();
}
