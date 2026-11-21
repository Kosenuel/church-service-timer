import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';
import '../domain/feature_cases.dart' show epoch, at, equal;

List<ServiceReport> reportFixtures() => [
  ServiceReport(
    'sunday',
    'Sunday Service',
    epoch.wall,
    at(3360).wall,
    3360000,
    1,
    false,
    const [
      ReportRow('Praise & Worship', 900000, 960000, 30000, 60000),
      ReportRow('Sermon', 1800000, 1800000, 0, 0),
      ReportRow('Closing', 600000, 600000, 0, 0),
    ],
  ),
  ServiceReport(
    'rehearsal',
    'Midweek Service',
    at(86400).wall,
    at(86526).wall,
    1260000,
    10,
    false,
    const [
      ReportRow('Welcome', 300000, 300000, 0, 0),
      ReportRow('Message', 1200000, 960000, 0, -120000),
    ],
  ),
  ServiceReport(
    'partial',
    'Prayer Meeting',
    at(172800).wall,
    at(173400).wall,
    600000,
    1,
    false,
    const [
      ReportRow('Prayer', 900000, 600000, 0, 0),
      ReportRow('Closing', 300000, null, 0, 0),
    ],
  ),
];

final revision04Cases = <String, void Function()>{
  'Fresh end screens match requested style and remain independently replaceable':
      () {
        final a = AppState.fresh(epoch);
        equal(a.defaults.zero, null);
        equal(
          a.defaults.end!.toJson(),
          const TextLayout(
            'Hallelujah',
            bold: true,
            italic: true,
            effect: 'scroll',
            align: 'center',
            speed: 12,
            height: 2,
          ).toJson(),
        );
        a.defaults = a.defaults.withEnd(const TextLayout('DEFAULT'));
        equal(a.templates.first.display.end!.text, 'Hallelujah');
        a.templates[0] = Timeline(
          'Sunday Service',
          a.templates.first.segments,
          a.templates.first.display.withEnd(const TextLayout('AMEN')),
        );
        equal(a.templates.last.display.end!.text, 'Hallelujah');
        equal(a.defaults.end!.text, 'DEFAULT');
      },
  '0.3 migration upgrades untouched ends, preserves custom and loaded ends, shares zero':
      () {
        final a = AppState.fresh(epoch);
        final old = DisplaySettings(
          end: const TextLayout('Hallelujah'),
          zero: const TextLayout('SHARED'),
        );
        a.defaults = old;
        a.templates[0] = Timeline(
          'Sunday',
          a.templates.first.segments,
          old.withZero(const TextLayout('OLD ZERO')),
        );
        a.templates[1] = Timeline(
          'Rehearsal',
          a.templates.last.segments,
          old.withEnd(const TextLayout('Hallelujah', speed: 20)),
        );
        a.session = transition(
          a.session,
          'load',
          epoch,
          value: a.templates.first,
        );
        final migrated = AppState.fromJson(a.toJson()..['version'] = 3);
        equal(migrated.defaults.end!.toJson(), defaultEndScreen.toJson());
        equal(
          migrated.templates.first.display.end!.toJson(),
          defaultEndScreen.toJson(),
        );
        equal(migrated.templates.last.display.end!.speed, 20);
        equal(
          migrated.session.timeline!.display.end!.toJson(),
          const TextLayout('Hallelujah').toJson(),
        );
        equal(migrated.session.timeline!.display.zero!.text, 'SHARED');
        equal(migrated.templates.first.display.zero!.text, 'SHARED');
        equal(AppState.fromJson(migrated.toJson()).toJson(), migrated.toJson());
      },
  'Shared zero survives prior-session restoration and does not change end ownership':
      () {
        final a = AppState.fresh(epoch);
        a.session = transition(
          a.session,
          'load',
          epoch,
          value: a.templates.first,
        );
        a.session = transition(a.session, 'start', epoch);
        a.session = transition(a.session, 'end', at(1));
        a.session = transition(
          a.session,
          'load',
          epoch,
          value: a.templates.last,
        );
        a.defaults = a.defaults.withZero(
          const TextLayout('FINISH', bold: true),
        );
        a.applySharedZero();
        equal(a.session.timeline!.display.zero!.text, 'FINISH');
        equal(a.session.prior!.timeline!.display.zero!.text, 'FINISH');
        equal(a.templates.every((t) => t.display.zero!.bold), true);
        a.defaults = a.defaults.withZero(null);
        a.applySharedZero();
        equal(a.session.prior!.timeline!.display.zero, null);
        equal(
          a.session.timeline!.display.end!.toJson(),
          defaultEndScreen.toJson(),
        );
      },
  'Portable import uses device shared zero while retaining the template end':
      () {
        final t = Timeline(
          'Imported',
          const [Segment('Talk', 3)],
          DisplaySettings(
            zero: const TextLayout('IGNORED'),
            end: const TextLayout('AMEN', italic: true),
          ),
        );
        final imported = importTemplate(
          exportJson(t),
          'service.json',
          DisplaySettings(zero: const TextLayout('GLOBAL')),
        );
        equal(imported.display.zero!.text, 'GLOBAL');
        equal(imported.display.end!.toJson(), t.display.end!.toJson());
        equal(
          importTemplate(
            exportJson(t),
            'service.json',
            DisplaySettings(),
          ).display.zero,
          null,
        );
      },
  'Bulk JSON keeps complete history, exact metrics, missing values and metadata':
      () {
        final records = reportFixtures();
        final j = jsonDecode(exportReportsJson(records));
        equal(j['type'], 'church-service-timer-reports');
        equal(j['recordCount'], 3);
        equal(j['reports'], records.map((r) => r.toJson()).toList());
        equal(jsonDecode(exportReportsJson([]))['reports'], []);
      },
  'Bulk CSV escapes multiline names, neutralizes formulas, and keeps null distinct from zero':
      () {
        final r = ServiceReport(
          'id',
          '=SUM(1,2)',
          null,
          epoch.wall,
          0,
          10,
          true,
          const [
            ReportRow('Talk, "one"\nnext', 60000, 0, 0, -1000),
            ReportRow('@UNSAFE', 60000, null, 0, 0),
          ],
        );
        final rows = parseCsv(exportReportsCsv([r]));
        equal(rows.length, 3);
        equal(rows.every((r) => r.length == 18), true);
        equal(rows[1][1], "'=SUM(1,2)");
        equal(rows[1][4], '');
        equal(
          rows[1][5],
          DateTime.fromMillisecondsSinceEpoch(
            epoch.wall,
            isUtc: true,
          ).toIso8601String(),
        );
        equal(rows[1][10], 'Talk, "one"\nnext');
        equal(rows[1][12], '0.000');
        equal(rows[1][15], '-1.000');
        equal(rows[2][10], "'@UNSAFE");
        equal(rows[2][12], '');
        equal(rows[2][16], 'Not recorded');
      },
  'Bulk CSV includes all segments and retains a record without segments': () {
    final records = [
      ...reportFixtures(),
      ServiceReport('empty', 'Legacy', null, epoch.wall, null, 1, true, []),
    ];
    final rows = parseCsv(exportReportsCsv(records));
    equal(rows.length, 9);
    equal(rows.map((r) => r.length).toSet().toList(), [18]);
    equal(rows.last[16], 'No segment records');
    equal(rows.last.last, '');
    equal(rows.skip(1).map((r) => r[0]).toSet().length, 4);
  },
  'Report summary excludes partial and uncertain records from outcome comparisons':
      () {
        final records = reportFixtures();
        records.add(
          ServiceReport(
            'uncertain',
            'Recovered',
            epoch.wall,
            at(2).wall,
            120000,
            1,
            true,
            const [ReportRow('Talk', 60000, 120000, 0, 0)],
          ),
        );
        records.add(
          ServiceReport(
            'ontime',
            'On time',
            epoch.wall,
            at(60).wall,
            60000,
            1,
            false,
            const [ReportRow('Talk', 60000, 60000, 0, 0)],
          ),
        );
        final s = ReportSummary(records);
        equal(s.comparable.length, 3);
        equal([s.ahead, s.onTime, s.behind], [1, 1, 1]);
        equal(s.averageVarianceMs, -60000);
        equal(s.recordedMs, 5400000);
        equal(records.first.pausedMs, 30000);
        equal(records[1].adjustmentMs, -120000);
      },
  'Empty or unrecorded history has no invented averages': () {
    equal(ReportSummary([]).averageVarianceMs, null);
    final s = ReportSummary([
      ServiceReport('none', 'Old', null, epoch.wall, null, 1, true, []),
    ]);
    equal(s.averageVarianceMs, null);
    equal(s.timedCount, 0);
    equal(s.recordedMs, 0);
  },
};
