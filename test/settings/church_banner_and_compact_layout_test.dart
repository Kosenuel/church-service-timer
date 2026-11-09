import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/church_banner.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import '../domain/feature_cases.dart' show epoch;
import '../reports/report_export_and_end_screen_cases.dart' show reportFixtures;
import 'church_banner_cases.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class BannerPort extends FakePort {
  String? picked;
  bool failPick = false;
  @override
  Future<String?> pickChurchBanner() async {
    if (failPick)
      throw PlatformException(code: 'IMAGE', message: 'Image too large');
    return picked;
  }

  // The profile page now picks a photo and crops it in the app.
  @override
  Future<String?> pickChurchPhoto() => pickChurchBanner();
}

void main() {
  for (final e in revision08Cases.entries) {
    test(e.key, e.value);
  }
  setUpAll(loadAppFonts);
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) =>
      setScreen(t, value);

  Future<AppController> setup(FakePort port) async {
    port.at = epoch;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    return c;
  }

  Future<void> profile(WidgetTester t) async {
    await t.tap(find.byType(NavigationDestination).at(3));
    await t.pumpAndSettle();
    await t.tap(find.text('Church profile'));
    await t.pumpAndSettle();
  }

  Future<void> settleBanner(WidgetTester t) async {
    await t.pump();
    final picture = find.descendant(
      of: find.byType(ChurchProfileBanner),
      matching: find.byType(Image),
    );
    if (picture.evaluate().isNotEmpty) {
      final image = t.widget<Image>(picture);
      final context = t.element(picture);
      await t.runAsync(() => precacheImage(image.image, context));
    }
    await t.pumpAndSettle();
    if (picture.evaluate().isNotEmpty) {
      final pixels = find.descendant(
        of: find.byType(ChurchProfileBanner),
        matching: find.byType(RawImage),
      );
      expect(t.widget<RawImage>(pixels).image, isNotNull);
    }
  }

  Future<void> pick(WidgetTester t) async {
    // Image codecs complete outside the fake widget-test clock.
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('choose-church-banner')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    // The photo opens in the 3:1 crop; use it as framed.
    final use = find.byKey(const ValueKey('use-cropped-image'));
    if (use.evaluate().isNotEmpty) {
      await t.runAsync(() async {
        await t.tap(use);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
    }
    await settleBanner(t);
  }

  Future<void> saveProfile(WidgetTester t) async {
    await t.ensureVisible(find.text('Save church profile'));
    await t.runAsync(() async {
      await t.tap(find.text('Save church profile'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pumpAndSettle();
  }

  Future<void> editor(WidgetTester t) async {
    await t.tap(find.byType(NavigationDestination).at(1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('template-row:Sunday Service')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Edit Program'));
    await t.tap(find.text('Edit Program'));
    await t.pumpAndSettle();
  }

  Future<void> changeWarning(WidgetTester t, String seconds) async {
    await t.scrollUntilVisible(
      find.byType(WarningSettingsPanel),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final edit = find.byKey(const ValueKey('warning-rule-0'));
    await t.scrollUntilVisible(
      edit.hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(edit.hitTestable());
    await t.pumpAndSettle();
    expect(find.byType(WarningEditor), findsOneWidget);
    await t.tap(find.text('Remaining time'));
    await t.pumpAndSettle();
    for (final entry in {0: '0', 1: seconds}.entries) {
      await t.tapAt(t.getCenter(find.byType(CupertinoPicker).at(entry.key)));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), entry.value);
      await t.tap(find.text('Use value'));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Use 00:$seconds'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save warning'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Shared warning edits update templates and loaded services after restart',
    (t) async {
      size(t);
      final port = FakePort();
      final c = await setup(port);
      await c.act('load', value: c.state.templates.first);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(3));
      await t.pumpAndSettle();
      await t.tap(find.text('Warnings & alerts'));
      await t.pumpAndSettle();
      await changeWarning(t, '43');
      expect(
        c.state.templates.every(
          (v) => v.display.warnings.any((w) => w.seconds == 43),
        ),
        true,
      );
      expect(c.state.session.timeline!.display.warnings.first.seconds, 43);
      await t.ensureVisible(find.byType(WarningSettingsPanel));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/warnings-settings-phone.png'),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = await setup(port);
      expect(restored.state.defaults.warnings.first.seconds, 43);
      restored.dispose();
    },
  );
  testWidgets(
    'Display settings is compact and has no warning editor or Editing selector',
    (t) async {
      size(t);
      final c = await setup(FakePort());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(3));
      await t.pumpAndSettle();
      await t.tap(find.text('Display settings'));
      await t.pumpAndSettle();
      expect(find.text('Editing'), findsNothing);
      expect(find.byType(WarningSettingsPanel), findsNothing);
      expect(find.text('Default end screen'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/display-settings-phone.png'),
      );
      await t.pageBack();
      await t.pumpAndSettle();
      await editor(t);
      expect(find.byType(WarningSettingsPanel), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Church banner previews, cancels, saves and restores across restart',
    (t) async {
      size(t);
      final port = BannerPort()..picked = bannerFixture();
      final c = await setup(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await profile(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/church-profile-default-phone.png'),
      );
      expect(
        t.getSize(find.byType(ChurchProfileBanner)).aspectRatio,
        closeTo(3, 0.001),
      );
      await pick(t);
      // The picked photo is cropped to 3:1 in the app and saved as a fresh
      // 600 × 200 PNG, so it is a valid banner but not the same bytes.
      final cropped = t
          .widget<ChurchProfileBanner>(find.byType(ChurchProfileBanner))
          .image;
      expect(cropped, isNotEmpty);
      expect(churchBannerValue(cropped), cropped);
      expect(c.state.churchBanner, '');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(c.state.churchBanner, '');
      await t.tap(find.text('Church profile'));
      await t.pumpAndSettle();
      await pick(t);
      await t.enterText(find.byType(TextField), 'Grace Chapel');
      t.testTextInput.hide();
      await settleBanner(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/church-profile-custom-phone.png'),
      );
      await saveProfile(t);
      // Cropped in the app, so a fresh 600 × 200 PNG, not the same bytes.
      expect(churchBannerValue(c.state.churchBanner), isNotEmpty);
      expect(c.state.churchName, 'Grace Chapel');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final saved = c.state.churchBanner;
      final restored = await setup(port);
      expect(restored.state.churchBanner, saved);
      restored.dispose();
    },
  );
  testWidgets(
    'Cancelled and failed image picks retain the preview and built-in reset waits for Save',
    (t) async {
      size(t);
      final port = BannerPort();
      final c = await setup(port);
      await t.runAsync(
        () => c.commit((a, _) => a.churchBanner = bannerFixture()),
      );
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await profile(t);
      await pick(t);
      expect(
        churchBannerValue(
          t.widget<ChurchProfileBanner>(find.byType(ChurchProfileBanner)).image,
        ),
        isNotEmpty,
      );
      port.failPick = true;
      await pick(t);
      expect(find.textContaining('Could not use this photo'), findsOneWidget);
      // Cropped in the app, so a fresh 600 × 200 PNG, not the same bytes.
      expect(churchBannerValue(c.state.churchBanner), isNotEmpty);
      await t.tap(find.text('Use built-in banner'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('built-in-church-banner')),
        findsOneWidget,
      );
      // Cropped in the app, so a fresh 600 × 200 PNG, not the same bytes.
      expect(churchBannerValue(c.state.churchBanner), isNotEmpty);
      await saveProfile(t);
      expect(c.state.churchBanner, '');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Failed profile save leaves committed data intact and a retry saves the chosen banner',
    (t) async {
      size(t);
      final port = BannerPort()..picked = bannerFixture();
      final c = await setup(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await profile(t);
      await pick(t);
      port.fail = true;
      await saveProfile(t);
      expect(c.state.churchBanner, '');
      expect(find.byType(ChurchProfilePage), findsOneWidget);
      port.fail = false;
      await saveProfile(t);
      // Cropped in the app, so a fresh 600 × 200 PNG, not the same bytes.
      expect(churchBannerValue(c.state.churchBanner), isNotEmpty);
      expect(find.byType(ChurchProfilePage), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'Banner backup restore is atomic and corrupt pixel streams are rejected',
    () async {
      final port = BannerPort();
      final c = await setup(port);
      final restored = importBackup(
        exportBackup(
          AppState.fresh(epoch)..churchBanner = bannerFixture(),
          epoch,
        ),
        epoch,
      );
      port.fail = true;
      expect(await c.restoreBackup(restored), false);
      expect(c.state.churchBanner, '');
      port.fail = false;
      expect(await c.retry!(), true);
      // Cropped in the app, so a fresh 600 × 200 PNG, not the same bytes.
      expect(churchBannerValue(c.state.churchBanner), isNotEmpty);
      final broken = base64Encode(base64Decode(bannerFixture()).sublist(0, 33));
      expect(await c.commit((a, _) => a.churchBanner = broken), false);
      // Cropped in the app, so a fresh 600 × 200 PNG, not the same bytes.
      expect(churchBannerValue(c.state.churchBanner), isNotEmpty);
      c.dispose();
    },
  );
  testWidgets(
    'Compact Reports retains filter, timing outcomes, rehearsal badges and detail navigation',
    (t) async {
      size(t);
      final c = await setup(FakePort());
      await c.commit((a, _) => a.reports = reportFixtures());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(2));
      await t.pumpAndSettle();
      expect(find.byType(ReportListRow), findsNWidgets(3));
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.textContaining('Rehearsal 10×'), findsOneWidget);
      // The row's outcome chip; the summary tile above may say the same.
      expect(
        find.descendant(
          of: find.byType(ReportListRow),
          matching: find.text('1 min over'),
        ),
        findsOneWidget,
      );
      expect(find.text('4 min under'), findsOneWidget);
      await t.tap(find.text('Rehearsals'));
      await t.pumpAndSettle();
      expect(find.byType(ReportListRow), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('open-report-rehearsal')));
      await t.pumpAndSettle();
      expect(find.byType(ReportDetailPage), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('report-actions')));
      await t.pumpAndSettle();
      expect(find.text('Delete report'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Compact Settings, Reports and banner profile support narrow enlarged text',
    (t) async {
      size(t, const Size(320, 1000));
      final c = await setup(FakePort());
      await c.commit((a, _) => a.reports = reportFixtures());
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme('midnight_lime'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Home(controller: c),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(3));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.text('Church profile'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save church profile'));
      expect(t.takeException(), isNull);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(2));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('open-report-sunday')));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
