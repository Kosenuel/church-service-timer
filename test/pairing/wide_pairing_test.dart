import 'dart:async';
import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort, sunday;
import '../support/widget_setup.dart';
import '../windows/stage_output_test.dart' show FakeLauncher;

/// A computer with a projector plugged in and two devices paired earlier.
class WidePairingPort extends DesktopFakePort {
  final launcher = FakeLauncher();
  @override
  late final StageOutputHost stageOutput = StageOutputHost(launcher);
  String? pairingData = jsonEncode({
    'version': 1,
    'hostId': 'saved-host',
    'port': 0,
    'devices': [
      SavedPairDevice(
        'screen',
        'Stage tablet',
        'stage',
        pairRandom(32),
        suspended: true,
        lastSeen: DateTime(2026, 10, 19, 10, 30).millisecondsSinceEpoch,
      ).toJson(),
      SavedPairDevice(
        'operator',
        'Assistant operator',
        'operator',
        pairRandom(32),
        lastSeen: DateTime(2026, 10, 19, 9, 15).millisecondsSinceEpoch,
      ).toJson(),
    ],
  });
  @override
  Future<String?> loadPairing() async => pairingData;
  @override
  Future<void> savePairing(String value) async {
    pairingData = value;
  }
}

const _nsd = MethodChannel('com.haberey/nsd');

/// Stands in for the network: discovery starts, then answers with [hosts].
void fakeNearbyHosts(List<({String name, String address})> hosts) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> tell(String method, Map<String, Object?> arguments) =>
      messenger.handlePlatformMessage(
        _nsd.name,
        _nsd.codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
  messenger.setMockMethodCallHandler(_nsd, (call) async {
    final handle = (call.arguments as Map)['handle'] as String;
    switch (call.method) {
      case 'startDiscovery':
        scheduleMicrotask(() async {
          await tell('onDiscoveryStartSuccessful', {'handle': handle});
          for (final host in hosts) {
            await tell('onServiceDiscovered', {
              'handle': handle,
              'service.name': host.name,
              'service.type': '_cstimer._tcp',
            });
          }
        });
      case 'resolve':
        final name = (call.arguments as Map)['service.name'];
        final host = hosts.firstWhere((h) => h.name == name);
        scheduleMicrotask(
          () => tell('onResolveSuccessful', {
            'handle': handle,
            'service.name': host.name,
            'service.type': '_cstimer._tcp',
            'service.host': host.address,
            'service.port': 41234,
            'service.addresses': host.address,
          }),
        );
      case 'stopDiscovery':
        scheduleMicrotask(
          () => tell('onDiscoveryStopSuccessful', {'handle': handle}),
        );
    }
    return null;
  });
}

const sizes = [Size(1200, 600), Size(1366, 768), Size(2560, 1440)];

