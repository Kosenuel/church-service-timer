import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/programs/send_program_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort, start, timeline;
import 'saved_devices_test.dart' show eventually, pair;

void main() {
  test('The host sends a program to a viewer, not to a stage screen', () async {
    final host = PairHub(), viewer = PairHub(), stage = PairHub();
    addTearDown(() async {
      for (final h in [viewer, stage, host]) {
        await h.stop();
        h.dispose();
      }
    });
    final got = <(Timeline, String)>[], stageGot = <Timeline>[];
    viewer.onProgramReceived = (p, from) => got.add((p, from));
    stage.onProgramReceived = (p, _) => stageGot.add(p);
    host.snapshotFor = (_) => {'revision': 1};
    await host.host('127.0.0.1');
    final viewerId = await pair(host, viewer, role: 'viewer');
    final stageId = await pair(host, stage);
    await eventually(() => host.syncedStagePeers.isNotEmpty);
    expect(host.programRecipients.map((p) => p.id), [viewerId]);
    final sent = await host.sendProgram(portableProgram(timeline().toJson()), {
      viewerId,
      stageId,
    }, 'Grace Chapel');
    expect(sent, 1);
    await eventually(() => got.isNotEmpty);
    expect(got.single.$1.name, 'Sunday');
    expect(got.single.$1.id, isEmpty);
    expect(got.single.$2, 'Grace Chapel');
    expect(stageGot, isEmpty);
  });

  test('Received programs wait in saved state, not in backups', () {
    final s = AppState.fresh(start);
    s.receiveProgram(timeline(), 'Grace Chapel', 10);
    s.receiveProgram(timeline(), 'Grace Chapel', 20);
    expect(s.programInbox, hasLength(1), reason: 'Same name replaces');
    for (var i = 0; i < 7; i++) {
      s.receiveProgram(timeline().renamed('P$i'), 'Grace Chapel', 30 + i);
    }
    expect(s.programInbox, hasLength(receivedProgramLimit));
    expect(s.programInbox.first.program.name, 'P6');
    // Kept across a restart, so leaving the pairing loses nothing.
    final reloaded = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(reloaded.programInbox.map((p) => p.program.name).toList(), [
      for (final p in s.programInbox) p.program.name,
    ]);
    expect(exportBackup(s, start), isNot(contains('programInbox')));
    reloaded.dismissReceived(reloaded.programInbox.first);
    expect(reloaded.programInbox, hasLength(receivedProgramLimit - 1));
  });

  test('A received program updates the same-named one or adds a copy', () {
    final s = AppState.fresh(start)..saveTemplate(timeline());
    final mine = s.programNamed('sunday')!;
    final incoming = Timeline('Sunday', [
      ...timeline().segments,
      const Segment('Offering', 4),
    ], DisplaySettings());
    final updated = s.saveReceivedProgram(incoming, update: true, at: 50);
    expect(updated.id, mine.id);
    expect(updated.segments.last.name, 'Offering');
    expect(s.versionsOf(mine.id).single.replacedWall, 50);
    final copy = s.saveReceivedProgram(incoming, update: false, at: 60);
    expect(copy.name, 'Sunday (2)');
    expect(copy.id, isNot(mine.id));
  });

  testWidgets('Review on Programs updates the program and clears the card', (
    t,
  ) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final mine = c.state.templates.first;
    await c.commit(
      (d, at) => d.receiveProgram(
        Timeline(mine.name, [
          ...mine.segments,
          const Segment('Offering', 4),
        ], mine.display),
        'Grace Chapel',
        at.wall,
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReceivedProgramCards(controller: c)),
      ),
    );
    expect(find.text('Program received: ${mine.name}'), findsOneWidget);
    await t.tap(find.text('Review'));
    await t.pumpAndSettle();
    expect(find.text('Update mine'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('save-received')));
      for (var i = 0; i < 50 && c.state.programInbox.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await t.pumpAndSettle();
    expect(c.state.programInbox, isEmpty);
    expect(find.text('Program received: ${mine.name}'), findsNothing);
    expect(c.state.templates.first.segments.last.name, 'Offering');
    expect(c.state.versionsOf(mine.id), hasLength(1));
    await t.pumpWidget(const SizedBox());
  });
}
