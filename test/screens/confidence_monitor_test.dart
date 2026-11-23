import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/confidence_monitor.dart';
import 'package:church_service_timer/pairing/countdown_face.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';

/// Slides and timer: the confidence monitor on every app screen
/// ([StageSurface]), and what it gives way to.
void main() {
  setUpAll(loadAppFonts);

  const wide = Size(1920, 1080), phone = Size(390, 800);

  Json monitor({
    String moment = 'normal',
    String themeId = 'midnight_lime',
    String alert = 'strong',
    bool next = true,
    Json? extra,
  }) => {
    'stageSharing': true,
    'stageLayout': 'timer',
    'stageShow': 'monitor',
    'displayText': moment == 'overtime' ? '+01:10' : '04:32',
    'remaining': moment == 'overtime' ? '+01:10' : '04:32',
    'effect': 'static',
    'displayIsTimer': true,
    'outputMode': 'Countdown',
    'phase': 'active',
    'segment': 'Worship',
    'overtime': moment == 'overtime',
    'paused': moment == 'paused',
    if (moment == 'warning') 'warning': true,
    'progress': .6,
    'overtimeAlert': alert,
    'stageTheme': StageColors.fieldsOf(paletteFor(themeId)),
    'confidence': {
      'v': 1,
      'key': 'well:0',
      'kind': 'song',
      'label': 'Verse 1',
      'text':
          'When peace like a river attendeth my way\n'
          'When sorrows like sea billows roll\n'
          'Whatever my lot, Thou hast taught me to say\n'
          'It is well, it is well with my soul',
      'clock': '10:42',
      if (next) 'next': {'label': 'Chorus', 'line': 'It is well with my soul'},
    },
    ...?extra,
  };

  Future<void> pump(WidgetTester t, Json data, Size size) async {
    setScreen(t, size);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: stageBackdropOf(data),
          body: StageSurface(data: data, stale: false),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> golden(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/confidence-$name.png'),
    );
  }

  for (final (name, data, size) in [
    ('wide', monitor(), wide),
    ('warning-wide', monitor(moment: 'warning'), wide),
    ('overtime-wide', monitor(moment: 'overtime'), wide),
    (
      'overtime-gentle-wide',
      monitor(moment: 'overtime', alert: 'gentle'),
      wide,
    ),
    ('phone', monitor(), phone),
    ('overtime-phone', monitor(moment: 'overtime'), phone),
    ('warning-phone', monitor(moment: 'warning'), phone),
    ('light-wide', monitor(themeId: 'warm_ivory'), wide),
    (
      'light-overtime-gentle-wide',
      monitor(themeId: 'warm_ivory', moment: 'overtime', alert: 'gentle'),
      wide,
    ),
  ]) {
    testWidgets('golden: $name', (t) async {
      await pump(t, data, size);
      expect(find.byType(ConfidenceMonitor), findsOneWidget);
      await golden(t, name);
    });
  }

  testWidgets('the words, the time and the next slide are all there', (
    t,
  ) async {
    await pump(t, monitor(), wide);
    expect(find.text('VERSE 1'), findsOneWidget);
    expect(find.text('TIME LEFT'), findsOneWidget);
    expect(
      find.text('Chorus · It is well with my soul', findRichText: true),
      findsOneWidget,
    );
    // The words take the larger side.
    final words = t.getSize(find.byKey(const ValueKey('confidence-words')));
    final side = t.getSize(find.byKey(const ValueKey('confidence-side')));
    expect(words.width, greaterThan(side.width * 1.5));
    // In the theme's colours, never a picture.
    expect(stageBackdropOf(monitor()), StageColors.of(monitor()).background);
    expect(stageFillsScreen(monitor()), isTrue);
  });

  testWidgets('the last slide says so; overtime says OVER TIME', (t) async {
    await pump(t, monitor(next: false, moment: 'overtime'), wide);
    expect(find.text('Last slide', findRichText: true), findsOneWidget);
    expect(find.text('OVER TIME'), findsOneWidget);
    final side = t.widget<DecoratedBox>(
      find.byKey(const ValueKey('confidence-side')),
    );
    expect(
      (side.decoration as BoxDecoration).color,
      StageColors.overtimeRed,
      reason: 'Strong: the time panel turns red, the words stay readable',
    );
  });

  testWidgets('Gentle overtime: red digits and a frame round the time', (
    t,
  ) async {
    final data = monitor(moment: 'overtime', alert: 'gentle');
    await pump(t, data, wide);
    final side = t.widget<DecoratedBox>(
      find.byKey(const ValueKey('confidence-side')),
    );
    final deco = side.decoration as BoxDecoration;
    expect(deco.color, StageColors.of(data).surface);
    expect(deco.border, isNotNull);
  });

  testWidgets('with no service, the time of day', (t) async {
    await pump(t, monitor(extra: {'phase': 'idle'}), wide);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.bySemanticsLabel('10:42'), findsOneWidget);
  });

  testWidgets('a quick message still covers it; Blank does not', (t) async {
    await pump(
      t,
      monitor(
        extra: {
          'quickMessage': {'body': 'Two minutes', 'headline': ''},
        },
      ),
      wide,
    );
    expect(find.byType(ConfidenceMonitor), findsNothing);
    expect(find.text('Two minutes'), findsOneWidget);
    await pump(
      t,
      monitor(extra: {'blank': true, 'displayIsTimer': false}),
      wide,
    );
    expect(
      find.byType(ConfidenceMonitor),
      findsOneWidget,
      reason: 'the person on stage keeps the words and the time',
    );
  });

  testWidgets('an older snapshot without it draws the countdown', (t) async {
    final data = monitor()..remove('confidence');
    await pump(t, data, wide);
    expect(find.byType(ConfidenceMonitor), findsNothing);
    expect(find.byType(StageCountdown), findsOneWidget);
  });

  testWidgets('long words never overflow, wide or upright', (t) async {
    final long = monitor(
      extra: {
        'confidence': {
          'label': 'Bridge',
          'text': List.filled(14, 'Hallelujah, glory to the Lamb').join('\n'),
          'next': {
            'label': 'Verse 3',
            'line': List.filled(9, 'word').join(' '),
          },
        },
      },
    );
    for (final size in [wide, phone, const Size(800, 480)]) {
      await pump(t, long, size);
      expect(t.takeException(), isNull);
    }
  });
}
