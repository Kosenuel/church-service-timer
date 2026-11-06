import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'program_library_and_wifi_rejoin_test.dart' show RejoinPort;
import '../domain/service_timing_test.dart' show FakePort, timeline, after;
import '../hardware/hardware_integration_test.dart' show W2Port, setup, flush;

class SelectedExportPort extends FakePort {
  final exports = <String>[];
  final filenames = <String>[];
  @override
  Future<void> exportFile(String name, String content) async {
    filenames.add(name);
    exports.add(content);
  }
}

class WifiUiPort extends RejoinPort {
  bool wifiEnabled = false;
  final joinGate = Completer<bool>();
  @override
  Future<Json> signWifiProfile(String id) async => {
    'supported': true,
    'wifiEnabled': wifiEnabled,
    'ssid': 'Test sign Wi-Fi',
    'security': 'wpa2',
    'passwordSaved': true,
  };
  @override
  Future<bool> joinSignWifi(String id) async {
    joins++;
    final result = await joinGate.future;
    wifi = result;
    return result;
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  void size(WidgetTester t, [Size size = const Size(430, 1000)]) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await Scrollable.ensureVisible(t.element(f), alignment: .5);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/$name.png'),
    );
  }

  testWidgets(
    'Running bar survives navigation, shows pause/warning/overtime and returns without mutation',
    (t) async {
      size(t);
      final p = FakePort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Programs').last);
      expect(find.byKey(const ValueKey('running-service-bar')), findsOneWidget);
      await shot(t, 'running-programs-021');
      await c.act('pause');
      await t.pumpAndSettle();
      expect(find.textContaining('remaining · Paused'), findsOneWidget);
      await c.act('pause');
      p.at = after(590);
      await c.tick();
      await t.pumpAndSettle();
      expect(find.textContaining('remaining · Warning'), findsOneWidget);
      p.at = after(605);
      await c.tick();
      await t.pumpAndSettle();
      expect(find.textContaining('overtime'), findsOneWidget);
      final before = jsonEncode(c.state.session.toJson());
      await tap(t, find.byKey(const ValueKey('running-service-bar')));
      expect(c.state.session.toJson(), jsonDecode(before));
      expect(find.byKey(const ValueKey('running-service-bar')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Programs pin/search and Start chooser use the same saved library',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Programs').last);
      // Long-press selects the program; the selection bar pins it.
      await t.longPress(
        find.byKey(const ValueKey('template-row:Sunday Service')),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('pin-selected-programs')));
      expect(
        c.state.programLibrary.favourites,
        contains(
          c.state.templates.firstWhere((p) => p.name == 'Sunday Service').id,
        ),
      );
      await tap(t, find.text('Done'));
      expect(
        find.byKey(const ValueKey('pinned:Sunday Service')),
        findsOneWidget,
      );
      await t.enterText(find.byKey(const ValueKey('program-search')), 'sunday');
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('template-row:Sunday Service')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('template-row:Quick Rehearsal')),
        findsNothing,
      );
      await shot(t, 'program-search-021');
      await tap(t, find.text('Live').last);
      await tap(t, find.text('Start service').last);
      expect(find.byType(BottomSheet), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('start-program-search')),
        'Sunday',
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Pinned').last);
      await shot(t, 'start-search-021');
      await tap(t, find.byKey(const ValueKey('start-program:Sunday Service')));
      expect(c.state.session.phase, 'ready');
      expect(
        c.state.programLibrary.recent.keys,
        contains(
          c.state.templates.firstWhere((p) => p.name == 'Sunday Service').id,
        ),
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Settings search opens the matching page and keeps Return to Live',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Settings').last);
      final search = find.byKey(const ValueKey('settings-search'));
      await t.enterText(search, 'clock');
      await t.pumpAndSettle();
      await shot(t, 'settings-search-021');
      await tap(t, find.text('Clock format'));
      expect(find.text('24-hour'), findsWidgets);
      await tap(t, find.byKey(const ValueKey('running-service-bar')).last);
      expect(find.byKey(const ValueKey('settings-search')), findsNothing);
      expect(c.state.session.active, true);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Tablet Programs and Reports keep list and selected details together',
    (t) async {
      size(t, const Size(1280, 1000));
      final p = FakePort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      p.at = after(20);
      await c.act('end');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Programs').last);
      await tap(t, find.byKey(const ValueKey('template-row:Sunday Service')));
      expect(find.byKey(const ValueKey('master-detail')), findsOneWidget);
      expect(find.text('Edit Program'), findsOneWidget);
      await shot(t, 'programs-tablet-021');
      await tap(t, find.text('Reports').last);
      await tap(
        t,
        find.byKey(ValueKey('open-report-${c.state.reports.single.id}')),
      );
      expect(
        find.byKey(const ValueKey('report-segment-breakdown')),
        findsOneWidget,
      );
      await shot(t, 'reports-tablet-021');
      await t.enterText(find.byKey(const ValueKey('report-search')), 'absent');
      await t.pumpAndSettle();
      expect(
        find.byKey(ValueKey('open-report-${c.state.reports.single.id}')),
        findsNothing,
      );
      expect(find.text('Select a service to view its report.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Flat report expands private detail and activity without per-segment cards',
    (t) async {
      size(t);
      final p = FakePort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      await c.act(
        'load',
        value: Timeline('Youth Sunday', const [
          Segment('Welcome', 1, notes: 'Check microphone', speaker: 'Grace'),
          Segment('Message', 2),
        ], DisplaySettings()),
      );
      await c.act('start');
      p.at = after(35);
      await c.act('end');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Reports').last);
      await tap(
        t,
        find.byKey(ValueKey('open-report-${c.state.reports.single.id}')),
      );
      final rows = find.byKey(const ValueKey('report-segment-breakdown'));
      expect(
        find.descendant(of: rows, matching: find.byType(Card)),
        findsNothing,
      );
      expect(find.text('Check microphone'), findsNothing);
      await tap(t, find.text('01  Welcome'));
      expect(find.textContaining('Check microphone'), findsOneWidget);
      await shot(t, 'report-flat-phone-021');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Cue delivery does not claim acceptance until current upload acknowledges',
    (t) async {
      size(t, const Size(430, 1400));
      final p = W2Port();
      final c = (await t.runAsync(() => setup(p)))!;
      p.acknowledged = false;
      await t.runAsync(() async {
        await c.act(
          'message',
          value: const StageOutputMessage(TextLayout('WAIT'), seconds: 8),
        );
        await flush();
      });
      await t.pumpWidget(TimerApp(controller: c));
      // The unconfirmed upload drops the sign link, so the reconnecting
      // spinner animates; pump frames instead of waiting for it to settle.
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('sign-reconnecting')), findsOneWidget);
      await t.ensureVisible(
        find.byKey(const ValueKey('cue-delivery-feedback')),
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('Returns to timer in 8s'), findsOneWidget);
      await shot(t, 'cue-not-sent-021');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Unavailable actions explain on tap without executing the disabled control',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnavailableAction(
              reason: 'Connect a stage screen first.',
              child: FilledButton(onPressed: null, child: const Text('Send')),
            ),
          ),
        ),
      );
      await t.tap(find.byType(UnavailableAction));
      await t.pumpAndSettle();
      expect(find.text('Connect a stage screen first.'), findsWidgets);
    },
  );
  testWidgets(
    'Picker feedback fires for user scroll only and Off suppresses it',
    (t) async {
      size(t);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('church.timer/device'),
            (call) async {
              calls.add(call);
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('church.timer/device'),
              null,
            ),
      );
      var value = 60;
      Future<void> mount(String mode) async {
        await t.pumpWidget(
          MaterialApp(
            theme: appTheme(
              'midnight_lime',
              appearance: AppearancePreferences(pickerFeedback: mode),
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (ctx, set) => TimeWheels(
                  value: value,
                  onChanged: (v) => set(() => value = v),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await mount('both');
      expect(calls, isEmpty);
      await t.drag(find.byType(CupertinoPicker).first, const Offset(0, -100));
      await t.pumpAndSettle();
      expect(
        calls.where((c) => c.method == 'pickerTick' && c.arguments == 'both'),
        isNotEmpty,
      );
      calls.clear();
      await mount('off');
      await t.drag(find.byType(CupertinoPicker).first, const Offset(0, -100));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final format in ['JSON', 'CSV']) {
    testWidgets(
      'Selected programs export only checked items across filters: $format',
      (t) async {
        size(t);
        final p = SelectedExportPort();
        final c = AppController(p);
        await c.initialize(startTicker: false);
        await t.pumpWidget(TimerApp(controller: c));
        await t.pumpAndSettle();
        await tap(t, find.text('Programs').last);
        await tap(t, find.byKey(const ValueKey('select-programs')));
        await t.enterText(
          find.byKey(const ValueKey('program-search')),
          'Sunday',
        );
        await t.pumpAndSettle();
        await tap(t, find.text('Select all shown'));
        await t.enterText(
          find.byKey(const ValueKey('program-search')),
          'Quick',
        );
        await t.pumpAndSettle();
        expect(find.text('1 selected · 1 hidden by filters'), findsOneWidget);
        await tap(t, find.byKey(const ValueKey('export-selected-programs')));
        expect(find.text('Export selected programs'), findsOneWidget);
        await tap(t, find.widgetWithText(FilledButton, format));
        expect(p.exports.single, contains('Sunday Service'));
        expect(p.exports.single, isNot(contains('Quick rehearsal')));
        if (format == 'JSON')
          expect((jsonDecode(p.exports.single)['programs'] as List).length, 1);
        expect(p.filenames.single, contains('selected-programs'));
        await shot(t, 'selected-programs-${format.toLowerCase()}-021');
        await tap(t, find.text('Clear selection'));
        expect(find.text('0 selected'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('Selected reports export only checked records: $format', (
      t,
    ) async {
      size(t);
      final p = SelectedExportPort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      for (final name in ['Morning Service', 'Evening Service']) {
        await c.act('load', value: timeline().renamed(name));
        await c.act('start');
        await c.act('end');
      }
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Reports').last);
      await tap(t, find.byKey(const ValueKey('select-reports')));
      await t.enterText(find.byKey(const ValueKey('report-search')), 'Morning');
      await t.pumpAndSettle();
      await tap(t, find.text('Select all shown'));
      await tap(t, find.byKey(const ValueKey('export-selected-reports')));
      await tap(
        t,
        find.widgetWithText(
          format == 'JSON' ? OutlinedButton : FilledButton,
          format,
        ),
      );
      expect(p.exports.single, contains('Morning Service'));
      expect(p.exports.single, isNot(contains('Evening Service')));
      if (format == 'JSON')
        expect(jsonDecode(p.exports.single)['recordCount'], 1);
      expect(p.filenames.single, contains('selected-reports'));
      await shot(t, 'selected-reports-${format.toLowerCase()}-021');
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Running service bar fits a small phone with large system text', (
    t,
  ) async {
    size(t, const Size(360, 1000));
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await tap(t, find.text('Settings').last);
    await shot(t, 'running-large-text-021');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Wi-Fi reconnect explains refusal, retries and cancels a late join without authentication',
    (t) async {
      size(t);
      final p = WifiUiPort()..hardwarePreference = true;
      final c = AppController(p);
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      // The remembered sign starts in automatic reconnection, whose spinner
      // keeps animating until the manual flow below takes over.
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('sign-reconnecting')), findsOneWidget);
      await t.tap(find.text('Reconnect display'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.textContaining('Wi-Fi is off.'), findsOneWidget);
      expect(c.hardware.autoReconnect, isFalse);
      await shot(t, 'wifi-reconnect-retry-021');
      p.wifiEnabled = true;
      await t.tap(find.text('Retry'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Joining Test sign Wi-Fi…'), findsOneWidget);
      expect(p.joins, 1);
      await shot(t, 'wifi-reconnect-progress-021');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      p.joinGate.complete(true);
      await t.pumpAndSettle();
      expect(c.hardware.autoReconnect, isFalse);
      expect(c.hardware.connected, isFalse);
      expect(p.connections, 0);
      expect(p.sent, isEmpty);
      expect(find.byType(WifiReconnectDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
}
