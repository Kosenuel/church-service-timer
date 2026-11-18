import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/hardware/w2_program.dart';
import '../support/fake_port.dart';

void main() {
  test(
    'Restoring a portable backup preserves the receiving device layout',
    () async {
      final c = AppController(FakePort());
      addTearDown(c.dispose);
      await c.initialize(startTicker: false);
      const local = AppearancePreferences(
        density: 'spacious',
        dividers: 'hidden',
        reducedMotion: true,
      );
      await c.commit((draft, _) => draft.appearance = local);
      final incoming = AppState.fresh(start)..clockBlink = false;
      expect(
        await c.restoreBackup(
          importBackup(exportBackup(incoming, start), start),
        ),
        isTrue,
      );
      expect(c.state.appearance, local);
      expect(c.state.clockBlink, isFalse);
    },
  );
  test(
    'Old state migrates to compact, subtle, blinking without changing service timing',
    () {
      final old = AppState.fresh(start).toJson()
        ..['version'] = 12
        ..remove('appearance')
        ..remove('clockBlink');
      (old['session'] as Map).remove('clockBlink');
      final state = AppState.fromJson(old);
      expect(state.appearance, const AppearancePreferences());
      expect(state.clockBlink, isTrue);
      expect(state.session.clockBlink, isTrue);
      expect(state.session.phase, 'idle');
    },
  );
  test(
    'All appearance choices persist and invalid imported preferences are rejected',
    () {
      for (final mode in ['compact', 'comfortable', 'spacious', 'automatic']) {
        final a = AppState.fresh(start)
          ..appearance = AppearancePreferences(
            density: mode,
            dividers: 'strong',
            highContrast: true,
            reducedMotion: true,
          )
          ..clockBlink = false;
        final copy = AppState.fromJson(jsonDecode(jsonEncode(a.toJson())));
        expect(copy.appearance, a.appearance);
        expect(copy.session.clockBlink, isFalse);
      }
      for (final bad in [
        {'density': 'tiny'},
        {'dividers': 'bright'},
        {'highContrast': 1},
        {'reducedMotion': 'true'},
      ]) {
        expect(
          () => AppearancePreferences.fromJson(bad),
          throwsA(isA<RuleError>()),
        );
      }
    },
  );
  test(
    'Portable backups exclude local layout choices but include clock behavior',
    () {
      final a = AppState.fresh(start)
        ..appearance = const AppearancePreferences(
          density: 'spacious',
          highContrast: true,
        )
        ..clockBlink = false;
      final raw = exportBackup(a, start);
      expect(jsonDecode(raw)['data'].containsKey('appearance'), isFalse);
      final restored = importBackup(raw, start);
      expect(restored.appearance, const AppearancePreferences());
      expect(restored.clockBlink, isFalse);
    },
  );
  test('Automatic density follows window space, manual mode stays fixed', () {
    const auto = AppearancePreferences(density: 'automatic');
    expect(
      AppLayout.resolve(auto, const Size(430, 960)).density,
      'comfortable',
    );
    expect(
      AppLayout.resolve(auto, const Size(960, 430)).density,
      'comfortable',
    );
    expect(
      AppLayout.resolve(auto, const Size(800, 1100)).density,
      'comfortable',
    );
    // A desktop layout packs the window, so it stays Comfortable; the
    // Classic single column still opens out.
    expect(
      AppLayout.resolve(auto, const Size(1280, 800)).density,
      'comfortable',
    );
    expect(
      AppLayout.resolve(
        const AppearancePreferences(desktopLayout: 'classic'),
        const Size(1280, 800),
      ).density,
      'spacious',
    );
    expect(
      AppLayout.resolve(
        const AppearancePreferences(density: 'spacious'),
        const Size(320, 640),
      ).density,
      'spacious',
    );
  });
  test(
    'Density increases spacing and targets without shrinking typography',
    () {
      final layouts = [
        for (final mode in ['compact', 'comfortable', 'spacious'])
          AppLayout.resolve(
            AppearancePreferences(density: mode),
            const Size(430, 900),
          ),
      ];
      expect(layouts.every((l) => l.controlHeight >= 48), isTrue);
      expect(layouts[0].rowPadding, lessThan(layouts[1].rowPadding));
      expect(layouts[1].rowPadding, lessThan(layouts[2].rowPadding));
      for (final mode in ['compact', 'comfortable', 'spacious']) {
        expect(
          appTheme(
            'royal_navy',
            appearance: AppearancePreferences(density: mode),
          ).textTheme.bodyMedium!.fontSize,
          15,
        );
      }
    },
  );
  test('High contrast strengthens text and borders in every preset theme', () {
    for (final palette in appPalettes) {
      final theme = appTheme(
        palette.id,
        appearance: const AppearancePreferences(highContrast: true),
      );
      final p = theme.extension<AppPalette>()!;
      expect(
        contrast(p.text, p.surface),
        greaterThanOrEqualTo(7),
        reason: palette.id,
      );
      expect(
        contrast(p.muted, p.surface),
        greaterThanOrEqualTo(7),
        reason: palette.id,
      );
      expect(
        contrast(p.accent, p.surface),
        greaterThanOrEqualTo(7),
        reason: palette.id,
      );
      expect(
        contrast(p.border, p.surface),
        greaterThan(contrast(palette.border, palette.surface)),
      );
    }
  });
  test(
    'Simulator blinks only colon pixels in each format; native preview remains steady',
    () {
      for (final format in ['12h', '24h']) {
        final session = running()
          ..showClock = true
          ..clockFormat = format;
        final sim = Simulator();
        sim.update(session, start);
        final on = [...sim.pixels];
        sim.update(
          session,
          Stamp(start.mono + 500, start.wall + 500, start.boot),
        );
        final off = [...sim.pixels];
        expect(on, isNot(off));
        final left = format == '12h' ? 8 : 13, width = format == '12h' ? 4 : 6;
        for (var i = 0; i < 512; i++) {
          if (i % 32 < left || i % 32 >= left + width) expect(off[i], on[i]);
        }
        expect(
          W2Program.clockPixels(
            DateTime.fromMillisecondsSinceEpoch(start.wall + 500),
            format12Hour: format == '12h',
          ),
          on,
        );
        session.clockBlink = false;
        sim.update(
          session,
          Stamp(start.mono + 500, start.wall + 500, start.boot),
        );
        expect(sim.pixels, on);
        expect(session.balance(start), 600000);
      }
    },
  );
  test(
    'Preview preferences are cancellable, saving persists, paired snapshot excludes them',
    () async {
      final port = FakePort(), c = AppController(FakePort());
      addTearDown(c.dispose);
      await c.initialize(startTicker: false);
      c.previewAppearance(const AppearancePreferences(density: 'spacious'));
      expect(c.appearanceSelection.value.density, 'spacious');
      expect(c.state.appearance.density, 'automatic');
      c.previewAppearance(null);
      expect(c.appearanceSelection.value.density, 'automatic');
      expect(
        await c.commit(
          (draft, _) => draft.appearance = const AppearancePreferences(
            density: 'comfortable',
          ),
        ),
        isTrue,
      );
      expect(c.appearanceSelection.value.density, 'comfortable');
      expect(c.pairedSnapshot(true).containsKey('appearance'), isFalse);
      expect(c.pairedSnapshot(false)['clockBlink'], isTrue);
      port.data = jsonEncode(c.state.toJson());
      final restarted = AppController(port);
      addTearDown(restarted.dispose);
      await restarted.initialize(startTicker: false);
      expect(restarted.appearanceSelection.value.density, 'comfortable');
    },
  );
}
