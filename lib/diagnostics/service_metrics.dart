import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:church_service_timer/domain/domain.dart';
import 'package:path_provider/path_provider.dart';

/// Where a recording is kept: on this phone only, until it is shared.
abstract class MetricsStore {
  Future<void> reset(String header);
  Future<void> append(String line);
  Future<String?> read();
}

class FileMetricsStore implements MetricsStore {
  /// Recordings beyond this size stop growing rather than fill the phone.
  static const maxBytes = 2 * 1024 * 1024;
  File? _file;
  Future<File> _target() async => _file ??= File(
    '${(await getApplicationSupportDirectory()).path}/service-metrics.csv',
  );
  @override
  Future<void> reset(String header) async =>
      (await _target()).writeAsString(header, flush: true);
  @override
  Future<void> append(String line) async {
    final f = await _target();
    if (await f.exists() && await f.length() > maxBytes) return;
    await f.writeAsString(line, mode: FileMode.append, flush: true);
  }

  @override
  Future<String?> read() async {
    final f = await _target();
    return await f.exists() ? f.readAsString() : null;
  }
}

class MemoryMetricsStore implements MetricsStore {
  final buffer = StringBuffer();
  bool written = false;
  @override
  Future<void> reset(String header) async {
    buffer
      ..clear()
      ..write(header);
    written = true;
  }

  @override
  Future<void> append(String line) async => buffer.write(line);
  @override
  Future<String?> read() async => written ? buffer.toString() : null;
}

/// What one recording found, for the Diagnostics page and the shared file.
class MetricsSummary {
  final String label;
  final int startedWall, durationMs, samples, frames, slowFrames, jankyFrames;
  final double peakMemoryMb, worstFrameMs;
  final int maxDriftMs, maxWarningLateMs, warnings, backgrounded, reconnects;
  final int? batteryStart, batteryEnd;
  const MetricsSummary({
    required this.label,
    required this.startedWall,
    required this.durationMs,
    required this.samples,
    required this.frames,
    required this.slowFrames,
    required this.jankyFrames,
    required this.peakMemoryMb,
    required this.worstFrameMs,
    required this.maxDriftMs,
    required this.maxWarningLateMs,
    required this.warnings,
    required this.backgrounded,
    required this.reconnects,
    this.batteryStart,
    this.batteryEnd,
  });

  /// Plain lines for the Diagnostics page and the top of the shared file.
  List<String> get lines => [
    '$label · ${durationLabel(durationMs)}',
    'Memory peak ${peakMemoryMb.toStringAsFixed(0)} MB',
    'Frames: ${frames == 0 ? 'none drawn' : '${(100 * (frames - slowFrames) / frames).toStringAsFixed(1)}% smooth · slowest ${worstFrameMs.toStringAsFixed(0)} ms'}',
    'Timer drift up to ${(maxDriftMs / 1000).toStringAsFixed(1)} s',
    'Warnings: $warnings · latest ${(maxWarningLateMs / 1000).toStringAsFixed(1)} s after due',
    'Sent to background $backgrounded× · reconnections $reconnects',
    if (batteryStart != null && batteryEnd != null)
      'Battery $batteryStart% → $batteryEnd%',
  ];
}

/// Records performance during one service: memory, frame times, timer
/// drift against the wall clock, warning lateness, backgrounding,
/// reconnections and battery. Never service content, names or notes.
class ServiceMetricsRecorder {
  final MetricsStore store;
  final int Function() memoryBytes;
  ServiceMetricsRecorder({MetricsStore? store, int Function()? memoryBytes})
    : store = store ?? FileMetricsStore(),
      memoryBytes = memoryBytes ?? (() => ProcessInfo.currentRss);

  static const sampleEveryMs = 60000;
  static const columns =
      'wall_utc,elapsed_s,kind,memory_mb,frames,slow_frames,janky_frames,worst_frame_ms,drift_ms,battery_pct,battery_temp_c,charging,detail';

  Stamp? _start;
  String _label = '';
  int _lastSampleMono = 0;
  // Frames since the last sample, and over the whole recording.
  int _frames = 0, _slow = 0, _janky = 0;
  double _worst = 0;
  int _allFrames = 0, _allSlow = 0, _allJanky = 0;
  double _allWorst = 0, _peakMb = 0;
  int _maxDrift = 0, _maxLate = 0, _warnings = 0, _background = 0;
  int _reconnects = 0, _samples = 0;
  int? _batteryStart, _batteryEnd;
  Future<void> _writes = Future.value();

  bool get recording => _start != null;

  Future<void> start(Stamp now, {required String label, String app = ''}) {
    _start = now;
    _label = label;
    _lastSampleMono = now.mono;
    _frames = _slow = _janky = 0;
    _worst = 0;
    _allFrames = _allSlow = _allJanky = 0;
    _allWorst = _peakMb = 0;
    _maxDrift = _maxLate = _warnings = _background = _reconnects = 0;
    _samples = 0;
    _batteryStart = _batteryEnd = null;
    return _queue(
      () => store.reset(
        '# Church Service Timer service metrics\n# $app\n# $label\n$columns\n',
      ),
    );
  }

