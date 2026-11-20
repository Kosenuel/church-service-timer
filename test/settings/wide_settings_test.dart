import 'dart:ui' as ui;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_preview.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/image_crop_page.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/settings/whats_new_page.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort, sunday;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The pages reached from Settings, in a large window: each uses the room
/// (a preview or summary beside it, or balanced columns) instead of one
/// phone column in the middle.
void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    desktopWording = true;
    // Fixed notes, so About's screenshot does not change with each release.
    changelogSource = () async => '''
## 0.31.0, 12 November 2026
- **Wide windows.** Settings pages use the room beside them for a preview.
- **Desktop layout.** Easier to find in Settings.

## 0.30.0, 2 November 2026
- **Mini timer.** A small always-on-top countdown for the operator.
- Reports open faster.

## 0.29.0, 20 October 2026
- Earlier changes.
''';
  });
  tearDown(() {
    desktopWording = false;
    changelogSource = bundledChangelog;
  });

  const full = Size(1920, 1080);
  const smallest = Size(1200, 600);

  /// The app on Settings, with a church, three programs and one finished
  /// service.
  Future<AppController> settings(WidgetTester t, Size size) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    // These pages were laid out and photographed under Three panes; the
    // default is covered in test/live/desktop_layout_test.dart.
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'three_panes',
      ),
    );
    await c.commit((draft, _) {
      draft.churchName = 'Grace Community Church';
      draft.templates.clear();
      draft.saveTemplate(sunday());
      draft.saveTemplate(
        Timeline('Midweek Prayer', const [
          Segment('Welcome', 5),
          Segment('Prayer', 30),
          Segment('Word', 20),
          Segment('Closing', 5),
        ], DisplaySettings()),
      );
      draft.saveTemplate(
        Timeline('Youth Night', const [
          Segment('Games', 15),
          Segment('Worship', 20),
          Segment('Talk', 25),
          Segment('Small groups', 30),
        ], DisplaySettings()),
      );
    });
    await c.act(
      'load',
      value: c.state.templates.firstWhere((p) => p.name == 'Sunday Service'),
    );
    await c.act('start');
    var at = 0;
    for (final seconds in const [340, 1330, 2300, 560]) {
      at += seconds;
      port.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    port.at = after(at + 280);
    await c.tick();
    await c.act('end');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> open(WidgetTester t, String entry) async {
    await t.ensureVisible(find.text(entry));
    await t.pumpAndSettle();
    await t.tap(find.text(entry));
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-settings-$name.png'),
    );
  }

  /// No filled or outlined button is stretched across its pane.
  void expectOrdinaryButtons(WidgetTester t, {double under = 420}) {
    for (final element in find.bySubtype<ButtonStyleButton>().evaluate()) {
      if (element.widget is! FilledButton &&
          element.widget is! OutlinedButton) {
        continue;
      }
      expect(
        (element.renderObject! as RenderBox).size.width,
        lessThan(under),
        reason: '${element.widget} is too wide',
      );
    }
  }

  testWidgets('Church profile has its preview beside the form', (t) async {
    await settings(t, full);
    await open(t, 'Church profile');
    expect(find.byKey(const ValueKey('profile-header-preview')), findsOne);
    expect(find.byKey(const ValueKey('choose-church-banner')), findsOne);
    expectOrdinaryButtons(t);
    await shot(t, 'church-profile');
    // Save keeps the name and goes back.
    await t.enterText(find.byType(TextField), 'Hope Chapel');
    await t.pumpAndSettle();
    expect(find.text('Hope Chapel'), findsNWidgets(2));
    await t.tap(find.byKey(const ValueKey('save-church-profile')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-church-profile')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Warnings & alerts shows each warning as the stage sees it', (
    t,
  ) async {
    await settings(t, full);
    await open(t, 'Warnings & alerts');
    expect(find.text('ON THE LED SIGN'), findsOne);
    expect(find.byType(CueStagePreview), findsNothing);
    await shot(t, 'warnings');
  });

  testWidgets('Warnings & alerts follows the stage simulator', (t) async {
    final c = await settings(t, full);
    await t.runAsync(() => c.setSimulatorKind('stage'));
    await open(t, 'Warnings & alerts');
    expect(find.text('ON THE STAGE SCREEN'), findsOne);
    expect(find.text('ON THE LED SIGN'), findsNothing);
    expect(find.byType(CueStagePreview), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('warning-preview-pane')),
        matching: find.byType(LedMatrix),
      ),
      findsNothing,
    );
    await shot(t, 'warnings-stage-screen');

    // Editing a warning's text starts on the stage screen's preview,
    // with the switch to see the LED sign's.
    // The editor's stage preview plays by itself, so it never settles.
    await t.tap(find.byKey(const ValueKey('warning-rule-0')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('cue-stage-preview')), findsOneWidget);
    await t.tap(find.text('Edit text and style'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final composer = find.byType(TextComposer);
    expect(
      find.descendant(of: composer, matching: find.byType(CuePreviewSwitch)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: composer,
        matching: find.byKey(const ValueKey('cue-stage-preview')),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('Display settings lists its sections beside the chosen one', (
    t,
  ) async {
    final c = await settings(t, full);
    await open(t, 'Display settings');
    expect(find.byKey(const ValueKey('display-sections')), findsOne);
    await shot(t, 'display');
    // A click on a section shows it in place, without leaving the page.
    await t.tap(find.byKey(const ValueKey('display-section-clock')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('clock-blink')), findsOne);
    expect(find.text('Display settings'), findsOne);
    await t.tap(find.text('12-hour'));
    await t.pumpAndSettle();
    expect(c.state.clockFormat, '12h');
    expect(find.text('12-hour · AM/PM'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('display-section-end')));
    await t.pumpAndSettle();
    expectOrdinaryButtons(t);
    await shot(t, 'display-end-screen');
    for (final key in ['connection', 'profile', 'shape', 'fonts', 'zero']) {
      await t.tap(find.byKey(ValueKey('display-section-$key')));
      await t.pumpAndSettle();
      expectOrdinaryButtons(t);
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('Stage cues shows each cue as the sign shows it', (t) async {
    await settings(t, full);
    await open(t, 'Stage cues');
    expect(find.text('ON THE LED SIGN'), findsOne);
    expect(find.byType(CueStagePreview), findsNothing);
    expectOrdinaryButtons(t);
    await shot(t, 'stage-cues');
  });

  testWidgets('Stage cues follows the stage simulator', (t) async {
    final c = await settings(t, full);
    await t.runAsync(() => c.setSimulatorKind('stage'));
    await t.runAsync(
      () => c.commit(
        (draft, _) => draft.stageCues = [
          const TextLayout(
            'WRAP UP',
            bold: true,
            screenColor: 'amber',
            screenPosition: 'bottom',
          ),
          const TextLayout("TIME'S UP", bold: true, screenColor: 'red'),
          ...draft.stageCues.skip(2),
        ],
      ),
    );
    await open(t, 'Stage cues');
    expect(find.text('ON THE STAGE SCREEN'), findsOne);
    expect(find.text('ON THE LED SIGN'), findsNothing);
    // Every cue as a stage screen draws it, none as LED dots.
    expect(
      find.byType(CueStagePreview),
      findsNWidgets(c.state.stageCues.length),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stage-cue-preview-pane')),
        matching: find.byType(LedMatrix),
      ),
      findsNothing,
    );
    expect(t.takeException(), isNull);
    await shot(t, 'stage-cues-stage-screen');

    // Back to the LED simulator: the sign's previews return.
    await t.runAsync(() => c.setSimulatorKind('led'));
    await t.pumpAndSettle();
    expect(find.text('ON THE LED SIGN'), findsOne);
    expect(find.byType(CueStagePreview), findsNothing);
  });

  testWidgets('LED device management uses two columns', (t) async {
    await settings(t, full);
    await open(t, 'LED device management');
    expect(find.text('SIGN SETTINGS'), findsOne);
    expectOrdinaryButtons(t, under: 560);
    await shot(t, 'led-device');
  });

  testWidgets('Backup & restore says what a backup holds', (t) async {
    await settings(t, full);
    await open(t, 'Backup & restore');
    expect(find.text('IN A BACKUP MADE NOW'), findsOne);
    expect(find.text('Grace Community Church'), findsOne);
    expectOrdinaryButtons(t);
    await shot(t, 'backup');
  });

  testWidgets('Feedback centre shows the email beside the form', (t) async {
    await settings(t, full);
    await open(t, 'Feedback centre');
    expect(find.byKey(const ValueKey('feedback-email-preview')), findsOne);
    await t.enterText(
      find.byKey(const ValueKey('feedback-title')),
      'Warning sound is quiet',
    );
    await t.enterText(
      find.byKey(const ValueKey('feedback-message')),
      'The one-minute warning is hard to hear at the sound desk.',
    );
    await t.pumpAndSettle();
    // The email follows what is typed.
    expect(
      find.text('Church Service Timer feedback: Warning sound is quiet'),
      findsOne,
    );
    expectOrdinaryButtons(t);
    await shot(t, 'feedback');
  });

  testWidgets('Settings PIN says what the PIN covers', (t) async {
    await settings(t, full);
    await open(t, 'Settings PIN');
    expect(find.text('WHAT THE PIN COVERS'), findsOne);
    expectOrdinaryButtons(t);
    await shot(t, 'pin');
  });

  testWidgets('About has the release notes beside it', (t) async {
    await settings(t, full);
    await open(t, 'About');
    expect(find.text('0.31.0, 12 November 2026'), findsOne);
    // The row that opens the notes is not needed with them alongside.
    expect(find.byKey(const ValueKey('about-whats-new')), findsNothing);
    await shot(t, 'about');
    await t.tap(find.byKey(const ValueKey('about-diagnostics')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-metrics')), findsOne);
    expectOrdinaryButtons(t);
    await shot(t, 'diagnostics');
  });

  testWidgets('Ready for service lists the loaded program beside the checks', (
    t,
  ) async {
    final c = await settings(t, full);
    await c.act(
      'load',
      value: c.state.templates.firstWhere((p) => p.name == 'Sunday Service'),
    );
    final home = t.state<HomeState>(find.byType(Home));
    home.openSettingsDetail('Ready for service', home.readinessSettings);
    await t.pumpAndSettle();
    expect(find.text('PROGRAM TO RUN'), findsOne);
    expect(find.text('Pastor Samuel'), findsOne);
    await shot(t, 'readiness');
  });

  testWidgets('Custom theme shows its sample beside the colours', (t) async {
    await settings(t, full);
    await open(t, 'Appearance');
    await t.tap(find.text('Create custom theme'));
    await t.pumpAndSettle();
    expect(find.text('HOW IT WILL LOOK'), findsOne);
    await shot(t, 'custom-theme');
    await t.tap(find.text('Use theme'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('What’s new keeps to a readable width', (t) async {
    setScreen(t, full);
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme('midnight_lime'),
        home: WhatsNewPage(load: changelogSource),
      ),
    );
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(Card).first).width, lessThan(800));
    expect(t.takeException(), isNull);
  });

  testWidgets('Cropping a photo has ordinary buttons', (t) async {
    setScreen(t, full);
    final image = (await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 900, 600),
        Paint()..color = const Color(0xff345d48),
      );
      return recorder.endRecording().toImage(900, 600);
    }))!;
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme('midnight_lime'),
        home: ImageCropPage(
          photo: image,
          title: 'Crop banner',
          hint: 'Drag and zoom the photo.',
          action: 'Use banner',
          width: 600,
          height: 200,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byKey(const ValueKey('use-cropped-image'))).width,
      lessThan(300),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('every settings page fits the smallest desktop window', (
    t,
  ) async {
    for (final size in [
      smallest,
      const Size(1366, 768),
      const Size(2560, 1440),
    ]) {
      final c = await settings(t, size);
      for (final entry in [
        'Church profile',
        'Warnings & alerts',
        'Display settings',
        'Stage cues',
        'LED device management',
        'Backup & restore',
        'Feedback centre',
        'Settings PIN',
        'About',
      ]) {
        await open(t, entry);
        expect(t.takeException(), isNull, reason: '$entry at $size');
        if (entry == 'Display settings') {
          for (final key in [
            'profile',
            'clock',
            'shape',
            'fonts',
            'zero',
            'end',
          ]) {
            await t.tap(find.byKey(ValueKey('display-section-$key')));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '$key at $size');
          }
        }
        if (entry == 'About') {
          await t.ensureVisible(
            find.byKey(const ValueKey('about-diagnostics')),
          );
          await t.tap(find.byKey(const ValueKey('about-diagnostics')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'Diagnostics at $size');
          await t.pageBack();
          await t.pumpAndSettle();
        }
        await t.pageBack();
        await t.pumpAndSettle();
      }
      final home = t.state<HomeState>(find.byType(Home));
      home.openSettingsDetail('Ready for service', home.readinessSettings);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'Ready for service at $size');
      await t.pageBack();
      await t.pumpAndSettle();
      await open(t, 'Appearance');
      await t.tap(find.text('Create custom theme'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'Custom theme at $size');
      await t.tap(find.text('Cancel').last);
      await t.pumpAndSettle();
      expect(c.error, isNull);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a sign preview plays while pointed at, then rests', (t) async {
    setScreen(t, const Size(1920, 1080));
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SignPreview(
                TextLayout('A LONG WARNING THAT SCROLLS', effect: 'scroll'),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.byType(SignPreview)));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    // Moving away stops it; a timer left running would fail this test.
    await mouse.moveTo(Offset.zero);
    await t.pump();
    await mouse.removePointer();
    expect(t.takeException(), isNull);
  });

  testWidgets('Quick message presets show each message beside the list', (
    t,
  ) async {
    final c = await settings(t, full);
    await c.commit(
      (draft, _) => draft.quickMessages = const [
        QuickMessage(headline: 'Two minutes', body: 'Please wrap up'),
        QuickMessage(body: 'Band to the stage', seconds: 0),
      ],
    );
    await open(t, 'Quick message presets');
    expect(find.text('ON A STAGE SCREEN'), findsOneWidget);
    expect(find.text('Stays until cleared'), findsOneWidget);
    await shot(t, 'quick-presets');
  });

  testWidgets('Choose display shows what the display is showing', (t) async {
    await settings(t, full);
    await open(t, 'Display settings');
    await open(t, 'Connect a display');
    expect(find.text('Where should your stage output appear?'), findsOneWidget);
    expect(find.text('ON THE DISPLAY NOW'), findsOneWidget);
    await shot(t, 'choose-display');
  });

  testWidgets('the Windows warning sound is a switch, off to begin with', (
    t,
  ) async {
    await settings(t, full);
    await open(t, 'Warnings & alerts');
    final toggle = find.byKey(const ValueKey('desktop-warning-sound'));
    expect(t.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('Off. Warnings make no sound'), findsOneWidget);
    await t.ensureVisible(toggle);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      find.textContaining('On. Each warning plays the sound'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('a computer says click where a phone says tap', (t) async {
    await settings(t, full);
    await t.tap(find.byKey(const ValueKey('desktop-tab-2')));
    await t.pumpAndSettle();
    expect(find.textContaining('Click a report to open it'), findsOneWidget);
    expect(find.textContaining('Tap a report'), findsNothing);
  });
}
