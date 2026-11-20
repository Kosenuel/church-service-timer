import 'dart:async';
import 'package:church_service_timer/shared/app_pickers.dart';
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/live/standing_by_desktop.dart';
import 'package:church_service_timer/live/practice_views.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/settings/diagnostics_views.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/keys_live.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/live/quick_timer_sheet.dart';
import 'package:church_service_timer/live/second_screen_control.dart';
import 'package:church_service_timer/live/service_check.dart';
import 'package:church_service_timer/live/simulator_choice.dart';
import 'package:church_service_timer/live/simulator_matrix.dart';

/// The Live page: standing by, Ready for service and the running service.
/// The widest Classic's Live page is usually laid out.
const classicUsualWidth = 1200.0;

/// The width it may use in a very wide window, where the rundown has a
/// column of its own.
const classicThreeColumnWidth = 2280.0;

/// The window width from which it does.
const classicThreeColumnsFromWindow = 1840.0;

extension LivePage on HomeState {
  /// The widest Classic's Live page is laid out. A very wide window gives
  /// it more while there is a rundown for the third column; everything
  /// else keeps the usual width, so nothing is stretched.
  double get classicLiveWidth {
    final s = c.liveSession;
    final rundown =
        s.timeline != null &&
        s.phase != 'idle' &&
        s.phase != 'ended' &&
        !c.reportSavePending &&
        !focused;
    return rundown &&
            MediaQuery.sizeOf(context).width >= classicThreeColumnsFromWindow
        ? classicThreeColumnWidth
        : classicUsualWidth;
  }

  Widget live() => AnimatedBuilder(
    animation: c.liveClock,
    builder: (context, _) => liveContent(),
  );

  Widget liveMatrix() => RepaintBoundary(
    child: c.hardware.enabled
        ? AnimatedBuilder(
            animation: c.previewClock,
            builder: (context, _) => LedMatrix(
              pixels: c.hardware.preview(c.now),
              hardware: true,
              stale:
                  c.hardware.held ||
                  !c.hardware.connected ||
                  c.hardware.interrupted,
            ),
          )
        // Scrolling text moves on every frame, at the sign's own pace.
        : SimulatorMatrix(controller: c),
  );

