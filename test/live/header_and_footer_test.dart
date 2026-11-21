import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class DesktopFakePort extends FakePort {
  @override
  bool get isDesktop => true;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': false,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5, speaker: 'Deacon Ruth'),
  Segment('Praise & Worship', 20, speaker: 'Worship team'),
  Segment('Sermon', 40, speaker: 'Pastor Samuel'),
  Segment('Response', 10, speaker: 'Worship team'),
  Segment('Closing', 5),
], DisplaySettings());

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  /// The app on a PC (or, with [desktop] false, a phone), with a church
  /// name, and a service loaded, running or neither.
  Future<AppController> open(
    WidgetTester t, {
    Size size = const Size(1366, 768),
    bool desktop = true,
    String layout = 'three_panes',
    String service = 'none',
    String keyHints = 'automatic',
  }) async {
    desktopWording = desktop;
    setScreen(t, size);
    final port = desktop ? DesktopFakePort() : FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    expect(
      await c.commit((draft, _) {
        draft.churchName = 'St Mark’s Church';
        draft.appearance = draft.appearance.copyWith(
          desktopLayout: layout,
          keyHints: keyHints,
        );
        draft.themeId = 'midnight_lime';
      }),
      isTrue,
    );
    if (service != 'none') await c.act('load', value: sunday());
    if (service == 'running') {
      await c.act('start');
      port.at = after(340);
      await c.tick();
      await c.act('advance');
      port.at = after(340 + 600);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));

  group('the name in the header returns to Live', () {
    for (final (device, desktop, size) in const [
      ('a PC', true, Size(1366, 768)),
      ('a phone', false, Size(430, 1000)),
    ]) {
      for (final service in const ['none', 'loaded', 'running']) {
        testWidgets(
          'on $device, with ${service == 'none' ? 'no service' : 'a $service service'}',
          (t) async {
            await open(t, desktop: desktop, size: size, service: service);
            // On Live it is only the name.
            expect(
              t.widget<InkWell>(key('header-return-to-live')).onTap,
              isNull,
            );
            expect(find.byTooltip('Return to Live'), findsNothing);
            for (final (page, target) in const [
              (1, 'header-title'),
              (2, 'header-church-name'),
              (3, 'header-title'),
              (1, 'header-church-name'),
            ]) {
              await home(t).goToPage(page);
              await t.pumpAndSettle();
              expect(home(t).page, page);
              expect(find.byTooltip('Return to Live'), findsOneWidget);
              // The app or service name and the church name are one target.
              expect(
                find.descendant(
                  of: key('header-return-to-live'),
                  matching: key(target),
                ),
                findsOneWidget,
              );
              await t.tap(key(target));
              await t.pumpAndSettle();
              expect(home(t).page, 0, reason: 'from page $page by $target');
            }
            expect(find.text('St Mark’s Church'), findsOneWidget);
            if (desktop && service == 'none') {
              expect(key('standing-by-desktop'), findsOneWidget);
            }
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }

    testWidgets('not while the controls are locked', (t) async {
      await open(t, service: 'running');
      await t.tap(key('control-lock'));
      await t.pumpAndSettle();
      // However it got there, a locked app stays where it is.
      home(t).navigatePage(2);
      await t.pumpAndSettle();
      expect(t.widget<InkWell>(key('header-return-to-live')).onTap, isNull);
      expect(find.byTooltip('Return to Live'), findsNothing);
      await t.tap(key('header-title'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(home(t).page, 2);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('the keys footer', () {
    testWidgets('lists Jump to segment with the other keys', (t) async {
      await open(t, layout: 'mission_control', service: 'running');
      final legend = key('key-legend');
      expect(legend, findsOneWidget);
      String text() => t
          .widgetList<Text>(
            find.descendant(of: legend, matching: find.byType(Text)),
          )
          .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
          .join(' · ');
      expect(
        text(),
        'Space  Pause · PgDn PgDn  Next · + −  Adjust time · Ctrl Z  Undo · '
        'J  Jump to segment · 1 – 9  Cues · M  Message · Ctrl L  Lock · '
        'Ctrl K  Commands · Timer changes ask to confirm',
      );
      await t.pumpWidget(const SizedBox());
      // Keys has it too.
      await open(t, layout: 'keys', service: 'running');
      expect(
        find.descendant(of: legend, matching: find.text('J  Jump to segment')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    for (final layout in const ['three_panes', 'dial']) {
      testWidgets('$layout has it wherever the ring has room for it', (
        t,
      ) async {
        Future<void> check(Size size, {String keyHints = 'automatic'}) async {
          await open(
            t,
            size: size,
            layout: layout,
            service: 'running',
            keyHints: keyHints,
          );
          final where = '$size, key labels $keyHints';
          expect(t.takeException(), isNull, reason: where);
          // With key labels on, in every window but one too short for
          // the panes even without it.
          final tall = size.height > 600 && keyHints != 'off';
          expect(
            key('pane-key-legend'),
            tall ? findsOneWidget : findsNothing,
            reason: where,
          );
          if (tall) {
            // At the bottom of the middle pane, under End service.
            final legend = t.getRect(key('pane-key-legend'));
            final pane = t.getRect(key('live-timer-pane'));
            expect(
              legend.top,
              greaterThanOrEqualTo(pane.bottom),
              reason: where,
            );
            expect(
              legend.bottom,
              lessThanOrEqualTo(size.height),
              reason: where,
            );
            expect(legend.left, closeTo(pane.left, 1), reason: where);
            expect(legend.width, closeTo(pane.width, 1), reason: where);
            expect(
              find.descendant(
                of: key('pane-key-legend'),
                matching: find.textContaining('Pause'),
              ),
              findsOneWidget,
            );
          }
          // As in the fit checks, a window under 768 high may scroll.
          for (final button in [
            if (size.height >= 768) ...[
              'pause-resume',
              'next-segment',
              'end-service',
            ],
          ]) {
            final found = key(button);
            expect(
              found.hitTestable(),
              findsOneWidget,
              reason: '$button, $where',
            );
            expect(
              t.getRect(found).bottom,
              lessThanOrEqualTo(
                tall ? t.getRect(key('pane-key-legend')).top : size.height,
              ),
              reason: '$button, $where',
            );
          }
          await t.pumpWidget(const SizedBox());
        }

        await check(const Size(1366, 768));
        await check(const Size(1200, 600));
        await check(const Size(1366, 900));
        await check(const Size(1920, 1080));
        await check(const Size(2560, 1440));
        await check(const Size(1920, 1080), keyHints: 'off');
      });
    }

    testWidgets('is not there before a service', (t) async {
      await open(t, size: const Size(1920, 1080), service: 'loaded');
      expect(key('pane-key-legend'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('leaves out the least needed keys rather than wrap', (t) async {
      setScreen(t, const Size(2000, 400));
      Future<List<String>> shown(double width, {String? status}) async {
        await t.pumpWidget(
          MaterialApp(
            theme: appTheme('midnight_lime'),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: KeyLegend(status: status),
                ),
              ),
            ),
          ),
        );
        expect(t.takeException(), isNull, reason: '$width');
        expect(t.getSize(key('key-legend')).height, 28);
        return t
            .widgetList<Text>(
              find.descendant(
                of: key('key-legend'),
                matching: find.byType(Text),
              ),
            )
            .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
            .toList();
      }

      final wide = await shown(1800);
      expect(wide, contains('Timer changes ask to confirm'));
      expect(wide, contains('J  Jump to segment'));
      // The reminder goes before any key.
      final middling = await shown(1100);
      expect(middling, isNot(contains('Timer changes ask to confirm')));
      expect(middling.length, 9);
      final narrow = await shown(600);
      expect(narrow, contains('Space  Pause'));
      expect(narrow, contains('PgDn PgDn  Next'));
      expect(narrow, isNot(contains('Ctrl K  Commands')));
      // The keys keep their order.
      expect(narrow.indexOf('Space  Pause'), 0);
      final tiny = await shown(200, status: 'Display connected');
      expect(tiny, contains('Display connected'));
      expect(await shown(80), isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('looks right in Three panes at 1920 × 1080', (t) async {
      await open(t, size: const Size(1920, 1080), service: 'running');
      expect(key('pane-key-legend'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-three-panes-1080-keys.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  });
}
