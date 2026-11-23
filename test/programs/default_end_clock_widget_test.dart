import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// "When the service ends" starts on the clock for a new install.
void main() {
  setUpAll(loadAppFonts);

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<AppController> app(WidgetTester t, {TextLayout? appEnd}) async {
    setScreen(t, const Size(430, 1000));
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    if (appEnd != null) {
      await c.commit(
        (draft, _) => draft.defaults = draft.defaults.withEnd(appEnd),
      );
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  bool clockChosen(WidgetTester t, String choice) {
    final button = t.widget<SegmentedButton<bool>>(key(choice));
    return button.selected.single == false;
  }

  testWidgets('a new program on a new install ends on the clock', (t) async {
    final c = await app(t);
    await t.tap(find.text('Programs').last);
    await t.pumpAndSettle();
    await t.tap(key('new-template'));
    await t.pumpAndSettle();
    expect(clockChosen(t, 'end-screen-choice'), isTrue);
    expect(key('no-end-screen'), findsOneWidget);
    expect(find.text('Use current default'), findsNothing);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/new-program-ends-on-clock-phone.png'),
    );
    expect(c.state.defaults.end, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a church that chose an end screen keeps it for new programs', (
    t,
  ) async {
    await app(t, appEnd: const TextLayout('Go in peace'));
    await t.tap(find.text('Programs').last);
    await t.pumpAndSettle();
    await t.tap(key('new-template'));
    await t.pumpAndSettle();
    expect(clockChosen(t, 'end-screen-choice'), isFalse);
    expect(find.text('End screen · Go in peace'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Settings shows the app-wide choice as the clock on a new install',
    (t) async {
      final c = await app(t);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Display settings'));
      await t.pumpAndSettle();
      expect(find.text('The clock · for new programs'), findsOneWidget);
      await t.ensureVisible(find.text('Default end screen'));
      await t.tap(find.text('Default end screen'));
      await t.pumpAndSettle();
      expect(clockChosen(t, 'default-end-choice'), isTrue);
      expect(find.text('Edit end screen'), findsNothing);
      expect(find.textContaining('show the clock'), findsOneWidget);
      expect(c.state.defaults.end, isNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
