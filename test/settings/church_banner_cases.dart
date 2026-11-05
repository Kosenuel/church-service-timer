import 'dart:convert';
import 'dart:io';
import 'package:church_service_timer/domain/domain.dart';
import '../domain/feature_cases.dart' show epoch, equal, rejects;

String bannerFixture() =>
    base64Encode(File('test/fixtures/church-banner.png').readAsBytesSync());

final revision08Cases = <String, void Function()>{
  'Version 7 upgrades with built-in banner without changing saved content': () {
    final old = AppState.fresh(epoch).toJson()..['version'] = 7;
    old.remove('churchBanner');
    final state = AppState.fromJson(old);
    equal(state.churchBanner, '');
    equal(state.toJson()['version'], 13);
    equal(state.templates.map((t) => t.toJson()).toList(), old['templates']);
  },
  'Banner survives saved-state and portable-backup round trips': () {
    final state = AppState.fresh(epoch)..churchBanner = bannerFixture();
    equal(AppState.fromJson(state.toJson()).churchBanner, state.churchBanner);
    final raw = exportBackup(state, epoch);
    equal(jsonDecode(raw)['schemaVersion'], 7);
    equal(importBackup(raw, epoch).churchBanner, state.churchBanner);
  },
  'Older schema 1 backups restore using the built-in banner': () {
    final raw = jsonDecode(exportBackup(AppState.fresh(epoch), epoch)) as Json;
    raw['schemaVersion'] = 1;
    (raw['data'] as Map).remove('churchBanner');
    (raw['data'] as Map).remove('quickMessages');
    (raw['data'] as Map).remove('notificationClearSeconds');
    (raw['data'] as Map).remove('printPreferences');
    (raw['data'] as Map).remove('clockFormat');
    (raw['data'] as Map).remove('clockBlink');
    equal(importBackup(jsonEncode(raw), epoch).churchBanner, '');
  },
  'Schema 2 rejects missing or malformed banners': () {
    final raw = jsonDecode(exportBackup(AppState.fresh(epoch), epoch)) as Json;
    (raw['data'] as Map).remove('churchBanner');
    rejects(() => importBackup(jsonEncode(raw), epoch));
    raw['data']['churchBanner'] = 'bad image';
    rejects(() => importBackup(jsonEncode(raw), epoch));
  },
  'Banner guards reject invalid types, oversized data and wrong dimensions':
      () {
        equal(churchBannerValue(''), '');
        equal(churchBannerValue(bannerFixture()), bannerFixture());
        rejects(() => churchBannerValue(4));
        rejects(() => churchBannerValue('a' * 666669));
        rejects(() => churchBannerValue('not base64'));
        final bytes = base64Decode(bannerFixture())..[19] = 1;
        rejects(() => churchBannerValue(base64Encode(bytes)));
        rejects(() => churchBannerValue(base64Encode([0, 1, 2])));
      },
  'Template warning overrides are normalized to shared settings': () {
    final state = AppState.fresh(epoch);
    final before = state.defaults.toJson();
    final other = state.templates.last.toJson();
    final warning = WarningRule(
      42,
      const TextLayout(
        'FINISH',
        bold: true,
        italic: true,
        effect: 'scroll',
        speed: 12,
        height: 2,
        font: 'cuekeeper_sq_matrix',
      ),
      destination: 'stage',
    );
    state.saveTemplate(
      state.templates.first.withDisplay(
        state.templates.first.display.withWarnings([warning]),
      ),
      replacing: 0,
    );
    final restored = AppState.fromJson(state.toJson());
    equal(
      restored.templates.first.display.warnings.map((w) => w.toJson()).toList(),
      state.defaults.warnings.map((w) => w.toJson()).toList(),
    );
    equal(restored.defaults.toJson(), before);
    equal(restored.templates.last.toJson(), other);
  },
  'New templates inherit current defaults but existing templates retain their settings':
      () {
        final state = AppState.fresh(epoch);
        final before = state.templates.first.toJson();
        state.defaults = state.defaults
            .withWarnings(const [WarningRule(25, TextLayout('READY'))])
            .withEnd(const TextLayout('AMEN'));
        state.saveTemplate(
          Timeline('New service', const [
            Segment('Welcome', 2),
          ], state.defaults),
        );
        equal(state.templates.last.display.toJson(), state.defaults.toJson());
        equal(state.templates.first.toJson(), before);
      },
};
