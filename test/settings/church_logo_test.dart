import 'dart:convert';
import 'dart:ui' as ui;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'church_banner_cases.dart' show bannerFixture;

class PhotoPort extends FakePort {
  String? photo;
  @override
  Future<String?> pickChurchPhoto() async => photo;
}

/// A [width] × [height] PNG: left half red, right half blue.
Future<String> testPhoto(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xffcc0000),
  );
  canvas.drawRect(
    Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    Paint()..color = const Color(0xff0000cc),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return base64Encode(data!.buffer.asUint8List());
}

/// Taps [key] where image decoding and encoding, which run outside the
/// test clock, can finish, then settles the UI.
Future<void> tapAndWait(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
  await t.runAsync(() async {
    await t.tap(find.byKey(ValueKey(key)));
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'The header logo opens Church profile, where a photo is cropped square and becomes the logo',
    (t) async {
      setScreen(t, const Size(430, 1000));
      final port = PhotoPort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      port.photo = await t.runAsync(() => testPhoto(800, 400));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('church-logo-image')), findsNothing);

      await t.tap(find.byKey(const ValueKey('header-logo')));
      await t.pumpAndSettle();
      expect(find.text('Church profile'), findsWidgets);
      expect(find.text('Logo'), findsOneWidget);

      await tapAndWait(t, 'choose-church-logo');
      expect(find.text('Crop logo'), findsOneWidget);
      final frame = t.getSize(find.byKey(const ValueKey('image-crop-frame')));
      expect(frame.width, closeTo(frame.height, .01));

      await tapAndWait(t, 'use-cropped-image');
      expect(find.text('Crop logo'), findsNothing);
      expect(find.text('Change logo'), findsOneWidget);

      await tapAndWait(t, 'save-church-profile');
      expect(c.state.churchLogo, isNotEmpty);
      expect(churchLogoValue(c.state.churchLogo), c.state.churchLogo);
      expect(find.byKey(const ValueKey('church-logo-image')), findsOneWidget);

      // Saved state survives a round trip, and the built-in mark returns.
      expect(
        AppState.fromJson(c.state.toJson()).churchLogo,
        c.state.churchLogo,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A photo much larger than the frame crops to what the frame shows',
    (t) async {
      // A phone photo is far larger than the frame, so the crop starts
      // zoomed well below 1. The saved logo must be the centred square,
      // not a small top-left corner.
      setScreen(t, const Size(430, 1000));
      final port = PhotoPort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      port.photo = await t.runAsync(() => testPhoto(1600, 800));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('header-logo')));
      await t.pumpAndSettle();
      await tapAndWait(t, 'choose-church-logo');
      await tapAndWait(t, 'use-cropped-image');
      await tapAndWait(t, 'save-church-profile');
      final colours = await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          base64Decode(c.state.churchLogo),
        );
        final image = (await codec.getNextFrame()).image;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        Color at(double x) {
          final i =
              ((image.height ~/ 2) * image.width + (image.width * x).toInt()) *
              4;
          return Color.fromARGB(
            255,
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          );
        }

        return [at(.1), at(.4), at(.6), at(.9)];
      });
      // The centre square of a red | blue photo is half red, half blue.
      expect(colours![0], const Color(0xffcc0000));
      expect(colours[1], const Color(0xffcc0000));
      expect(colours[2], const Color(0xff0000cc));
      expect(colours[3], const Color(0xff0000cc));
      await t.pumpWidget(const SizedBox());
    },
  );

  test('A church logo must be a square 256 px PNG', () async {
    expect(churchLogoValue(''), '');
    expect(() => churchLogoValue('not base64!'), throwsA(isA<RuleError>()));
  });

  testWidgets(
    'A church logo travels in backups as version 10; without one the version is unchanged',
    (t) async {
      final logo = await t.runAsync(() async {
        // A real 256 × 256 PNG, as the crop produces.
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 256, 256),
          Paint()..color = const Color(0xff336699),
        );
        final image = await recorder.endRecording().toImage(256, 256);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return base64Encode(data!.buffer.asUint8List());
      });
      const now = Stamp(1, 1, 'boot');
      final plain = AppState.fresh(now);
      final withLogo = AppState.fresh(now)..churchLogo = logo!;

      final plainBackup = jsonDecode(exportBackup(plain, now)) as Map;
      expect(plainBackup['schemaVersion'], lessThan(10));
      expect((plainBackup['data'] as Map).containsKey('churchLogo'), isFalse);
      expect(importBackup(exportBackup(plain, now), now).churchLogo, '');

      final raw = exportBackup(withLogo, now);
      expect((jsonDecode(raw) as Map)['schemaVersion'], 10);
      expect(importBackup(raw, now).churchLogo, logo);

      // A wrong-size image is refused.
      expect(() => churchLogoValue(bannerFixture()), throwsA(isA<RuleError>()));
    },
  );
}
