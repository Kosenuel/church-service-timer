import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/pairing.dart';
import '../support/waiting.dart';
import '../support/widget_setup.dart';

// A stage screen that joins while the host's display is the simulator (the
// default) was left on a waiting message with nothing on the host to say
// why. The host now counts such screens so Live can offer to show on them.

void main() {
  test('a stage screen joining a running service is counted as waiting until '
      'the host shows on stage screens', () async {
    final c = AppController(FakePort()), stage = PairHub();
    await c.initialize(startTicker: false);
    addTearDown(() async {
      await stage.stop();
      await c.pairing.stop();
      stage.dispose();
      c.dispose();
    });
    await c.act(
      'load',
      value: Timeline('Service', const [Segment('Talk', 5)], DisplaySettings()),
    );
    await c.act('start');
    expect(c.destination, 'simulator');
    expect(c.stageScreensWaiting, 0);

    await c.pairing.host('127.0.0.1');
    expect(c.stageScreensWaiting, 0);
    await stage.join(c.pairing.code!.encode(), 'Office PC', 'stage');
    await until(() => c.pairing.peers.isNotEmpty);
    // Not counted until the host has approved it.
    expect(c.stageScreensWaiting, 0);
    await c.pairing.approve(c.pairing.peers.single);
    await until(() => stage.snapshot != null);
    expect(c.stageScreensWaiting, 1);
    expect(stage.snapshot!['stageSharing'], isFalse);

    expect(await c.selectDestination('mobile'), isTrue);
    expect(c.stageScreensWaiting, 0);
    await until(() => stage.snapshot?['stageSharing'] == true);
    expect(stage.snapshot!['remaining'], isNotEmpty);

    // Sharing to stage screens switched off again: waiting once more.
    c.pairing.setStageSharing(false);
    expect(c.stageScreensWaiting, 1);
    c.pairing.setStageSharing(true);
    expect(c.stageScreensWaiting, 0);

    // An operator's device is not a stage screen.
    expect(await c.selectDestination('simulator'), isTrue);
    expect(c.stageScreensWaiting, 1);
    await stage.stop();
    await until(() => c.pairing.stagePeers.isEmpty);
    expect(c.stageScreensWaiting, 0);
  });

  testWidgets(
    'Live says a stage screen is waiting and shows on it in one tap',
    (t) async {
      setScreen(t);
      late AppController c;
      late PairHub stage;
      await t.runAsync(() async {
        c = AppController(FakePort());
        stage = PairHub();
        await c.initialize(startTicker: false);
        await c.act('load', value: c.state.templates.first);
        await c.act('start');
        await c.pairing.host('127.0.0.1');
        await pair(c.pairing, stage);
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('stage-screens-waiting')),
        findsOneWidget,
      );
      expect(
        find.textContaining('A stage screen has joined but is not being shown'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      final button = t.widget<TextButton>(
        find.byKey(const ValueKey('show-on-stage-screens')),
      );
      await t.runAsync(() async {
        button.onPressed!();
        await until(() => stage.snapshot?['stageSharing'] == true);
      });
      await t.pumpAndSettle();
      expect(c.destination, 'mobile');
      expect(c.stageScreensWaiting, 0);
      expect(find.byKey(const ValueKey('stage-screens-waiting')), findsNothing);
      await t.runAsync(() async {
        await stage.stop();
        await c.pairing.stop();
      });
      await t.pumpWidget(const SizedBox());
    },
  );
}
