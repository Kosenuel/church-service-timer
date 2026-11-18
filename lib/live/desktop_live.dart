import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// Live in a wide window: the desktop layouts chosen in Settings ›
/// Appearance. They arrange the same timer, cues, stage preview and rundown
/// as the phone, so a change to one of those shows in every layout.
extension DesktopLive on HomeState {
  /// The desktop layout this window is drawn in, or null when it uses the
  /// phone and tablet layout: a narrow or short window, the focused
  /// operator view, or the Classic choice.
  String? get desktopLayout {
    if (!c.ready || focused) return null;
    final size = MediaQuery.sizeOf(context);
    if (size.width < desktopLayoutMinWidth ||
        size.height < desktopLayoutMinHeight)
      return null;
    final id = effectiveDesktopLayout(
      appLayout(context).preferences.desktopLayout,
    );
    return id == 'classic' ? null : id;
  }

  /// Tabs in the header replace the side rail.
  bool get useTopTabs => desktopLayout == 'three_panes';

  /// Panes meet the header edge to edge, so it loses its rounded corners.
  bool get squareHeader => desktopLayout != null;

  /// Live fills the window, each pane scrolling on its own, once a
  /// service is loaded. Standing by keeps its single centred column.
  bool get liveFillsWindow =>
      desktopLayout != null && page == 0 && !liveStandingBy;

  /// Whether buttons show the key that presses them.
  bool get showKeyHints => switch (appLayout(context).preferences.keyHints) {
    'on' => true,
    'off' => false,
    _ => c.port.isDesktop,
  };

