import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/diagnostics/performance_report.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:flutter/scheduler.dart';

/// Diagnostics: records performance around one service when asked, and
/// writes the marked report when it ends.
class MetricsTracker {
  final AppController app;
  MetricsTracker(this.app);

  String _display = '';

  TimingsCallback? _timings;
  bool _timingsOn = false;
  void frameTimings(bool on) {
    if (on == _timingsOn) return;
    _timings ??= app.metrics.addFrames;
    try {
      on
          ? SchedulerBinding.instance.addTimingsCallback(_timings!)
          : SchedulerBinding.instance.removeTimingsCallback(_timings!);
      _timingsOn = on;
    } catch (_) {
      // Without a running Flutter engine there are no frames to time; the
      // rest of the recording still works.
    }
  }

  /// Starts, samples and stops a metrics recording around a service. Runs
  /// on every tick; cheap when Diagnostics is off.
  Future<void> track() async {
    final s = app.state.session;
    if (!app.metrics.recording) {
      if (!app.state.recordMetrics || !s.active) return;
      frameTimings(true);
      _display = app.displayConnection.label;
      await app.metrics.start(
        app.now,
        label: s.noReport ? 'Test service' : 'Service',
        app: '$appName ${appVersion.split(' ').first}',
      );
      await app.metrics.sample(
        app.now,
        battery: await app.port.batteryStatus(),
        detail: 'start; display=$_display',
      );
      app.notifyChanged();
      return;
    }
    app.metrics.touch(app.now);
    final display = app.displayConnection.label;
    if (display != _display) {
      unawaited(
        app.metrics.event(
          app.now,
          // Back to connected after a drop counts as a reconnection.
          {
                    DisplayConnection.connected.label,
                    DisplayConnection.stageConnected.label,
                  }.contains(display) &&
                  _display != DisplayConnection.simulator.label
              ? 'reconnected'
              : 'display',
          'display=$display',
        ),
      );
      _display = display;
    }
    if (!s.active) {
      await _stop();
      // Recording is for one service, so it is never left on by accident.
      if (app.state.recordMetrics)
        await app.commit((draft, _) => draft.recordMetrics = false);
      app.notifyChanged();
      return;
    }
    if (app.metrics.sampleDue(app.now))
      await app.metrics.sample(
        app.now,
        battery: await app.port.batteryStatus(),
        detail: 'display=$display; peers=${app.pairing.peers.length}',
      );
  }

  Future<void> _stop() async {
    frameTimings(false);
    final started = app.metrics.summary?.startedWall;
    app.lastMetrics = await app.metrics.stop(
      app.now,
      battery: await app.port.batteryStatus(),
    );
    final csv = await app.metrics.store.read();
    if (csv == null) return;
    String device = '';
    try {
      device = await app.port.deviceDescription();
    } catch (_) {
      /* The report is still useful without the model. */
    }
    final report = buildPerformanceReport(
      csv,
      device: device,
      when: started == null ? '' : _reportDate(started),
      batteryBaseline: app.state.metricsBatteryBaseline,
    );
    app.lastReport = report;
    await app.metrics.store.writeReport(report.markdown);
    // A rising level means it was charged; that is no baseline.
    if (report.batteryPerHour case final rate? when rate > 0)
      await app.commit((draft, _) => draft.metricsBatteryBaseline = rate);
  }

  static String _reportDate(int wall) {
    final d = DateTime.fromMillisecondsSinceEpoch(wall);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> setRecord(bool on) async {
    final ok = await app.commit((draft, _) => draft.recordMetrics = on);
    if (ok && !on && app.metrics.recording) {
      await _stop();
      app.notifyChanged();
    }
    return ok;
  }
}
