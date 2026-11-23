import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'desktop_layout_test.dart' show sunday;

/// Text only has to fit the LED sign's 32 pixels when a sign is the display
/// in use. With stage screens only, Continue is not held back by it.
void main() {
  setUpAll(loadAppFonts);

  const wide = TextLayout('Thank you', effect: 'static');

  group('the fit check', () {
    test('the message every new user gets fits the sign', () {
      validateLayout(const TextLayout('Thank you'));
      expect(const TextLayout('Thank you').effect, 'scroll');
    });

    test('Thank you held still is too wide for the sign', () {
      expect(textWidth(wide), greaterThan(32));
      expect(() => validateLayout(wide), throwsA(anything));
    });

    test('without a sign the same text is allowed', () {
      validateLayout(wide, signFit: false);
    });

    test('other faults are still refused without a sign', () {
      expect(
        () => validateLayout(
          const TextLayout('é€', effect: 'static'),
          signFit: false,
        ),
        throwsA(anything),
      );
    });
  });

  Future<AppController> service(
    WidgetTester t, {
    String kind = 'led',
    String? destination,
  }) async {
    late AppController c;
    await t.runAsync(() async {
      c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.setSimulatorKind(kind);
      await c.act('load', value: sunday());
      await c.act('start');
      if (destination != null) await c.selectDestination(destination);
    });
    return c;
  }

  Future<AppController> open(
    WidgetTester t, {
    String kind = 'led',
    String? destination,
    Size size = const Size(900, 1600),
  }) async {
    setScreen(t, size);
    final c = await service(t, kind: kind, destination: destination);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    unawaited(t.state<HomeState>(find.byType(Home)).sendStageMessage());
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return c;
  }

  Future<void> chooseStatic(WidgetTester t, String label) async {
    await t.tap(find.byKey(const ValueKey('effect-choice')));
    await t.pump(const Duration(milliseconds: 800));
    await t.ensureVisible(find.text(label).last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text(label).last);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  bool continueEnabled(WidgetTester t) =>
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed !=
      null;

  group('Send message', () {
    testWidgets('on the sign, the default message can be continued', (t) async {
      await open(t, destination: 'led');
      expect(continueEnabled(t), isTrue);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('on the sign, Static text too wide still holds Continue off', (
      t,
    ) async {
      await open(t, destination: 'led');
      await chooseStatic(t, 'Static (must fit)');
      expect(continueEnabled(t), isFalse);
      expect(find.textContaining('must fit the LED sign'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('on stage screens, Static text too wide can be continued', (
      t,
    ) async {
      await open(t, destination: 'mobile');
      expect(continueEnabled(t), isTrue);
      await chooseStatic(t, 'Static');
      expect(continueEnabled(t), isTrue);
      expect(find.textContaining('must fit the LED sign'), findsNothing);
      expect(find.text('Static (must fit)'), findsNothing);
      expect(find.textContaining('Too wide for the LED sign'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the note for text too wide for a sign, on a phone', (t) async {
      await open(t, destination: 'mobile', size: const Size(430, 1000));
      await t.enterText(find.byType(TextField).first, 'Thank you all');
      await chooseStatic(t, 'Static');
      expect(continueEnabled(t), isTrue);
      await t.ensureVisible(find.textContaining('Too wide for the LED sign'));
      await t.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../goldens/send-message-wide-static-stage-phone.png',
        ),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('with the stage simulator, Static text can be continued', (
      t,
    ) async {
      await open(t, kind: 'stage');
      await chooseStatic(t, 'Static');
      expect(continueEnabled(t), isTrue);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('sending', () {
    testWidgets('a wide static message goes to stage screens', (t) async {
      final c = await service(t, destination: 'mobile');
      late bool sent;
      await t.runAsync(() async {
        sent = await c.act(
          'message',
          value: const StageOutputMessage(wide),
          revision: c.state.session.revision,
        );
      });
      expect(sent, isTrue, reason: c.error);
      expect(c.state.session.alert?.text, 'Thank you');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the same message is refused when a sign is in use', (t) async {
      final c = await service(t, destination: 'led');
      late bool sent;
      await t.runAsync(() async {
        sent = await c.act(
          'message',
          value: const StageOutputMessage(wide),
          revision: c.state.session.revision,
        );
      });
      expect(sent, isFalse);
      expect(c.error, contains('must fit the LED sign'));
      await t.pumpWidget(const SizedBox());
    });
  });
}
