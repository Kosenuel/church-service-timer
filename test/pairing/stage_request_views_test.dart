import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

void main() {
  testWidgets('A request waits on Live; Add 2 min adjusts the time', (t) async {
    t.view.physicalSize = const Size(430, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.commit((d, _) => d.stageRequests = true);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(c.stageRequests.receive('tablet', 'Pulpit tablet', 'time'), isTrue);
    await t.pumpAndSettle();
    final id = c.stageRequests.open.single.id;
    expect(find.text('Need 2 minutes'), findsOneWidget);
    expect(find.textContaining('Pulpit tablet · just now'), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-request-note')), findsOneWidget);
    final before = c.state.session.remaining(c.now);
    await t.tap(find.byKey(ValueKey('add-request-time-$id')));
    await t.pumpAndSettle();
    expect(c.state.session.remaining(c.now) - before, 120000);
    expect(find.byKey(ValueKey('stage-request-$id')), findsNothing);
    // Other requests offer only Acknowledge and Dismiss.
    expect(c.stageRequests.receive('choir', 'Choir phone', 'mic'), isTrue);
    await t.pumpAndSettle();
    final mic = c.stageRequests.open.single.id;
    expect(find.byKey(ValueKey('add-request-time-$mic')), findsNothing);
    await t.tap(find.byKey(ValueKey('dismiss-request-$mic')));
    await t.pumpAndSettle();
    expect(c.stageRequests.open, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The stage screen button sends a fixed choice and shows state', (
    t,
  ) async {
    final sent = <String>[];
    Widget button(Map<String, dynamic>? status) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: StageRequestButton(
            status: status,
            enabled: true,
            onSend: (k) async => sent.add(k),
          ),
        ),
      ),
    );
    await t.pumpWidget(button(null));
    await t.tap(find.byKey(const ValueKey('stage-request-button')));
    await t.pumpAndSettle();
    expect(find.text('Ready to finish'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('send-request-finish')));
    await t.pumpAndSettle();
    expect(sent, ['finish']);
    await t.pumpWidget(
      button({'kind': 'finish', 'label': 'Ready to finish', 'state': 'sent'}),
    );
    expect(find.text('Sent · Ready to finish'), findsOneWidget);
    await t.pumpWidget(
      button({'kind': 'finish', 'label': 'Ready to finish', 'state': 'seen'}),
    );
    expect(find.text('Seen by operator'), findsOneWidget);
  });
}
