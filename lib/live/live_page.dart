import 'dart:math' as math;
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
import 'package:church_service_timer/live/balanced_columns.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/keys_live.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/live/quick_timer_sheet.dart';
import 'package:church_service_timer/live/second_screen_control.dart';
import 'package:church_service_timer/live/service_check.dart';
import 'package:church_service_timer/live/update_available_notice.dart';
import 'package:church_service_timer/live/whats_new_notice.dart';
import 'package:church_service_timer/live/simulator_choice.dart';
import 'package:church_service_timer/live/simulator_matrix.dart';

/// The Live page: standing by, Ready for service and the running service.
/// Classic fits the ring and controls to a window at least this wide and
/// less than [classicBesideBelowHeight] tall, or less than
/// [classicUsualWidth] wide at any height (see [LivePage.classicFit]). Under
/// about 890 wide the page is one column, and the ring is sized the same
/// way.
const classicBesideFromWidth = 600.0;
const classicBesideBelowHeight = 1000.0;

/// How Classic sets out the ring and the controls in such a window.
enum ClassicArrangement {
  /// The controls beside the ring, under the segment's name: a window
  /// wide enough for both.
  beside,

  /// The ring centred under the segment's name and the controls across
  /// the card under it: a narrow window with height to spare.
  stacked,

  /// The segment's name beside the ring and the controls across the card
  /// under both: a narrow, shorter window.
  titleBeside,
}

/// The arrangement, the width of the ring, and the width of the column
/// for the display and cues (null for the usual share of the page).
typedef ClassicFit = ({
  ClassicArrangement arrangement,
  double ring,
  double? side,
});

/// The narrowest the display and cue column is made when the ring goes
/// under the segment's name, so its headings and cues read in full.
const classicSideMinWidth = 340.0;

/// The card width from which the Ready form sets its rows in pairs.
const classicReadyPairsFrom = 520.0;

/// The page width from which Classic sets its cards in two columns.
const classicTwoColumnsFrom = 820.0;

