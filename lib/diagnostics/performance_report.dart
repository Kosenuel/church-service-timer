import 'dart:math' as math;

import 'package:church_service_timer/diagnostics/service_metrics.dart';

/// Pass marks for a recording. scripts/perf_report.py uses the same values
/// (a test keeps them in step) and docs/PERFORMANCE-REVIEW.md explains them.
abstract final class PerformanceTargets {
  /// Frames drawn within 16.7 ms.
  static const smoothPct = 90.0;

  /// Memory growth after the first 10 minutes.
  static const memoryGrowthMbPerHour = 10.0;

  /// Timer against the phone clock over the whole run.
  static const driftSeconds = 1.0;

  /// Latest warning after its threshold.
  static const warningLateSeconds = 5.0;

  /// Display back after a drop.
  static const reconnectSeconds = 15.0;

  /// Battery use may exceed this phone's last run by this share.
  static const batteryTolerance = 0.10;

  /// Shorter runs give no battery figure; the rate is too noisy.
  static const batteryMinimumHours = 0.5;
}

class PerformanceResult {
  final String measure, result, target;

  /// null when there is nothing to compare with yet.
  final bool? ok;
  const PerformanceResult(this.measure, this.result, this.target, this.ok);
}

class PerformanceReport {
  final String title, subtitle;
  final List<PerformanceResult> results;

  /// Battery use in % per hour, kept as this phone's next baseline.
  final double? batteryPerHour;
  const PerformanceReport(
    this.title,
    this.subtitle,
    this.results,
    this.batteryPerHour,
  );

  List<PerformanceResult> get failed => [
    for (final r in results)
      if (r.ok == false) r,
  ];

  static const watermark = 'Created by I-Proton';

  String get markdown {
    String mark(bool? ok) => ok == null ? '—' : (ok ? '✅' : '❌');
    final out = StringBuffer('# $title\n\n$subtitle\n\n');
    if (results.isEmpty) {
      out.writeln('No measurements were recorded.');
    } else {
      out
        ..writeln('| Measure | Result | Target | |')
        ..writeln('|---|---|---|---|');
      for (final r in results) {
        out.writeln(
          '| ${r.measure} | ${r.result} | ${r.target} | ${mark(r.ok)} |',
        );
      }
      out.writeln();
      out.writeln(
        failed.isEmpty
            ? 'All measured targets met.'
            : '${failed.length} to check: ${failed.map((r) => r.measure).join(', ')}.',
      );
    }
    out
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('*$watermark · Church Service Timer*');
    return out.toString();
  }
}

double? _num(String? v) => v == null ? null : double.tryParse(v);

/// Least-squares slope of (seconds, MB) after warm-up, in MB per hour.
double? memoryGrowthPerHour(List<(double, double)> points) {
  final p = [
    for (final e in points)
      if (e.$1 >= 600) e,
  ];
  if (p.length < 3) return null;
  final mt = p.fold(0.0, (n, e) => n + e.$1) / p.length;
  final mm = p.fold(0.0, (n, e) => n + e.$2) / p.length;
  final variance = p.fold(0.0, (n, e) => n + math.pow(e.$1 - mt, 2));
  if (variance == 0) return null;
  final slope = p.fold(0.0, (n, e) => n + (e.$1 - mt) * (e.$2 - mm)) / variance;
  return slope * 3600;
}

String _duration(double seconds) {
  final m = (seconds / 60).round();
  return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
}