  /// [text] followed by its keyboard key, when key labels are on.
  Widget keyLabel(String text, String key, {TextAlign? textAlign}) =>
      showKeyHints
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(text, textAlign: textAlign)),
            const SizedBox(width: 10),
            KeyHint(key),
          ],
        )
      : Text(text, textAlign: textAlign);

  Widget desktopTabs() {
    final colors = appColors(context);
    const names = ['Live', 'Programs', 'Reports', 'Settings'];
    return Row(
      key: const ValueKey('desktop-tabs'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < names.length; i++)
          Semantics(
            selected: page == i,
            button: true,
            child: InkWell(
              key: ValueKey('desktop-tab-$i'),
              borderRadius: BorderRadius.circular(6),
              onTap: controlsLocked ? null : () => goToPage(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: page == i ? colors.accent : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    names[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: page == i ? colors.text : colors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Rundown on the left, timer in the middle, stage and cues on the right.
  Widget threePaneLive({
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
    final line = VerticalDivider(width: 1, thickness: 1, color: colors.border);
    return LayoutBuilder(
      builder: (context, space) {
        final side = (space.maxWidth * .25).clamp(320.0, 460.0);
        final stage = (space.maxWidth * .28).clamp(372.0, 540.0);
        return Row(
          key: const ValueKey('three-pane-live'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: side,
              child: ColoredBox(
                color: colors.surface,
                child: rundownPane(enabled),
              ),
            ),
            line,
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('live-timer-pane'),
                // Page Down is Next segment here, not a scroll key.
                primary: false,
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...notices,
                        timer ??
                            desktopTimer(
                              header: header,
                              endService: endService,
                              enabled: enabled,
                              canJump: canJump,
                              // What is left of the window once the title,
                              // controls and End service have their room.
                              gauge: math.min(
                                space.maxWidth - side - stage - 120,
                                space.maxHeight - 470,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            line,
            SizedBox(
              width: stage,
              child: ColoredBox(
                color: colors.surface,
                child: SingleChildScrollView(
                  key: const ValueKey('live-stage-pane'),
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FlatPanels(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.stageRequests.open.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: stageRequestCards(),
                          ),
                        display,
                        const AppDivider(),
                        cues,
                        if (c.destination == 'mobile') ...[
                          const AppDivider(),
                          quickMessagePanel(),
                        ],
                        if (s.phase == 'ended') const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The running segment's name; tap it to jump to a later segment.
  Widget segmentTitle(bool canJump, {double size = 34, bool centred = true}) {
    final colors = appColors(context);
    final segment = c.liveSession.timeline!.segments[c.liveSession.index];
    return Semantics(
      button: true,
      enabled: canJump,
      hint: 'Jump to segment',
      child: InkWell(
        key: const ValueKey('jump-to-segment'),
        borderRadius: BorderRadius.circular(8),
        onTap: canJump ? jumpToSegment : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  segment.name,
                  textAlign: centred ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              if (canJump) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more,
                  color: colors.muted,
                  semanticLabel: 'Jump to segment',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The running segment in the middle pane: name, countdown, controls,
  /// private note and End service.
  Widget desktopTimer({
    required Widget header,
    required Widget endService,
    required bool enabled,
    required bool canJump,
    required double gauge,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final segment = t.segments[s.index];
    final next = s.index + 1 < t.segments.length
        ? t.segments[s.index + 1]
        : null;
    return Column(
      key: const ValueKey('timer-card-content'),
      children: [
        header,
        const SizedBox(height: 6),
        segmentTitle(canJump),
        const SizedBox(height: 6),
        if (!s.quickTimer)
          Text(
            [
              if (segment.speaker.isNotEmpty) 'Speaker: ${segment.speaker}',
              next == null
                  ? 'Final segment'
                  : 'Next · ${next.name} · ${next.durationText}',
            ].join('   ·   '),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted),
          ),
        const SizedBox(height: 4),
        SegmentGauge(
          session: s,
          now: c.now,
          maxWidth: gauge.clamp(270.0, 460.0),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              liveControls(enabled),
              if (segment.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const AppDivider(indent: 0, endIndent: 0),
                const SizedBox(height: 12),
                Text(
                  'Private note',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  segment.notes,
                  key: const ValueKey('desktop-private-note'),
                ),
              ],
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: endService),
            ],
          ),
        ),
      ],
    );
  }

  /// The whole service at the left: how it is running against the plan,
  /// then every segment with its planned and actual time.
  Widget rundownPane(bool enabled) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!, run = s.run;
    final muted = TextStyle(color: colors.muted, fontSize: 12);
    final projected = s.projectedTotal(c.now);
    final variance = projected - s.plannedMs;
    final over = variance > 999;
    // When each segment still to come would start, if the rest keep to
    // their planned time.
    var ahead = s.remaining(c.now);
    final starts = <int, int>{};
    for (var i = s.index + 1; i < t.segments.length; i++) {
      starts[i] = c.now.wall + (ahead / s.rate).round();
      ahead += t.segments[i].durationMs;
    }
    final compactButton = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
    );
    Widget trailing(int i) {
      final segment = t.segments[i];
      Widget pair(
        String top,
        String bottom, {
        Color? color,
        bool bold = false,
      }) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            top,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            bottom,
            style: muted.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
      if (i == s.index && s.active) {
        final balance = s.balance(c.now);
        return pair(
          '${operatorTime(balance)} ${balance < 0 ? 'over' : 'left'}',
          'of ${formatTime(s.allocatedMs)}',
          bold: true,
        );
      }
      if (run != null && run.skipped.contains(i)) {
        return pair('Skipped', segment.durationText);
      }
      final actual = run == null || i >= run.actualMs.length
          ? null
          : run.actualMs[i];
      if (i < s.index && actual != null) {
        final diff = actual - segment.durationMs;
        return pair(
          formatTime(actual),
          signedTime(diff),
          color: diff > 30000
              ? colors.warning
              : diff < 0
              ? colors.success
              : null,
        );
      }
      final start = starts[i];
      return pair(
        segment.durationText,
        start == null || !s.active ? '' : 'about ${clockLabel(start)}',
      );
    }

    return Column(
      key: const ValueKey('rundown-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
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
              const Spacer(),
              if (run != null && s.active)
                Text(
                  varianceLabel(variance),
                  key: const ValueKey('rundown-variance'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: over ? colors.warning : colors.success,
                  ),
                ),
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
        if (run != null && s.active)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${durationLabel(s.totalElapsed(c.now))} in',
                      style: muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ends ${clockLabel(c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round())}${s.paused ? ' if resumed now' : ''} · plan ${clockLabel(run.startedWall + (s.plannedMs / s.rate).round())}',
                        key: const ValueKey('rundown-finish'),
                        textAlign: TextAlign.end,
                        style: muted,
                      ),
                    ),
                  ],
                ),
                if (s.targetFinishWall != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Target finish ${clockLabel(s.targetFinishWall!)}',
                      style: muted,
                    ),
                  ),
              ],
            ),
          ),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: ListView.separated(
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: t.segments.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: colors.border),
            itemBuilder: (context, i) {
              final segment = t.segments[i];
              final current = i == s.index;
              final done = i < s.index;
              return Material(
                color: current
                    ? colors.accent.withValues(alpha: .13)
                    : Colors.transparent,
                child: InkWell(
                  key: ValueKey('rundown-$i'),
                  onTap: () => showSegmentDetails(i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: math.max(8, appLayout(context).rowPadding - 4),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${i + 1}',
                            style: muted.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                segment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: current
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: done ? colors.muted : null,
                                ),
                              ),
                              Text(
                                segment.speaker.isEmpty
                                    ? (current ? 'Now' : segment.durationText)
                                    : segment.speaker,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: muted,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        trailing(i),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (s.active) ...[
          Divider(height: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: compactButton,
                    onPressed: enabled ? editUpcoming : null,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Edit upcoming'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: compactButton,
                    onPressed: enabled ? recoverTime : null,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('Recover time'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "+0:40" or "−1:15": how far a finished segment ran over or under.
String signedTime(int ms) {
  final seconds = (ms.abs() / 1000).round();
  return '${ms < 0 ? '−' : '+'}${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The key that presses a button, shown quietly beside its label.
class KeyHint extends StatelessWidget {
  final String keys;
  const KeyHint(this.keys, {super.key});
  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return ExcludeSemantics(
      child: Text(
        keys,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: .4,
          color: style.color?.withValues(alpha: .62),
        ),
      ),
    );
  }
}

/// The service as one bar, a piece per segment sized by its planned time:
/// finished pieces filled, the running one filled as far as it has got.
class ServiceProgressBar extends StatelessWidget {
  final List<int> durations;
  final int index;
  final double progress;
  const ServiceProgressBar({
    super.key,
    required this.durations,
    required this.index,
    required this.progress,
  });
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final done = colors.accent.withValues(alpha: .5);
    return ExcludeSemantics(
      child: SizedBox(
        height: 6,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < durations.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: math.max(1, durations[i] ~/ 1000),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: i == index
                      ? LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: colors.accent,
                          backgroundColor: colors.track,
                        )
                      : ColoredBox(color: i < index ? done : colors.track),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
