import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/native_fonts.dart';
import 'package:church_service_timer/pixels.dart';
import 'package:church_service_timer/warning_notifications.dart';
import 'domain_test.dart' show FakePort;
import 'feature_cases.dart' show epoch, at, service;

class NotificationPort extends FakePort {
  final plans = <Json>[];
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'sound': true,
    'exact': true,
  };
  @override
  Future<void> syncWarnings(Json plan) async => plans.add(plan);
}

class FontPort extends FakePort {
  int renders = 0;
  @override
  Future<bool> hasTinosFont() async => true;
  @override
  Future<Json> rasterizeTinos(TextLayout l) async {
    renders++;
    return {
      'width': 40,
      'height': 3,
      'rows': ['10' * 20, '01' * 20, '10' * 20],
    };
  }
}

void main() {
  test(
    '0.2 migration preserves customized cues and removes retired font selections',
    () {
      final old = AppState.fresh(epoch).toJson()..['version'] = 2;
      old.remove('stageCues');
      old['savedCues'] = [
        {
          'name': 'My saved cue',
          'layout': {
            ...const TextLayout('SAVED', bold: true, speed: 21).toJson(),
            'font': 'service_serif',
          },
        },
      ];
      final state = AppState.fromJson(old);
      expect(state.stageCues.last.text, 'SAVED');
      expect(state.stageCues.last.bold, true);
      expect(state.stageCues.last.speed, 21);
      expect(state.stageCues.last.font, 'cuekeeper_matrix');
      expect(state.stageCues.length, 4);
      expect(AppState.fromJson(state.toJson()).stageCues.length, 4);
      expect(displayFontNames.keys, [
        'cuekeeper_matrix',
        'cuekeeper_sq_matrix',
        'tinos',
      ]);
    },
  );

  test(
    'Send saves and publishes atomically; a failed write does neither',
    () async {
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      final original = c.state.stageCues.first.toJson();
      const changed = TextLayout(
        'FINISH',
        bold: true,
        italic: true,
        speed: 20,
        align: 'right',
      );
      port.fail = true;
      expect(await c.sendAndSaveCue(changed, index: 0), false);
      expect(c.state.stageCues.first.toJson(), original);
      expect(c.state.session.alert, isNull);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.stageCues.first.toJson(), changed.toJson());
      expect(c.simulator.delivered!.text, 'FINISH');
      await c.sendAndSaveCue(const TextLayout('NEW'));
      expect(c.state.stageCues.last.text, 'NEW');
      await c.act('end');
      await c.act('load', value: c.state.templates.first);
      expect(c.state.stageCues.first.toJson(), changed.toJson());
      c.dispose();
    },
  );

  test(
    'Report clearing is durable, scoped and leaves unrelated records on retry',
    () async {
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      for (var i = 0; i < 2; i++) {
        await c.act('load', value: c.state.templates.last);
        await c.act('start');
        await c.act('end');
      }
      final first = c.state.reports.first.id;
      port.fail = true;
      expect(await c.clearReports({first}), false);
      expect(c.state.reports.length, 2);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.reports.length, 1);
      final persisted = AppState.fromJson(jsonDecode(port.data!));
      expect(persisted.reports.single.id, c.state.reports.single.id);
      c.dispose();
    },
  );

  test(
    'Phone warning deadlines reschedule on pause, adjustment and rehearsal',
    () {
      var s = service(rate: 10);
      var plan = warningNotificationPlan(s, at(0));
      expect((plan['alarms'] as List).first['at'], epoch.mono + 6000);
      s = transition(s, 'pause', at(2));
      expect(warningNotificationPlan(s, at(3))['alarms'], isEmpty);
      s = transition(s, 'pause', at(4));
      plan = warningNotificationPlan(s, at(4));
      expect((plan['alarms'] as List).first['at'], epoch.mono + 8000);
      s = transition(s, 'adjust', at(4), value: 60);
      expect(
        (warningNotificationPlan(s, at(4))['alarms'] as List).first['at'],
        epoch.mono + 14000,
      );
      s = transition(s, 'end', at(5));
      expect(warningNotificationPlan(s, at(5))['alarms'], isEmpty);
    },
  );

  test(
    'Due warning overlays a manual cue and creates one urgent phone notice after durable save',
    () async {
      final port = NotificationPort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act(
        'load',
        value: Timeline('Test', const [Segment('Talk', 3)], DisplaySettings()),
      );
      await c.act('start');
      await c.sendAndSaveCue(const TextLayout('MANUAL'), index: 0);
      port.at = at(60);
      port.fail = true;
      await c.tick();
      expect(c.simulator.delivered!.text, 'MANUAL');
      expect(port.plans.last['notice'], isNull);
      port.fail = false;
      await c.retry!();
      expect(c.simulator.delivered!.text, '2 MIN LEFT');
      expect((port.plans.last['notice'] as Map)['title'], '2 MIN LEFT');
      port.at = at(68);
      await c.tick();
      expect(c.simulator.delivered!.text, '01:52');
      c.dispose();
    },
  );

  test(
    'Live warning edits update the current service and persist for its next run',
    () async {
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      await c.setSharedWarnings([
        const WarningRule(45, TextLayout('CHECK'), destination: 'stage'),
      ]);
      expect(c.state.session.timeline!.display.warnings.single.seconds, 45);
      expect(c.state.templates.last.display.warnings.single.seconds, 45);
      expect(c.state.session.warningSeen, isEmpty);
      c.dispose();
    },
  );

  test(
    'Editing past thresholds consumes them without sending a retroactive notification',
    () async {
      final port = NotificationPort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      port.at = at(20);
      await c.setSharedWarnings([
        const WarningRule(50, TextLayout('PAST'), destination: 'stage'),
        const WarningRule(10, TextLayout('FUTURE'), destination: 'stage'),
      ]);
      expect(c.state.session.warningSeen, [0]);
      expect(port.plans.last['notice'], isNull);
      expect((port.plans.last['alarms'] as List).single['title'], 'FUTURE');
      c.dispose();
    },
  );

  test('Upgrade uses shared defaults as the authoritative warning rules', () {
    final old = AppState.fresh(epoch).toJson()..['version'] = 2;
    for (final warning in old['defaults']['warnings']) {
      warning['destination'] = 'operator';
    }
    old['templates'][0]['display']['warnings'] = [
      const WarningRule(45, TextLayout('CUSTOM')).toJson(),
    ];
    final state = AppState.fromJson(old);
    expect(
      state.defaults.warnings.every((w) => w.destination == 'stage'),
      true,
    );
    expect(
      state.templates.first.display.warnings.map((w) => w.toJson()).toList(),
      state.defaults.warnings.map((w) => w.toJson()).toList(),
    );
  });

  test(
    'Unavailable native Tinos is explicit; native rasters are cached, clipped and scrolled without scaling',
    () async {
      const l = TextLayout('TEST', font: 'tinos', height: 2);
      await NativeDisplayFonts.initialize(FakePort());
      await expectLater(
        NativeDisplayFonts.prepare(l),
        throwsA(isA<RuleError>()),
      );
      final port = FontPort();
      await NativeDisplayFonts.initialize(port);
      await Future.wait([
        NativeDisplayFonts.prepare(l),
        NativeDisplayFonts.prepare(l),
      ]);
      expect(port.renders, 1);
      expect(textWidth(l), 40);
      final frame = renderPixels(l, 0);
      expect(frame.length, 512);
      expect(
        frame.skip(6 * 32).take(32).toList(),
        List.generate(32, (i) => i.isEven),
      );
      expect(renderPixels(l, 100), isNot(frame));
      expect(
        () => TextRaster.fromJson({
          'width': 2,
          'height': 1,
          'rows': ['100'],
        }),
        throwsA(isA<RuleError>()),
      );
    },
  );

  void size(WidgetTester t) {
    t.view.physicalSize = const Size(700, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Pause, resume, fixed adjustments and Custom require confirmation',
    (t) async {
      size(t);
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Pause'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, false);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, false);
      await t.tap(find.byTooltip('Pause'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm pause'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, true);
      await t.tap(find.byTooltip('Resume'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, true);
      await t.tap(find.text('Confirm resume'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, false);
      for (final label in ['+2 min', '−2 min']) {
        final before = c.state.session.remaining(c.now);
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        expect(c.state.session.remaining(c.now), before);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(c.state.session.remaining(c.now), before);
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        await t.tap(find.text('Confirm $label'));
        await t.pumpAndSettle();
        expect(
          c.state.session.remaining(c.now),
          before + (label.startsWith('+') ? 120000 : -120000),
        );
      }
      final before = c.state.session.remaining(c.now);
      await t.tap(find.text('Custom'));
      await t.pumpAndSettle();
      expect(c.state.session.remaining(c.now), before);
      await t.tap(find.text('Confirm add time'));
      await t.pumpAndSettle();
      expect(c.state.session.remaining(c.now), before + 30000);
      expect(find.byKey(const ValueKey('end-service')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Report deletion offers cancel and confirmation for one or all records',
    (t) async {
      size(t);
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      for (var i = 0; i < 2; i++) {
        await c.act('load', value: c.state.templates.last);
        await c.act('start');
        await c.act('end');
      }
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Reports'));
      await t.pumpAndSettle();
      final record = find.byKey(
        ValueKey('open-report-${c.state.reports.last.id}'),
      );
      await t.ensureVisible(record);
      await t.tap(record);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Clear report'));
      await t.tap(find.text('Clear report'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.reports.length, 2);
      await t.tap(find.text('Clear report'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Clear report'));
      await t.pumpAndSettle();
      expect(c.state.reports.length, 1);
      final all = find.byKey(const ValueKey('clear-all-reports'));
      await t.ensureVisible(find.byTooltip('Report list options'));
      await t.tap(find.byTooltip('Report list options'));
      await t.pumpAndSettle();
      await t.tap(all);
      await t.pumpAndSettle();
      expect(c.state.reports.length, 1);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.reports.length, 1);
      await t.tap(find.byTooltip('Report list options'));
      await t.pumpAndSettle();
      await t.tap(all);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Clear all reports'));
      await t.pumpAndSettle();
      expect(c.state.reports, isEmpty);
      expect(find.textContaining('No completed services yet'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