/// The same in a window 1000 or more high.
const classicTwoColumnsFromTall = 740.0;

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

  /// The width a cue button needs for the longest word of any cue on one
  /// line: the word, the padding, and the icon and number key beside it.
  /// [dense] buttons, in a desktop layout, have no icon and set the cue in
  /// the stage face.
  double cueWordRoom({required bool dense}) {
    final style = dense
        ? stageCueStyle
        : (Theme.of(context).textTheme.labelLarge ?? const TextStyle());
    var widest = 0.0;
    for (final cue in c.state.stageCues) {
      for (final word in cue.text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(text: word, style: measureBase(context).merge(style)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
    }
    // The padding at each side, the number key and the space before it,
    // the icon and the space after it, and a pixel to spare.
    return widest + 28 + (showKeyHints ? 14 : 0) + (dense ? 0 : 28) + 1;
  }

  /// The ring beside the controls in a timer card [width] wide inside:
  /// as large as the height under the title allows, leaving the controls
  /// room for Pause and Next segment. In the narrowest windows the ring
  /// gives way, so the labels keep to one line.
  double classicBesideRing(double width) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    return math
        .min(
          (MediaQuery.sizeOf(context).height - 380 * scale) * 300 / 260,
          width - 400 * scale,
        )
        .clamp(160.0, 440.0)
        .toDouble();
  }

  /// How Classic sets out a running or Ready service in a window at least
  /// [classicBesideFromWidth] wide and less than [classicBesideBelowHeight]
  /// tall or [classicUsualWidth] wide, with [width] for the timer card and
  /// the column beside it, or all of the page when it is a [single] column.
  ///
  /// A laptop window has the controls beside the ring. A narrower one,
  /// such as 1366 × 768 or 1920 × 1200 at 125% or 150% display scaling,
  /// has too little width for both: there the ring goes under the
  /// segment's name, or beside it in a shorter window, with the controls
  /// across the card, whichever gives the larger ring. The display and
  /// cues then keep a column at least [classicSideMinWidth] wide.
  ///
  /// The heights are those of a running service, the tallest of running
  /// and Ready, so the ring keeps its size when the service starts.
  ClassicFit classicFit(double width, {bool single = false}) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final height = MediaQuery.sizeOf(context).height;
    final s = c.liveSession, segment = s.timeline!.segments[s.index];
    // The card's padding at each side, and the gap between the columns.
    const padding = 56.0, gap = 20.0;
    double ringFor(double gaugeHeight) => (gaugeHeight - 32) * 300 / 260;
    double gaugeOf(double ring) => ring * 260 / 300 + 32;

    // The controls beside the ring, with the usual share for the column,
    // or enough for the display heading and its badge on one line.
    final usualSide = single ? 0.0 : (width - gap) * 3 / 10;
    final narrowSide = !single && 300 * scale > usualSide ? 300 * scale : null;
    final usualInner = single
        ? width - padding
        : width - gap - (narrowSide ?? usualSide) - padding;
    final beside = classicBesideRing(usualInner);
    final besideFits =
        usualInner - 20 - beside >= (showKeyHints ? 350 : 310) * scale;

    // Under the title, with a column wide enough for the display and cues.
    final side = single
        ? 0.0
        : math.max(usualSide, classicSideMinWidth * scale);
    final inner = single ? width - padding : width - gap - side - padding;
    final notes = segment.notes.isEmpty ? 0.0 : 56 * scale;
    final speaker = segment.speaker.isEmpty ? 0.0 : 30 * scale;
    // From the top of the window to the segment's name: the header, the
    // timing bar, the card's padding and its first line.
    // A single column has the timing line inside the card instead.
    final top = (single ? 250 : 234) * scale;
    // The name, the next segment and the speaker.
    double titleHeight(double across) =>
        (72 * scale) +
        speaker +
        notes +
        extraTitleHeight(segment.name, across + 48, size: 27);
    // Under the ring: the controls and End service, or the Ready form,
    // and the foot of the card and the page. Ready has no timing bar, so
    // its card starts 62 higher.
    final pairs = inner >= classicReadyPairsFrom * scale;
    final under =
        math.max(214.0, (pairs ? 196.0 : 252.0) + 16 - 62) * scale + 44;
    final stacked = math.min(
      ringFor(height - top - titleHeight(inner) - 8 - under),
      math.min(inner, 440.0),
    );
    // The name, what follows and the speaker take a column beside it,
    // with Check this service under them in Ready.
    final titleWidth = 200 * scale;
    final titleBesideRing = math.min(
      ringFor(height - top - under),
      math.min(inner - 24 - titleWidth, 440.0),
    );
    final titleBesideFits =
        titleHeight(inner - 24 - titleBesideRing) + 64 * scale <=
        gaugeOf(titleBesideRing) + 8;

    final options = <ClassicFit>[
      if (besideFits)
        (
          arrangement: ClassicArrangement.beside,
          ring: beside,
          side: narrowSide,
        ),
      // A ring under 230 wide moves its labels outside it; not worth it.
      if (stacked >= 230)
        (arrangement: ClassicArrangement.stacked, ring: stacked, side: side),
      if (titleBesideFits && titleBesideRing >= 230)
        (
          arrangement: ClassicArrangement.titleBeside,
          ring: titleBesideRing,
          side: side,
        ),
    ];
    if (options.isEmpty) {
      return (
        arrangement: ClassicArrangement.beside,
        ring: beside,
        side: narrowSide,
      );
    }
    final best = options.reduce((a, b) => b.ring > a.ring ? b : a);
    // The ring under the title fills the card down to the foot of the
    // window, where beside the title it leaves a band empty: worth a
    // ring a little smaller.
    final ringFirst = options
        .where((o) => o.arrangement == ClassicArrangement.stacked)
        .firstOrNull;
    return ringFirst != null && ringFirst.ring >= best.ring * .92
        ? ringFirst
        : best;
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
  /// [compact] is the smaller row under the ring of a desktop layout: no
  /// icon, and no reminder to start, which the Start first segment button
  /// under it already gives.
  Widget preServiceRow({bool compact = false}) {
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
    final hint = compact && !outputHeld ? '' : '\n$preServiceHint';
    // Under a desktop ring the line under it says what the display
    // shows meanwhile.
    final summary = at == null
        ? (compact ? 'Off' : 'Off · the display keeps its current output')
        : left > preServiceCountdownMs
        ? 'Starts ${wallTime(at)} · clock now, countdown from ${wallTime(at - preServiceCountdownMs - 1000)}$hint'
        : left > 0
        ? 'Starts ${wallTime(at)} · counting down on the display$hint'
        : 'Start time reached · display shows “Starting soon”$hint';
    final trailing = at == null
        ? TextButton(
            style: compact
                ? TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : null,
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
            visualDensity: compact ? VisualDensity.compact : null,
            onPressed: c.busy ? null : () => c.act('schedule', value: null),
            icon: const Icon(Icons.close),
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colors.border),
    );
    if (compact) {
      return Material(
        key: const ValueKey('pre-service-row'),
        color: colors.background,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: c.busy ? null : pickServiceStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: summary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Shrinks a little in a narrow tile, never cut.
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Pre-service countdown',
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      key: const ValueKey('pre-service-row'),
      color: colors.background,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: shape,
        leading: Icon(Icons.schedule, color: colors.accent),
        title: const Text(
          'Pre-service countdown',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          summary,
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
        trailing: trailing,
        onTap: c.busy ? null : pickServiceStart,
      ),
    );
  }

  /// What Ready adds to the timer before the first segment starts: the
  /// program, the readiness row, the pre-service countdown, the service
  /// mode, and the buttons to start, cancel or check the service.
  ///
  /// [compact] is the arrangement a desktop layout puts where Pause and
  /// Next segment go once the service runs, so the ring above keeps its
  /// size and place: two to a row where there is room. A layout that puts
  /// the buttons, Check this service or the readiness row elsewhere
  /// passes [buttons], [check] or [inline] false.
  Widget readyControls({
    bool compact = false,
    bool buttons = true,
    bool check = true,
    bool inline = true,
    double pairsFrom = 500,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline;
    final review = t == null ? null : c.state.latestReviewFor(t);
    final reviewNote = review == null
        ? null
        : Material(
            key: const ValueKey('last-review-note'),
            color: colors.info.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.rate_review_outlined,
                    size: 20,
                    color: colors.info,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: compact
                        // One line under the ring; the whole note on
                        // hover.
                        ? Tooltip(
                            message: review.note.text,
                            child: Text(
                              'Last time · ${serviceDateLabel(review.report.startedWall ?? review.report.endedWall)} · ${review.note.text}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last time · ${serviceDateLabel(review.report.startedWall ?? review.report.endedWall)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(review.note.text),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
    final mode = readyModeField(compact: compact);
    if (!compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reviewNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: reviewNote,
            ),
          if (t != null) ...[readyProgramRow(t), const SizedBox(height: 8)],
          readyInline(),
          const SizedBox(height: 10),
          preServiceRow(),
          const SizedBox(height: 12),
          mode,
          const SizedBox(height: 12),
          readyNotStartedLine(),
          const SizedBox(height: 12),
          readyButtons(),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        // Two to a row while each half has room for its words.
        final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
        final pairs = box.maxWidth >= pairsFrom * scale;
        Widget pair(Widget a, Widget b) => pairs
            ? Row(
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 12),
                  Expanded(child: b),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [a, const SizedBox(height: 8), b],
              );
        return Column(
          key: const ValueKey('ready-controls'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reviewNote != null) ...[reviewNote, const SizedBox(height: 8)],
            if (t != null && inline)
              pair(readyProgramRow(t, compact: true), readyInline())
            else if (t != null)
              readyProgramRow(t, compact: true)
            else if (inline)
              readyInline(),
            const SizedBox(height: 8),
            pair(preServiceRow(compact: true), mode),
            if (buttons) ...[
              const SizedBox(height: 8),
              readyNotStartedLine(compact: true),
              const SizedBox(height: 8),
              readyButtons(compact: true, check: check),
            ],
          ],
        );
      },
    );
  }

  /// Live timing or a fast rehearsal.
  Widget readyModeField({bool compact = false}) {
    final s = c.liveSession;
    return ChoiceField<int>(
      key: ValueKey('speed-${s.id}'),
      value: s.rate,
      decoration: InputDecoration(
        labelText: 'Service mode',
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.fromLTRB(14, 11, 8, 11)
            : null,
      ),
      options: [1, 5, 10, 30, 60]
          .map(
            (rate) => ChoiceOption(
              value: rate,
              label: rate == 1 ? 'Live timing · 1×' : 'Fast rehearsal · $rate×',
            ),
          )
          .toList(),
      onChanged: c.busy ? null : (v) => c.act('rate', value: v),
    );
  }

  /// Timing has not started yet, and what the display shows meanwhile.
  Widget readyNotStartedLine({bool compact = false}) => Text(
    // With a pre-service start time the display counts down to it, so
    // "keeps its previous output" would contradict the pre-service row.
    c.state.session.startsAtWall == null
        ? 'Timing has not started. The display keeps its current output.'
        : 'Timing has not started. The display shows the pre-service countdown until you start the first segment.',
    key: const ValueKey('ready-not-started'),
    style: TextStyle(
      color: appColors(context).muted,
      fontSize: compact ? 13 : null,
    ),
  );

  /// Start first segment, Cancel setup and Check this service. [check]
  /// false leaves out Check this service, for a layout that puts it
  /// elsewhere. [compact] buttons have less padding, so the three fit on
  /// one line under a desktop ring.
  Widget readyButtons({
    bool check = true,
    bool compact = false,
    double? height,
  }) {
    final t = c.liveSession.timeline;
    final buttons = Wrap(
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
        if (check && t != null) checkServiceButton(t),
      ],
    );
    if (!compact) return buttons;
    final theme = Theme.of(context);
    const padding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16),
    );
    final size = height == null
        ? null
        : WidgetStatePropertyAll(Size(0, height));
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(padding: padding, minimumSize: size),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(padding: padding, minimumSize: size),
        ),
      ),
      child: buttons,
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
    // A wide window less than 1000 tall, such as a laptop, or one too
    // narrow for the desktop layouts at any height: Classic sizes the ring
    // to the window and keeps the controls in view without scrolling,
    // beside the ring or under it (see [classicFit]).
    final screen = MediaQuery.sizeOf(context);
    final shortWide =
        !liveFillsWindow &&
        !focused &&
        t != null &&
        (s.active || s.phase == 'ready') &&
        screen.width >= classicBesideFromWidth &&
        (screen.height < classicBesideBelowHeight ||
            screen.width < classicUsualWidth);
    // Set from the width of the page before the timer card is built.
    ClassicFit fit = (
      arrangement: ClassicArrangement.beside,
      ring: 0.0,
      side: null,
    );
    Widget timerPanelOf({required bool wide}) {
      final arranged = shortWide;
      final arrangement = arranged ? fit.arrangement : null;
      final title = <Widget>[
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
                  // The time keeps to the end of the name, as "20 min", not
                  // split over two lines.
                  ? 'Next · ${t.segments[s.index + 1].name}\u00a0·\u00a0${t.segments[s.index + 1].durationText.replaceAll(' ', '\u00a0')}'
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
        ],
      ];
      final gauge = arranged
          ? SegmentGauge(session: s, now: c.now, maxWidth: fit.ring)
          : SegmentGauge(session: s, now: c.now);
      // Under the ring and across the card: the controls and End service,
      // or the Ready form in their place.
      final under = <Widget>[
        const SizedBox(height: 16),
        if (s.active) ...[
          liveControls(enabled),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: endServiceButton(compact: true),
          ),
        ] else
          readyControls(
            compact: true,
            check: arrangement == ClassicArrangement.stacked,
            pairsFrom: classicReadyPairsFrom,
          ),
      ];
      return panel(
        child: Column(
          key: const ValueKey('timer-card-content'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            timerHeader,
            const SizedBox(height: 8),
            if (arrangement == ClassicArrangement.titleBeside) ...[
              // The ring at the left with the segment's name, what follows
              // and the speaker beside it, and the controls across the card
              // under both: the most ring a short, narrow window allows.
              Row(
                key: const ValueKey('classic-title-beside'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: fit.ring, child: gauge),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...title,
                        if (s.phase == 'ready') ...[
                          const SizedBox(height: 16),
                          checkServiceButton(t!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              ...under,
            ] else if (arrangement == ClassicArrangement.stacked) ...[
              // The ring centred under the title, as large as the height
              // allows, and the controls across the card under it.
              ...title,
              Center(
                key: const ValueKey('classic-stacked'),
                child: SizedBox(width: fit.ring, child: gauge),
              ),
              ...under,
            ] else ...[
              ...title,
              if (t != null && !arranged) gauge,
              if (t == null) const SizedBox(height: 18),
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
                        c.pairing.hosting
                            ? 'Manage sharing'
                            : 'Share to screens',
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
                              onPressed: () => refreshHome(
                                () => batteryHintDismissed = true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (arranged)
                LayoutBuilder(
                  builder: (context, box) {
                    // As large as the height under the title allows, leaving
                    // the controls beside it room for Pause and Next segment.
                    final ring = classicBesideRing(box.maxWidth);
                    return Row(
                      key: const ValueKey('classic-beside'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: ring,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SegmentGauge(
                                session: s,
                                now: c.now,
                                maxWidth: ring,
                              ),
                              // Under the ring, so Start and Cancel setup have
                              // a line of their own; with them under a ring
                              // too small for it.
                              if (s.phase == 'ready' && ring >= 200)
                                Center(child: checkServiceButton(t)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: s.active
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    liveControls(enabled),
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: endServiceButton(compact: true),
                                    ),
                                  ],
                                )
                              : readyControls(compact: true, check: ring < 200),
                        ),
                      ],
                    );
                  },
                )
              else if (s.phase == 'ready')
                readyControls()
              else if (s.active) ...[
                liveControls(enabled),
                // Set apart from the time adjustments above, so a slip doesn't
                // land on End service.
                const SizedBox(height: 28),
                endServiceButton(),
              ],
            ],
          ],
        ),
      );
    }

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
                ...lyricsOnLive(),
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
                  // Lyrics beside it, so the panel is no taller.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      button(
                        'Change display',
                        Icons.devices,
                        c.busy || c.corrupt ? null : chooseDisplay,
                      ),
                      lyricsButton(),
                    ],
                  ),
                ],
                ...secondScreenControl(),
                ...fullScreenControl(),
                ...lyricsOnLive(button: false),
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
    // With no end screen the clock is what an ended service shows, so
    // there is nothing to swap back to.
    final clockSwap = !s.outputBlank && mode == 'Clock' && !s.endsOnClock;
    final messageSwap =
        !s.outputBlank && mode == 'Message' && c.currentQuickMessage == null;
    // Outputs that no swapped button represents (automatic warnings, quick
    // messages, cues sent from elsewhere) still get an explicit way back.
    final needsReturn =
        (!s.outputBlank &&
            !const ['Countdown', 'Standby', 'End screen'].contains(mode) &&
            !(mode == 'Clock' && s.endsOnClock) &&
            activeCueIndex < 0 &&
            !clockSwap &&
            !messageSwap) ||
        c.currentQuickMessage != null;
    final returnLabel = s.endsOnClock
        ? 'Back to clock'
        : s.phase == 'ended'
        ? 'Show end screen'
        : 'Show timer';
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
          // row rather than leaving a gap. Three across where they fit, so
          // the seven cues a church starts with take three rows, not four.
          ControlGrid(
            maxColumns: 3,
            // A desktop layout's narrow cue pane still takes three, as
            // its buttons have no icon. Never so narrow that a word of a
            // cue breaks across lines.
            minWidth: math.max(dense ? 96 : 118, cueWordRoom(dense: dense)),
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
            // Two by two: the display actions and Quick timer. In one row
            // in a desktop layout, so the cue pane fits without scrolling.
            maxColumns: dense ? 4 : 2,
            minWidth: dense ? 76 : 92,
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
                  outputControlsEnabled && !s.endsOnClock
                      ? () => c.act('clock')
                      : null,
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
      if (standingBy) updateAvailableNotice(),
      if (standingBy) whatsNewNotice(),
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
                      s.endsOnClock
                          ? 'Send clock'
                          : s.phase == 'ended'
                          ? 'Send end screen'
                          : 'Resume output',
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
      // Ready draws each layout's own timer, with the Ready form where
      // the timer controls go once the service runs. A report still saving
      // keeps the card's own content in the panes.
      final ownTimer = s.active || s.phase == 'ready';
      if (desktopLayout == 'keys' && ownTimer) {
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
        timer: ownTimer ? null : FlatPanels(child: timerPanelOf(wide: true)),
        endService: endServiceButton(compact: true),
        display: displayPanel,
        cues: cuePanel,
        enabled: enabled,
        canJump: canJump,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns need room for the timer card and a column of cues
        // beside it; under that, one column.
        // A tall window can have them a little sooner: its ring stacks
        // under the name and needs no width beside it.
        final wide =
            constraints.maxWidth >=
            (MediaQuery.sizeOf(context).height >= 1000
                ? classicTwoColumnsFromTall
                : classicTwoColumnsFrom);
        // A very wide window has a column for the rundown.
        final threeColumns = constraints.maxWidth > classicUsualWidth;
        if (shortWide) {
          fit = classicFit(constraints.maxWidth, single: !wide);
        }
        // The cards beside the timer, each as its own card for
        // [BalancedColumns] to place by their heights.
        Widget card(String name, Widget child) =>
            KeyedSubtree(key: ValueKey('classic-card:$name'), child: child);
        final sideCards = [
          card('display', displayPanel),
          card('cues', cuePanel),
          if (c.destination == 'mobile') card('message', quickMessagePanel()),
        ];
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
              if (showRundown && threeColumns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: shortWide ? 7 : 5,
                      child: timerPanelOf(wide: true),
                    ),
                    const SizedBox(width: 20),
                    // A narrow window gives the display and cues a column
                    // of their own width, so their headings and cues read
                    // in full.
                    if (shortWide && fit.side != null)
                      SizedBox(
                        width: fit.side,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, w) in sideCards.indexed) ...[
                              if (i > 0) const SizedBox(height: 16),
                              w,
                            ],
                          ],
                        ),
                      )
                    else
                      Expanded(
                        flex: shortWide ? 3 : 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, w) in sideCards.indexed) ...[
                              if (i > 0) const SizedBox(height: 16),
                              w,
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: rundownPanel()),
                  ],
                )
              else
                // Two columns, the cards placed so that both end about
                // together: the rundown goes under the timer when the
                // display and cues already run lower.
                BalancedColumns(
                  leftFlex: shortWide ? 7 : 5,
                  rightFlex: shortWide ? 3 : 5,
                  rightWidth: shortWide ? fit.side : null,
                  tolerance: MediaQuery.sizeOf(context).height / 4,
                  // Under the header, the timing bar and the page's padding.
                  viewHeight: MediaQuery.sizeOf(context).height - 150,
                  children: [
                    card('timer', timerPanelOf(wide: true)),
                    ...sideCards,
                    if (showRundown) card('rundown', rundownPanel()),
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
