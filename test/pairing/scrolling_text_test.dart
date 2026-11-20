import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/scrolling_text.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';

/// Counts how often the stage around the scrolling text is painted.
class _Paints extends CustomPainter {
  static var count = 0;
  @override
  void paint(Canvas canvas, Size size) => count++;
  @override
  bool shouldRepaint(_Paints old) => false;
}

const frame = Duration(microseconds: 16667);

void main() {
  setUpAll(loadAppFonts);

  Json cue(String text, {int speed = 12, Json extra = const {}}) => {
    'displayText': text,
    'effect': 'scroll',
    'speed': speed,
    'stageSharing': true,
    ...extra,
  };

  Future<void> show(WidgetTester t, Json data, {bool stale = false}) =>
      t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _Paints()),
                StageSurface(data: data, stale: stale),
              ],
            ),
          ),
        ),
      );

  double left(WidgetTester t, String text) => t.getRect(find.text(text)).left;

  /// A 1920 × 1080 second screen.
  Future<void> screen(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('moves on every frame by the time since the last one', (t) async {
    await screen(t);
    await show(t, cue('PLEASE WRAP UP'));
    await t.pump();
    final steps = <double>[];
    var last = left(t, 'PLEASE WRAP UP');
    // A second of frames and no new picture from the host.
    for (var i = 0; i < 60; i++) {
      await t.pump(frame);
      final x = left(t, 'PLEASE WRAP UP');
      steps.add(last - x);
      last = x;
    }
    expect(steps.first, greaterThan(1));
    // Every frame the same step: the pace does not wait for snapshots.
    for (final step in steps) {
      expect(step, closeTo(steps.first, .01));
    }
    // A frame twice as long moves it twice as far.
    await t.pump(frame * 2);
    expect(last - left(t, 'PLEASE WRAP UP'), closeTo(steps.first * 2, .02));
    // Nothing else on the screen is painted again while it moves.
    _Paints.count = 0;
    for (var i = 0; i < 30; i++) {
      await t.pump(frame);
    }
    expect(_Paints.count, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a new picture with the same cue carries on where it was', (
    t,
  ) async {
    await screen(t);
    await show(t, cue('PLEASE WRAP UP'));
    await t.pump();
    for (var i = 0; i < 30; i++) {
      await t.pump(frame);
    }
    final before = left(t, 'PLEASE WRAP UP');
    // The host's next snapshot: the same cue, a second later.
    await show(t, cue('PLEASE WRAP UP', extra: {'revision': 2}));
    expect(left(t, 'PLEASE WRAP UP'), closeTo(before, .01));
    await t.pump(frame);
    final step = before - left(t, 'PLEASE WRAP UP');
    expect(step, greaterThan(1));
    expect(step, lessThan(10));
    // A faster speed changes the pace, not the place.
    final at = left(t, 'PLEASE WRAP UP');
    await show(t, cue('PLEASE WRAP UP', extra: {'screenSpeed': 24}));
    expect(left(t, 'PLEASE WRAP UP'), closeTo(at, .01));
    await t.pump(frame);
    expect(at - left(t, 'PLEASE WRAP UP'), closeTo(step * 2, .02));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a different cue starts again from the right-hand edge', (
    t,
  ) async {
    await screen(t);
    await show(t, cue('PLEASE WRAP UP'));
    await t.pump();
    for (var i = 0; i < 60; i++) {
      await t.pump(frame);
    }
    expect(left(t, 'PLEASE WRAP UP'), lessThan(1800));
    await show(t, cue('MIC LOW'));
    // At the right-hand edge, inside the screen's 12 px margin.
    expect(left(t, 'MIC LOW'), closeTo(1920 - 12, 1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('keeps the speed: twice the speed, twice as far', (t) async {
    await screen(t);
    Future<double> moved(Json data) async {
      await t.pumpWidget(const SizedBox());
      await show(t, data);
      await t.pump();
      final start = left(t, 'PLEASE WRAP UP');
      for (var i = 0; i < 30; i++) {
        await t.pump(frame);
      }
      return start - left(t, 'PLEASE WRAP UP');
    }

    final sign = await moved(cue('PLEASE WRAP UP'));
    final fast = await moved(cue('PLEASE WRAP UP', speed: 24));
    final screens = await moved(
      cue('PLEASE WRAP UP', extra: {'screenSpeed': 6}),
    );
    expect(fast, closeTo(sign * 2, .1));
    expect(screens, closeTo(sign / 2, .1));
    // 12 on the sign is 72 px a second at the preview's size, scaled up
    // with the text: half a second here.
    expect(sign, greaterThan(100));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('holds still while the host is out of touch, then carries on', (
    t,
  ) async {
    await screen(t);
    await show(t, cue('PLEASE WRAP UP'));
    await t.pump();
    for (var i = 0; i < 10; i++) {
      await t.pump(frame);
    }
    final held = left(t, 'PLEASE WRAP UP');
    await show(t, cue('PLEASE WRAP UP'), stale: true);
    await t.pump(const Duration(seconds: 2));
    expect(left(t, 'PLEASE WRAP UP'), held);
    expect(t.binding.hasScheduledFrame, isFalse);
    await show(t, cue('PLEASE WRAP UP'));
    await t.pump();
    await t.pump(frame);
    expect(left(t, 'PLEASE WRAP UP'), lessThan(held));
    expect(left(t, 'PLEASE WRAP UP'), greaterThan(held - 10));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('scrolls as before with reduced motion turned on', (t) async {
    await screen(t);
    await t.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true, size: Size(1920, 1080)),
        child: MaterialApp(
          home: Scaffold(
            body: ScrollingText(
              text: 'AMEN',
              style: TextStyle(fontSize: 100),
              speed: 100,
            ),
          ),
        ),
      ),
    );
    await t.pump();
    final start = left(t, 'AMEN');
    await t.pump(const Duration(milliseconds: 500));
    expect(start - left(t, 'AMEN'), closeTo(50, .01));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a new size keeps the text where it was', (t) async {
    Future<void> sized(double width) => t.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const ScrollingText(
              text: 'AMEN',
              style: TextStyle(fontSize: 40),
              speed: 100,
            ),
          ),
        ),
      ),
    );
    await sized(800);
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(left(t, 'AMEN'), closeTo(600, .01));
    await sized(400);
    // The same share of the way across: half way.
    expect(left(t, 'AMEN'), closeTo(300, .01));
    await t.pump(const Duration(seconds: 1));
    expect(left(t, 'AMEN'), closeTo(200, .01));
    await t.pumpWidget(const SizedBox());
  });
}