/// Builds the marked report from a recording file. [device] and [when]
/// fill the subtitle; [batteryBaseline] is this phone's previous rate.
PerformanceReport buildPerformanceReport(
  String csv, {
  String device = '',
  String when = '',
  double? batteryBaseline,
}) {
  final lines = csv.split('\n');
  final header = lines.indexOf(ServiceMetricsRecorder.columns);
  final comments = [
    for (final l in lines.take(header < 0 ? 0 : header))
      if (l.startsWith('# ')) l.substring(2),
  ];
  // Header comments: title line, app, then the label.
  final app = comments.length > 1 ? comments[1] : 'Church Service Timer';
  final label = comments.length > 2 ? comments[2] : 'Service';
  final names = ServiceMetricsRecorder.columns.split(',');
  final rows = <Map<String, String>>[];
  if (header >= 0) {
    for (final l in lines.skip(header + 1)) {
      if (l.isEmpty || l.startsWith('#')) continue;
      final cells = l.split(',');
      if (cells.length != names.length) continue;
      rows.add({for (var i = 0; i < names.length; i++) names[i]: cells[i]});
    }
  }
  final results = <PerformanceResult>[];
  double? batteryRate;
  final elapsed = rows.isEmpty ? 0.0 : (_num(rows.last['elapsed_s']) ?? 0);
  if (rows.isNotEmpty) {
    final samples = [
      for (final r in rows)
        if (r['kind'] == 'sample') r,
    ];
    final frames = samples.fold(
      0,
      (n, r) => n + (_num(r['frames']) ?? 0).toInt(),
    );
    final slow = samples.fold(
      0,
      (n, r) => n + (_num(r['slow_frames']) ?? 0).toInt(),
    );
    if (frames > 0) {
      final smooth = 100 * (frames - slow) / frames;
      results.add(
        PerformanceResult(
          'Smooth frames',
          '${smooth.toStringAsFixed(1)}%',
          '≥ ${PerformanceTargets.smoothPct.toStringAsFixed(0)}%',
          smooth >= PerformanceTargets.smoothPct,
        ),
      );
    }
    final growth = memoryGrowthPerHour([
      for (final r in samples)
        if (_num(r['elapsed_s']) case final t?)
          if (_num(r['memory_mb']) case final m?) (t, m),
    ]);
    if (growth != null) {
      results.add(
        PerformanceResult(
          'Memory growth after warm-up',
          '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)} MB/h',
          '≤ ${PerformanceTargets.memoryGrowthMbPerHour.toStringAsFixed(0)} MB/h',
          growth <= PerformanceTargets.memoryGrowthMbPerHour,
        ),
      );
    }
    final drift =
        rows.fold(
          0.0,
          (n, r) => math.max(n, (_num(r['drift_ms']) ?? 0).abs()),
        ) /
        1000;
    results.add(
      PerformanceResult(
        'Timer drift',
        '${drift.toStringAsFixed(1)} s',
        '≤ ${PerformanceTargets.driftSeconds.toStringAsFixed(0)} s',
        drift <= PerformanceTargets.driftSeconds,
      ),
    );
    final late = [
      for (final r in rows)
        if (r['kind'] == 'warning')
          if (RegExp(r'late_ms=(\d+)').firstMatch(r['detail'] ?? '')
              case final m?)
            int.parse(m.group(1)!) / 1000,
    ];
    if (late.isNotEmpty) {
      final worst = late.reduce(math.max);
      results.add(
        PerformanceResult(
          'Latest warning',
          '${worst.toStringAsFixed(1)} s after due (${late.length} warning${late.length == 1 ? '' : 's'})',
          '≤ ${PerformanceTargets.warningLateSeconds.toStringAsFixed(0)} s',
          worst <= PerformanceTargets.warningLateSeconds,
        ),
      );
    }
    double? dropped;
    final waits = <double>[];
    for (final r in rows) {
      final t = _num(r['elapsed_s']) ?? 0;
      if (r['kind'] == 'display' &&
          (r['detail'] ?? '').contains('Disconnected'))
        dropped ??= t;
      if (r['kind'] == 'reconnected' && dropped != null) {
        waits.add(t - dropped);
        dropped = null;
      }
    }
    if (waits.isNotEmpty) {
      final worst = waits.reduce(math.max);
      results.add(
        PerformanceResult(
          'Slowest reconnect',
          '${worst.toStringAsFixed(0)} s (${waits.length} drop${waits.length == 1 ? '' : 's'})',
          '≤ ${PerformanceTargets.reconnectSeconds.toStringAsFixed(0)} s',
          worst <= PerformanceTargets.reconnectSeconds,
        ),
      );
    }
    final levels = [for (final r in rows) ?_num(r['battery_pct'])];
    final charging = rows.any((r) => r['charging'] == '1');
    final hours = elapsed / 3600;
    if (levels.length >= 2 &&
        hours >= PerformanceTargets.batteryMinimumHours &&
        !charging) {
      batteryRate = (levels.first - levels.last) / hours;
      final limit = batteryBaseline == null
          ? null
          : batteryBaseline * (1 + PerformanceTargets.batteryTolerance);
      results.add(
        PerformanceResult(
          'Battery use',
          '${batteryRate.toStringAsFixed(1)}%/h (${levels.first.toStringAsFixed(0)}% → ${levels.last.toStringAsFixed(0)}%)',
          limit == null
              ? 'first run sets this phone’s baseline'
              : '≤ ${limit.toStringAsFixed(1)}%/h (last run ${batteryBaseline!.toStringAsFixed(1)}%/h)',
          limit == null ? null : batteryRate <= limit,
        ),
      );
    } else if (levels.length >= 2) {
      results.add(
        PerformanceResult(
          'Battery use',
          charging ? 'charging during the run' : 'run too short to measure',
          'unplugged, ≥ 30 min',
          null,
        ),
      );
    }
  }
  return PerformanceReport(
    'Service metrics · $label',
    [
      app,
      if (device.isNotEmpty) device,
      if (when.isNotEmpty) when,
      _duration(elapsed),
    ].join(' · '),
    results,
    batteryRate,
  );
}
