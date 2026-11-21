import 'package:church_service_timer/display/clock_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the large time inside [within] is drawn: the whole time, then
/// each of its characters' places.
({String text, Rect time, List<Rect> chars}) timeLayout(
  WidgetTester t,
  Finder within,
) {
  final clock = find.descendant(of: within, matching: find.byType(ClockText));
  expect(clock, findsOneWidget);
  final text = t.widget<ClockText>(clock).text;
  return (
    text: text,
    time: t.getRect(clock),
    chars: [
      for (var i = 0; i < text.length; i++)
        t.getRect(
          find.descendant(
            of: clock,
            matching: find.byKey(ValueKey('clock-char-$i')),
          ),
        ),
    ],
  );
}

/// Shows each of [times] with [show] and checks the time inside [within]
/// keeps one size and every character its place as the digits change.
Future<void> expectTimeHoldsStill(
  WidgetTester t,
  Finder within,
  List<String> times,
  Future<void> Function(String time) show,
) async {
  ({String text, Rect time, List<Rect> chars})? first;
  for (final time in times) {
    await show(time);
    final now = timeLayout(t, within);
    expect(now.text, time);
    if (first == null) {
      first = now;
      expect(now.time.width, greaterThan(0));
      // Every digit has a place as wide as the others, whatever the font.
      final digits = [
        for (var i = 0; i < time.length; i++)
          if (RegExp(r'[0-9]').hasMatch(time[i])) now.chars[i].width,
      ];
      for (final width in digits) {
        expect(width, closeTo(digits.first, .01), reason: time);
      }
      continue;
    }
    final reason = '$time against ${first.text}';
    expectSameRect(now.time, first.time, reason);
    for (var i = 0; i < now.chars.length; i++) {
      expectSameRect(now.chars[i], first.chars[i], '$reason, character $i');
    }
  }
}

/// [a] and [b] are the same to a hundredth of a pixel.
void expectSameRect(Rect a, Rect b, String reason) {
  expect(a.left, closeTo(b.left, .01), reason: '$reason: left');
  expect(a.top, closeTo(b.top, .01), reason: '$reason: top');
  expect(a.width, closeTo(b.width, .01), reason: '$reason: width');
  expect(a.height, closeTo(b.height, .01), reason: '$reason: height');
}

/// Every piece of text inside [within] is drawn in Roboto, the face the
/// app carries, and never falls back to the system's own font.
void expectBundledFont(WidgetTester t, Finder within) {
  final texts = find.descendant(of: within, matching: find.byType(RichText));
  expect(texts, findsWidgets);
  for (final text in t.widgetList<RichText>(texts)) {
    final span = text.text;
    if (span.toPlainText().trim().isEmpty) continue;
    // Icons are drawn from their own font.
    if (span.style?.fontFamily == 'MaterialIcons') continue;
    expect(
      span.style?.fontFamily,
      'Roboto',
      reason: '"${span.toPlainText()}" is not in Roboto',
    );
  }
}
