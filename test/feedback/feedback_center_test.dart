import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/feedback/feedback_page.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/platform.dart';
import '../domain/feature_cases.dart' show epoch;
import 'feedback_message_cases.dart';
import '../support/ports.dart';
import '../support/widget_setup.dart';

void main() {
  for (final e in revision09Cases.entries) {
    test(e.key, e.value);
  }
  setUpAll(loadAppFonts);
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) =>
      setScreen(t, value);

  Future<AppController> setup(WidgetTester t, FeedbackPort port) async {
    port.at = epoch;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byType(NavigationDestination).at(4));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Feedback centre'));
    await t.pumpAndSettle();
    await t.tap(find.text('Feedback centre'));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> fill(WidgetTester t) async {
    await t.enterText(
      find.byKey(const ValueKey('feedback-title')),
      'Timer paused unexpectedly',
    );
    await t.enterText(
      find.byKey(const ValueKey('feedback-message')),
      'The timer paused during rehearsal.\nI expected it to keep counting.',
    );
    await t.enterText(
      find.byKey(const ValueKey('feedback-contact')),
      'operator@example.com',
    );
    t.testTextInput.hide();
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Feedback form validates before opening email and retains the complaint afterwards',
    (t) async {
      size(t);
      final port = FeedbackPort();
      final c = await setup(t, port);
      await tap(t, 'Open email app');
      expect(port.messages, isEmpty);
      expect(find.text('Enter a title.'), findsOneWidget);
      expect(find.text('Enter a message.'), findsOneWidget);
      expect(find.text('Enter a contact.'), findsOneWidget);
      await fill(t);
      await t.ensureVisible(find.text('Tell us what happened.'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/feedback-center-phone.png'),
      );
      await tap(t, 'Open email app');
      expect(
        port.messages.single['subject'],
        contains('Timer paused unexpectedly'),
      );
      expect(port.messages.single['body'], contains('operator@example.com'));
      expect(
        port.messages.single['body'],
        contains('Version: ${c.appVersion}'),
      );
      expect(
        find.textContaining('This app cannot confirm delivery'),
        findsOneWidget,
      );
      expect(find.text('Timer paused unexpectedly'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Unavailable email app and launch errors retain text and offer Copy feedback',
    (t) async {
      size(t);
      final port = FeedbackPort()..available = false;
      await setup(t, port);
      await fill(t);
      await tap(t, 'Open email app');
      expect(find.textContaining('No email app is available'), findsOneWidget);
      expect(find.text('Timer paused unexpectedly'), findsOneWidget);
      port.failEmail = true;
      await tap(t, 'Open email app');
      expect(
        find.textContaining('Could not open your email app'),
        findsOneWidget,
      );
      expect(find.text('operator@example.com'), findsOneWidget);
      expect(find.text('Copy feedback'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Copy feedback preserves recipient, subject and body and clear requires confirmation',
    (t) async {
      size(t);
      final port = FeedbackPort();
      await setup(t, port);
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await fill(t);
      await tap(t, 'Copy feedback');
      expect(
        copied,
        startsWith(
          'To: immanuelproton@gmail.com\nSubject: Church Service Timer feedback:',
        ),
      );
      expect(copied, contains('operator@example.com'));
      expect(port.messages, isEmpty);
      await tap(t, 'Clear draft');
      await tap(t, 'Cancel');
      expect(find.text('Timer paused unexpectedly'), findsOneWidget);
      await tap(t, 'Clear draft');
      await t.tap(find.widgetWithText(FilledButton, 'Clear draft'));
      await t.pumpAndSettle();
      expect(find.text('Timer paused unexpectedly'), findsNothing);
      expect(find.byKey(const ValueKey('feedback-status')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'Android email bridge reports hand-off availability with exact content',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidPort.channel, (call) async {
            observed = call;
            return false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AndroidPort.channel, null),
      );
      expect(
        await AndroidPort().composeFeedback(
          'Subject & Unicode 🙏',
          'Line 1\nLine 2',
        ),
        false,
      );
      expect(observed!.method, 'composeFeedback');
      expect(observed!.arguments, {
        'subject': 'Subject & Unicode 🙏',
        'body': 'Line 1\nLine 2',
      });
    },
  );
  testWidgets('Feedback Center stays usable with narrow enlarged text', (
    t,
  ) async {
    size(t, const Size(320, 1100));
    final c = AppController(FeedbackPort()..at = epoch);
    await c.initialize(startTicker: false);
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme('warm_ivory'),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: FeedbackCenterPage(controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    await fill(t);
    await tap(t, 'Open email app');
    expect(
      find.textContaining('This app cannot confirm delivery'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}
