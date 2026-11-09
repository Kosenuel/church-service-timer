import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import '../support/fake_port.dart';
import '../support/pairing.dart';
import '../support/w2_port.dart';
import '../support/waiting.dart';
import '../support/widget_setup.dart';

class PasswordPort extends W2Port {
  String? saved;
  int removals = 0;
  bool failRemoval = false;
  @override
  Future<String?> savedDisplayPassword(String id) async => saved;
  @override
  Future<void> saveDisplayPassword(String id, String value) async {
    saved = value;
  }

  @override
  Future<void> forgetDisplayPassword(String id) async {
    if (failRemoval) throw StateError('Storage unavailable');
    saved = null;
    removals++;
  }
}

// Transport delivery and report immutability are exercised with real loopback
// peers in revision_17_test.dart. Here we inspect the UI's confirmation contract.
class ConfirmationController extends AppController {
  QuickMessage? sent;
  String? confirmedSession;
  ConfirmationController(super.port);
  @override
  Future<bool> sendQuickMessage(
    QuickMessage message, {
    bool test = false,
    String? confirmedEndedSession,
    Set<String>? recipientIds,
  }) async {
    sent = message;
    confirmedSession = confirmedEndedSession;
    return true;
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.haberey/nsd'), (
          _,
        ) async {
          throw PlatformException(code: 'notAvailable');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.haberey/nsd'), null);
  });
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) =>
      setScreen(t, value);

  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).last);
    await t.pumpAndSettle();
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  Future<void> openConnection(WidgetTester t, AppController c) async {
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('header-connection')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('destination-led')));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Welcome joins as stage by default; cancelling preserves the local service',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      final before = jsonEncode(c.state.toJson()..remove('editDrafts'));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Join a service');
      expect(
        t.widget<ChoiceField<String>>(find.byType(ChoiceField<String>)).value,
        'stage',
      );
      expect(find.text('Scan QR code instead'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/join-stage-screen.png'),
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(jsonEncode(c.state.toJson()..remove('editDrafts')), before);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpAndSettle();
      expect(find.text('Join a service'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Go to Live leaves stage sharing and connected receivers intact',
    (t) async {
      size(t);
      late AppController c;
      final receiver = PairHub();
      await t.runAsync(() async {
        c = AppController(FakePort());
        await c.initialize(startTicker: false);
        await c.selectDestination('mobile');
        await c.pairing.host('127.0.0.1');
        await pair(c.pairing, receiver);
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Settings');
      await tap(t, 'Screens & devices');
      await tap(t, 'Return to Live');
      expect(find.text('STANDING BY'), findsOneWidget);
      expect(c.pairing.hosting, true);
      await t.runAsync(() async {
        await c.pairing.publish();
        await eventually(() => c.stageConnected && !receiver.stale);
      });
      expect(c.stageConnected, true);
      expect(receiver.stale, false);
      await t.runAsync(() async {
        await receiver.stop();
        await c.pairing.stop();
        receiver.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final theme in ['midnight_lime', 'warm_ivory']) {
    testWidgets(
      'Themed choices select, cancel and search with large text: $theme',
      (t) async {
        size(t, const Size(360, 800));
        String value = 'Choice 3';
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(theme),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ChoiceField<String>(
                      value: value,
                      decoration: const InputDecoration(
                        labelText: 'Display font',
                      ),
                      options: List.generate(
                        12,
                        (i) => ChoiceOption(
                          value: 'Choice $i',
                          label: 'Choice $i',
                        ),
                      ),
                      onChanged: (v) => update(() => value = v!),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tap(t, 'Choice 3');
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/choice-sheet-$theme.png'),
        );
        await t.tap(find.byTooltip('Close Display font'));
        await t.pumpAndSettle();
        expect(value, 'Choice 3');
        await tap(t, 'Choice 3');
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(t.view.resetViewInsets);
        await t.pumpAndSettle();
        await t.enterText(
          find.widgetWithText(TextField, 'Search options'),
          'Choice 11',
        );
        await t.pumpAndSettle();
        await tap(t, 'Choice 11');
        expect(value, 'Choice 11');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Short choices stay visible and disabled fields cannot change', (
    t,
  ) async {
    bool chosen = true;
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme('midnight_lime'),
        home: Scaffold(
          body: Column(
            children: [
              ChoiceField<bool>(
                value: chosen,
                decoration: const InputDecoration(labelText: 'Print'),
                options: const [
                  ChoiceOption(value: true, label: 'Report'),
                  ChoiceOption(value: false, label: 'Rundown'),
                ],
                onChanged: (v) => chosen = v!,
              ),
              const ChoiceField<int>(
                value: 0,
                decoration: InputDecoration(labelText: 'Unavailable'),
                options: [
                  ChoiceOption(value: 0, label: 'A long disabled choice'),
                ],
                onChanged: null,
              ),
            ],
          ),
        ),
      ),
    );
    await tap(t, 'Rundown');
    expect(chosen, false);
    await tap(t, 'A long disabled choice');
    expect(find.byType(BottomSheet), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('LED connection remembers the entered password by default', (
    t,
  ) async {
    size(t);
    final port = PasswordPort();
    final controller = AppController(port);
    await controller.initialize(startTicker: false);
    await openConnection(t, controller);
    final remember = find.widgetWithText(
      CheckboxListTile,
      'Remember password on this phone',
    );
    expect(t.widget<CheckboxListTile>(remember).value, true);
    await t.enterText(
      find.widgetWithText(TextField, 'Display device password'),
      'test-only',
    );
    await tap(t, 'Connect selected display');
    expect(port.saved, 'test-only');
    expect(controller.hardware.connected, true);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Opting out removes an existing saved password without disconnecting; errors remain retryable',
    (t) async {
      size(t);
      final port = PasswordPort()..saved = 'test-only';
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.selectDestination('led');
      await c.hardware.discover();
      await c.hardware.connect('synthetic-w2', 'test-only');
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme('midnight_lime'),
          home: HardwareConnectionPage(controller: c),
        ),
      );
      await t.pumpAndSettle();
      final remember = find.widgetWithText(
        CheckboxListTile,
        'Remember password on this phone',
      );
      port.failRemoval = true;
      await t.tap(remember);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(remember).value, true);
      expect(port.saved, 'test-only');
      port.failRemoval = false;
      await t.tap(remember);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(remember).value, false);
      expect(port.saved, null);
      expect(port.removals, 1);
      expect(c.hardware.connected, true);
      await tap(t, 'Connect selected display');
      expect(c.hardware.connected, true);
      expect(port.saved, null);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Ended message shows recipient count and confirmation; cancel preserves draft and report',
    (t) async {
      size(t);
      late ConfirmationController c;
      final receiver = PairHub();
      await t.runAsync(() async {
        c = ConfirmationController(FakePort());
        await c.initialize(startTicker: false);
        await c.act('load', value: timeline());
        await c.act('start');
        await c.selectDestination('mobile');
        await c.pairing.host('127.0.0.1');
        await pair(c.pairing, receiver);
        await c.act('end');
      });
      final before = jsonEncode(c.state.toJson()..remove('editDrafts'));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      // After End service, Stage & display starts closed; open it.
      await t.ensureVisible(find.text('Stage & display'));
      await t.tap(find.text('Stage & display'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('open-quick-message')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('open-quick-message')));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Message'),
        'Please remain seated',
      );
      // Keep the real loopback peer fresh after scrolling; Flutter's fake
      // frame clock does not advance the socket heartbeat on a busy machine.
      await t.ensureVisible(find.text('Send message').last);
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await c.pairing.publish();
        await eventually(() => c.stageConnected);
      });
      await t.pump();
      await t.tap(find.text('Send message').last);
      await t.pumpAndSettle();
      expect(find.text('Send message after service?'), findsOneWidget);
      expect(find.textContaining('Sending to 1:'), findsWidgets);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/ended-message-confirmation.png'),
      );
      await tap(t, 'Cancel');
      expect(c.currentQuickMessage, null);
      expect(jsonEncode(c.state.toJson()..remove('editDrafts')), before);
      expect(find.text('Please remain seated'), findsWidgets);
      expect(find.textContaining('Could not complete'), findsNothing);
      await t.runAsync(() async {
        await c.pairing.publish();
        await eventually(() => c.stageConnected);
      });
      await t.pumpAndSettle();
      await tap(t, 'Send message');
      expect(c.stageConnected, true);
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Send message'),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(c.sent?.body, 'Please remain seated');
      // A sent message closes the composer and confirms on Live.
      expect(find.text('Quick message'), findsNothing);
      expect(find.byKey(const ValueKey('quick-message-sent')), findsOneWidget);
      expect(c.confirmedSession, c.state.session.id);
      expect(jsonEncode(c.state.toJson()..remove('editDrafts')), before);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        await receiver.stop();
        await c.pairing.stop();
        receiver.dispose();
      });
      await t.pumpWidget(const SizedBox());
    },
  );
}
