import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app_theme.dart';
import 'package:church_service_timer/church_banner.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/main.dart';
import 'domain_test.dart' show FakePort;
import 'feature_cases.dart' show epoch;
import 'revision_04_cases.dart' show reportFixtures;
import 'revision_08_cases.dart';

class BannerPort extends FakePort {
  String? picked;
  bool failPick = false;
  @override
  Future<String?> pickChurchBanner() async {
    if (failPick)
      throw PlatformException(code: 'IMAGE', message: 'Image too large');
    return picked;
  }
}

void main() {
  for (final e in revision08Cases.entries) {
    test(e.key, e.value);
  }
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

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
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
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
    final edit = find
        .descendant(
          of: find.byType(WarningSettingsPanel),
          matching: find.byType(ListTile),
        )
        .first;
    await t.scrollUntilVisible(
      edit.hitTestable(),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(edit.hitTestable());
    await t.pumpAndSettle();
    expect(find.byType(WarningEditor), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Minutes'), '0');
    await t.enterText(find.widgetWithText(TextField, 'Seconds'), seconds);
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
        matchesGoldenFile('goldens/warnings-settings-phone.png'),
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
        matchesGoldenFile('goldens/display-settings-phone.png'),
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
        matchesGoldenFile('goldens/church-profile-default-phone.png'),
      );
      expect(
        t.getSize(find.byType(ChurchProfileBanner)).aspectRatio,
        closeTo(3, 0.001),
      );
      await pick(t);
      expect(
        t.widget<ChurchProfileBanner>(find.byType(ChurchProfileBanner)).image,
        port.picked,
      );
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
        matchesGoldenFile('goldens/church-profile-custom-phone.png'),
      );
      await saveProfile(t);
      expect(c.state.churchBanner, bannerFixture());
      expect(c.state.churchName, 'Grace Chapel');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = await setup(port);
      expect(restored.state.churchBanner, bannerFixture());
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
        t.widget<ChurchProfileBanner>(find.byType(ChurchProfileBanner)).image,
        bannerFixture(),
      );
      port.failPick = true;
      await pick(t);
      expect(find.textContaining('Could not use this image'), findsOneWidget);
      expect(c.state.churchBanner, bannerFixture());
      await t.tap(find.text('Use built-in banner'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('built-in-church-banner')),
        findsOneWidget,
      );
      expect(c.state.churchBanner, bannerFixture());
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
      expect(c.state.churchBanner, bannerFixture());
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
      expect(c.state.churchBanner, bannerFixture());
      final broken = base64Encode(base64Decode(bannerFixture()).sublist(0, 33));
      expect(await c.commit((a, _) => a.churchBanner = broken), false);
      expect(c.state.churchBanner, bannerFixture());
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
      expect(find.text('Rehearsal 10×'), findsOneWidget);
      expect(find.text('1m 0s behind'), findsOneWidget);
      expect(find.text('4m 0s ahead'), findsOneWidget);
      await t.tap(find.text('Rehearsals'));
      await t.pumpAndSettle();
      expect(find.byType(ReportListRow), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('open-report-rehearsal')));
      await t.pumpAndSettle();
      expect(find.byType(ReportDetailPage), findsOneWidget);
      await t.ensureVisible(find.text('Clear report'));
      expect(find.text('Clear report'), findsOneWidget);
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
