import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:church_service_timer/windows/stage_output_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/steady_time.dart';
import '../support/widget_setup.dart';

/// The large time on every screen keeps one size and each digit its
/// place as it counts: paired phones and tablets, a web screen's app view,
/// the second screen, full screen on the host and the stage simulator all
/// draw it with [StageSurface].
void main() {
  setUpAll(loadAppFonts);

  const times = ['11:11', '48:03', '47:58', '00:00', '20:01'];

  Json countdown(String time) => {
    'displayText': time,
    'remaining': time,
    'effect': 'static',
    'displayIsTimer': true,
    'outputMode': 'Countdown',
    'phase': 'active',
    'segment': 'Sermon',
  };

  // What a scheduled service shows before it starts: the countdown to
  // its start in its last hour, and the clock before that.
  Json preService(String time) => {
    'displayText': time,
    'effect': 'static',
    'displayIsTimer': false,
    'outputMode': 'Pre-service',
    'phase': 'ready',
  };

  Json clock(String time) => {
    'displayText': time,
    'effect': 'static',
    'displayIsTimer': false,
    'outputMode': 'Clock',
  };

  Future<void> surface(WidgetTester t, Json data, Size size) async {
    setScreen(t, size);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: StageSurface(data: data, stale: false),
        ),
      ),
    );
    await t.pump();
  }

  final stage = find.byType(StageSurface);

  for (final size in const [Size(1920, 1080), Size(844, 390), Size(320, 480)]) {
    testWidgets('the countdown holds still on a ${size.width.toInt()} × '
        '${size.height.toInt()} screen', (t) async {
      await expectTimeHoldsStill(
        t,
        stage,
        times,
        (time) => surface(t, countdown(time), size),
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('the countdown before a service starts holds still, in Roboto', (
    t,
  ) async {
    await expectTimeHoldsStill(
      t,
      stage,
      times,
      (time) => surface(t, preService(time), const Size(1920, 1080)),
    );
    expect(
      t.widget<ClockText>(find.byType(ClockText)).style.fontFamily,
      'Roboto',
    );
    // It is the same size as the countdown once the service starts.
    final before = t.getRect(find.byType(ClockText));
    await surface(t, countdown('48:03'), const Size(1920, 1080));
    expect(t.getRect(find.byType(ClockText)), before);
  });

  testWidgets('the clock holds still, on 24 and 12-hour clocks', (t) async {
    // The clock is a flip clock: its cards keep one size and place as the
    // time changes, whatever the digits.
    for (final times in [
      ['11:11', '20:48', '09:07'],
      ['11:11 AM', '12:48 PM', '10:07 AM'],
    ]) {
      Rect? first;
      for (final time in times) {
        await surface(t, clock(time), const Size(1920, 1080));
        await t.pump(const Duration(seconds: 1));
        final box = t.getRect(find.byKey(const ValueKey('flip-time')));
        expect(box.size, (first ??= box).size, reason: time);
        expect(box.center, first.center, reason: time);
      }
    }
    // And the clock before a scheduled service.
    await expectTimeHoldsStill(t, stage, [
      '11:11 AM',
      '10:48 AM',
    ], (time) => surface(t, preService(time), const Size(1920, 1080)));
  });

  testWidgets('overtime holds still', (t) async {
    await expectTimeHoldsStill(
      t,
      stage,
      ['+01:11', '+48:03', '+00:00'],
      (time) => surface(t, {
        ...countdown(time),
        'overtime': true,
      }, const Size(1920, 1080)),
    );
  });

  testWidgets('the countdown under a banner holds still', (t) async {
    await expectTimeHoldsStill(
      t,
      stage,
      times,
      (time) => surface(t, {
        'displayText': 'WRAP UP',
        'effect': 'static',
        'displayIsTimer': false,
        'outputMode': 'Cue',
        'cuePosition': 'top',
        'underText': time,
        'underMode': 'Countdown',
      }, const Size(1920, 1080)),
    );
  });

  testWidgets('the stage window on a second screen holds still', (t) async {
    setScreen(t, const Size(1280, 720));
    final feed = StageFeed();
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await expectTimeHoldsStill(t, find.byType(StageOutputScreen), times, (
      time,
    ) async {
      feed.receive(
        jsonEncode({
          ...c.stageWindowSnapshot(),
          'displayText': time,
          'remaining': time,
        }),
      );
      await t.pumpWidget(StageOutputApp(feed: feed, onClose: () {}));
      await t.pump();
    });
    // Before a scheduled service, as the second copy is sent it.
    await expectTimeHoldsStill(t, find.byType(StageOutputScreen), times, (
      time,
    ) async {
      feed.receive(jsonEncode(preService(time)));
      await t.pump();
    });
    await t.pumpWidget(const SizedBox());
    c.dispose();
    feed.dispose();
  });

  // On Windows the app's own text is in Segoe UI; stage screens are not.
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets('everything on a stage screen is in the face the app carries', (
    t,
  ) async {
    final screens = <String, Json>{
      'countdown and segment': {
        ...countdown('48:03'),
        'stageLayout': 'segment',
      },
      'up next': {
        ...countdown('48:03'),
        'stageLayout': 'next',
        'upNext': 'Response · Worship team · 6 min',
      },
      'before the service': preService('48:03'),
      'clock': clock('9:30 AM'),
      'a cue': {
        'displayText': 'PLEASE WRAP UP',
        'effect': 'static',
        'displayIsTimer': false,
        'outputMode': 'Cue',
      },
      'a coloured cue': {
        'displayText': 'MIC IS LIVE',
        'effect': 'static',
        'displayIsTimer': false,
        'outputMode': 'Cue',
        'cueColor': '#4ade80',
      },
      'a scrolling cue': {
        'displayText': 'THE BAND COMES BACK ON STAGE NOW PLEASE',
        'effect': 'scroll',
        'displayIsTimer': false,
        'outputMode': 'Cue',
      },
      'a banner': {
        'displayText': 'WRAP UP',
        'effect': 'static',
        'displayIsTimer': false,
        'outputMode': 'Cue',
        'cuePosition': 'bottom',
        'underText': '48:03',
        'underMode': 'Countdown',
        'segment': 'Sermon',
        'stageLayout': 'segment',
      },
      'a message': {
        'quickMessage': {'headline': 'Welcome', 'body': 'Please find a seat'},
      },
      'not sending': {'stageSharing': false},
    };
    for (final entry in screens.entries) {
      await surface(t, entry.value, const Size(1280, 720));
      expect(t.takeException(), isNull, reason: entry.key);
      expectBundledFont(t, stage);
    }
    await t.pumpWidget(const SizedBox());
  }, variant: windows);

  testWidgets('the second screen window is in the face the app carries', (
    t,
  ) async {
    setScreen(t, const Size(1280, 720));
    final feed = StageFeed();
    await t.pumpWidget(StageOutputApp(feed: feed, onClose: () {}));
    // Waiting for the app, and then showing what it sends.
    expectBundledFont(t, find.byType(StageOutputScreen));
    expect(
      Theme.of(
        t.element(find.byType(StageOutputScreen)),
      ).textTheme.bodyMedium!.fontFamily,
      'Roboto',
    );
    for (final data in [
      {...countdown('48:03'), 'stageLayout': 'segment'},
      preService('48:03'),
      clock('20:48'),
    ]) {
      feed.receive(jsonEncode(data));
      await t.pump();
      expectBundledFont(t, find.byType(StageOutputScreen));
    }
    await t.pumpWidget(const SizedBox());
    feed.dispose();
  }, variant: windows);

  test('every time the host sends is held still on screens', () {
    final c = {
      for (final text in [
        '48:03',
        '+01:10',
        '123:00',
        '9:30 AM',
        '12:04 PM',
        '1:02:03',
      ])
        text: stageTimePattern.hasMatch(text),
    };
    expect(c.values, everyElement(isTrue));
    for (final text in ['STARTING SOON', '10:30 service', 'WRAP UP', '']) {
      expect(stageShowsTime(preService(text)), isFalse, reason: text);
    }
    expect(stageShowsTime(preService('48:03')), isTrue);
    expect(stageShowsTime(clock('09:30')), isTrue);
    expect(stageShowsTime(countdown('48:03')), isTrue);
    // A scrolling or flashing countdown is shown as its effect asks.
    expect(stageShowsTime({...preService('48:03'), 'effect': 'scroll'}), false);
    // The countdown before a service does not blink, as before.
    expect(stageTimeBlinks(preService('48:03')), isFalse);
    expect(stageTimeBlinks(countdown('48:03')), isTrue);
    expect(stageTimeBlinks({...countdown('48:03'), 'paused': true}), isFalse);
  });

  test('web screens put every digit of a time in a place of its own', () {
    for (final part in [
      "#stage .dg { display:inline-block; text-align:center; width:var(--dg, .6em); }",
      r"const TIME = /^[+-]?\d{1,3}(:\d\d){1,2}( [AP]M)?$/;",
      "text.style.setProperty('--dg', placeWidth(text, '0123456789', 0.6) + 'em');",
      "/[AP]/.test(char) ? el('span', 'ap', char)",
      "el('span', 'dg', char)",
    ]) {
      expect(webStagePage, contains(part), reason: part);
    }
  });
}