  /// Pinned (or most recent) programs that load straight into Ready.
  Widget pinnedPrograms() {
    final lib = c.state.programLibrary;
    final pinned = c.state.templates
        .where((p) => lib.favourites.contains(p.id))
        .toList();
    final recent =
        c.state.templates.where((p) => lib.recent.containsKey(p.id)).toList()
          ..sort((a, b) => lib.recent[b.id]!.compareTo(lib.recent[a.id]!));
    final items = (pinned.isNotEmpty ? pinned : recent).take(4).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = appColors(context);
    final disabled =
        c.busy || c.corrupt || c.reportSavePending || controlsLocked;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(pinned.isNotEmpty ? 'Pinned' : 'Recent'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, space) {
              final width = (space.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (i, p) in items.indexed)
                    SizedBox(
                      // A lone card, or the odd one out at the end, fills
                      // the row instead of leaving half of it empty.
                      width: items.length.isOdd && i == items.length - 1
                          ? space.maxWidth
                          : width,
                      child: Material(
                        key: ValueKey('quick-load:${p.name}'),
                        color: colors.surface,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: colors.border),
                        ),
                        child: InkWell(
                          onTap: disabled
                              ? null
                              : () async {
                                  try {
                                    c.state.templateIndex(p);
                                    await c.act('load', value: p);
                                  } catch (e) {
                                    if (mounted) await showError('$e');
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_outline,
                                      size: 18,
                                      color: colors.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  templateSummary(p),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget lastServiceCard() {
    final r = c.state.reports.reduce(
      (a, b) => b.endedWall > a.endedWall ? b : a,
    );
    final colors = appColors(context);
    final variance = r.comparable ? r.totalMs! - r.plannedMs : null;
    final tone = variance == null || variance >= 1000
        ? colors.warning
        : variance <= -1000
        ? colors.info
        : colors.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        key: const ValueKey('last-service-card'),
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
        child: InkWell(
          onTap: () => openReport(r),
          child: Padding(
            // The same insets and gap as the Recent cards above.
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: label('Last service')),
                    Text(
                      'View last service report',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${r.name} · ${reportDate(r.startedWall ?? r.endedWall)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (r.totalMs != null) durationLabel(r.totalMs!),
                    variance == null
                        ? 'Partial record'
                        : varianceLabel(variance),
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: tone),
                ),
                if (r.review != null && r.review!.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.review!.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: colors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String wallTime(int wall) {
    final d = DateTime.fromMillisecondsSinceEpoch(wall);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> pickServiceStart() async {
    final now = DateTime.fromMillisecondsSinceEpoch(c.now.wall);
    final current = c.state.session.startsAtWall;
    final initial = current == null
        ? TimeOfDay.fromDateTime(
            DateTime(now.year, now.month, now.day, now.hour + 1),
          )
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(current));
    final picked = await showAppTimePicker(
      context,
      initialTime: initial,
      use24Hour: c.state.clockFormat != '12h',
      typed: c.port.isDesktop,
      helpText: 'Service starts at',
    );
    if (picked == null || !mounted) return;
    var start = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (!start.isAfter(now)) start = start.add(const Duration(days: 1));
    if (!await c.act('schedule', value: start.millisecondsSinceEpoch) &&
        mounted)
      await showError(c.error ?? 'Could not schedule the start.');
  }

  /// Optional scheduled start: the stage shows the clock, then a countdown to
  /// the start, then "Starting soon". The service still starts only on tap.
  Widget preServiceRow() {
    final colors = appColors(context);
    final at = c.state.session.startsAtWall;
    final left = at == null ? 0 : at - c.now.wall;
    // A hold (after Undo start, a cancelled setup or a reconnect) stops the
    // pre-service output reaching the display until it is released.
    final outputHeld =
        at != null &&
        (c.state.session.held ||
            (c.destination == 'led' &&
                c.hardware.connected &&
                c.hardware.held));
    final preServiceHint = outputHeld
        ? 'Output is held, so the display does not show it yet.'
        : deviceText('Tap Start first segment when the service begins.');
    final summary = at == null
        ? 'Off · the display keeps its current output'
        : left > preServiceCountdownMs
        ? 'Starts ${wallTime(at)} · clock now, countdown from ${wallTime(at - preServiceCountdownMs - 1000)}\n$preServiceHint'
        : left > 0
        ? 'Starts ${wallTime(at)} · counting down on the display\n$preServiceHint'
        : 'Start time reached · display shows “Starting soon”\n$preServiceHint';
    return Material(
      key: const ValueKey('pre-service-row'),
      color: colors.background,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        leading: Icon(Icons.schedule, color: colors.accent),
        title: const Text(
          'Pre-service countdown',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          summary,
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
        trailing: at == null
            ? TextButton(
                onPressed: c.busy ? null : pickServiceStart,
                child: const Text('Set time'),
              )
            : outputHeld
            ? TextButton(
                key: const ValueKey('show-pre-service'),
                onPressed: c.busy
                    ? null
                    : () async {
                        if (!await c.showPreService() && mounted)
                          await showError(
                            c.error ?? 'Connect the display, then try again.',
                          );
                      },
                child: const Text('Show on display'),
              )
            : IconButton(
                tooltip: 'Turn off pre-service countdown',
                onPressed: c.busy ? null : () => c.act('schedule', value: null),
                icon: const Icon(Icons.close),
              ),
        onTap: c.busy ? null : pickServiceStart,
      ),
    );
  }

  /// Display status and readiness verdict, shown while a service is in Ready.
  Widget readyInline() {
    final colors = appColors(context);
    final problems = readinessChecks()
        .where((x) => !x.ok && x.key != 'program')
        .length;
    final tone = problems == 0 && c.destinationConnected
        ? colors.accent
        : colors.warning;
    return Material(
      key: const ValueKey('ready-inline'),
      color: tone.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openSettingsDetail('Ready for service', readinessSettings),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(connectionIcon(c.displayConnection), color: tone, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${c.displayConnection.label} · ${problems == 0 ? 'all set' : '${plural(problems, 'thing')} to check'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// A segment's times, speaker and private note, opened from the rundown.
  Future<void> showSegmentDetails(int index) {
    final s = c.liveSession, t = s.timeline!;
    final segment = t.segments[index];
    final current = index == s.index;
    return showAppSelection<void>(
      context,
      title: 'Segment details',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(segment.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Segment ${index + 1} of ${t.segments.length} · ${segment.durationText} planned',
          ),
          if (current)
            Text(
              '${operatorTimeDescription(s.balance(c.now))} · ${formatTime(s.allocatedMs)} allocated',
            ),
          if (s.run?.actualMs[index] != null)
            Text(
              'Recorded duration: ${durationLabel(s.run!.actualMs[index]!)}',
            ),
          if (segment.speaker.isNotEmpty) Text('Speaker: ${segment.speaker}'),
          SizedBox(height: appLayout(context).gap),
          const AppDivider(indent: 0, endIndent: 0),
          SizedBox(height: appLayout(context).gap),
          const Text(
            'Private operator note',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            segment.notes.isEmpty
                ? 'No private note for this segment.'
                : segment.notes,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget liveContent() {
    final s = c.liveSession;
    // A practice run just ended: show its summary once, after this frame.
    if (c.practice.finished != null && !practiceSummaryQueued) {
      practiceSummaryQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await showPracticeSummary();
        practiceSummaryQueued = false;
      });
    }
    final standingBy =
        s.phase == 'idle' || (s.phase == 'ended' && !c.reportSavePending);
    final t = standingBy ? null : s.timeline;
    final enabled =
        s.active &&
        !c.reportSavePending &&
        !c.busy &&
        !c.corrupt &&
        !controlsLocked &&
        c.pairing.localControl;
    final phase = standingBy
        ? 'Standing by'
        : s.phase == 'active'
        ? (s.phase == 'ended'
              ? 'Screen blank'
              : s.paused
              ? 'Paused'
              : 'Live')
        : s.phase == 'ready'
        ? 'Ready'
        : s.phase == 'ended'
        ? 'Service ended'
        : 'Standing by';
    final canJump = enabled && t != null && s.index + 1 < t.segments.length;
    final timerHeader = Row(
      children: [
        Expanded(
          child: label(
            standingBy
                ? 'Standing by'
                : t == null
                ? 'Live production'
                : s.quickTimer
                ? 'Quick timer'
                : 'Segment ${s.index + 1} of ${t.segments.length}',
          ),
        ),
        // Visible whenever recording is on, so it is never left on by
        // accident.
        if (c.state.recordMetrics || c.metrics.recording)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              key: const ValueKey('metrics-chip'),
              avatar: Icon(
                Icons.fiber_manual_record,
                size: 12,
                color: appColors(context).error,
              ),
              label: Text(
                s.noReport ? 'Test · recording' : 'Recording metrics',
              ),
              onPressed: openDiagnostics,
            ),
          ),
        if (!standingBy)
          Chip(
            label: Text(
              !standingBy && s.rehearsal ? '$phase · ${s.rate}×' : phase,
            ),
            avatar: Icon(
              s.active && !s.paused ? Icons.circle : Icons.circle_outlined,
              size: 12,
              color: appColors(context).accent,
            ),
          ),
      ],
    );
    Widget endServiceButton({bool compact = false}) => practiceSpot(
      'end',
      FilledButton.icon(
        key: const ValueKey('end-service'),
        onPressed: enabled ? confirmEndService : null,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(s.quickTimer ? 'End timer' : 'End service'),
        style: FilledButton.styleFrom(
          backgroundColor: destructiveColor,
          foregroundColor: Colors.white,
          minimumSize: compact
              ? const Size(0, 44)
              : const Size(double.infinity, 54),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: compact ? 14 : 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      radius: 12,
    );
    Widget timerPanelOf({required bool wide}) => panel(
      child: Column(
        key: const ValueKey('timer-card-content'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          timerHeader,
          const SizedBox(height: 8),
          if (t == null)
            const Text(
              'Ready when you are',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            )
          else
            Semantics(
              button: s.active,
              enabled: canJump,
              hint: s.active ? 'Jump to segment' : null,
              child: InkWell(
                key: const ValueKey('jump-to-segment'),
                borderRadius: BorderRadius.circular(8),
                onTap: s.active && canJump ? jumpToSegment : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.segments[s.index].name,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (s.active && canJump) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more,
                          color: appColors(context).muted,
                          semanticLabel: 'Jump to segment',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (t != null) ...[
            const SizedBox(height: 6),
            if (!s.quickTimer)
              Text(
                s.index + 1 < t.segments.length
                    ? 'Next · ${t.segments[s.index + 1].name} · ${t.segments[s.index + 1].durationText}'
                    : 'Final segment',
                style: TextStyle(color: appColors(context).muted),
              ),
            if (s.active && !wide) ...[
              const SizedBox(height: 12),
              timingStatusLine(),
            ],
            const SizedBox(height: 6),
            if (t.segments[s.index].speaker.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Speaker: ${t.segments[s.index].speaker}'),
              ),
            if (t.segments[s.index].notes.isNotEmpty)
              OperatorNotes(
                key: ValueKey('${s.id}-${s.index}'),
                notes: t.segments[s.index].notes,
              ),
            SegmentGauge(session: s, now: c.now),
          ] else
            const SizedBox(height: 18),
          if (!s.active && s.phase != 'ready' && !c.reportSavePending)
            // Side by side when they fit, stacked at large text sizes.
            ControlGrid(
              maxColumns: 2,
              minWidth: 150,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 54),
                  child: button(
                    'Start service',
                    Icons.play_arrow,
                    c.busy || c.corrupt ? null : chooseService,
                    primary: true,
                  ),
                ),
                // A single countdown with no program or Ready step.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 54),
                  child: OutlinedButton.icon(
                    key: const ValueKey('quick-timer-live'),
                    onPressed: quickTimerAvailable ? openQuickTimer : null,
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text(
                      'Quick timer',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          if (standingBy) ...[
            const SizedBox(height: 10),
            ControlGrid(
              maxColumns: 2,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('share-service-live'),
                  onPressed:
                      c.busy ||
                          c.corrupt ||
                          c.reportSavePending ||
                          controlsLocked
                      ? null
                      : shareServiceSetup,
                  icon: const Icon(Icons.cast_connected),
                  label: Text(
                    c.pairing.hosting ? 'Manage sharing' : 'Share to screens',
                    textAlign: TextAlign.center,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      c.busy ||
                          c.corrupt ||
                          c.reportSavePending ||
                          controlsLocked ||
                          !c.pairing.localControl
                      ? null
                      : joinAsStageScreen,
                  icon: const Icon(Icons.tablet_mac_outlined),
                  label: const Text(
                    'Join a service',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
          // Ready already counts battery in its "things to check" row.
          if (standingBy &&
              c.batteryUnrestricted == false &&
              !batteryHintDismissed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                key: const ValueKey('battery-hint'),
                color: appColors(context).warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: c.port.openBatterySettings,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.battery_alert_outlined,
                          size: 20,
                          color: appColors(context).warning,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Battery optimisation may delay warnings with the screen off. Tap to fix.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('battery-hint-dismiss'),
                          tooltip: 'Hide until the app is next opened',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              refreshHome(() => batteryHintDismissed = true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (s.phase == 'ready' && t != null)
            if (c.state.latestReviewFor(t) case final last?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  key: const ValueKey('last-review-note'),
                  color: appColors(context).info.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.rate_review_outlined,
                          size: 20,
                          color: appColors(context).info,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last time · ${serviceDateLabel(last.report.startedWall ?? last.report.endedWall)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(last.note.text),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          if (s.phase == 'ready') ...[
            if (t != null) ...[readyProgramRow(t), const SizedBox(height: 8)],
            readyInline(),
            const SizedBox(height: 10),
            preServiceRow(),
            const SizedBox(height: 12),
            ChoiceField<int>(
              key: ValueKey('speed-${s.id}'),
              value: s.rate,
              decoration: const InputDecoration(labelText: 'Service mode'),
              options: [1, 5, 10, 30, 60]
                  .map(
                    (rate) => ChoiceOption(
                      value: rate,
                      label: rate == 1
                          ? 'Live timing · 1×'
                          : 'Fast rehearsal · $rate×',
                    ),
                  )
                  .toList(),
              onChanged: c.busy ? null : (v) => c.act('rate', value: v),
            ),
            const SizedBox(height: 12),
            Text(
              // With a pre-service start time the display counts down to
              // it, so "keeps its previous output" would contradict the row
              // above.
              s.startsAtWall == null
                  ? 'Timing has not started. The display keeps its current output.'
                  : 'Timing has not started. The display follows the pre-service start time above.',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                practiceSpot(
                  'start',
                  button(
                    'Start first segment',
                    Icons.play_arrow,
                    c.busy ? null : startFirst,
                    primary: true,
                  ),
                ),
                button(
                  'Cancel setup',
                  Icons.close,
                  c.busy ? null : () => c.act('cancelReady'),
                ),
                // A quick run-through on the Simulator before the day.
                if (t != null) checkServiceButton(t),
              ],
            ),
          ],
          if (s.active) ...[
            liveControls(enabled),
            // Set apart from the time adjustments above, so a slip doesn't
            // land on End service.
            const SizedBox(height: 28),
            endServiceButton(),
          ],
        ],
      ),
    );
    final dense = liveFillsWindow;
    final displayPanel = c.destination == 'mobile'
        ? panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                displayPreviewHeader(),
                const SizedBox(height: 14),
                mobileStagePreview(),
                ...secondScreenPreviewBeneath(),
                const SizedBox(height: 12),
                stageSharingControls(),
                ...secondScreenControl(),
                ...fullScreenControl(),
              ],
            ),
          )
        : panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                displayPreviewHeader(
                  secondScreen:
                      secondScreenPreviewNow ==
                      SecondScreenPreviewPlace.replaces,
                ),
                const SizedBox(height: 14),
                previewOrSecondScreen(displayPreview()),
                ...secondScreenPreviewBeneath(),
                if (s.outputBlank)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Screen intentionally blanked'),
                  ),
                const SizedBox(height: 12),
                // The sign's size; not shown over a copy of the second
                // screen, or where the Simulator is a stage screen.
                if (!dense &&
                    !c.stageSimulator &&
                    secondScreenPreviewNow != SecondScreenPreviewPlace.replaces)
                  Text(
                    '32 × 16 · ${c.state.pixelShape == 'square' ? 'Square' : 'Circular'} LEDs',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
                if (s.disconnected ||
                    (s.held && (s.active || s.phase == 'ended'))) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.disconnected
                        ? 'Output unavailable · showing the last simulated frame'
                        : 'Output paused after an interruption · resume below',
                    style: TextStyle(color: appColors(context).error),
                  ),
                ],
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final intended = s.outputBlank
                        ? 'Blank'
                        : s.intended(c.now)?.text ?? 'Nothing new';
                    final current = c.hardware.enabled
                        ? c.hardware.acceptedLabel
                        : c.simulator.delivered?.text ?? 'Blank';
                    final muted = TextStyle(color: appColors(context).muted);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.hardware.enabled
                              ? 'Sign accepted: $current'
                              : 'Showing: $current',
                          style: muted,
                        ),
                        if (intended != current)
                          Text(
                            c.hardware.enabled
                                ? 'Waiting to send: $intended'
                                : 'Waiting to show: $intended',
                            style: muted,
                          ),
                      ],
                    );
                  },
                ),
                // A desktop layout keeps the stage pane short, so the cues
                // below stay in view; the chip in the header changes display.
                if (!dense || c.hardware.enabled) ...[
                  const SizedBox(height: 8),
                  Text(
                    c.hardware.enabled
                        ? 'Preview is an estimate of the last accepted program, not a live camera view of the sign.'
                        : 'Simulator only · connect a display in Settings for physical output.',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (!dense) ...[
                  const SizedBox(height: 12),
                  button(
                    'Change display',
                    Icons.devices,
                    c.busy || c.corrupt ? null : chooseDisplay,
                  ),
                ],
                ...secondScreenControl(),
                ...fullScreenControl(),
              ],
            ),
          );
    final mode = s.outputMode(c.now);
    // Match the sent cue to its prepared button: exact formatting first,
    // then by text, so a restyled preset still swaps to its return button.
    var activeCueIndex = -1;
    if (!s.outputBlank && s.hasManualCue(c.now) && !s.alertIsMessage) {
      final sent = s.alert!;
      activeCueIndex = c.state.stageCues.indexWhere(
        (cue) => cue.toJson().toString() == sent.toJson().toString(),
      );
      if (activeCueIndex < 0)
        activeCueIndex = c.state.stageCues.indexWhere(
          (cue) => cue.text == sent.text,
        );
    }
    final clockSwap = !s.outputBlank && mode == 'Clock';
    final messageSwap =
        !s.outputBlank && mode == 'Message' && c.currentQuickMessage == null;
    // Outputs that no swapped button represents (automatic warnings, quick
    // messages, cues sent from elsewhere) still get an explicit way back.
    final needsReturn =
        (!s.outputBlank &&
            !const ['Countdown', 'Standby', 'End screen'].contains(mode) &&
            activeCueIndex < 0 &&
            !clockSwap &&
            !messageSwap) ||
        c.currentQuickMessage != null;
    final returnLabel = s.phase == 'ended' ? 'Show end screen' : 'Show timer';
    void returnToTimer() => c.act(s.phase == 'ended' ? 'endScreen' : 'timer');
    // A cue or message sits over whatever was showing; clearing it reveals
    // that output again (the clock, the countdown or the end screen).
    final cueReturnLabel = s.showClock ? 'Back to clock' : returnLabel;
    void returnFromCue() => c.act('clearCue');
    final cuePanel = panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label('Stage cues')),
              TextButton(
                onPressed: controlsLocked
                    ? null
                    : () => openSettingsDetail('Stage cues', stageCueSettings),
                child: const Text('Manage cues'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            liveShowingText(),
            key: const ValueKey('stage-showing'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          cueDeliveryFeedback(),
          const SizedBox(height: 12),
          // Cues: every button the same height; a lone last cue fills its
          // row rather than leaving a gap.
          ControlGrid(
            maxColumns: 2,
            fillLastRow: true,
            children: c.state.stageCues.asMap().entries.map((e) {
              final active = e.key == activeCueIndex;
              if (active) {
                return practiceSpot(
                  'timer',
                  ShowTimerButton(
                    key: ValueKey('show-timer-cue-${e.key}'),
                    label: cueReturnLabel,
                    showing: '${e.value.text} ${destinationPhrase()}',
                    sending: c.hardware.sending,
                    onPressed: outputControlsEnabled ? returnFromCue : null,
                  ),
                  radius: 12,
                );
              }
              return practiceSpot(
                'cue',
                enabled: e.key == 0,
                Tooltip(
                  message: e.value.text,
                  child: UnavailableAction(
                    reason: outputControlsEnabled && !c.hardware.sending
                        ? null
                        : c.hardware.sending
                        ? 'Wait for the current cue to finish sending.'
                        : unavailableReason('Send cue'),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, dense ? 48 : 68),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      // A desktop layout sets the cue as the stage shows
                      // it, so it needs no icon to say what it is.
                      icon: dense
                          ? null
                          : const Icon(Icons.chat_bubble_outline, size: 20),
                      label: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.value.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: dense ? stageCueStyle : null,
                            ),
                          ),
                          // The number key that sends it, on a computer.
                          if (showKeyHints && c.port.isDesktop && e.key < 9)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: KeyHint('${e.key + 1}'),
                            ),
                        ],
                      ),
                      onPressed: outputControlsEnabled && !c.hardware.sending
                          ? () => sendPreparedCue(e.value)
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Display actions sit apart from the cues, in one even row.
          ControlGrid(
            // Two by two: the display actions and Quick timer.
            maxColumns: 2,
            minWidth: 92,
            children: [
              if (clockSwap)
                ShowTimerButton(
                  key: const ValueKey('show-timer-clock'),
                  label: returnLabel,
                  showing: 'Clock ${destinationPhrase()}',
                  sending: c.hardware.sending,
                  onPressed: outputControlsEnabled ? returnToTimer : null,
                )
              else
                stackedButton(
                  'Show clock',
                  Icons.schedule,
                  outputControlsEnabled ? () => c.act('clock') : null,
                ),
              if (messageSwap)
                ShowTimerButton(
                  key: const ValueKey('show-timer-message'),
                  label: cueReturnLabel,
                  showing: 'Message ${destinationPhrase()}',
                  sending: c.hardware.sending,
                  onPressed: outputControlsEnabled ? returnFromCue : null,
                )
              else
                stackedButton(
                  'Send message',
                  Icons.edit_note,
                  outputControlsEnabled ? sendStageMessage : null,
                ),
              practiceSpot(
                'blank',
                stackedButton(
                  s.outputBlank ? 'Unblank screen' : 'Blank screen',
                  s.outputBlank ? Icons.tv_outlined : Icons.tv_off_outlined,
                  (s.active || s.phase == 'ended') &&
                          !c.busy &&
                          !c.corrupt &&
                          !controlsLocked &&
                          c.pairing.localControl
                      ? confirmBlank
                      : null,
                  primary: s.outputBlank,
                ),
                radius: 12,
              ),
              stackedButton(
                'Quick timer',
                Icons.timer_outlined,
                quickTimerAvailable ? openQuickTimer : null,
              ),
            ],
          ),
          if (needsReturn) ...[
            const SizedBox(height: 12),
            button(
              returnLabel,
              Icons.timer_outlined,
              outputControlsEnabled ? returnToTimer : null,
              primary: true,
            ),
          ],
        ],
      ),
    );
    final showRundown = t != null && !c.reportSavePending;
    Widget rundownPanel() => panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label('Service rundown')),
              IconButton(
                key: const ValueKey('print-rundown'),
                tooltip: 'Print order of service',
                onPressed: controlsLocked ? null : () => printServiceSheet(t!),
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              if (s.active)
                TextButton.icon(
                  onPressed: enabled ? editUpcoming : null,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: keyLabel('Edit upcoming', 'E'),
                ),
              if (s.active)
                TextButton.icon(
                  onPressed: enabled ? recoverTime : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: keyLabel('Recover time', 'R'),
                ),
            ],
          ),
          if (s.targetFinishWall != null)
            Text(
              'Target finish ${clockLabel(s.targetFinishWall!)} · actual finish depends on manual advances',
            ),
          const SizedBox(height: 12),
          ...t!.segments.asMap().entries.map((e) {
            final current = e.key == s.index;
            return Column(
              children: [
                if (e.key > 0) const AppDivider(),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: current
                        ? appColors(context).accent.withValues(alpha: .14)
                        : null,
                    // Every row keeps the 4 px edge, clear when not
                    // current, so the numbers line up.
                    border: Border(
                      left: BorderSide(
                        color: current
                            ? appColors(context).accent
                            : Colors.transparent,
                        width: 4,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      key: ValueKey('rundown-${e.key}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: Text('${e.key + 1}'.padLeft(2, '0')),
                      title: Text(
                        e.value.name,
                        style: TextStyle(
                          fontWeight: current
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${e.value.durationText}${current ? ' · Now' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showSegmentDetails(e.key),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
    final liveNotices = <Widget>[
      if (controlsLocked)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            key: const ValueKey('controls-locked-banner'),
            color: appColors(context).surface,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.lock, color: appColors(context).warning),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Controls locked',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Semantics(
                    label: 'Hold to unlock controls',
                    child: OutlinedButton(
                      key: const ValueKey('unlock-controls'),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                deviceText(
                                  'Press and hold to unlock controls.',
                                ),
                              ),
                            ),
                          ),
                      onLongPress: () => refreshHome(
                        () => c.uiLocked = controlsLocked = false,
                      ),
                      child: const Text('Hold to unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (c.practice.active) practiceCoach(),
      if (!c.hardware.enabled &&
          c.displayConnection == DisplayConnection.disconnected &&
          (s.active || s.phase == 'ended'))
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            key: const ValueKey('display-disconnected-banner'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: appColors(context).surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.wifi_off, color: appColors(context).error),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Display disconnected',
                        style: TextStyle(
                          color: appColors(context).error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (c.hardware.enabled)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: hardwareStatusPanel(),
        ),
      if (c.destination == 'simulator' &&
          s.held &&
          (s.active || s.phase == 'ended'))
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Output paused after an interruption',
                  style: TextStyle(
                    color: appColors(context).warning,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${s.timeline!.name}\nLast activity: ${DateTime.fromMillisecondsSinceEpoch(s.checkpoint.wall).toLocal()}\n${s.uncertain ? 'Elapsed time is uncertain after a reboot or clock change. ' : ''}${s.phase == 'ended' ? 'The service has ended.' : 'The timer continues locally.'} Check the time, then resume to update the simulator.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    button(
                      s.phase == 'ended' ? 'Send end screen' : 'Resume output',
                      Icons.play_arrow,
                      c.busy ? null : () => c.act('release'),
                      primary: true,
                    ),
                    if (s.hasManualCue(c.now))
                      button(
                        'Dismiss alert & show timer',
                        Icons.timer,
                        c.busy ? null : () => c.act('releaseTimer'),
                      ),
                    button(
                      'Keep disconnected',
                      Icons.link_off,
                      c.busy ? null : () => c.act('disconnect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
    if (liveFillsWindow && standingBy) {
      return standingByDesktop(
        notices: liveNotices,
        header: timerHeader,
        start: timerPanelOf(wide: false),
        display: displayPanel,
        cues: cuePanel,
      );
    }
    if (liveFillsWindow) {
      // Keys is for a running service; Ready and a report still saving
      // use the panes, which have room for their forms.
      if (desktopLayout == 'keys' && s.active) {
        return keysLive(
          notices: liveNotices,
          header: timerHeader,
          endService: endServiceButton(compact: true),
          display: displayPanel,
          cues: cuePanel,
          enabled: enabled,
          canJump: canJump,
        );
      }
      final arrange = desktopLayout == 'mission_control'
          ? missionControlLive
          : threePaneLive;
      return arrange(
        notices: liveNotices,
        header: timerHeader,
        // Ready and a report still saving keep the card's own content.
        timer: s.active ? null : FlatPanels(child: timerPanelOf(wide: true)),
        endService: endServiceButton(compact: true),
        display: displayPanel,
        cues: cuePanel,
        enabled: enabled,
        canJump: canJump,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        // A very wide window has a column for the rundown.
        final threeColumns = constraints.maxWidth > classicUsualWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...liveNotices,
            if (focused) ...[
              stageRequestCards(),
              timerPanelOf(wide: true),
              const SizedBox(height: 16),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    displayPreviewHeader(
                      secondScreen:
                          secondScreenPreviewNow ==
                          SecondScreenPreviewPlace.replaces,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: c.destination == 'mobile'
                            ? mobileStagePreview()
                            : previewOrSecondScreen(displayPreview()),
                      ),
                    ),
                    ...secondScreenPreviewBeneath(maxWidth: 320),
                    const SizedBox(height: 8),
                    if (c.destination == 'mobile')
                      stageSharingControls()
                    else
                      Text(
                        s.outputBlank
                            ? 'Screen intentionally blanked'
                            : c.hardware.enabled
                            ? c.hardware.acceptedLabel
                            : 'Simulator · ${s.intended(c.now)?.text ?? 'No new output'}',
                      ),
                  ],
                ),
              ),
              if (s.active) ...[
                const SizedBox(height: 20),
                focusedTimingOverview(),
              ],
              const SizedBox(height: 16),
              cuePanel,
              if (c.destination == 'mobile') ...[
                const SizedBox(height: 20),
                quickMessagePanel(),
              ],
              if (showRundown) ...[const SizedBox(height: 20), rundownPanel()],
            ] else if (standingBy) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      timerPanelOf(wide: false),
                      practicePrompt(),
                      pinnedPrograms(),
                      if (c.state.reports.isNotEmpty) lastServiceCard(),
                      const SizedBox(height: 14),
                      panel(
                        padding: EdgeInsets.zero,
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            // Closed after End service, so the finished
                            // service's welcome card leads; it still opens
                            // with a tap. Before any service it opens when
                            // stage screens are in use.
                            key: ValueKey(
                              'stage-and-display-${c.pairing.hosting || c.destination == 'mobile'}-${c.state.session.phase == 'ended'}',
                            ),
                            initiallyExpanded:
                                c.state.session.phase != 'ended' &&
                                (c.pairing.hosting ||
                                    c.destination == 'mobile'),
                            leading: Icon(
                              connectionIcon(c.displayConnection),
                              color: appColors(context).accent,
                            ),
                            title: const Text(
                              'Stage & display',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${c.destinationName} · ${s.outputMode(c.now) == 'End screen' ? 'showing the end screen' : s.outputMode(c.now).toLowerCase()} · ${plural(c.state.stageCues.length, 'cue')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: appColors(context).muted,
                              ),
                            ),
                            childrenPadding: const EdgeInsets.only(bottom: 8),
                            // The sections draw flat, divided by lines,
                            // instead of as cards inside this card.
                            children: [
                              FlatPanels(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const AppDivider(),
                                    cuePanel,
                                    if (c.destination == 'mobile') ...[
                                      const AppDivider(),
                                      quickMessagePanel(),
                                    ],
                                    const AppDivider(),
                                    displayPanel,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (wide) ...[
              if (s.active) ...[
                timingStatusLine(bar: true),
                const SizedBox(height: 16),
              ],
              stageRequestCards(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: timerPanelOf(wide: true)),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        displayPanel,
                        const SizedBox(height: 16),
                        cuePanel,
                        if (c.destination == 'mobile') ...[
                          const SizedBox(height: 16),
                          quickMessagePanel(),
                        ],
                        if (showRundown && !threeColumns) ...[
                          const SizedBox(height: 16),
                          rundownPanel(),
                        ],
                      ],
                    ),
                  ),
                  if (showRundown && threeColumns) ...[
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: rundownPanel()),
                  ],
                ],
              ),
            ] else ...[
              stageRequestCards(),
              timerPanelOf(wide: false),
              const SizedBox(height: 16),
              cuePanel,
              if (c.destination == 'mobile') ...[
                const SizedBox(height: 16),
                quickMessagePanel(),
              ],
              const SizedBox(height: 16),
              displayPanel,
              if (showRundown) ...[const SizedBox(height: 16), rundownPanel()],
            ],
          ],
        );
      },
    );
  }
}
