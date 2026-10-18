import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app_theme.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/native_fonts.dart';
import 'domain_test.dart' show FakePort;
import 'feature_cases.dart' show epoch, at;
import 'revision_03_test.dart' show FontPort, NotificationPort;
import 'revision_09_test.dart' show FeedbackPort;
import 'revision_10_cases.dart';

void main() {
  for (final e in revision10Cases.entries) {
    test(e.key, e.value);
  }
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<AppController> setup(FakePort port) async {
    port.at = epoch;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    return c;
  }

  void size(WidgetTester t, [Size value = const Size(430, 1100)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, String text) async {
    final f = find.text(text).last;
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  test(
    'Shared warnings save atomically, reschedule and survive restart',
    () async {
      final port = NotificationPort();
      final c = await setup(port);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      port.at = at(20);
      port.fail = true;
      final before = c.state.defaults.toJson();
      expect(
        await c.setSharedWarnings(const [
          WarningRule(50, TextLayout('OLD')),
          WarningRule(10, TextLayout('FUTURE')),
        ]),
        false,
      );
      expect(c.state.defaults.toJson(), before);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(
        c.state.templates.every((t) => t.display.warnings.length == 2),
        true,
      );
      expect(c.state.session.warningSeen, [0]);
      expect(port.plans.last['notice'], isNull);
      expect((port.plans.last['alarms'] as List).single['title'], 'FUTURE');
      c.dispose();
      final restored = AppController(port);
      await restored.initialize(startTicker: false);
      expect(restored.state.defaults.warnings.last.seconds, 10);
      restored.dispose();
    },
  );

  test(
    'Blank waits for durable save, survives restart and disconnected output',
    () async {
      final port = FakePort();
      final c = await setup(port);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      final pixels = [...c.simulator.pixels];
      port.fail = true;
      expect(await c.act('blank'), false);
      expect(c.simulator.pixels, pixels);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.simulator.pixels.any((p) => p), false);
      await c.act('disconnect');
      port.at = at(15);
      await c.tick();
      expect(c.state.session.remaining(c.now), 45000);
      c.dispose();
      final restored = AppController(port);
      await restored.initialize(startTicker: false);
      expect(restored.state.session.outputBlank, true);
      await restored.act('connect');
      expect(restored.simulator.pixels.any((p) => p), false);
      await restored.act('timer');
      expect(restored.simulator.delivered!.text, '00:45');
      restored.dispose();
    },
  );

  test(
    'Tinos caches all four style combinations independently without font import',
    () async {
      final port = FontPort();
      await NativeDisplayFonts.initialize(port);
      for (final bold in [false, true]) {
        for (final italic in [false, true]) {
          final layout = TextLayout(
            'AMEN',
            font: 'tinos',
            bold: bold,
            italic: italic,
            height: 2,
          );
          await NativeDisplayFonts.prepare(layout);
          await NativeDisplayFonts.prepare(layout);
          expect(NativeDisplayFonts.cached(layout), isNotNull);
        }
      }
      expect(port.renders, 4);
    },
  );

  test(
    'Diagnostic categories never include private content or raw exceptions',
    () async {
      final c = await setup(FakePort());
      c.state.churchName = 'PRIVATE CHURCH';
      c.error = 'PRIVATE TOKEN /secret/path';
      c.notificationError = 'PRIVATE CUE';
      final details = c.feedbackDiagnostics;
      expect(details, contains('app action, notifications'));
      for (final text in ['PRIVATE', '/secret', 'TOKEN']) {
        expect(details, isNot(contains(text)));
      }
      c.dispose();
    },
  );

  testWidgets(
    'Header status opens accurate connection details and updates on disconnect',
    (t) async {
      size(t);
      final c = await setup(FakePort());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final status = find.byKey(const ValueKey('header-connection'));
      expect(
        t.getCenter(status).dx,
        greaterThan(t.getCenter(find.text(appName)).dx),
      );
      await t.tap(status);
      await t.pumpAndSettle();
      expect(find.text('Physical delivery'), findsOneWidget);
      expect(
        find.text('Available after connecting a supported W2 display'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/connection-phone.png'),
      );
      await tap(t, 'Disconnect simulator');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        find.byTooltip('Disconnected · connection details'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Readiness preview does not change timing or publish a cue', (
    t,
  ) async {
    size(t);
    final c = await setup(FakePort());
    await c.act('load', value: c.state.templates.last);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final before = jsonEncode(c.state.toJson());
    final pixels = [...c.simulator.pixels];
    await tap(t, 'Ready for service');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/readiness-phone.png'),
    );
    await tap(t, 'Preview test cue');
    expect(find.text('Isolated simulator test'), findsOneWidget);
    expect(jsonEncode(c.state.toJson()), before);
    expect(c.simulator.pixels, pixels);
    await tap(t, 'Close');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Focused operator view keeps confirmations and explicit display controls',
    (t) async {
      size(t, const Size(650, 1500));
      final c = await setup(FakePort());
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Focused operator view');
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('SERVICE TIMING OVERVIEW'), findsNothing);
      expect(find.byType(WarningSettingsPanel), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/operator-focus.png'),
      );
      await t.tap(find.byTooltip('Pause'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, false);
      await tap(t, 'Cancel');
      await tap(t, 'Blank sign');
      expect(c.state.session.outputBlank, false);
      await tap(t, 'Blank simulator');
      expect(c.state.session.outputBlank, true);
      await tap(t, 'Show timer');
      expect(c.state.session.outputBlank, false);
      await tap(t, 'Exit focused view');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Segment editor saves private speaker and notes without changing sign output',
    (t) async {
      size(t, const Size(650, 1500));
      final c = await setup(FakePort());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(1));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('template-row:Quick rehearsal')));
      await t.pumpAndSettle();
      await tap(t, 'Edit template');
      await tap(t, 'Welcome');
      await t.enterText(
        find.widgetWithText(TextField, 'Speaker (optional)'),
        'Pastor Grace',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Private operator notes'),
        'Check the microphone',
      );
      t.testTextInput.hide();
      await tap(t, 'Save segment');
      await t.scrollUntilVisible(
        find.text('Save timeline'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(TemplateEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(t, 'Save timeline');
      expect(c.state.templates.last.segments.first.speaker, 'Pastor Grace');
      expect(
        c.state.templates.last.segments.first.notes,
        'Check the microphone',
      );
      expect(c.simulator.delivered, isNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Feedback diagnostics are opt-in, visible for review and removable',
    (t) async {
      size(t);
      final port = FeedbackPort();
      final c = await setup(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(2));
      await t.pumpAndSettle();
      await tap(t, 'Feedback Center');
      await t.enterText(find.byKey(const ValueKey('feedback-title')), 'Test');
      await t.enterText(
        find.byKey(const ValueKey('feedback-message')),
        'Check the timer',
      );
      await t.enterText(
        find.byKey(const ValueKey('feedback-contact')),
        'user@example.com',
      );
      t.testTextInput.hide();
      await t.pumpAndSettle();
      await tap(t, 'Open email app');
      expect(
        port.messages.last['body'],
        isNot(contains('Optional diagnostics')),
      );
      await tap(t, 'Include optional diagnostics');
      expect(find.byKey(const ValueKey('diagnostics-preview')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('diagnostics-preview')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/feedback-diagnostics-phone.png'),
      );
      await tap(t, 'Open email app');
      expect(port.messages.last['body'], contains('Output adapter: Simulator'));
      await tap(t, 'Include optional diagnostics');
      await tap(t, 'Open email app');
      expect(
        port.messages.last['body'],
        isNot(contains('Optional diagnostics')),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Compact Display settings and Appearance support narrow screens and large text',
    (t) async {
      size(t, const Size(320, 1100));
      final c = await setup(FakePort());
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('midnight_lime'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Home(controller: c),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(2));
      await t.pumpAndSettle();
      await tap(t, 'Display settings');
      expect(t.takeException(), isNull);
      await tap(t, 'Display profile');
      expect(find.text('PHYSICAL SIGN'), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(t.element(find.text('Resolution'))).scale(10),
        16,
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/display-profile-large-text.png'),
      );
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, 'Appearance');
      await t.ensureVisible(find.byKey(const ValueKey('theme-warm_ivory')));
      await t.tap(find.byKey(const ValueKey('theme-warm_ivory')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await tap(t, 'Cancel');
      await t.pumpWidget(const SizedBox());
    },
  );
}
