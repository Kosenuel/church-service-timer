import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';

/// The Mission control desktop layout: a status strip, the timer, stage
/// and cues side by side, and the whole rundown as a timeline along the
/// bottom. Nothing scrolls during a normal service.
/// The height above the timeline from which Mission control's sections
/// grow to fill it.
const missionFillFromHeight = 900.0;

/// The window height from which the timeline's blocks are taller, with
/// the speaker and planned against actual time.
const missionRichTimelineFromHeight = 1200.0;

/// The height kept under a large dial for Pause, Next segment and the time
/// adjustments, or the Ready form in their place.
const missionControlsHeight = 165.0;

/// The widest Pause and Next segment are drawn beside a large dial.
const missionPrimaryButtonWidth = 360.0;

extension MissionControlLive on HomeState {
  Widget missionControlLive({
    required List<Widget> notices,
    required Widget header,
    required Widget? timer,
    required Widget endService,
    required Widget display,
    required Widget cues,
    required bool enabled,
    required bool canJump,
  }) {
    final colors = appColors(context);
    final s = c.liveSession;
    final line = finishRule(
      context,
      VerticalDivider(width: 1, thickness: 1, color: colors.border),
    );
    final rule = finishRule(
      context,
      Divider(height: 1, thickness: 1, color: colors.border),
    );
    // A finish floats each pane with a gap round it, which the timer's
    // size must leave out.
    final floating = finishLook(context).active;
    // A large window has height to spare for a fuller timeline.
    final richTimeline =
        (s.active || s.phase == 'ready') &&
        MediaQuery.sizeOf(context).height >= missionRichTimelineFromHeight;
    return Column(
      key: const ValueKey('mission-control-live'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ready has a strip of the same height, so the ring keeps its
        // place when the service starts.
        if (s.active) ...[
          FinishPane(
            strip: true,
            seams: finishSeamBelow,
            child: missionStatus(endService),
          ),
          rule,
        ],
        if (s.phase == 'ready') ...[
          FinishPane(
            strip: true,
            seams: finishSeamBelow,
            child: missionReadyStatus(),
          ),
          rule,
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, space) {
              // Ready leaves room for the keys line the running service
              // has along the bottom, so the ring keeps its size when the
              // service starts.
              final height =
                  space.maxHeight -
                  (showKeyHints && s.phase == 'ready' ? keyLegendHeight : 0);
              // The sections grow into a large window instead of leaving
              // a band above the timeline.
              final fill = timer == null && height >= missionFillFromHeight;
              final timerWidth = (space.maxWidth * (fill ? .4 : .37)).clamp(
                440.0,
                fill ? 1500.0 : 640.0,
              );
              final stageWidth = (space.maxWidth * (fill ? .29 : .3)).clamp(
                340.0,
                fill ? 1100.0 : 520.0,
              );
              // A tall window has room under the stage preview and the
              // cues for who is connected and what has happened.
              final tall = space.maxHeight >= 620;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: timerWidth,
                    child: FinishPane(
                      child: SingleChildScrollView(
                        key: const ValueKey('live-timer-pane'),
                        // Page Down is Next segment here, not a scroll key.
                        primary: false,
                        // A floating pane has its gap outside, so it takes
                        // less inside and the timer keeps the size it has in
                        // Flat.
                        padding: EdgeInsets.fromLTRB(
                          floating ? 20 - finishGapX : 20,
                          floating ? 2 : 8,
                          floating ? 20 - finishGapX : 20,
                          floating ? 2 : 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...notices,
                            timer ??
                                missionTimer(
                                  header: header,
                                  enabled: enabled,
                                  canJump: canJump,
                                  width: timerWidth - 40,
                                  height:
                                      height -
                                      (floating ? 2 * finishGapY + 4 : 16),
                                  fill: fill,
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  line,
                  SizedBox(
                    width: stageWidth,
                    child: FinishPane(
                      child: SingleChildScrollView(
                        key: const ValueKey('live-stage-pane'),
                        primary: false,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: FlatPanels(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (c.stageRequests.open.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    0,
                                  ),
                                  child: stageRequestCards(),
                                ),
                              display,
                              if (c.destination == 'mobile') ...[
                                const AppDivider(),
                                quickMessagePanel(),
                              ],
                              if (tall) ...[
                                const AppDivider(),
                                screensSection(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  line,
                  Expanded(
                    child: FinishPane(
                      child: SingleChildScrollView(
                        key: const ValueKey('live-cue-pane'),
                        primary: false,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: FlatPanels(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cues,
                              if (tall) ...[
                                const AppDivider(),
                                activitySection(latest: fill ? 24 : 8),
                              ],
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
        ),
        rule,
        FinishPane(
          flatSurface: true,
          strip: true,
          seams: finishSeamAbove,
          child: timelineStrip(enabled, rich: richTimeline),
        ),
        if (showKeyHints && s.active) ...[
          rule,
          KeyLegend(clicker: clickerKeysOn),
        ],
      ],
    );
  }

  Widget _sectionTitle(String text, {Widget? action}) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: appColors(context).muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      ?action,
    ],
  );

  /// The state of the output's connection, in a few words.
  String get displayStatusText => displayReconnecting
      ? 'Reconnecting…'
      : c.displayConnection == DisplayConnection.simulator
      ? 'no physical display'
      : c.displayConnection.label;

  /// The colour that goes with [displayStatusText].
  Color get displayStatusColour {
    final colors = appColors(context);
    if (displayReconnecting) return colors.warning;
    return switch (c.displayConnection) {
      DisplayConnection.disconnected ||
      DisplayConnection.stageDisconnected => colors.error,
      DisplayConnection.stageWaiting => colors.warning,
      DisplayConnection.simulator => colors.info,
      _ => colors.success,
    };
  }

  Widget _statusDot(Color colour) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
  );

  /// Where the output is going and which screens have joined.
  Widget screensSection() {
    final colors = appColors(context);
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    Widget row(String name, String status, Color dot) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _statusDot(dot),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Text(status, style: muted),
        ],
      ),
    );
    // Every device paired with this one while it is sharing, so a screen
    // that has dropped off stays listed instead of vanishing.
    final hub = c.pairing;
    final paired = hub.hosting ? hub.savedDevices : const <SavedPairDevice>[];
    Widget pairedRow(SavedPairDevice d) {
      final connected = hub.connectedDevice(d.id);
      final role = switch (d.role) {
        'stage' => 'Stage screen',
        'operator' => 'Operator',
        _ => 'Viewer',
      };
      // "Disconnected" is this device's own choice in Screens & devices;
      // "not answering" is a device that should be there and is not.
      final state = connected
          ? (hub.owner == d.id ? 'controls the service' : 'connected')
          : d.suspended
          ? 'disconnected'
          : 'not answering';
      return row(
        d.name,
        '$role · $state',
        connected
            ? colors.success
            : d.suspended
            ? colors.muted
            : colors.warning,
      );
    }

    // Screens the team opened in a browser. People following the order of
    // service on their phones are counted, not listed.
    final web = c.webStage.activeDevices;
    final team = web.where((d) => d.team).toList();
    final following = web.length - team.length;
    return Padding(
      key: const ValueKey('screens-section'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'Screens & sign',
            action: TextButton(
              onPressed: controlsLocked
                  ? null
                  : () => openSettingsDetail(
                      'Screens & devices',
                      pairedDeviceSettings,
                    ),
              child: const Text('Manage'),
            ),
          ),
          row(
            'Showing on ${c.destinationName}',
            displayStatusText,
            displayStatusColour,
          ),
          for (final d in paired) pairedRow(d),
          for (final d in team)
            row(
              d.label.isEmpty ? 'Web screen' : d.label,
              'Web · ${d.role.label.toLowerCase()}',
              colors.success,
            ),
          if (following > 0)
            row(
              'Order of service on the web',
              following == 1 ? '1 person following' : '$following following',
              colors.success,
            ),
          if (paired.isEmpty && web.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('No stage screens have joined.', style: muted),
            ),
        ],
      ),
    );
  }

  /// Stage screens showing the output now: paired ones and web ones.
  int get stageScreensConnected =>
      c.pairing.stagePeers.length +
      c.webStage.activeDevices.where((d) => d.role == WebRole.stage).length;

  /// Where the output is going, how many stage screens have joined and
  /// whether the controls are locked, in one line for the Keys layout.
  String get liveStatusText {
    final screens = stageScreensConnected;
    return [
      '${c.destinationName} · $displayStatusText',
      if (screens > 0) plural(screens, 'stage screen'),
      if (controlsLocked) 'Controls locked',
    ].join('   ·   ');
  }

  /// The latest entries of the service's activity, newest first; the
  /// report keeps them all.
  Widget activitySection({int latest = 8}) {
    final colors = appColors(context);
    final events = c.liveSession.events.reversed.take(latest).toList();
    final muted = TextStyle(
      color: colors.muted,
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      key: const ValueKey('activity-section'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Activity'),
          const SizedBox(height: 6),
          if (events.isEmpty)
            Text(
              'Nothing yet.',
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(clockLabel(e.wall), style: muted),
                  ),
                  Expanded(
                    child: Text(
                      e.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// How the service is running, in one line across the top.
  Widget missionStatus(Widget endService) {
    final colors = appColors(context);
    final s = c.liveSession, run = s.run;
    final projected = s.projectedTotal(c.now);
    final variance = projected - s.plannedMs;
    Widget figure(String label, String value, {Color? color, Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(right: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: colors.muted)),
              Text(
                value,
                key: key,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
    return Padding(
      key: const ValueKey('mission-status'),
      padding: const EdgeInsets.fromLTRB(20, 7, 16, 7),
      child: Row(
        children: [
          if (run != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Text(
                varianceLabel(variance),
                key: const ValueKey('rundown-variance'),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: variance > 999 ? colors.warning : colors.success,
                ),
              ),
            ),
            figure('Now', clockLabel(c.now.wall)),
            figure('Elapsed', durationLabel(s.totalElapsed(c.now))),
            figure(
              'Planned finish',
              clockLabel(run.startedWall + (s.plannedMs / s.rate).round()),
            ),
            figure(
              s.paused ? 'Ending, if resumed now' : 'Now ending',
              clockLabel(
                c.now.wall +
                    ((projected - s.totalElapsed(c.now)) / s.rate).round(),
              ),
              color: variance > 999 ? colors.warning : null,
              key: const ValueKey('rundown-finish'),
            ),
            if (s.targetFinishWall != null)
              figure('Target finish', clockLabel(s.targetFinishWall!)),
          ],
          const Spacer(),
          endService,
        ],
      ),
    );
  }

  /// The strip across the top in Ready: the readiness row, timing has not
  /// started, and the buttons to start, cancel or check the service where End service
  /// goes once it runs.
  Widget missionReadyStatus() => Padding(
    key: const ValueKey('mission-ready-status'),
    padding: const EdgeInsets.fromLTRB(20, 7, 16, 7),
    child: Row(
      children: [
        Text(
          'Ready',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: appColors(context).accent,
          ),
        ),
        const SizedBox(width: 28),
        // The readiness row, where the figures go once the service runs.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: readyInline(),
        ),
        const SizedBox(width: 16),
        Expanded(child: readyNotStartedLine(compact: true)),
        const SizedBox(width: 16),
        readyButtons(compact: true, height: 44),
      ],
    ),
  );

  /// The running segment: name, the dial beside its figures, the controls.
  /// In Ready the same dial shows the first segment's full time, with the
  /// Ready form where the controls go.
  Widget missionTimer({
    required Widget header,
    required bool enabled,
    required bool canJump,
    required double width,
    required double height,
    bool fill = false,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final segment = t.segments[s.index];
    Segment? later(int steps) => s.index + steps < t.segments.length
        ? t.segments[s.index + steps]
        : null;
    final next = later(1), then = later(2);
    // The dial takes the height the title and controls leave.
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    // With large text the controls stack and need more of the height.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18
        ? 190.0
        : 0.0;
    final gauge = fill
        // A large window: the dial has the height the title, the controls
        // and the note leave, and the facts keep a column beside it.
        ? math
              .min(width - 290, (height - 350 * scale - stacked) * 300 / 250)
              .clamp(232.0, 1000.0)
        // Otherwise it has what the title above and the controls, or the
        // Ready form, under it leave, beside a column for the facts.
        : math
              .min(width - 196, (height - 285 * scale - stacked) * 300 / 260)
              .clamp(232.0, 640.0);
    // In a short window the private note sits beside the dial.
    final noteBelow = height - (gauge * 260 / 300) > 360;
    // The facts beside a large dial are larger too.
    final big = fill && gauge >= 480;
    final muted = TextStyle(color: colors.muted, fontSize: big ? 15 : 13);
    Widget fact(String label, String value) => Padding(
      padding: EdgeInsets.only(bottom: big ? 12 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: (big ? 84 : 68) * scale,
            child: Text(label, style: muted),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: big ? 16 : 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    Widget note({int? lines}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Private note', style: muted.copyWith(fontSize: 12)),
        const SizedBox(height: 2),
        Tooltip(
          message: segment.notes,
          child: Text(
            segment.notes,
            key: const ValueKey('desktop-private-note'),
            maxLines: lines,
            overflow: lines == null ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
    final title = Align(
      alignment: Alignment.centerLeft,
      child: segmentTitle(canJump, size: big ? 38 : 30, centred: false),
    );
    final ready = s.phase == 'ready';
    // A short window has no room under the dial for the whole Ready form:
    // the program and the service mode take the place of the facts beside
    // it, and the pre-service countdown is under it.
    final formBeside =
        ready && !fill && MediaQuery.sizeOf(context).height < 760;
    final controls = !ready
        ? liveControls(enabled)
        : formBeside
        ? preServiceRow(compact: true)
        : readyControls(compact: true, buttons: false, inline: false);
    final dial = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: gauge,
          child: SegmentGauge(
            session: s,
            now: c.now,
            maxWidth: gauge,
            noticeInside: fill,
          ),
        ),
        SizedBox(width: big ? 28 : 16),
        if (formBeside)
          Expanded(
            child: Column(
              key: const ValueKey('ready-controls'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                readyProgramRow(t, narrow: true),
                const SizedBox(height: 10),
                readyModeField(compact: true),
              ],
            ),
          )
        else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                fact('Allocated', formatTime(s.allocatedMs)),
                fact(
                  'Used',
                  formatTime(math.max(0, s.allocatedMs - s.balance(c.now))),
                ),
                if (segment.speaker.isNotEmpty)
                  fact('Speaker', segment.speaker),
                if (!s.quickTimer)
                  fact(
                    'Next',
                    next == null
                        ? 'Final segment'
                        : '${next.name} · ${next.durationText}',
                  ),
                if (then != null)
                  fact('Then', '${then.name} · ${then.durationText}'),
                if (segment.notes.isNotEmpty && !noteBelow) ...[
                  const SizedBox(height: 2),
                  note(lines: 3),
                ],
              ],
            ),
          ),
      ],
    );
    final noteUnder = [
      if (segment.notes.isNotEmpty && noteBelow) ...[
        const SizedBox(height: 16),
        const AppDivider(indent: 0, endIndent: 0),
        const SizedBox(height: 12),
        note(),
      ],
    ];
    if (fill) {
      // Title at the top; the dial with its controls straight under it in
      // the middle of what is left. Pause and Next segment keep to a width
      // that still reads as a button.
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: math.max(0, height)),
        child: Column(
          key: const ValueKey('timer-card-content'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, title],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dial,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      // A quick timer has Pause alone.
                      maxWidth: s.quickTimer
                          ? missionPrimaryButtonWidth + 120
                          : missionPrimaryButtonWidth * 2 + 8,
                      // The Ready form and the controls take the same
                      // height, so the dial keeps its place when the
                      // service starts.
                      minHeight: missionControlsHeight * scale,
                    ),
                    child: controls,
                  ),
                ),
                ...noteUnder,
              ],
            ),
            const SizedBox(),
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('timer-card-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, title, dial, controls, ...noteUnder],
    );
  }

  /// The rundown as a timeline, with the planning actions above it.
  Widget timelineStrip(bool enabled, {bool rich = false}) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final small = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
    );
    return Padding(
      key: const ValueKey('timeline-strip'),
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // As tall in Ready, without the planning buttons, as while the
          // service runs, so the sections above keep their size.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Text(
                  'Rundown',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                if (s.active) ...[
                  _swatch(colors.warning.withValues(alpha: .45)),
                  Text(
                    '  Ran over',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
                const Spacer(),
                if (s.active) ...[
                  OutlinedButton.icon(
                    style: small,
                    onPressed: enabled ? editUpcoming : null,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                    label: keyLabel('Edit upcoming', 'E'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: small,
                    onPressed: enabled ? recoverTime : null,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                    label: keyLabel('Recover time', 'R'),
                  ),
                ],
                IconButton(
                  key: const ValueKey('print-rundown'),
                  tooltip: 'Print order of service',
                  visualDensity: VisualDensity.compact,
                  onPressed: controlsLocked ? null : () => printServiceSheet(t),
                  icon: const Icon(Icons.print_outlined, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          RundownTimeline(
            session: s,
            now: c.now,
            onSegment: showSegmentDetails,
            rich: rich,
          ),
        ],
      ),
    );
  }

  Widget _swatch(Color color) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

/// One piece of the timeline: where a segment starts and how long it is,
/// in service time.
class TimelinePiece {
  final int index, startMs, lengthMs;

  /// Planned length, to mark how much of a finished segment ran over.
  final int plannedMs;
  const TimelinePiece(this.index, this.startMs, this.lengthMs, this.plannedMs);
}

/// Lays the service out end to end: finished segments at the time they
/// really took, the running one at its allocation (or longer, in overtime)
/// and the rest as planned. Skipped segments take no room.
List<TimelinePiece> timelinePieces(Session s, Stamp now) {
  final t = s.timeline!, run = s.run;
  final pieces = <TimelinePiece>[];
  var at = 0;
  for (var i = 0; i < t.segments.length; i++) {
    final planned = t.segments[i].durationMs;
    int length;
    if (run != null && run.skipped.contains(i)) {
      continue;
    } else if (i < s.index && s.phase != 'ready') {
      length = run != null && i < run.actualMs.length
          ? run.actualMs[i] ?? planned
          : planned;
    } else if (i == s.index && s.active) {
      length = math.max(s.allocatedMs, s.currentElapsed(now));
    } else {
      length = planned;
    }
    pieces.add(TimelinePiece(i, at, length, planned));
    at += length;
  }
  return pieces;
}

/// The whole service as a row of blocks sized by time, with a marker at
/// now and clock times underneath.
class RundownTimeline extends StatelessWidget {
  final Session session;
  final Stamp now;
  final ValueChanged<int> onSegment;

  /// Taller blocks that also name the speaker and give planned against
  /// actual time, for a window with height to spare.
  final bool rich;
  const RundownTimeline({
    super.key,
    required this.session,
    required this.now,
    required this.onSegment,
    this.rich = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final s = session, t = s.timeline!, run = s.run;
    final pieces = timelinePieces(s, now);
    final total = math.max(
      1,
      pieces.fold<int>(0, (n, p) => math.max(n, p.startMs + p.lengthMs)),
    );
    final running = s.active && run != null;
    final elapsed = running ? s.totalElapsed(now) : 0;
    final small = TextStyle(
      fontSize: 11,
      color: colors.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, space) {
        final w = space.maxWidth;
        double x(int ms) => ms / total * w;
        final plannedEnd = x(s.plannedMs);
        // Two lines of text in each block and one under it: taller with
        // large system text, so nothing is cut off.
        final scaler = MediaQuery.textScalerOf(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: rich ? scaler.scale(88) + 30 : scaler.scale(31) + 19,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final p in pieces)
                    Positioned(
                      left: x(p.startMs),
                      width: math.max(4, x(p.lengthMs) - 3),
                      top: 0,
                      bottom: 0,
                      child: _block(context, p),
                    ),
                  if (running)
                    Positioned(
                      key: const ValueKey('timeline-now'),
                      left: (x(elapsed) - 1).clamp(0, w - 2),
                      top: -4,
                      bottom: -4,
                      width: 2,
                      child: ColoredBox(color: colors.text),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: scaler.scale(13) + 3,
              child: run == null || s.phase == 'ready'
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${t.segments.length} segments · ${durationLabel(s.plannedMs)} planned',
                        style: small,
                      ),
                    )
                  : TimelineClockScale(
                      startedWall: run.startedWall,
                      totalMs: total,
                      rate: s.rate,
                      width: w,
                      trailing:
                          'plan ${clockLabel(run.startedWall + (s.plannedMs / s.rate).round())}${plannedEnd < w - 1 ? ' · ends ${clockLabel(run.startedWall + (total / s.rate).round())}' : ''}',
                      trailingKey: const ValueKey('timeline-ends'),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _block(BuildContext context, TimelinePiece p) {
    final colors = appColors(context);
    final s = session, segment = s.timeline!.segments[p.index];
    final current = p.index == s.index && s.active;
    final done = p.index < s.index && s.phase != 'ready';
    final over = done ? p.lengthMs - p.plannedMs : 0;
    final doneFill = timelineDoneFill(colors);
    final String detail;
    // The richer block: what was planned, then how it went or will go.
    final String outcome;
    if (current) {
      final balance = s.balance(now);
      detail =
          '${operatorTime(balance)} ${balance < 0 ? 'over' : 'left'} of ${formatTime(s.allocatedMs)}';
      outcome = '${operatorTime(balance)} ${balance < 0 ? 'over' : 'left'}';
    } else if (done) {
      detail = '${formatTime(p.lengthMs)} · ${signedTime(over)}';
      outcome = 'Took ${formatTime(p.lengthMs)} · ${signedTime(over)}';
    } else {
      detail = segment.durationText;
      final run = s.run;
      outcome = run == null || !s.active
          ? ''
          : 'Starts about ${clockLabel(run.startedWall + (p.startMs / s.rate).round())}';
    }
    return TimelineBlock(
      inkKey: ValueKey('timeline-${p.index}'),
      name: segment.name,
      detail: detail,
      more: rich
          ? [
              segment.speaker,
              'Planned ${formatTime(current ? s.allocatedMs : p.plannedMs)}',
              outcome,
            ]
          : null,
      outcomeColour: done && over > 30000
          ? colors.warning
          : done && over < 0
          ? colors.success
          : null,
      fill: done ? doneFill : null,
      border: current
          ? colors.accent
          : done
          ? Colors.transparent
          : colors.border,
      strong: current,
      // How far the running segment has got.
      progress: current
          ? (s.currentElapsed(now) / math.max(1, p.lengthMs)).clamp(0.0, 1.0)
          : null,
      over: over > 0 ? (over / math.max(1, p.lengthMs)).clamp(0.0, 1.0) : 0,
      onTap: () => onSegment(p.index),
    );
  }
}

/// Clock times every 5, 10, 15, 30 or 60 minutes, whichever keeps them
/// about 110 px apart on a timeline [width] wide.
int timelineClockStep(double minutes, double width) => const [
  5,
  10,
  15,
  30,
  60,
].firstWhere((m) => minutes / m * 110 <= width, orElse: () => 120);

/// The fill of a finished block on a timeline.
Color timelineDoneFill(AppPalette colors) =>
    Color.alphaBlend(colors.accent.withValues(alpha: .16), colors.surface);

/// Clock times under a timeline that started at [startedWall] and covers
/// [totalMs] of service time, with a note at the right-hand end.
class TimelineClockScale extends StatelessWidget {
  final int startedWall, totalMs, rate;
  final double width;
  final String trailing;
  final Key? trailingKey;
  const TimelineClockScale({
    super.key,
    required this.startedWall,
    required this.totalMs,
    required this.rate,
    required this.width,
    required this.trailing,
    this.trailingKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final small = TextStyle(
      fontSize: 11,
      color: colors.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    double x(int ms) => ms / totalMs * width;
    final step = timelineClockStep(totalMs / rate / 60000, width);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var m = 0; x(m * 60000 * rate) < width - 150; m += step)
          Positioned(
            left: x(m * 60000 * rate),
            child: Container(
              padding: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: colors.border)),
              ),
              child: Text(clockLabel(startedWall + m * 60000), style: small),
            ),
          ),
        Positioned(
          right: 0,
          child: Text(trailing, key: trailingKey, style: small),
        ),
      ],
    );
  }
}

/// One block of a timeline: a name over a line of figures, optionally
/// part-filled to show progress and marked where it ran over.
class TimelineBlock extends StatelessWidget {
  final String name, detail;
  final Color? fill;
  final Color border;

  /// The running segment: a heavier outline and name.
  final bool strong;

  /// How much of the block is filled from the left, 0 to 1.
  final double? progress;

  /// The share at the right-hand end that is past the planned time.
  final double over;
  final VoidCallback? onTap;
  final Key? inkKey;

  /// A taller block: the speaker, the planned time and how it went, each
  /// on its own line under the name, in place of [detail].
  final List<String>? more;

  /// The colour of the last of [more], when it ran over or under.
  final Color? outcomeColour;
  const TimelineBlock({
    super.key,
    required this.name,
    required this.detail,
    required this.border,
    this.fill,
    this.strong = false,
    this.progress,
    this.over = 0,
    this.onTap,
    this.inkKey,
    this.more,
    this.outcomeColour,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final more = this.more;
    Widget line(String text, {Color? colour, bool strong = false}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontSize: 12,
        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        color: colour ?? colors.muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: '$name, $detail',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: inkKey,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: border, width: strong ? 1.5 : 1),
            ),
            child: Stack(
              children: [
                if (progress != null)
                  FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: ColoredBox(
                      color: colors.accent.withValues(alpha: .22),
                    ),
                  ),
                // The part past the planned time.
                if (over > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: over,
                      heightFactor: 1,
                      child: ColoredBox(
                        color: colors.warning.withValues(alpha: .45),
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, box) {
                    // A short segment's block is narrow. It keeps what
                    // can be read in it: the full lines, then the name
                    // with the short detail, then the name alone.
                    final scale =
                        MediaQuery.textScalerOf(context).scale(100) / 100;
                    final roomy = box.maxWidth >= 128 * scale;
                    final tight = box.maxWidth < 64 * scale;
                    final rich = more != null && !tight;
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: rich && roomy ? 10 : 7,
                        vertical: more == null ? 6 : 9,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: rich && roomy ? 15 : 12,
                              fontWeight: strong
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                          if (more != null && tight)
                            const SizedBox()
                          else if (more != null && !roomy) ...[
                            const Spacer(),
                            line(
                              detail,
                              colour:
                                  outcomeColour ??
                                  (strong ? colors.text : null),
                              strong: strong || outcomeColour != null,
                            ),
                          ] else if (more != null) ...[
                            line(more[0]),
                            const Spacer(),
                            line(more[1]),
                            line(
                              more[2],
                              colour:
                                  outcomeColour ??
                                  (strong ? colors.text : null),
                              strong: strong || outcomeColour != null,
                            ),
                          ] else
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One key in [KeyLegend]: the keys, what they do, and how much the
/// operator needs to see it (0 most) when there is not room for all.
typedef KeyLegendEntry = ({String keys, String action, int rank});

/// The keys that work on Live, along the bottom of the window: Mission
/// control and Keys, and the middle pane of Three panes and The dial
/// wherever the ring has room for it. It keeps to one line: when the keys are wider than the
/// room, the least needed ones are left out rather than wrapped.
class KeyLegend extends StatelessWidget {
  /// Whether to list the keys at all. Off, only [status] shows.
  final bool keys;

  /// Also lists the number keys that send cues.
  final bool cues;

  /// Ends with the reminder that timer changes ask first, room allowing.
  final bool reminder;

  /// Also lists Space and Page Down, which follow Clicker and foot pedal.
  final bool clicker;

  /// A status line at the right, after a dot in [statusColour]. It keeps
  /// to one line, and when the two do not both fit it takes the place of
  /// the reminder about confirming.
  final String? status;
  final Color? statusColour;
  const KeyLegend({
    super.key,
    this.keys = true,
    this.cues = true,
    this.reminder = true,
    this.clicker = true,
    this.status,
    this.statusColour,
  });

  static const _reminder = 'Timer changes ask to confirm';

  /// Every entry, in the order they show.
  static List<KeyLegendEntry> entries({
    bool cues = true,
    bool clicker = true,
  }) => [
    if (clicker) (keys: 'Space', action: 'Pause', rank: 0),
    if (clicker) (keys: 'PgDn PgDn', action: 'Next', rank: 1),
    (keys: '+ −', action: 'Adjust time', rank: 2),
    (keys: 'Ctrl Z', action: 'Undo', rank: 4),
    (keys: 'J', action: 'Jump to segment', rank: 5),
    if (cues) (keys: '1 – 9', action: 'Cues', rank: 6),
    (keys: 'M', action: 'Message', rank: 7),
    (keys: 'Ctrl L', action: 'Lock', rank: 3),
    // The two that show how to find the rest: always last, never dropped.
    (keys: '?', action: 'Keys', rank: pinnedRank),
    (keys: 'Ctrl K', action: 'Commands', rank: pinnedRank),
  ];

  /// The rank of an entry that stays however narrow the line is.
  static const pinnedRank = 100;

  /// Space after each entry.
  static const _gap = 22.0;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final style = TextStyle(fontSize: 12, color: colors.muted);
    TextSpan span(KeyLegendEntry e) => TextSpan(
      children: [
        TextSpan(
          text: e.keys,
          style: TextStyle(
            color: colors.text,
            fontWeight: FontWeight.w600,
            letterSpacing: .3,
          ),
        ),
        TextSpan(text: '  ${e.action}'),
      ],
    );
    Widget item(KeyLegendEntry e) => Padding(
      padding: const EdgeInsets.only(right: _gap),
      child: Text.rich(span(e), maxLines: 1, softWrap: false, style: style),
    );
    double measure(InlineSpan text) {
      final painter = TextPainter(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.merge(style),
          children: [text],
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    double width(String text) => measure(TextSpan(text: text));

    // A strip of the surface in Flat; with a finish a strip of its material,
    // or, at the foot of a panel, part of that panel.
    final finished = finishLook(context).active;
    final onPanel = finished && FinishOnPanel.of(context);
    Widget plate(Widget child) => finished && !onPanel
        ? FinishSurface(
            key: const ValueKey('key-legend'),
            pane: true,
            child: child,
          )
        : KeyedSubtree(key: const ValueKey('key-legend'), child: child);
    return plate(
      Container(
        color: finished ? null : colors.surface,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: LayoutBuilder(
          builder: (context, box) {
            // What the keys leave room for: the reminder, or enough of the
            // status line to read.
            final reminderRoom = reminder ? 24 + width(_reminder) + 2 : 0.0;
            final statusRoom = status == null
                ? 0.0
                : 16 + math.min(width(status!), 220.0) + 2;
            var shown = keys
                ? entries(cues: cues, clicker: clicker)
                : <KeyLegendEntry>[];
            double keysWidth() =>
                shown.fold(0.0, (sum, e) => sum + measure(span(e)) + _gap);
            // Too many keys for the room: the reminder goes first, then
            // the least needed keys.
            final withReminder =
                reminder &&
                status == null &&
                keysWidth() + reminderRoom <= box.maxWidth;
            final room =
                box.maxWidth - (withReminder ? reminderRoom : statusRoom);
            while (keysWidth() > room) {
              final droppable = shown.where((e) => e.rank < pinnedRank);
              if (droppable.isEmpty) break;
              final least = droppable.reduce((a, b) => a.rank > b.rank ? a : b);
              shown = [...shown]..remove(least);
            }
            return Row(
              children: [
                for (final e in shown) item(e),
                if (status == null) ...[
                  const Spacer(),
                  if (withReminder) Text(_reminder, style: style),
                ] else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, space) {
                        // The dot and its gap, the status, then the reminder.
                        final both =
                            reminder &&
                            16 + width(status!) + reminderRoom <=
                                space.maxWidth;
                        return Row(
                          mainAxisAlignment: keys
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Row(
                                key: const ValueKey('live-status-line'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColour ?? colors.muted,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      status!,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: style,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (keys && both) ...[
                              const SizedBox(width: 24),
                              Text(_reminder, style: style),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
