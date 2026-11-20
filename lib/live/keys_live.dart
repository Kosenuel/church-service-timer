import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The Keys desktop layout: dense, and made to be run from the keyboard.
/// The running segment and its controls are one strip across the top; the
/// rundown is a table with every figure in a column; the stage preview and
/// cues sit beside it, and the keys are listed along the bottom.
extension KeysLive on HomeState {
  Widget keysLive({
    required List<Widget> notices,
    required Widget header,
    required Widget endService,
    required Widget display,
    required Widget cues,
    required bool enabled,
    required bool canJump,
  }) {
    final colors = appColors(context);
    final line = VerticalDivider(width: 1, thickness: 1, color: colors.border);
    final rule = Divider(height: 1, thickness: 1, color: colors.border);
    return Column(
      key: const ValueKey('keys-live'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: notices,
            ),
          ),
        ColoredBox(
          color: colors.surface,
          child: nowStrip(header: header, enabled: enabled, canJump: canJump),
        ),
        rule,
        Expanded(
          child: LayoutBuilder(
            builder: (context, space) {
              final stage = (space.maxWidth * .22).clamp(318.0, 420.0);
              final cuePane = (space.maxWidth * .24).clamp(320.0, 460.0);
              // A tall window has room for who is connected and what has
              // happened, as in Mission control.
              final tall = space.maxHeight >= 620;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: rundownTable(enabled, endService)),
                  line,
                  SizedBox(
                    width: stage,
                    child: ColoredBox(
                      color: colors.surface,
                      child: SingleChildScrollView(
                        key: const ValueKey('live-stage-pane'),
                        // Page Down is Next segment here, not a scroll key.
                        primary: false,
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
                  SizedBox(
                    width: cuePane,
                    child: ColoredBox(
                      color: colors.surface,
                      child: SingleChildScrollView(
                        key: const ValueKey('live-cue-pane'),
                        primary: false,
                        child: FlatPanels(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cues,
                              if (tall) ...[
                                const AppDivider(),
                                activitySection(),
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
        KeyLegend(
          keys: showKeyHints,
          clicker: clickerKeysOn,
          status: liveStatusText,
          statusColour: displayStatusColour,
        ),
      ],
    );
  }

  /// The running segment in one line: name, countdown, how the service is
  /// doing, and the timer controls.
  Widget nowStrip({
    required Widget header,
    required bool enabled,
    required bool canJump,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!, run = s.run;
    final segment = t.segments[s.index];
    final next = s.index + 1 < t.segments.length
        ? t.segments[s.index + 1]
        : null;
    final balance = s.balance(c.now);
    final warning = s.nearWarning(c.now);
    final expired = balance < 0 || balance == 0;
    final clockColour = expired
        ? colors.error
        : warning
        ? colors.warning
        : colors.text;
    final projected = s.projectedTotal(c.now);
    final variance = projected - s.plannedMs;
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    return Padding(
      key: const ValueKey('now-strip'),
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  key: const ValueKey('timer-card-content'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    segmentTitle(canJump, size: 28, centred: false),
                    const SizedBox(height: 2),
                    if (!s.quickTimer)
                      Text(
                        [
                          if (segment.speaker.isNotEmpty) segment.speaker,
                          next == null
                              ? 'Final segment'
                              : 'Next · ${next.name} · ${next.durationText}',
                        ].join('   ·   '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Semantics(
                label:
                    '${operatorTimeDescription(balance)}, ${formatTime(s.allocatedMs)} allocated',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      operatorTime(balance),
                      key: const ValueKey('operator-clock'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 84,
                        fontWeight: FontWeight.w300,
                        height: 1,
                        letterSpacing: -2.5,
                        color: clockColour,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      balance < 0
                          ? 'over · ${formatTime(s.allocatedMs)} allocated'
                          : 'left of ${formatTime(s.allocatedMs)}',
                      key: const ValueKey('allocated-time'),
                      style: muted.copyWith(
                        color: balance < 0 ? colors.error : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              if (run != null)
                SizedBox(
                  width: 176,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        varianceLabel(variance),
                        key: const ValueKey('rundown-variance'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: variance > 999
                              ? colors.warning
                              : colors.success,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ends ${clockLabel(c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round())}${s.paused ? ' if resumed now' : ''}',
                        key: const ValueKey('rundown-finish'),
                        style: muted,
                      ),
                      Text(
                        'Plan ${clockLabel(run.startedWall + (s.plannedMs / s.rate).round())} · ${durationLabel(s.totalElapsed(c.now))} in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 20),
              SizedBox(width: 408, child: liveControls(enabled)),
            ],
          ),
          const SizedBox(height: 10),
          ServiceProgressBar(
            durations: [for (final e in t.segments) e.durationMs],
            index: s.index,
            progress:
                1 -
                (s.remaining(c.now) / math.max(1, s.allocatedMs)).clamp(
                  0.0,
                  1.0,
                ),
          ),
        ],
      ),
    );
  }

  /// The rundown with every figure in its own column, then the planning
  /// actions, End service and the private note.
  Widget rundownTable(bool enabled, Widget endService) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!, run = s.run;
    final segment = t.segments[s.index];
    final figures = const [FontFeature.tabularFigures()];
    final head = TextStyle(
      color: colors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    // When each segment began, or would begin if the rest keep to plan.
    final starts = <int, int>{};
    if (run != null) {
      var at = run.startedWall.toDouble();
      for (var i = 0; i <= s.index && i < t.segments.length; i++) {
        starts[i] = at.round();
        if (i < s.index && !run.skipped.contains(i)) {
          at += (run.actualMs[i] ?? 0) / s.rate;
        }
      }
    }
    var ahead = s.remaining(c.now);
    for (var i = s.index + 1; i < t.segments.length; i++) {
      starts[i] = c.now.wall + (ahead / s.rate).round();
      ahead += t.segments[i].durationMs;
    }
    Widget cell(
      Widget child, {
      double? width,
      int flex = 0,
      bool right = false,
    }) {
      // A little air between a name and the column after it.
      final box = Padding(
        padding: EdgeInsets.only(right: right ? 0 : 10),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      );
      return width != null
          ? SizedBox(width: width, child: box)
          : Expanded(flex: flex, child: box);
    }

    Widget row(List<Widget> cells) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: cells),
    );
    Text text(String value, {TextStyle? style}) =>
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Column(
      key: const ValueKey('rundown-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: row([
            cell(text('#', style: head), width: 34),
            cell(text('Segment', style: head), flex: 5),
            cell(text('Speaker', style: head), flex: 4),
            cell(text('Planned', style: head), width: 64, right: true),
            cell(text('Start', style: head), width: 62, right: true),
            cell(text('Actual', style: head), width: 96, right: true),
            cell(text('±', style: head), width: 56, right: true),
            const SizedBox(width: 14),
            cell(text('State', style: head), width: 78),
          ]),
        ),
        Divider(height: 1, color: colors.border),
        Flexible(
          child: ListView.separated(
            primary: false,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: t.segments.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: colors.border),
            itemBuilder: (context, i) {
              final item = t.segments[i];
              final current = i == s.index;
              final done = i < s.index;
              final skipped = run != null && run.skipped.contains(i);
              final actual = done && !skipped && run != null
                  ? run.actualMs[i]
                  : null;
              final diff = actual == null ? null : actual - item.durationMs;
              final base = TextStyle(
                fontSize: 13,
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                color: done ? colors.muted : null,
                fontFeatures: figures,
              );
              final start = starts[i];
              return Material(
                color: current
                    ? colors.accent.withValues(alpha: .1)
                    : Colors.transparent,
                child: InkWell(
                  key: ValueKey('rundown-$i'),
                  onTap: () => showSegmentDetails(i),
                  child: SizedBox(
                    height: appLayout(context).density == 'spacious' ? 46 : 38,
                    child: row([
                      cell(text('${i + 1}', style: base), width: 34),
                      cell(text(item.name, style: base), flex: 5),
                      cell(text(item.speaker, style: base), flex: 4),
                      cell(
                        text(formatTime(item.durationMs), style: base),
                        width: 64,
                        right: true,
                      ),
                      cell(
                        text(
                          start == null || skipped
                              ? '—'
                              : '${i > s.index ? '~' : ''}${clockLabel(start)}',
                          style: base,
                        ),
                        width: 62,
                        right: true,
                      ),
                      cell(
                        text(
                          current
                              ? '${formatTime(s.currentElapsed(c.now))} so far'
                              : actual == null
                              ? '—'
                              : formatTime(actual),
                          style: base,
                        ),
                        width: 96,
                        right: true,
                      ),
                      cell(
                        text(
                          diff == null ? '—' : signedTime(diff),
                          style: base.copyWith(
                            color: diff == null
                                ? null
                                : diff > 30000
                                ? colors.warning
                                : diff < 0
                                ? colors.success
                                : null,
                          ),
                        ),
                        width: 56,
                        right: true,
                      ),
                      const SizedBox(width: 14),
                      cell(
                        text(
                          skipped
                              ? 'Skipped'
                              : done
                              ? 'Done'
                              : current
                              ? (s.paused ? 'Paused' : 'Running')
                              : i == s.index + 1
                              ? 'Next'
                              : 'Upcoming',
                          style: base,
                        ),
                        width: 78,
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        Divider(height: 1, color: colors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
          child: Row(
            children: [
              // One line when there is room. In a narrow window, such as
              // 1200 wide, the rundown is too narrow for all of them beside
              // End service, so Recover time and Print go under Edit
              // upcoming.
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: enabled ? editUpcoming : null,
                      icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                      label: keyLabel('Edit upcoming', 'E'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: enabled ? recoverTime : null,
                          icon: const Icon(
                            Icons.auto_fix_high_outlined,
                            size: 18,
                          ),
                          label: keyLabel('Recover time', 'R'),
                        ),
                        IconButton(
                          key: const ValueKey('print-rundown'),
                          tooltip: 'Print order of service',
                          onPressed: controlsLocked
                              ? null
                              : () => printServiceSheet(t),
                          icon: const Icon(Icons.print_outlined, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              endService,
            ],
          ),
        ),
        if (segment.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Private note · ${segment.name}', style: head),
                const SizedBox(height: 3),
                Tooltip(
                  message: segment.notes,
                  child: Text(
                    segment.notes,
                    key: const ValueKey('desktop-private-note'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
