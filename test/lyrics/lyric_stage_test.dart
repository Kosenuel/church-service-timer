import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';

const verse =
    '’Twas grace that taught my heart to fear,\nAnd grace my fears relieved;\nHow precious did that grace appear\nThe hour I first believed.';

Json slide(
  String bg, {
  String text = verse,
  Map<String, Object?> more = const {},
}) => {
  'v': 1,
  'key': 'k:$bg',
  'kind': 'song',
  'label': 'Verse 2',
  'text': text,
  'bg': bg,
  'dim': 70,
  'size': 'm',
  'align': 'center',
  'motion': false,
  ...more,
};

/// What a screen is sent with lyrics on it: the countdown is still there.
Json picture(Json lyrics) => {
  'stageSharing': true,
  'displayIsTimer': true,
  'displayText': '12:34',
  'remaining': '12:34',
  'phase': 'active',
  'lyrics': lyrics,
};

Future<void> show(
  WidgetTester t,
  Json data, {
  Size size = const Size(960, 540),
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
  // Let a photo decode.
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);

  for (final bg in [
    'mountain_dusk',
    'aurora',
    'starry_night',
    'linen',
    'photo:northern-lights',
    'stained_glass',
  ]) {
    testWidgets('a lyric slide on $bg', (t) async {
      await show(t, picture(slide(bg)));
      expect(find.byKey(const ValueKey('lyric-stage')), findsOneWidget);
      expect(
        find.text('12:34'),
        findsNothing,
        reason: 'the slide covers the countdown',
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile(
          '../goldens/lyrics-slide-${bg.replaceAll(':', '-')}.png',
        ),
      );
    });
  }

  testWidgets('the countdown chip in the corner', (t) async {
    await show(t, picture(slide('ocean', more: {'chip': '12:34'})));
    expect(find.byKey(const ValueKey('lyric-chip')), findsOneWidget);
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/lyrics-chip.png'),
    );
  });

  testWidgets('Black is black, with no chip', (t) async {
    await show(
      t,
      picture({
        'v': 1,
        'key': 'b',
        'black': true,
        'bg': 'aurora',
        'chip': '1:00',
      }),
    );
    expect(find.byKey(const ValueKey('lyric-black')), findsOneWidget);
    expect(find.byKey(const ValueKey('lyric-chip')), findsNothing);
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/lyrics-black.png'),
    );
  });

  testWidgets('a Bible verse slide with its reference line', (t) async {
    await show(
      t,
      picture(
        slide(
          'royal_velvet',
          text:
              '¹⁶ For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life. ¹⁷ For God sent not his Son into the world to condemn the world; but that the world through him might be saved.',
          more: {'kind': 'scripture', 'reference': 'John 3:16-17 · KJV'},
        ),
      ),
    );
    expect(find.text('John 3:16-17 · KJV'), findsOneWidget);
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/lyrics-scripture.png'),
    );
  });

  testWidgets('an announcement slide', (t) async {
    await show(
      t,
      picture(
        slide(
          'midnight',
          text:
              'Join us after the service for tea, coffee and cake in the church hall. Everyone is welcome.',
          more: {
            'kind': 'announcement',
            'title': 'Harvest lunch',
            'detail': 'Sunday 30 November · 12:30 · Church hall',
            'align': 'left',
          },
        ),
      ),
    );
    expect(find.text('Harvest lunch'), findsOneWidget);
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/lyrics-announcement.png'),
    );
  });

  testWidgets('long words never overflow, at any shape of screen', (t) async {
    const long =
        'Immortal, invisible, God only wise, in light inaccessible hid from our eyes, most blessèd, most glorious, the Ancient of Days, almighty, victorious, Thy great name we praise.\nUnresting, unhasting, and silent as light,\nNor wanting, nor wasting, Thou rulest in might';
    for (final size in const [
      Size(360, 780),
      Size(780, 360),
      Size(1366, 768),
      Size(1920, 1080),
      Size(200, 120),
    ]) {
      for (final s in ['s', 'm', 'l']) {
        await show(
          t,
          picture(slide('midnight', text: long, more: {'size': s})),
          size: size,
        );
        expect(t.takeException(), isNull, reason: '$size $s');
        final words = t.getRect(find.byKey(const ValueKey('lyric-words')));
        final screen = t.getRect(find.byType(StageSurface));
        expect(
          screen.contains(words.topLeft) &&
              screen.contains(words.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: '$size $s',
        );
      }
    }
  });

  testWidgets('a quick message to the stage still wins over a slide', (
    t,
  ) async {
    await show(t, {
      ...picture(slide('aurora')),
      'quickMessage': const QuickMessage(body: 'Two minutes').toJson(),
    });
    expect(find.byKey(const ValueKey('lyric-stage')), findsNothing);
    expect(find.text('Two minutes'), findsOneWidget);
  });

  testWidgets('without lyrics the screen shows its countdown as before', (
    t,
  ) async {
    final data = picture(slide('aurora'))..remove('lyrics');
    await show(t, data);
    expect(find.byKey(const ValueKey('lyric-stage')), findsNothing);
  });
}
