import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/large_screen_live.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/live/service_dial.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The keys line and the rule above it.
const keyLegendHeight = 29.0;

/// The least height the ring of Three panes and The dial is given. The
/// keys line along the bottom of the middle pane shows whenever the ring
/// still has this much with the line taken out, so a laptop window has
/// it too, with the ring a little smaller.
const desktopRingMinRoom = 240.0;

/// The height of the middle pane of Three panes and The dial above the
/// ring: the padding, the header, a one-line title and the line under it.
const desktopTimerAbove = 139.0;

/// The height under the ring: Pause, Next segment, the time adjustments
/// and End service, or the Ready form in their place, and the padding.
const desktopTimerBelow = 208.0;

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
  bool get useTopTabs =>
      const {'three_panes', 'dial', 'keys'}.contains(desktopLayout);

  /// Panes meet the header edge to edge, so it loses its rounded corners.
  bool get squareHeader => desktopLayout != null;

  /// Live fills the window, each pane scrolling on its own, before a
  /// service as well as during one.
  bool get liveFillsWindow => desktopLayout != null && page == 0;

  /// Programs fills the window too: the list, the chosen program as a
  /// table, and its summary, each scrolling on its own.
  bool get programsFillWindow => desktopLayout != null && page == 1;

  /// Whether buttons show the key that presses them.
  bool get showKeyHints => switch (appLayout(context).preferences.keyHints) {
    'on' => true,
    'off' => false,
    _ => c.port.isDesktop,
  };

  /// Whether Space, B, Page Down and → do anything on Live. They are the
  /// keys a clicker or pedal sends, and follow Clicker and foot pedal on
  /// a computer too.
  bool get clickerKeysOn => c.state.clickerControls;

  /// [text] followed by its keyboard key, when key labels are on and the
  /// key does something.
  Widget keyLabel(String text, String? key, {TextAlign? textAlign}) =>
      showKeyHints && key != null
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
        // A tall window has room under the cues for who is connected and
        // what has happened, as in Mission control. A laptop does not:
        // there the stage preview and cues fill the pane.
        final tall = space.maxHeight >= 900;
        // The keys line along the bottom of the middle pane, whenever the
        // ring still has room above the controls with it taken out; the
        // timer has the height that is left. Ready leaves its room, so the
        // ring keeps its size when the service starts.
        final paneWidth = space.maxWidth - side - stage - 2;
        final legendRoom =
            showKeyHints &&
            (s.active || s.phase == 'ready') &&
            desktopRingRoom(paneWidth, space.maxHeight - keyLegendHeight) >=
                desktopRingMinRoom;
        final legend = legendRoom && s.active;
        final paneHeight = space.maxHeight - (legendRoom ? keyLegendHeight : 0);
        // A large window gives the ring more of the pane.
        final large = timer == null
            ? largePaneMode(paneWidth, paneHeight)
            : LargePane.off;
        return Row(
          key: const ValueKey('three-pane-live'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: side,
              child: ColoredBox(
                color: colors.surface,
                child: rundownPane(
                  enabled,
                  upNext: desktopLayout == 'dial' && s.active
                      ? upNextBlock()
                      : null,
                ),
              ),
            ),
            line,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: large != LargePane.off
                        ? largeTimerPane(
                            mode: large,
                            notices: notices,
                            header: header,
                            endService: endService,
                            enabled: enabled,
                            canJump: canJump,
                            width: paneWidth,
                            height: paneHeight,
                          )
                        : SingleChildScrollView(
                            key: const ValueKey('live-timer-pane'),
                            // Page Down is Next segment here, not a scroll key.
                            primary: false,
                            padding: const EdgeInsets.fromLTRB(28, 10, 28, 12),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 620,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ...notices,
                                    timer ??
                                        desktopTimer(
                                          header: header,
                                          endService: endService,
                                          enabled: enabled,
                                          canJump: canJump,
                                          paneWidth: paneWidth,
                                          paneHeight: paneHeight,
                                        ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (legend) ...[
                    Divider(height: 1, thickness: 1, color: colors.border),
                    KeyLegend(
                      key: const ValueKey('pane-key-legend'),
                      clicker: clickerKeysOn,
                    ),
                  ],
                ],
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
                        if (tall) ...[
                          const AppDivider(),
                          screensSection(),
                          const AppDivider(),
                          activitySection(),
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

  /// How much more height than one line a segment title of [size] takes
  /// in a pane [width] wide, for the ring to give up.
  double extraTitleHeight(String name, double width, {double size = 34}) {
    final title = TextPainter(
      text: TextSpan(
        text: name,
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(120, width - 48));
    final extra = title.height - title.preferredLineHeight;
    title.dispose();
    return math.max(0, extra);
  }

  /// Whether the private note takes one line under the title rather than
  /// a block of its own, in a middle pane [paneWidth] by [paneHeight]. The
  /// Dial layout draws the whole service as a ring and wants the height,
  /// so it does this in a short window; Three panes in a very short one,
  /// or wherever the block would leave the ring less than its least room.
  bool desktopNoteInline(double paneWidth, double paneHeight) {
    final s = c.liveSession;
    if (s.timeline!.segments[s.index].notes.isEmpty) return false;
    return paneHeight < (desktopLayout == 'dial' ? 820 : 680) ||
        desktopRingRoom(paneWidth, paneHeight, noteInline: false) <
            desktopRingMinRoom;
  }

  /// The height the ring has in a middle pane [paneWidth] by [paneHeight]:
  /// what the rest leaves, the header, title and next line above it, and
  /// under it the controls and End service, or the Ready form in their
  /// place, which is about as tall. Both are counted in Ready and while
  /// running, so the ring keeps its size when the service starts.
  /// [noteInline] says where the private note goes, if not where
  /// [desktopNoteInline] puts it.
  double desktopRingRoom(
    double paneWidth,
    double paneHeight, {
    bool? noteInline,
  }) {
    final s = c.liveSession;
    final segment = s.timeline!.segments[s.index];
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final inline = noteInline ?? desktopNoteInline(paneWidth, paneHeight);
    final below = segment.notes.isNotEmpty && !inline;
    return paneHeight -
        (desktopTimerAbove + desktopTimerBelow) * scale -
        extraTitleHeight(segment.name, math.min(620.0, paneWidth - 56)) -
        (inline && segment.notes.isNotEmpty ? 20 * scale : 0) -
        (below ? 96 * scale : 0);
  }

  /// The running segment in the middle pane: name, countdown, controls,
  /// private note and End service. In Ready the same ring, at the same
  /// size, shows the first segment's full time, and the Ready form takes
  /// the place of the controls and End service.
  Widget desktopTimer({
    required Widget header,
    required Widget endService,
    required bool enabled,
    required bool canJump,
    required double paneWidth,
    required double paneHeight,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final ready = s.phase == 'ready';
    final segment = t.segments[s.index];
    final next = s.index + 1 < t.segments.length
        ? t.segments[s.index + 1]
        : null;
    final dial = desktopLayout == 'dial';
    final noteInline = desktopNoteInline(paneWidth, paneHeight);
    final noteBelow = segment.notes.isNotEmpty && !noteInline;
    final inner = math.min(620.0, paneWidth - 56);
    final room = desktopRingRoom(paneWidth, paneHeight);
    final note = <Widget>[
      if (noteBelow) ...[
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
        Tooltip(
          message: segment.notes,
          child: Text(
            segment.notes,
            key: const ValueKey('desktop-private-note'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ];
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
        if (noteInline)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Tooltip(
              message: segment.notes,
              child: Text(
                'Private note: ${segment.notes}',
                key: const ValueKey('desktop-private-note'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            ),
          ),
        const SizedBox(height: 4),
        if (dial)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ServiceDial(
              session: s,
              now: c.now,
              size: math
                  .min(room - 10, inner)
                  .clamp(desktopRingMinRoom - 10, 640.0),
              onSegment: showSegmentDetails,
            ),
          )
        else
          SegmentGauge(
            session: s,
            now: c.now,
            // The gauge is a little wider than tall, with a line under it
            // for the warning.
            maxWidth: math
                .min((room - 32) * 300 / 260, inner)
                .clamp(desktopRingMinRoom, 620.0),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ready)
                readyControls(compact: true)
              else
                liveControls(enabled),
              ...note,
              if (!ready) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: endService),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// What follows the running segment, above the Dial layout's rundown.
  Widget upNextBlock() {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final next = s.index + 1 < t.segments.length
        ? t.segments[s.index + 1]
        : null;
    final muted = TextStyle(color: colors.muted, fontSize: 12);
    // If the running segment ends on time.
    final start = c.now.wall + (s.remaining(c.now) / s.rate).round();
    return Padding(
      key: const ValueKey('up-next'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Up next', style: muted.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            next == null ? 'Final segment' : next.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (next != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                next.durationText,
                if (next.speaker.isNotEmpty) next.speaker,
                'starts about ${clockLabel(start)}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The whole service at the left: how it is running against the plan,
  /// then every segment with its planned and actual time. [upNext] sits
  /// above the list.
  Widget rundownPane(bool enabled, {Widget? upNext}) {
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
        if (upNext != null) ...[
          upNext,
          Divider(height: 1, color: colors.border),
        ],
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
                    label: keyLabel('Edit upcoming', 'E'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: compactButton,
                    onPressed: enabled ? recoverTime : null,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: keyLabel('Recover time', 'R'),
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

/// A cue on its button as it will read on stage: the bold LED text face
/// (Tinos, registered in pubspec.yaml), a little larger than a label.
const stageCueStyle = TextStyle(
  fontFamily: 'Tinos',
  fontWeight: FontWeight.w700,
  fontSize: 17,
  height: 1.1,
  letterSpacing: .2,
);

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
