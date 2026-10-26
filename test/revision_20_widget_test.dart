import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/app_theme.dart';
import 'package:church_service_timer/clock_text.dart';
import 'domain_test.dart' show FakePort, timeline;

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
  void size(WidgetTester t, [Size value = const Size(430, 1000)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, String text) async {
    final target = text == 'Layout density'
        ? find.byKey(const ValueKey('layout-density'))
        : find.text(text).last;
    await Scrollable.ensureVisible(t.element(target), alignment: 0.5);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets(
    'Welcome offers aligned sharing and joining actions, opening host setup',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final share = find.byKey(const ValueKey('share-service-live'));
      final join = find.widgetWithText(OutlinedButton, 'Join as stage screen');
      expect(t.getRect(share).top, t.getRect(join).top);
      expect(t.getSize(share).height, t.getSize(join).height);
      await shot(t, 'welcome-sharing-020');
      await tap(t, 'Share service');
      expect(find.text('Your stage, on another screen'), findsOneWidget);
      expect(find.text('Share to stage screens'), findsOneWidget);
      expect(c.destination, 'mobile');
      expect(c.pairing.hosting, false);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final entry in ['Live', 'Stage screens', 'Paired devices']) {
    testWidgets(
      '$entry Stop sharing confirms and closes the host, preserving the local service',
      (t) async {
        size(t);
        late AppController c;
        await t.runAsync(() async {
          c = AppController(FakePort());
          await c.initialize(startTicker: false);
          await c.selectDestination('mobile');
          await c.pairing.host('127.0.0.1');
        });
        final pin = c.pairing.pin;
        await t.pumpWidget(TimerApp(controller: c));
        await t.pumpAndSettle();
        // Manage sharing must preserve the existing host and code.
        await tap(t, 'Manage sharing');
        expect(find.text('Control: this phone'), findsOneWidget);
        expect(c.pairing.pin, pin);
        if (entry != 'Paired devices') {
          await tap(t, 'Go to Live');
          if (entry == 'Stage screens') await tap(t, 'Pair screen');
        }
        await tap(t, 'Stop sharing');
        expect(
          find.textContaining(
            'All paired screens and operators will disconnect.',
          ),
          findsOneWidget,
        );
        await tap(t, 'Cancel');
        expect(c.pairing.hosting, true);
        await tap(t, 'Stop sharing');
        await t.tap(find.widgetWithText(FilledButton, 'Stop sharing').last);
        await t.pumpAndSettle();
        await t.runAsync(() async {
          for (var i = 0; i < 40 && c.pairing.hosting; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        await t.pumpAndSettle();
        expect(c.pairing.hosting, false);
        expect(c.pairing.code, isNull);
        expect(c.state.session.phase, 'idle');
        expect(c.destination, 'mobile');
        expect(c.currentQuickMessage, isNull);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Automatic density reacts to resizing and respects system accessibility',
    (t) async {
      size(t);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            highContrast: true,
          );
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.commit(
        (draft, _) => draft.appearance = const AppearancePreferences(
          density: 'automatic',
        ),
      );
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      AppLayout current() => appLayout(t.element(find.byType(Scaffold).first));
      expect(current().density, 'compact');
      expect(current().preferences.highContrast, isTrue);
      expect(current().preferences.reducedMotion, isTrue);
      t.view.physicalSize = const Size(1280, 800);
      await t.pumpAndSettle();
      expect(current().density, 'spacious');
      expect(c.state.appearance.highContrast, isFalse);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpAndSettle();
      await c.act('end');
      await t.pumpAndSettle();
      expect(find.text('LIVE PRODUCTION'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Clock blinks once per second without changing its bounds or semantics; stale and steady stay visible',
    (t) async {
      size(t);
      Widget clock({bool blink = true, bool stale = false}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: ClockText(
              text: '12:59 PM',
              style: const TextStyle(fontSize: 60, color: Colors.white),
              blink: blink,
              stale: stale,
            ),
          ),
        ),
      );
      await t.pumpWidget(clock());
      final bounds = t.getRect(find.byKey(const ValueKey('clock-text')));
      Color? colonColor() =>
          ((t.widget<RichText>(find.byKey(const ValueKey('clock-text'))).text
                          as TextSpan)
                      .children![2]
                  as TextSpan)
              .style
              ?.color;
      expect(colonColor(), isNull);
      await t.pump(const Duration(milliseconds: 500));
      expect(colonColor(), Colors.transparent);
      expect(t.getRect(find.byKey(const ValueKey('clock-text'))), bounds);
      expect(find.bySemanticsLabel('12:59 PM'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 500));
      expect(colonColor(), isNull);
      await t.pumpWidget(clock(stale: true));
      await t.pump(const Duration(milliseconds: 500));
      expect(colonColor(), isNull);
      await t.pumpWidget(clock(blink: false));
      await t.pump(const Duration(seconds: 2));
      expect(colonColor(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Hidden dividers retain destructive-action separation', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(
          'midnight_lime',
          appearance: const AppearancePreferences(dividers: 'hidden'),
        ),
        home: const Scaffold(
          body: Column(children: [AppDivider(), AppDivider(essential: true)]),
        ),
      ),
    );
    expect(find.byType(Divider), findsOneWidget);
  });

  for (final density in ['compact', 'comfortable', 'spacious']) {
    testWidgets('$density preview keeps readable labels and touch targets', (
      t,
    ) async {
      size(t);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            'royal_navy',
            appearance: AppearancePreferences(density: density),
          ),
          home: const Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: AppearanceSample(),
              ),
            ),
          ),
        ),
      );
      for (final item in t.widgetList<ListTile>(find.byType(ListTile))) {
        final f = find.byWidget(item);
        expect(t.getSize(f).height, greaterThanOrEqualTo(48));
      }
      await shot(t, 'layout-$density-020');
    });
  }

  testWidgets(
    'Spacious high contrast supports large phone text without overflow',
    (t) async {
      size(t, const Size(320, 1000));
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(
            'warm_ivory',
            appearance: const AppearancePreferences(
              density: 'spacious',
              highContrast: true,
              dividers: 'strong',
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: AppearanceSample(),
              ),
            ),
          ),
        ),
      );
      await shot(t, 'layout-high-contrast-020');
    },
  );

  testWidgets(
    'Appearance previews changes, Cancel restores saved preferences, Save persists',
    (t) async {
      size(t);
      final port = FakePort(), c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Settings');
      await tap(t, 'Appearance');
      await tap(t, 'Layout density');
      await tap(t, 'Spacious');
      expect(c.appearanceSelection.value.density, 'spacious');
      expect(c.state.appearance.density, 'compact');
      await tap(t, 'High contrast');
      expect(c.appearanceSelection.value.highContrast, isTrue);
      await tap(t, 'Cancel');
      expect(c.appearanceSelection.value, const AppearancePreferences());
      await tap(t, 'Appearance');
      await tap(t, 'Layout density');
      await tap(t, 'Comfortable');
      await tap(t, 'Reduced motion');
      await t.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 1000),
      );
      await t.pumpAndSettle();
      await shot(t, 'appearance-020');
      await tap(t, 'Save appearance');
      expect(c.state.appearance.density, 'comfortable');
      expect(c.state.appearance.reducedMotion, isTrue);
      port.data = (c.port as FakePort).data;
      await t.pumpWidget(const SizedBox());
      final next = AppController(port);
      await next.initialize(startTicker: false);
      expect(next.state.appearance.density, 'comfortable');
      next.dispose();
    },
  );

  testWidgets(
    'Long press and three-dot menus match and retain a delete divider',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Programs');
      await t.longPress(
        find.byKey(const ValueKey('template-row:Sunday Service')),
      );
      await t.pumpAndSettle();
      expect(find.text('Export program'), findsOneWidget);
      expect(find.text('Delete program'), findsOneWidget);
      final firstBounds = t.getRect(find.byType(SimpleDialog));
      await shot(t, 'program-menu-020');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Program actions').first);
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(SimpleDialog)), firstBounds);
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.byType(AppDivider),
        ),
        findsOneWidget,
      );
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('import-programs')));
      await t.pumpAndSettle();
      expect(
        t.widget(find.byKey(const ValueKey('import-programs'))),
        isA<OutlinedButton>(),
      );
      expect(
        t.widget(find.byKey(const ValueKey('export-programs'))),
        isA<OutlinedButton>(),
      );
      await shot(t, 'program-buttons-020');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Jump button is outlined, destinations separated, final segment explains unavailability',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Jump to segment');
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Second'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Last'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.byType(AppDivider),
        ),
        findsOneWidget,
      );
      await shot(t, 'jump-menu-020');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(
        t.widget(find.byKey(const ValueKey('jump-to-segment'))),
        isA<OutlinedButton>(),
      );
      await c.act('jump', value: 2);
      await t.pumpAndSettle();
      expect(find.text('No upcoming segments'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('jump-to-segment')),
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Live rundown has dividers and a bold active segment labelled Now',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: timeline());
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('rundown-0')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('rundown-0')),
                matching: find.text('First'),
              ),
            )
            .style!
            .fontWeight,
        FontWeight.w800,
      );
      expect(find.textContaining('· Now'), findsOneWidget);
      await shot(t, 'rundown-020');
      await t.pumpWidget(const SizedBox());
    },
  );
}
