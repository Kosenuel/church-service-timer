import 'dart:convert';
import 'package:church_service_timer/domain.dart';
import 'feature_cases.dart' show epoch, at, service, equal, rejects;

final revision07Cases = <String, void Function()>{
  'Version 6 migration keeps saved content and uses optional profile defaults':
      () {
        final old = AppState.fresh(epoch).toJson()..['version'] = 6;
        old.remove('churchName');
        old.remove('themeId');
        old.remove('keepScreenAwake');
        final a = AppState.fromJson(old);
        equal(a.churchName, '');
        equal(a.themeId, 'midnight_lime');
        equal(a.keepScreenAwake, true);
        equal(a.templates.map((t) => t.toJson()).toList(), old['templates']);
        equal(a.stageCues.map((t) => t.toJson()).toList(), old['stageCues']);
        equal(a.toJson()['version'], 10);
      },
  'Church and appearance preferences survive state round trip': () {
    for (final theme in themeIds) {
      final a = AppState.fresh(epoch)
        ..churchName = 'Grace & Hope Church'
        ..themeId = theme
        ..keepScreenAwake = false;
      final b = AppState.fromJson(jsonDecode(jsonEncode(a.toJson())) as Json);
      equal(b.churchName, a.churchName);
      equal(b.themeId, theme);
      equal(b.keepScreenAwake, false);
    }
  },
  'Church names support Unicode, optional blanks and reject control characters':
      () {
        equal(churchNameValue('  Église de Grâce  '), 'Église de Grâce');
        equal(churchNameValue('  '), '');
        rejects(() => churchNameValue('a\nb'));
        rejects(() => churchNameValue('a' * 81));
        rejects(() => churchNameValue(23));
        rejects(() => themeIdValue('unknown'));
        rejects(() => boolSetting('yes'));
      },
  'Report church snapshot survives transitions and old records stay unbranded':
      () {
        var s = service()..churchName = 'First Church';
        s = Session.fromJson(s.toJson());
        s = transition(s, 'end', at(60));
        final r = ServiceReport.fromSession(s, at(60));
        equal(r.churchName, 'First Church');
        equal(ServiceReport.fromJson(r.toJson()).churchName, 'First Church');
        final legacy = r.toJson()..remove('churchName');
        equal(ServiceReport.fromJson(legacy).churchName, '');
      },
  'Report CSV church column is escaped and formula-safe in single and bulk exports':
      () {
        final s = transition(service(), 'end', at(15))
          ..churchName = '=Grace, "Church"';
        final r = ServiceReport.fromSession(s, at(15));
        for (final csv in [
          exportReportCsv(r),
          exportReportsCsv([r]),
        ]) {
          final rows = parseCsv(csv);
          equal(rows.first.last, 'Church');
          equal(rows[1].last, "'=Grace, \"Church\"");
          equal(rows.every((row) => row.length == rows.first.length), true);
        }
        equal(jsonDecode(exportReportJson(r))['churchName'], s.churchName);
        equal(
          jsonDecode(exportReportsJson([r]))['reports'][0]['churchName'],
          s.churchName,
        );
      },
  'Full backup round trip preserves saved setup but excludes active clock': () {
    final a = AppState.fresh(epoch)
      ..churchName = 'Grace Church'
      ..themeId = 'warm_ivory'
      ..keepScreenAwake = false
      ..groupTemplates = true
      ..pixelShape = 'circular';
    a.defaults = a.defaults.withZero(const TextLayout('FINISH', bold: true));
    a.stageCues = [
      const TextLayout(
        'WRAP UP',
        italic: true,
        bold: true,
        speed: 12,
        font: 'cuekeeper_sq_matrix',
      ),
    ];
    a.session = service()..churchName = a.churchName;
    a.reports.add(
      ServiceReport.fromSession(transition(a.session, 'end', at(9)), at(9)),
    );
    a.applySharedZero();
    final raw = exportBackup(a, at(20));
    equal((jsonDecode(raw)['data'] as Map).containsKey('session'), false);
    final b = importBackup(raw, at(30));
    final expected = a.toJson()..remove('session');
    final actual = b.toJson()..remove('session');
    equal(actual, expected);
    equal(b.session.phase, 'idle');
    equal(b.session.intended(at(30)), null);
  },
  'Malformed, missing and unsupported backup data is rejected': () {
    rejects(() => importBackup('not json', epoch));
    final raw = exportBackup(AppState.fresh(epoch), epoch);
    for (final key in [
      'templates',
      'defaults',
      'reports',
      'stageCues',
      'churchName',
      'themeId',
      'keepScreenAwake',
      'groupTemplates',
      'pixelShape',
    ]) {
      final j = jsonDecode(raw) as Json;
      (j['data'] as Map).remove(key);
      rejects(() => importBackup(jsonEncode(j), epoch));
    }
    final j = jsonDecode(raw) as Json;
    j['schemaVersion'] = 99;
    rejects(() => importBackup(jsonEncode(j), epoch));
    j['schemaVersion'] = 1;
    j['data']['themeId'] = 'missing';
    rejects(() => importBackup(jsonEncode(j), epoch));
  },
  'Backups reject duplicate templates, report IDs and invalid metrics': () {
    final a = AppState.fresh(epoch);
    final r = ServiceReport.fromSession(
      transition(service(), 'end', at(9)),
      at(9),
    );
    a.reports.add(r);
    final raw = exportBackup(a, epoch);
    final duplicate = jsonDecode(raw) as Json;
    (duplicate['data']['reports'] as List).add(r.toJson());
    rejects(() => importBackup(jsonEncode(duplicate), epoch));
    final invalid = jsonDecode(raw) as Json;
    invalid['data']['reports'][0]['rows'][0]['actualMs'] = -1;
    rejects(() => importBackup(jsonEncode(invalid), epoch));
    final badDate = jsonDecode(raw) as Json;
    badDate['data']['reports'][0]['endedWall'] = 8640000000000001;
    rejects(() => importBackup(jsonEncode(badDate), epoch));
    final templates = jsonDecode(raw) as Json;
    (templates['data']['templates'] as List).add(a.templates.first.toJson());
    rejects(() => importBackup(jsonEncode(templates), epoch));
  },
  'Backup size limit applies before parsing': () {
    rejects(() => importBackup('x' * (backupLimitBytes + 1), epoch));
  },
};
