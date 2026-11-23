import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:church_service_timer/windows/second_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/waiting.dart';
import '../support/widget_setup.dart';
import '../windows/second_screen_live_test.dart' show SecondPort;

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5),
  Segment('Sermon', 40, speaker: 'Pastor Ade'),
  Segment('Response', 6, seconds: 30, speaker: 'Worship team'),
  Segment('Closing', 2),
], DisplaySettings());

const countdown = <String, dynamic>{
  'stageSharing': true,
  'phase': 'active',
  'displayText': '12:34',
  'effect': 'static',
  'displayIsTimer': true,
  'outputMode': 'Countdown',
  'segment': 'Sermon',
  'nextSegment': 'Response',
  'upNext': 'Next: Response · Worship team · 6 min 30 s',
  'stageLayout': 'next',
};

Future<void> stage(
  WidgetTester t,
  Json data, {
  Size size = const Size(1920, 1080),
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
  await t.pump(const Duration(milliseconds: 400));
}

Rect digits(WidgetTester t) {
  final line = t.getRect(find.byKey(const ValueKey('stage-time-width')));
  final em = line.height / 1.1;
  return Rect.fromLTRB(
    line.left,
    line.top + .155 * em,
    line.right,
    line.top + .875 * em,
  );
}

// The name in the band for what is next (Timer and up next), and its words.
final line = find.byKey(const ValueKey('stage-band-name'));
final detail = find.byKey(const ValueKey('stage-band-detail'));
String lineText(WidgetTester t) => t.widget<Text>(line).data!;

void main() {
  setUpAll(loadAppFonts);

  group('the up next line', () {
    test('names who is next and for how long', () {
      final t = sunday();
      expect(stageUpNextLine(t, 0), 'Next: Sermon · Pastor Ade · 40 min');
      expect(
        stageUpNextLine(t, 1),
        'Next: Response · Worship team · 6 min 30 s',
      );
      // No speaker: the name and length only.
      expect(stageUpNextLine(t, 2), 'Next: Closing · 2 min');
      // Nothing after the last segment, during a Quick timer or with no
      // program.
      expect(stageUpNextLine(t, 3), '');
      expect(stageUpNextLine(t, 0, quick: true), '');
      expect(stageUpNextLine(null, 0), '');
    });

    test('every chooser offers the same four choices in the same words', () {
      expect(stageLayouts, {
        'timer': 'Timer only',
        'current': 'Timer and segment name',
        'next': 'Timer and up next',
        'only': 'Up next only',
      });
      expect(identical(screenLayouts, stageLayouts), isTrue);
      expect(identical(secondScreenLayouts, stageLayouts), isTrue);
      expect(stageLayoutValue('next'), 'next');
      expect(stageLayoutValue('only'), 'only');
      expect(stageLayoutValue('nonsense'), 'timer');
      expect(stageLayoutValue(null), 'timer');
    });

    test('a snapshot from an older host still shows the next name', () {
      expect(
        stageLayoutLine({'nextSegment': 'Offering'}, 'next'),
        'Next: Offering',
      );
      expect(stageLayoutLine({'nextSegment': ''}, 'next'), '');
      expect(stageLayoutLine(countdown, 'timer'), '');
      expect(stageLayoutLine(countdown, 'current'), 'Sermon');
    });
  });

  group('the host', () {
    test('the snapshot carries the line, and none on the last segment or '
        'during a Quick timer', () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act('load', value: sunday());
      await c.act('start');
      expect(
        c.pairedSnapshot(false)['upNext'],
        'Next: Sermon · Pastor Ade · 40 min',
      );
      await c.act('advance');
      await c.act('advance');
      await c.act('advance');
      expect(c.state.session.index, 3);
      expect(c.pairedSnapshot(false)['upNext'], '');
      await c.act('end');
      expect(
        await c.startQuickTimer(const QuickTimerChoice('Offering', 300)),
        isTrue,
      );
      expect(c.state.session.quickTimer, isTrue);
      expect(c.pairedSnapshot(false)['upNext'], '');
    });

    test('the stage simulator, second screen, full screen and web screens '
        'each follow their own choice', () async {
      final port = SecondPort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act('load', value: sunday());
      await c.act('start');
      const next = 'Next: Sermon · Pastor Ade · 40 min';
      // Each starts with the timer only.
      expect(c.stageSimulatorSnapshot()['stageLayout'], 'timer');
      expect(c.stageWindowSnapshot()['stageLayout'], 'timer');
      expect(c.webStageSettings.stageLayout, 'timer');
      expect(c.stageSimulatorSnapshot()['upNext'], next);
      // The simulator: kept on this device, never in a backup.
      expect(await c.setSimulatorLayout('next'), isTrue);
      expect(c.stageSimulatorSnapshot()['stageLayout'], 'next');
      expect(AppState.fromJson(c.state.toJson()).simulatorLayout, 'next');
      expect(exportBackup(c.state, c.now), isNot(contains('simulatorLayout')));
      expect(await c.setSimulatorLayout('nonsense'), isFalse);
      // The second screen, which full screen on a computer follows too.
      await c.secondScreen!.setLayout('current');
      expect(c.stageWindowSnapshot()['stageLayout'], 'current');
      expect(c.stageSimulatorSnapshot()['stageLayout'], 'next');
      // Web stage displays: a choice for all of them, saved with the
      // web screen options.
      final settings = c.webStageSettings;
      expect(
        viewFor(WebRole.stage, c.web.snapshot(), settings)['layout'],
        'timer',
      );
      expect(
        await c.setWebStageSettings(settings.copyWith(stageLayout: 'next')),
        isTrue,
      );
      expect(c.webStageSettings.stageLayout, 'next');
      expect(
        WebStageSettings.fromJson(
          c.webStageSettings.toJson(),
          churchName: '',
        ).stageLayout,
        'next',
      );
      final view = viewFor(WebRole.stage, c.web.snapshot(), c.webStageSettings);
      expect(view['layout'], 'next');
      expect(view['countdown']['next'], {
        'name': 'Sermon',
        'detail': 'Pastor Ade · 40 min',
      });
      expect(
        viewFor(
          WebRole.stage,
          c.web.snapshot(),
          c.webStageSettings.copyWith(stageLayout: 'current'),
        )['countdown']['now'],
        {'name': 'Welcome', 'by': ''},
      );
      // Up next only is chosen and kept like the others.
      expect(
        await c.setWebStageSettings(settings.copyWith(stageLayout: 'only')),
        isTrue,
      );
      expect(
        WebStageSettings.fromJson(
          c.webStageSettings.toJson(),
          churchName: '',
        ).stageLayout,
        'only',
      );
    });

    test('a web stage display shows no countdown bands over a cue or '
        'message', () {
      final settings = const WebStageSettings(
        orderCode: 'abcd',
        localName: 'church-timer',
        stageLayout: 'next',
      );
      expect(
        viewFor(WebRole.stage, countdown, settings)['countdown']['next'],
        isNotNull,
      );
      expect(
        viewFor(WebRole.stage, {
          ...countdown,
          'displayIsTimer': false,
        }, settings).containsKey('countdown'),
        isFalse,
      );
    });

    test('a paired stage screen set to up next receives the line', () async {
      final host = AppController(FakePort());
      final client = PairHub();
      await host.initialize(startTicker: false);
      addTearDown(() async {
        await client.stop();
        client.dispose();
        await host.pairing.stop();
        host.dispose();
      });
      await host.act('load', value: sunday());
      await host.act('start');
      await host.selectDestination('mobile');
      await host.pairing.host('127.0.0.1');
      await client.join(host.pairing.code!.encode(), 'Band', 'stage');
      await host.pairing.approve(host.pairing.peers.last);
      final id = host.pairing.peers.last.id;
      await eventually(() => !client.stale);
      await host.pairing.configureScreen(id, group: 'choir', layout: 'next');
      await eventually(() => client.snapshot?['stageLayout'] == 'next');
      expect(client.snapshot!['upNext'], 'Next: Sermon · Pastor Ade · 40 min');
    });
  });

  group('the stage screen', () {
    testWidgets('shows what is next in a band under the countdown on a big '
        'screen', (t) async {
      await stage(t, countdown);
      expect(t.takeException(), isNull);
      expect(lineText(t), 'Response');
      expect(t.widget<Text>(detail).data, 'Worship team · 6 min 30 s');
      expect(find.text('UP NEXT'), findsOneWidget);
      final rect = t.getRect(find.byKey(const ValueKey('stage-band-up next')));
      expect(rect.top, greaterThan(digits(t).bottom));
      expect(rect.bottom, lessThanOrEqualTo(1080));
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-up-next-1080.png'),
      );
    });

    testWidgets('shows the band on a phone on its side', (t) async {
      await stage(t, countdown, size: const Size(844, 390));
      expect(t.takeException(), isNull);
      expect(
        t.getRect(find.byKey(const ValueKey('stage-band-up next'))).top,
        greaterThan(digits(t).bottom),
      );
      await expectLater(
        find.byType(StageSurface),
        matchesGoldenFile('../goldens/stage-up-next-phone.png'),
      );
    });

    testWidgets('shows nothing on the last segment or for the timer only', (
      t,
    ) async {
      await stage(t, {...countdown, 'upNext': '', 'nextSegment': ''});
      expect(line, findsNothing);
      await stage(t, {...countdown, 'stageLayout': 'timer'});
      expect(line, findsNothing);
      // Nor over a cue that fills the screen.
      await stage(t, {
        ...countdown,
        'displayIsTimer': false,
        'outputMode': 'Cue',
        'displayText': 'WRAP UP',
      });
      expect(line, findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a long name stays on one line and ends in an ellipsis on a '
        'wide screen', (t) async {
      const long =
          'Testimony and thanksgiving for the harvest season with the '
          'youth fellowship choir and friends';
      for (final size in const [Size(844, 390), Size(1920, 1080)]) {
        await stage(t, {
          ...countdown,
          'nextSegment': long,
          'upNext': 'Next: $long · Brother Emmanuel · 12 min 30 s',
        }, size: size);
        expect(t.takeException(), isNull, reason: '$size');
        final text = t.widget<Text>(line);
        expect(text.maxLines, 1);
        expect(text.softWrap, isFalse);
        expect(text.overflow, TextOverflow.ellipsis);
        final rect = t.getRect(line);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        final paragraph = t.renderObject<RenderParagraph>(
          find.descendant(of: line, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isTrue, reason: '$size');
      }
    });

    testWidgets('fits small and odd-shaped screens without overflow', (
      t,
    ) async {
      for (final size in const [
        Size(320, 568),
        Size(844, 390),
        Size(1920, 1080),
      ]) {
        await stage(t, countdown, size: size);
        expect(t.takeException(), isNull, reason: '$size');
        final time = digits(t);
        final rect = t.getRect(
          find.byKey(const ValueKey('stage-band-up next')),
        );
        expect(time.left, greaterThanOrEqualTo(0));
        expect(time.right, lessThanOrEqualTo(size.width));
        expect(rect.top, greaterThan(time.bottom), reason: '$size');
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
    });

    testWidgets('a banner cue leaves the band clear of its own band', (
      t,
    ) async {
      for (final size in const [
        Size(320, 568),
        Size(844, 390),
        Size(1920, 1080),
      ]) {
        for (final position in ['top', 'bottom']) {
          await stage(t, {
            ...countdown,
            'displayText': 'WRAP UP',
            'displayIsTimer': false,
            'outputMode': 'Cue',
            'cueColor': '#ffc247',
            'cuePosition': position,
            'underText': '12:34',
            'underMode': 'Countdown',
          }, size: size);
          final reason = '$size $position';
          expect(t.takeException(), isNull, reason: reason);
          final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
          final rect = t.getRect(
            find.byKey(const ValueKey('stage-band-up next')),
          );
          final time = digits(t);
          expect(lineText(t), 'Response');
          expect(rect.overlaps(band), isFalse, reason: reason);
          expect(rect.overlaps(time), isFalse, reason: reason);
          expect(time.overlaps(band), isFalse, reason: reason);
          await t.pumpWidget(const SizedBox());
        }
      }
    });
  });

  testWidgets('Choose display offers the same choice for the stage simulator '
      'and its preview follows it', (t) async {
    setScreen(t);
    late AppController c;
    await t.runAsync(() async {
      c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.setSimulatorKind('stage');
      await c.act('load', value: sunday());
      await c.act('start');
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final preview = find.byKey(const ValueKey('stage-simulator-preview'));
    expect(find.descendant(of: preview, matching: line), findsNothing);
    await t.tap(find.byKey(const ValueKey('header-connection')));
    await t.pumpAndSettle();
    for (final label in stageLayouts.values) {
      expect(find.text(label), findsOneWidget);
    }
    final chip = find.byKey(const ValueKey('simulator-layout-next'));
    expect(find.byKey(const ValueKey('simulator-layout-only')), findsOneWidget);
    await t.ensureVisible(chip);
    await t.runAsync(() async {
      await t.tap(chip);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(c.state.simulatorLayout, 'next');
    expect(find.byType(AlertDialog), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.descendant(of: preview, matching: line)).data,
      'Sermon',
    );
    expect(
      t.widget<Text>(find.descendant(of: preview, matching: detail)).data,
      'Pastor Ade · 40 min',
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
