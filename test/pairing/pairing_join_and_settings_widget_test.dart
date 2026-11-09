import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class PrintPort extends FakePort {
  Uint8List? pdf;
  @override
  Future<void> printServicePdf(
    String name,
    Future<Uint8List> Function(double, double) layout,
  ) async {
    pdf = await layout(595.28, 841.89);
  }
}

void main() {
  setUpAll(loadAppFonts);
  void size(WidgetTester t, {Size value = const Size(450, 1000)}) =>
      setScreen(t, value);

  Future<AppController> open(WidgetTester t, {FakePort? port}) async {
    final c = AppController(port ?? FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> setting(WidgetTester t, String title) async {
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text(title));
    await t.pumpAndSettle();
    await t.tap(find.text(title));
    await t.pumpAndSettle();
  }

  for (final title in [
    'Stage cues',
    'Screens & devices',
    'LED device management',
  ]) {
    testWidgets('$title settings preview', (t) async {
      size(t);
      await open(t);
      await setting(t, title);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../goldens/settings-${title.toLowerCase().replaceAll(' & ', '-').replaceAll(' ', '-')}.png',
        ),
      );
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'Pairing shows six digits and optional QR instead of a long token',
    (t) async {
      size(t);
      final c = await open(t);
      // The screenshot shows the web address, so it needs the preferred
      // port. Other test files run at the same time and may hold it for a
      // moment, in which case the server takes a random port: start the
      // web server again (it tries the preferred port first) until it gets
      // it.
      await t.runAsync(() async {
        await c.pairing.host('127.0.0.1');
        for (var i = 0; i < 100 && !c.webStage.running; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        for (
          var attempt = 0;
          attempt < 60 && c.webStage.port != WebStageServer.preferredPort;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await c.webStage.start('127.0.0.1');
        }
      });
      expect(
        c.webStage.port,
        WebStageServer.preferredPort,
        reason: 'Port 8080 stayed busy for 30 seconds.',
      );
      expect(c.webStage.port, WebStageServer.preferredPort);
      // Web-screen codes are random; fix them for a stable screenshot.
      c.state.webStage['orderCode'] = '4821';
      c.webStage.teamCode = '246810';
      c.pairing.pin = '001234';
      c.pairing.code = PairCode(
        '192.168.1.17',
        12345,
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        9999999999999,
      );
      await setting(t, 'Screens & devices');
      expect(find.text('001 234'), findsOneWidget);
      expect(find.text('Copy new pairing code'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/pairing-short-code.png'),
      );
      await t.ensureVisible(find.text('Show QR code'));
      await t.tap(find.text('Show QR code'));
      await t.pumpAndSettle();
      expect(find.text('Pair with QR code'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/pairing-qr.png'),
      );
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      await t.runAsync(() => c.pairing.stop());
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Join page offers six-digit input and a camera-free fallback', (
    t,
  ) async {
    size(t);
    const nsdChannel = MethodChannel('com.haberey/nsd');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nsdChannel, (_) async {
          throw PlatformException(code: 'notAvailable');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nsdChannel, null),
    );
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme('midnight_lime'),
        home: JoinDevicePage(controller: c),
      ),
    );
    await t.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Six-digit code');
    await t.enterText(field, '001234567x');
    await t.pumpAndSettle();
    expect(t.widget<TextField>(field).controller!.text, '001234');
    expect(find.text('Scan QR code instead'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Join service'),
          )
          .onPressed,
      isNull,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/pairing-join.png'),
    );
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('Warnings support disabling and confirmed deletion', (t) async {
    size(t);
    final c = await open(t);
    await setting(t, 'Warnings & alerts');
    final count = c.state.defaults.warnings.length;
    await t.ensureVisible(find.byTooltip('Warning actions').first);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Warning actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Disable warning'));
    await t.pumpAndSettle();
    expect(c.state.defaults.warnings.first.enabled, false);
    await t.tap(find.byTooltip('Warning actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete warning'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Cancel'));
    await t.pumpAndSettle();
    expect(c.state.defaults.warnings.length, count);
    await t.tap(find.byTooltip('Warning actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete warning'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete warning'));
    await t.pumpAndSettle();
    expect(c.state.defaults.warnings.length, count - 1);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Upcoming rundown editor hides template settings and allows final segment removal',
    (t) async {
      size(t);
      final c = await open(t);
      await c.act(
        'load',
        value: Timeline('Sunday', const [
          Segment('Current', 2),
          Segment('Upcoming', 3, notes: 'PRIVATE'),
        ], DisplaySettings()),
      );
      await c.act('start');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Edit upcoming'));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit upcoming'));
      await t.pumpAndSettle();
      expect(find.text('Template name'), findsNothing);
      expect(find.text('End screen · this template'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/upcoming-editor.png'),
      );
      await t.tap(find.byTooltip('Remove segment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Review rundown changes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Update rundown'));
      await t.pumpAndSettle();
      expect(c.state.session.timeline!.segments.length, 1);
      expect(c.state.session.timeline!.segments.first.name, 'Current');
      expect(c.state.session.remaining(c.now), 120000);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Printable service sheet requires private-note opt in', (
    t,
  ) async {
    size(t);
    final p = PrintPort();
    final c = await open(t, port: p);
    await c.act(
      'load',
      value: Timeline('Sunday', const [
        Segment('Talk', 5, notes: 'SECRET'),
      ], DisplaySettings()),
    );
    await c.act('start');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('print-rundown')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('print-rundown')));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/print-service-sheet.png'),
    );
    expect(find.text('Print order of service'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('print-service-pdf')));
    await t.pumpAndSettle();
    expect(p.pdf, isNotNull);
    expect(String.fromCharCodes(p.pdf!.take(5)), '%PDF-');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Paired stage preview has no private notes and marks stale state',
    (t) async {
      size(t, value: const Size(900, 600));
      final c = await open(t);
      c.pairing.mode = 'stage';
      c.pairing.lastSnapshot = DateTime.now().millisecondsSinceEpoch;
      c.pairing.status = 'Connected';
      c.pairing.snapshot = {
        'church': 'Grace Community Church',
        'service': 'Sunday service',
        'displayText': '04:32',
        'effect': 'static',
        'blank': false,
        'bold': true,
      };
      c.pairing.changed();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('04:32'), findsOneWidget);
      expect(find.text('Private notes'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/paired-stage.png'),
      );
      c.pairing.lastSnapshot = 1;
      c.pairing.changed();
      await t.pump();
      expect(find.textContaining('Host disconnected'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