  Future<void> _queue(Future<void> Function() write) =>
      _writes = _writes.then((_) => write()).catchError((_) {});

  /// Frame build and raster times, from the Flutter scheduler.
  void addFrames(List<FrameTiming> timings) {
    if (!recording) return;
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000;
      _frames++;
      _allFrames++;
      if (ms > 16.7) {
        _slow++;
        _allSlow++;
      }
      if (ms > 33.4) {
        _janky++;
        _allJanky++;
      }
      _worst = math.max(_worst, ms);
      _allWorst = math.max(_allWorst, ms);
    }
  }

  /// How far the wall clock has moved from the app's monotonic clock.
  int drift(Stamp now) {
    final s = _start!;
    return (now.wall - s.wall) - (now.mono - s.mono);
  }

  String _row(
    Stamp now,
    String kind, {
    Json battery = const {},
    String detail = '',
  }) {
    final mb = memoryBytes() / (1024 * 1024);
    _peakMb = math.max(_peakMb, mb);
    final d = drift(now);
    if (d.abs() > _maxDrift.abs()) _maxDrift = d;
    final pct = battery['level'];
    if (pct is int) {
      _batteryStart ??= pct;
      _batteryEnd = pct;
    }
    final row = [
      DateTime.fromMillisecondsSinceEpoch(
        now.wall,
        isUtc: true,
      ).toIso8601String(),
      ((now.mono - _start!.mono) / 1000).toStringAsFixed(0),
      kind,
      mb.toStringAsFixed(1),
      _frames,
      _slow,
      _janky,
      _worst.toStringAsFixed(1),
      d,
      pct ?? '',
      battery['temperature'] ?? '',
      battery['charging'] == null ? '' : (battery['charging'] == true ? 1 : 0),
      detail.replaceAll(RegExp(r'[,\n\r]'), ' '),
    ].join(',');
    return '$row\n';
  }

  /// Takes a sample once a minute; call on every tick.
  bool sampleDue(Stamp now) =>
      recording && now.mono - _lastSampleMono >= sampleEveryMs;

  Future<void> sample(
    Stamp now, {
    Json battery = const {},
    String detail = '',
  }) {
    if (!recording) return Future.value();
    _lastSampleMono = now.mono;
    _samples++;
    final line = _row(now, 'sample', battery: battery, detail: detail);
    _frames = _slow = _janky = 0;
    _worst = 0;
    return _queue(() => store.append(line));
  }

  /// A moment worth noting, such as a warning, backgrounding or reconnection.
  Future<void> event(Stamp now, String kind, [String detail = '']) {
    if (!recording) return Future.value();
    if (kind == 'background') _background++;
    if (kind == 'reconnected') _reconnects++;
    return _queue(() => store.append(_row(now, kind, detail: detail)));
  }

  /// A warning reached the display [lateMs] after its threshold.
  Future<void> warning(Stamp now, int lateMs) {
    _warnings++;
    _maxLate = math.max(_maxLate, lateMs);
    return event(now, 'warning', 'late_ms=$lateMs');
  }

  MetricsSummary? get summary {
    final s = _start;
    if (s == null) return null;
    return _summaryAt(s, _lastNow ?? s);
  }

  Stamp? _lastNow;
  void touch(Stamp now) => _lastNow = now;

  MetricsSummary _summaryAt(Stamp s, Stamp now) => MetricsSummary(
    label: _label,
    startedWall: s.wall,
    durationMs: now.mono - s.mono,
    samples: _samples,
    frames: _allFrames,
    slowFrames: _allSlow,
    jankyFrames: _allJanky,
    peakMemoryMb: _peakMb,
    worstFrameMs: _allWorst,
    maxDriftMs: _maxDrift.abs(),
    maxWarningLateMs: _maxLate,
    warnings: _warnings,
    backgrounded: _background,
    reconnects: _reconnects,
    batteryStart: _batteryStart,
    batteryEnd: _batteryEnd,
  );

  /// Ends the recording with a final sample and the summary.
  Future<MetricsSummary?> stop(Stamp now, {Json battery = const {}}) async {
    final s = _start;
    if (s == null) return null;
    await sample(now, battery: battery, detail: 'end');
    final result = _summaryAt(s, now);
    final summary = [for (final l in result.lines) '# $l'].join('\n');
    await _queue(() => store.append('$summary\n'));
    await _writes;
    _start = null;
    return result;
  }

  Future<void> flush() => _writes;
}

/// A generated 2-hour service for endurance testing. It uses the shared
/// warnings and end screen, and is never saved to the program list.
Timeline testServiceProgram() => Timeline('Test service (2 h)', const [
  Segment('Welcome', 5),
  Segment('Worship', 20),
  Segment('Prayer', 5),
  Segment('Announcements', 5),
  Segment('Offering', 5),
  Segment('Choir', 10),
  Segment('Bible reading', 5),
  Segment('Sermon', 40),
  Segment('Response', 10),
  Segment('Closing', 10),
  Segment('Benediction', 5),
], DisplaySettings());
