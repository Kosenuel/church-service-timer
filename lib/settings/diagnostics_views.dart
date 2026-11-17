import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/diagnostics/service_metrics.dart';
import 'package:church_service_timer/diagnostics/performance_report.dart';
import 'package:church_service_timer/feedback/feedback_page.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The table rows (measure, result, target, mark) of a markdown report.
List<List<String>> reportRows(String markdown) => [
  for (final l in markdown.split('\n'))
    if (l.startsWith('| ') &&
        !l.startsWith('| Measure') &&
        l.split('|').length >= 6)
      [for (final v in l.split('|').sublist(1, 5)) v.trim()],
];

/// The summary written at the end of a recording file.
List<String> recordingSummaryLines(String csv) {
  final lines = csv.split('\n');
  final columns = lines.indexOf(ServiceMetricsRecorder.columns);
  if (columns < 0) return const [];
  return [
    for (final l in lines.skip(columns + 1))
      if (l.startsWith('# ')) l.substring(2),
  ];
}

extension DiagnosticsViews on HomeState {
  Future<void> openDiagnostics() =>
      openSettingsDetail('Diagnostics', diagnosticsSettings);

  Widget diagnosticsSettings() {
    final colors = appColors(context);
    final s = c.state.session;
    final recording = c.metrics.recording;
    final armed = c.state.recordMetrics;
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Record performance during a service, for troubleshooting.',
          style: TextStyle(color: colors.muted),
        ),
        const SizedBox(height: 16),
        section('Recording', [
          SwitchListTile(
            key: const ValueKey('record-metrics'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Record service metrics'),
            subtitle: Text(
              recording
                  ? 'Recording now · switches off when this service ends'
                  : armed
                  ? 'Starts when the next service starts, then switches off when it ends'
                  : 'Records one service, then switches itself off',
            ),
            value: armed || recording,
            onChanged: c.busy || c.corrupt
                ? null
                : (v) async {
                    if (!await c.setRecordMetrics(v) && mounted)
                      await showError(c.error ?? 'Could not change recording.');
                  },
          ),
          const SizedBox(height: 4),
          Text(
            deviceText(
              'Recorded once a minute and at key moments: memory use, battery level and temperature, how smoothly the screen draws, timer accuracy against the phone clock, how promptly warnings fire, going to the background, and display or paired-phone reconnections.',
            ),
            style: TextStyle(color: colors.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            deviceText(
              'Nothing about the service content or people is recorded: no program or segment names, notes, messages, church details or device names. The recording stays on this phone until you tap Share recording.',
            ),
            style: TextStyle(color: colors.muted, height: 1.4),
          ),
        ]),
        section('Last recording', [
          FutureBuilder<(String?, String?)>(
            future: _readRecording(),
            builder: (context, snap) {
              final csv = snap.data?.$1, report = snap.data?.$2;
              final rows = report == null
                  ? const <List<String>>[]
                  : reportRows(report);
              final hasFile = csv != null && !recording;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (recording)
                    const Text('Recording in progress.')
                  else if (rows.isEmpty)
                    Text(
                      hasFile
                          ? 'A recording is saved, without a report (it may have been interrupted).'
                          : 'No recording yet.',
                    )
                  else ...[
                    for (final r in rows)
                      Padding(
                        key: ValueKey('report-row:${r[0]}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 10, top: 1),
                              child: switch (r[3]) {
                                '✅' => Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: colors.accent,
                                  semanticLabel: 'Pass',
                                ),
                                '❌' => Icon(
                                  Icons.cancel,
                                  size: 18,
                                  color: colors.error,
                                  semanticLabel: 'Check',
                                ),
                                _ => Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                  color: colors.muted,
                                  semanticLabel: 'No mark yet',
                                ),
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r[0],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text('${r[1]} · target ${r[2]}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      PerformanceReport.watermark,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('share-recording'),
                    onPressed: hasFile
                        ? () => shareRecording(csv, report)
                        : null,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share recording'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shares a report with pass marks (.md) and the minute-by-minute data (.csv).',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              );
            },
          ),
        ]),
        section('Test service', [
          const Text(
            'Runs a generated 2-hour service on the current display, with recording on, to check battery, memory and reliability over a full service. It saves no report and is not added to Programs. End it from Live at any time.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('start-test-service'),
            onPressed: c.busy || c.corrupt || s.active || s.phase == 'ready'
                ? null
                : startTestService,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Start 2-hour test service'),
          ),
          if (s.active || s.phase == 'ready')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Available when no service is loaded or running.',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            ),
        ]),
        section('Feedback', [
          const Text(
            'When reporting a problem, Send feedback can include optional diagnostics (connection and notification status), shown to you before sending. You can attach a shared recording to the same email.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FeedbackCenterPage(controller: c),
              ),
            ),
            icon: const Icon(Icons.feedback_outlined),
            label: const Text('Send feedback'),
          ),
        ]),
      ],
    );
  }

  Future<(String?, String?)> _readRecording() async =>
      (await c.metrics.store.read(), await c.metrics.store.readReport());

  Future<void> shareRecording(String csv, String? report) async {
    try {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      await c.port.shareFiles([
        if (report != null)
          SharedFile.text(
            'Church-Service-Timer-$day-report.md',
            report,
            'text/markdown',
          ),
        SharedFile.text(
          'Church-Service-Timer-$day-metrics.csv',
          csv,
          'text/csv',
        ),
      ], subject: 'Church Service Timer service metrics');
    } catch (e) {
      if (mounted) await showError('Sharing failed: $e');
    }
  }

  Future<void> startTestService() async {
    if (!await confirm(
      'Start a 2-hour test service?',
      'It runs on the current display with service metrics recording. Warnings and the end screen behave as in a real service. No report is saved.',
      'Start test',
    ))
      return;
    if (!await c.startTestService()) {
      if (mounted)
        await showError(c.error ?? 'The test service could not start.');
      return;
    }
    if (!mounted) return;
    navigatePage(0);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}