/// The pairing screens in a large window: panes side by side, forms and
/// buttons of their own size, nothing stretched across the window.
void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() {
    desktopWording = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nsd, null);
  });

  Future<AppController> open(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
  }) async {
    setScreen(t, size);
    final c = AppController(WidePairingPort());
    await c.initialize(startTicker: false);
    // These pages were laid out and photographed under Three panes; the
    // default is covered in test/live/desktop_layout_test.dart.
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      ),
    );
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> openScreens(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Screens & devices'));
    await t.pumpAndSettle();
    await t.tap(find.text('Screens & devices'));
    await t.pumpAndSettle();
  }

  Future<void> openJoin(WidgetTester t) async {
    // In a short window the button is further down the middle pane.
    await t.ensureVisible(find.text('Join a service'));
    await t.pumpAndSettle();
    await t.tap(find.text('Join a service'));
    await t.pumpAndSettle();
  }

  testWidgets('Join a service: hosts on the left, the steps beside them', (
    t,
  ) async {
    fakeNearbyHosts(const [
      (name: 'Grace Chapel sound desk', address: '192.168.1.24'),
      (name: 'Youth hall laptop', address: '192.168.1.31'),
    ]);
    await open(t);
    await openJoin(t);
    expect(find.byKey(const ValueKey('join-hosts-pane')), findsOneWidget);
    expect(find.text('2 hosts found'), findsOneWidget);
    expect(find.text('Choose the host'), findsOneWidget);
    expect(find.text('Name this device'), findsOneWidget);
    expect(find.text('Enter the code shown on the host'), findsOneWidget);
    final join = find.widgetWithText(FilledButton, 'Join service');
    expect(t.widget<FilledButton>(join).onPressed, isNull);
    await t.tap(find.text('Youth hall laptop'));
    await t.pumpAndSettle();
    // The button says what it is still waiting for.
    expect(find.text('Enter all six digits to join.'), findsOneWidget);
    final code = find.widgetWithText(TextField, 'Six-digit code');
    await t.enterText(code, '482913');
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(join).onPressed, isNotNull);
    // Ordinary sizes, not the width of the window.
    expect(t.getSize(join).width, lessThan(500));
    expect(t.getSize(code).width, lessThan(500));
    expect(
      t.getSize(find.widgetWithText(TextField, 'Device name')).width,
      lessThan(640),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-join-service.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Join a service says what to do when no host answers', (t) async {
    fakeNearbyHosts(const []);
    await open(t);
    await openJoin(t);
    expect(find.text('No host found yet'), findsOneWidget);
    expect(find.textContaining('choose Share to screens'), findsOneWidget);
    expect(find.text('Search again'), findsOneWidget);
    // The steps are waiting on the first one, and say so.
    expect(find.text('Choose a host on the left first.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-join-service-empty.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Join a service fits every desktop window size', (t) async {
    for (final size in sizes) {
      fakeNearbyHosts(const [
        (name: 'Grace Chapel sound desk', address: '192.168.1.24'),
      ]);
      await open(t, size: size);
      await openJoin(t);
      expect(find.byKey(const ValueKey('join-hosts-pane')), findsOneWidget);
      expect(
        t.getSize(find.widgetWithText(FilledButton, 'Join service')).width,
        lessThan(500),
      );
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Join a service keeps the phone page in a narrow window', (
    t,
  ) async {
    fakeNearbyHosts(const []);
    await open(t, size: const Size(1000, 800));
    await t.tap(find.text('Join a service'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-hosts-pane')), findsNothing);
    expect(find.text('Nearby hosts'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Screens & devices before sharing: columns, not one long list', (
    t,
  ) async {
    await open(t);
    await openScreens(t);
    expect(find.byKey(const ValueKey('screens-devices-wide')), findsOneWidget);
    expect(find.text('Second screen'), findsOneWidget);
    expect(find.text('Stage tablet'), findsOneWidget);
    expect(find.text('Requests from the stage'), findsOneWidget);
    // Web screens say how to start them, instead of leaving a gap.
    expect(find.byKey(const ValueKey('web-screens-idle')), findsOneWidget);
    // The two columns start level.
    expect(
      t.getTopLeft(find.byKey(const ValueKey('screens-devices-column'))).dy,
      t.getTopLeft(find.byKey(const ValueKey('screens-own-column'))).dy,
    );
    expect(
      t.getSize(find.byKey(const ValueKey('screens-devices-column'))).width,
      lessThan(640),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-screens-devices.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  /// Shares on the preferred web port, with fixed codes, so the screenshot
  /// is the same every time.
  Future<void> share(WidgetTester t, AppController c) async {
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
    // Whether the easy name could be announced depends on the machine
    // (the mDNS port may be taken), and decides which line the page shows.
    // The screenshot is of the usual case, where it could.
    c.web.localNameActive = true;
    c.state.webStage['orderCode'] = '4821';
    c.webStage.teamCode = '246810';
    c.pairing.pin = '001234';
    c.pairing.code = PairCode(
      '192.168.1.17',
      12345,
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      9999999999999,
    );
  }

  testWidgets('Screens & devices while sharing: web screens in their own '
      'pane, the QR beside its addresses', (t) async {
    final c = await open(t);
    await share(t, c);
    expect(
      c.webStage.port,
      WebStageServer.preferredPort,
      reason: 'Port 8080 stayed busy for 30 seconds.',
    );
    await openScreens(t);
    expect(find.byKey(const ValueKey('web-screens-pane')), findsOneWidget);
    expect(find.text('001 234'), findsOneWidget);
    expect(find.text('Web screens'), findsOneWidget);
    // The QR sits beside the address, not above it.
    final qr = t.getRect(find.byKey(const ValueKey('web-qr')));
    final address = t.getRect(find.byKey(const ValueKey('web-address')));
    expect(address.left, greaterThan(qr.right));
    expect(address.top, lessThan(qr.bottom));
    // Buttons keep their own size.
    for (final key in ['export-join-slide', 'web-new-codes']) {
      expect(t.getSize(find.byKey(ValueKey(key))).width, lessThan(320));
    }
    expect(
      t.getSize(find.widgetWithText(FilledButton, 'Stop sharing')).width,
      lessThan(320),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-screens-devices-sharing.png'),
    );
    await t.runAsync(() => c.pairing.stop());
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Screens & devices fits every desktop window size', (t) async {
    for (final size in sizes) {
      final c = await open(t, size: size);
      await openScreens(t);
      expect(
        find.byKey(const ValueKey('screens-devices-wide')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull, reason: 'before sharing, $size');
      await share(t, c);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('web-qr')), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'sharing, $size');
      await t.runAsync(() => c.pairing.stop());
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Quick message: the form on the left, the preview beside it', (
    t,
  ) async {
    await open(t);
    final home = t.state<HomeState>(find.byType(Home));
    unawaited(home.openQuickMessage());
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('quick-message-preview-pane')),
      findsOneWidget,
    );
    await t.enterText(
      find.widgetWithText(TextField, 'Headline (optional)'),
      'Two minutes',
    );
    await t.enterText(
      find.widgetWithText(TextField, 'Message'),
      'Please bring the sermon to a close.',
    );
    await t.pumpAndSettle();
    // The preview is beside the form, not above it.
    final form = t.getRect(find.widgetWithText(TextField, 'Message'));
    final preview = t.getRect(
      find.byKey(const ValueKey('quick-message-preview')),
    );
    expect(preview.left, greaterThan(form.right));
    expect(form.width, lessThan(640));
    // One main button, of its own size, at the bottom right.
    final send = t.getRect(find.widgetWithText(FilledButton, 'Send message'));
    expect(send.width, lessThan(320));
    expect(send.right, greaterThan(1800));
    expect(
      t.getSize(find.byKey(const ValueKey('save-quick-preset'))).width,
      lessThan(320),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-quick-message.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Quick message and a new preset fit every desktop window size', (
    t,
  ) async {
    for (final size in [...sizes, const Size(1920, 1080)]) {
      await open(t, size: size);
      final home = t.state<HomeState>(find.byType(Home));
      unawaited(home.openQuickMessage());
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('quick-message-preview-pane')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull, reason: 'message, $size');
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      unawaited(home.editQuickPreset());
      await t.pumpAndSettle();
      expect(
        t.getSize(find.widgetWithText(FilledButton, 'Save preset')).width,
        lessThan(320),
      );
      expect(t.takeException(), isNull, reason: 'preset, $size');
      await t.pumpWidget(const SizedBox());
    }
  });

  /// A joined device following a running service.
  Future<AppController> joined(
    WidgetTester t,
    String mode, {
    Size size = const Size(1920, 1080),
  }) async {
    setScreen(t, size);
    final c = AppController(WidePairingPort());
    await c.initialize(startTicker: false);
    // These pages were laid out and photographed under Three panes; the
    // default is covered in test/live/desktop_layout_test.dart.
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      ),
    );
    await c.commit((draft, _) {
      draft.templates.clear();
      draft.saveTemplate(sunday());
    });
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    c.pairing
      ..mode = mode
      ..status = 'Connected to Grace Chapel sound desk'
      ..snapshot = c.pairedSnapshot(false)
      ..lastSnapshot = DateTime.now().millisecondsSinceEpoch;
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme('midnight_lime'),
        home: PairedScreen(controller: c),
      ),
    );
    await t.pump();
    return c;
  }

  testWidgets('A joined viewer: the timer on the left, the order of service '
      'in its own pane', (t) async {
    await joined(t, 'viewer');
    expect(find.byKey(const ValueKey('paired-rundown-pane')), findsOneWidget);
    expect(find.text('Welcome'), findsWidgets);
    expect(find.text('Closing'), findsOneWidget);
    final timer = t.getRect(find.byKey(const ValueKey('paired-main-pane')));
    final rundown = t.getRect(
      find.byKey(const ValueKey('paired-rundown-pane')),
    );
    expect(rundown.left, greaterThan(timer.right));
    expect(timer.width, lessThanOrEqualTo(640));
    expect(
      t.getSize(find.widgetWithText(FilledButton, 'Open stage display')).width,
      lessThan(320),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-service-viewer.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A joined device fits every desktop window size', (t) async {
    for (final size in sizes) {
      for (final mode in ['viewer', 'operator']) {
        await joined(t, mode, size: size);
        expect(
          find.byKey(const ValueKey('paired-rundown-pane')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull, reason: '$mode, $size');
        await t.pumpWidget(const SizedBox());
      }
    }
  });
}
