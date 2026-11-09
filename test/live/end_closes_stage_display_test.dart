import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  testWidgets(
    'End service leaves Stage & display closed; before a service it opens for stage screens',
    (t) async {
      setScreen(t, const Size(430, 1100));
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      expect(await c.selectDestination('mobile'), isTrue);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();

      ExpansionTile tile() => t.widget<ExpansionTile>(
        find.byWidgetPredicate(
          (w) => w is ExpansionTile && '${w.key}'.contains('stage-and-display'),
          skipOffstage: false,
        ),
      );
      // Before any service, with stage screens, it starts open.
      expect(tile().initiallyExpanded, isTrue);

      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await t.pumpAndSettle();
      await c.act('end');
      await t.pumpAndSettle();
      expect(c.state.session.phase, 'ended');
      // After End service it is closed, so the finished service leads.
      expect(tile().initiallyExpanded, isFalse);
      expect(find.text('Manage cues', skipOffstage: false), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
}
