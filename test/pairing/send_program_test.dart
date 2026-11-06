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
    host.snapshotFor = (_) => {'revision': 1};
    await host.host('127.0.0.1');
    final viewerId = await pair(host, viewer, role: 'viewer');
    final stageId = await pair(host, stage);
    await eventually(() => host.syncedStagePeers.isNotEmpty);
    expect(host.programRecipients.map((p) => p.id), [viewerId]);
    final program = portableProgram(timeline().toJson());
    final sent = await host.sendProgram(program, {
      viewerId,
      stageId,
    }, 'Grace Chapel');
    expect(sent, 1);
    await eventually(() => viewer.receivedPrograms.isNotEmpty);
    final received = viewer.receivedPrograms.single;
    expect(received.program.name, 'Sunday');
    expect(received.program.id, isEmpty);
    expect(received.from, 'Grace Chapel');
    expect(stage.receivedPrograms, isEmpty);
    // Sending again replaces, rather than stacks, the same program.
    await host.sendProgram(program, {viewerId}, 'Grace Chapel');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(viewer.receivedPrograms, hasLength(1));
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

  testWidgets('Review on the paired phone updates its program', (t) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final mine = c.state.templates.first;
    c.pairing.receivedPrograms.add(
      ReceivedProgram(
        Timeline(mine.name, [
          ...mine.segments,
          const Segment('Offering', 4),
        ], mine.display),
        'Grace Chapel',
        0,
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
      for (var i = 0; i < 50 && c.pairing.receivedPrograms.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await t.pumpAndSettle();
    expect(c.pairing.receivedPrograms, isEmpty);
    expect(c.state.templates.first.segments.last.name, 'Offering');
    expect(c.state.versionsOf(mine.id), hasLength(1));
    await t.pumpWidget(const SizedBox());
  });
}
