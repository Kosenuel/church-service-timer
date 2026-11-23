import 'package:church_service_timer/shared/finish_widgets.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/mission_control_live.dart'
    show TimelineBlock, TimelineClockScale;
import 'package:church_service_timer/live/service_dial.dart' show DialGeometry;
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/reports/report_outcome.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/wide_layout.dart';

/// A segment counts as having run over from this much past its plan.
const reportOverrunMs = 60000;

/// Reports in a desktop layout: the report list down the left and the
/// chosen report filling the rest of the window, each scrolling on its
/// own. Smaller windows and Classic keep the page in
/// `report_library_views.dart`.
extension ReportsDesktop on HomeState {
  /// Reports fills the window in any desktop layout.
  bool get reportsFillWindow => desktopLayout != null && page == 2;

  Widget reportsDesktop() {
    final colors = appColors(context);
    final history = c.state.reports.where(reportMatches).toList()
      ..sort((a, b) => b.endedWall.compareTo(a.endedWall));
    // The newest report shows until another is chosen.
    final shown =
        history.where((r) => r.id == reportsPage.open).firstOrNull ??
        history.firstOrNull;
    final graph = reportsPage.view == 'graph' && !reportsPage.selecting;
    final Widget main;
    if (graph && history.isNotEmpty) {
      main = LayoutBuilder(
        builder: (context, space) => SingleChildScrollView(
          key: const ValueKey('reports-graph-pane'),
          primary: false,
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Align(
            alignment: Alignment.topLeft,
            // With room, the totals sit beside the charts instead of
            // under them.
            child: space.maxWidth >= 1300
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1560),
                    child: reportGraphs(history, columns: true),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: reportGraphs(history),
                  ),
          ),
        ),
      );
    } else if (shown == null) {
      main = Center(
        key: const ValueKey('reports-detail-empty'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights_outlined, size: 40, color: colors.muted),
              const SizedBox(height: 14),
              Text(
                c.state.reports.isEmpty ? 'No reports yet' : 'Nothing to show',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                c.state.reports.isEmpty
                    ? 'End a live service or fast rehearsal to see its report here.'
                    : 'No report matches this search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ],
          ),
        ),
      );
    } else {
      main = ReportDesktopDetail(
        key: ValueKey('report-desktop-${shown.id}'),
        report: shown,
        ring: desktopLayout == 'dial',
        onExport: (format) => exportReport(shown, format),
        onPrint: () => printServiceSheet(shown.program, report: shown),
        onDelete: () => confirmClearReports(record: shown),
        onEditReview: () => editReviewNote(shown),
      );
    }
    return LayoutBuilder(
      builder: (context, space) => Row(
        key: const ValueKey('reports-desktop'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: (space.maxWidth * .2).clamp(300.0, 360.0),
            child: FinishPane(
              flatSurface: true,
              child: FlatPanels(
                child: SingleChildScrollView(
                  key: const ValueKey('reports-list-pane'),
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  child: reports(
                    desktop: true,
                    openId: graph ? null : shown?.id,
                  ),
                ),
              ),
            ),
          ),
          finishRule(
            context,
            VerticalDivider(width: 1, thickness: 1, color: colors.border),
          ),
          // The report sits on a panel of the finish, like Live's cards,
          // not on the bare wall (a report draws its own panes).
          Expanded(child: shown == null ? FinishPane(child: main) : main),
        ],
      ),
    );
  }
}

/// The report page is this wide before notes and activity move into a
/// pane of their own beside the timings.
const reportAsideMinWidth = 1500.0;

/// The colour for how a segment or service compared with its plan. Royal
/// Navy's gold accent would read as the amber warning, so its "on time"
/// is the theme's green.
Color _tone(AppPalette colors, int varianceMs) =>
    varianceMs.abs() < 1000 ? _calm(colors) : outcomeColor(colors, varianceMs);

Color _calm(AppPalette colors) =>
    colors.id == 'royal_navy' ? colors.success : colors.accent;

const _figures = [FontFeature.tabularFigures()];

/// One report laid out flat across a desktop window: figures, a picture
/// of planned against actual, the segment table, then notes and activity.
class ReportDesktopDetail extends StatefulWidget {
  final ServiceReport report;

  /// The Dial layout draws the picture as a ring; the others as a twin
  /// timeline.
  final bool ring;
  final Future<void> Function() onPrint;
  final Future<void> Function(String) onExport;
  final Future<bool> Function() onDelete;
  final Future<void> Function() onEditReview;
  const ReportDesktopDetail({
    super.key,
    required this.report,
    required this.ring,
    required this.onPrint,
    required this.onExport,
    required this.onDelete,
    required this.onEditReview,
  });

  @override
  State<ReportDesktopDetail> createState() => _ReportDesktopDetailState();
}

class _ReportDesktopDetailState extends State<ReportDesktopDetail> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report, colors = appColors(context);
    final rule = Divider(height: 1, thickness: 1, color: colors.border);
    final when = r.startedWall ?? r.endedWall;
    final day = reportDate(when).split(' · ').first;
    final variance = r.totalMs == null ? null : r.totalMs! - r.plannedMs;
    final table = ReportSegmentTable(report: r);
    return LayoutBuilder(
      builder: (context, space) {
        final beside = widget.ring && space.maxWidth >= 900;
        final ringSize = (space.maxWidth * .3).clamp(280.0, 400.0);
        // In a large window the notes and the activity record get a pane
        // of their own, so the timings keep a comfortable width.
        final aside = space.maxWidth >= reportAsideMinWidth;
        final asideWidth = (space.maxWidth * .3).clamp(400.0, 640.0);
        // A tall window has room for deeper timeline blocks.
        final lane = MediaQuery.sizeOf(context).height >= 1200 ? 64.0 : 50.0;
        // The report as a whole keeps the 'report-detail-pane' key: the
        // scrolling timings on their own, or the row with the pane.
        final timings = SingleChildScrollView(
          key: ValueKey(aside ? 'report-timings-pane' : 'report-detail-pane'),
          primary: false,
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: aside ? 1480 : 1360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (r.churchName.isNotEmpty) r.churchName,
                                reportMode(r),
                              ].join(' · ').toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sectionLabelStyle(context),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.name,
                              key: const ValueKey('report-name'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 26,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r.startedWall == null
                                  ? '$day · ended ${clockLabel(r.endedWall)} · start not recorded'
                                  : '$day · ${clockLabel(r.startedWall!)} to ${clockLabel(r.endedWall)}',
                              key: const ValueKey('report-when'),
                              style: TextStyle(
                                color: colors.muted,
                                fontFeatures: _figures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        key: const ValueKey('print-report'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: busy ? null : () => run(widget.onPrint),
                        icon: const Icon(Icons.print_outlined, size: 20),
                        label: const Text('Print report'),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        key: const ValueKey('report-actions'),
                        tooltip: 'Report actions',
                        enabled: !busy,
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) => run(() async {
                          if (value == 'delete') {
                            await widget.onDelete();
                          } else {
                            await widget.onExport(value);
                          }
                        }),
                        itemBuilder: (context) =>
                            appMenuEntries(context, const [
                              AppMenuAction('csv', 'Export report CSV'),
                              AppMenuAction('json', 'Export report JSON'),
                              AppMenuAction(
                                'delete',
                                'Delete report',
                                destructive: true,
                              ),
                            ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  rule,
                  IntrinsicHeight(
                    child: Row(
                      key: const ValueKey('report-figures'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _figure('Planned', durationLabel(r.plannedMs)),
                        _figure(
                          'Actual',
                          r.totalMs == null
                              ? 'Not recorded'
                              : durationLabel(r.totalMs!),
                        ),
                        _figure(
                          'Variance',
                          variance == null ? '—' : outcomeLabel(variance),
                          color: variance == null
                              ? colors.muted
                              : _tone(colors, variance),
                        ),
                        _figure(
                          'Paused',
                          durationLabel(r.pausedMs),
                          color: r.pausedMs == 0 ? colors.muted : null,
                        ),
                        _figure(
                          'Time adjustments',
                          '${r.adjustmentMs > 0
                              ? '+'
                              : r.adjustmentMs < 0
                              ? '−'
                              : ''}${durationLabel(r.adjustmentMs)}',
                          color: r.adjustmentMs == 0 ? colors.muted : null,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  rule,
                  if (!r.comparable)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Partial or uncertain timing. Review the breakdown before comparing this record.',
                        style: TextStyle(color: colors.warning),
                      ),
                    ),
                  if (r.rehearsal)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Rehearsal durations are simulated time. Dates show real local clock time.',
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (beside)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: ringSize,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _pictureHeading(context),
                              ReportRing(report: r, size: ringSize),
                              const SizedBox(height: 6),
                              const ReportPictureLegend(
                                ring: true,
                                centred: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(child: table),
                      ],
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(child: _pictureHeading(context)),
                        ReportPictureLegend(ring: widget.ring),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (widget.ring)
                      Center(
                        child: ReportRing(
                          report: r,
                          size: math.min(ringSize, space.maxWidth - 56),
                        ),
                      )
                    else
                      ReportTwinTimeline(report: r, laneHeight: lane),
                    const SizedBox(height: 22),
                    table,
                  ],
                  if (!aside) ...[
                    const SizedBox(height: 22),
                    rule,
                    const SizedBox(height: 16),
                    ReviewNoteSection(
                      review: r.review,
                      busy: busy,
                      flat: true,
                      onEdit: () => run(widget.onEditReview),
                    ),
                    const SizedBox(height: 16),
                    rule,
                    ReportActivityTile(report: r),
                  ],
                ],
              ),
            ),
          ),
        );
        // With a finish the timings are a panel, beside the notes' own.
        if (!aside) return FinishPane(child: timings);
        return Row(
          key: const ValueKey('report-detail-pane'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: FinishPane(child: timings)),
            finishRule(
              context,
              VerticalDivider(width: 1, thickness: 1, color: colors.border),
            ),
            SizedBox(
              width: asideWidth,
              child: FinishPane(
                flatSurface: true,
                child: SingleChildScrollView(
                  key: const ValueKey('report-aside-pane'),
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ReviewNoteSection(
                        review: r.review,
                        busy: busy,
                        flat: true,
                        onEdit: () => run(widget.onEditReview),
                      ),
                      const SizedBox(height: 20),
                      rule,
                      const SizedBox(height: 20),
                      ReportActivityList(report: r),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pictureHeading(BuildContext context) =>
      Text('PLANNED AGAINST ACTUAL', style: sectionLabelStyle(context));

  Widget _figure(
    String label,
    String value, {
    Color? color,
    bool last = false,
  }) {
    final colors = appColors(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
        margin: EdgeInsets.only(right: last ? 0 : 16),
        decoration: BoxDecoration(
          border: last ? null : Border(right: BorderSide(color: colors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color ?? colors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFeatures: _figures,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The actual ring: text-toned, so it cannot be taken for the warning
/// colour or for a gold accent.
Color _ran(AppPalette colors) =>
    Color.lerp(colors.background, colors.text, .78)!;

/// The planned ring, quieter than the actual one.
Color _plan(AppPalette colors) =>
    Color.lerp(colors.background, colors.text, .36)!;

/// A finished block on the report timeline.
Color _done(AppPalette colors) =>
    Color.alphaBlend(_calm(colors).withValues(alpha: .16), colors.surface);

/// What the colours in the picture mean.
class ReportPictureLegend extends StatelessWidget {
  final bool ring, centred;
  const ReportPictureLegend({
    super.key,
    required this.ring,
    this.centred = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    Widget item(String text, Color color, {bool outline = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: outline ? null : color,
            border: outline ? Border.all(color: color) : null,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: colors.muted)),
      ],
    );
    return Wrap(
      alignment: centred ? WrapAlignment.center : WrapAlignment.end,
      spacing: 16,
      runSpacing: 4,
      children: ring
          ? [
              item('Planned', _plan(colors)),
              item('Actual', _ran(colors)),
              item('A minute or more over', colors.warning),
            ]
          : [
              item('Planned', colors.muted, outline: true),
              item('Actual', _done(colors)),
              item('Ran over', colors.warning.withValues(alpha: .45)),
            ],
    );
  }
}

/// Where each segment of a report sits in service time, planned and as
/// it really ran. Skipped segments, and ones with no recorded time, take
/// no room in the actual row.
class ReportPieces {
  /// (row index, start, length) in service time.
  final List<(int, int, int)> planned, actual;
  final int plannedMs, actualMs;
  ReportPieces._(this.planned, this.actual, this.plannedMs, this.actualMs);

  factory ReportPieces(ServiceReport r) {
    final planned = <(int, int, int)>[], actual = <(int, int, int)>[];
    var p = 0, a = 0;
    for (final (i, row) in r.rows.indexed) {
      if (row.plannedMs > 0) planned.add((i, p, row.plannedMs));
      p += math.max(0, row.plannedMs);
      final ran = row.skipped ? null : row.actualMs;
      if (ran != null && ran > 0) {
        actual.add((i, a, ran));
        a += ran;
      }
    }
    return ReportPieces._(planned, actual, p, a);
  }

  /// One scale for both rows.
  int get scaleMs => math.max(1, math.max(plannedMs, actualMs));
}

/// A row of planned blocks above a row of actual blocks on one time
/// scale, with clock times underneath: the Live timeline, looking back.
class ReportTwinTimeline extends StatelessWidget {
  final ServiceReport report;

  /// How deep each row of blocks is.
  final double laneHeight;
  const ReportTwinTimeline({
    super.key,
    required this.report,
    this.laneHeight = 50,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final r = report, pieces = ReportPieces(r), total = pieces.scaleMs;
    final rate = math.max(1, r.rate);
    final done = _done(colors);
    final small = TextStyle(
      fontSize: 11,
      color: colors.muted,
      fontFeatures: _figures,
    );
    const gutter = 64.0;
    Widget lane(String name, double w, List<Widget> blocks) => SizedBox(
      height: laneHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: gutter,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ),
          ),
          SizedBox(
            width: w,
            child: Stack(children: blocks),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      key: const ValueKey('report-timeline'),
      builder: (context, space) {
        final w = math.max(40.0, space.maxWidth - gutter);
        double x(int ms) => ms / total * w;
        Widget at((int, int, int) piece, Widget child) => Positioned(
          left: x(piece.$2),
          width: math.max(4, x(piece.$3) - 3),
          top: 0,
          bottom: 0,
          child: child,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            lane('Planned', w, [
              for (final piece in pieces.planned)
                at(
                  piece,
                  TimelineBlock(
                    key: ValueKey('report-planned-${piece.$1}'),
                    name: r.rows[piece.$1].name,
                    detail: formatTime(piece.$3),
                    border: colors.border,
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            lane('Actual', w, [
              for (final piece in pieces.actual)
                at(piece, () {
                  final over = piece.$3 - r.rows[piece.$1].plannedMs;
                  return TimelineBlock(
                    key: ValueKey('report-actual-${piece.$1}'),
                    name: r.rows[piece.$1].name,
                    detail: '${formatTime(piece.$3)} · ${signedTime(over)}',
                    fill: done,
                    border: Colors.transparent,
                    over: over > 0 ? (over / piece.$3).clamp(0.0, 1.0) : 0,
                  );
                }()),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: gutter),
              child: SizedBox(
                height: 16,
                child: r.startedWall == null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Start time not recorded · ended ${clockLabel(r.endedWall)}',
                          style: small,
                        ),
                      )
                    : TimelineClockScale(
                        startedWall: r.startedWall!,
                        totalMs: total,
                        rate: rate,
                        width: w,
                        trailing:
                            'plan ${clockLabel(r.startedWall! + (pieces.plannedMs / rate).round())} · ended ${clockLabel(r.endedWall)}',
                        trailingKey: const ValueKey('report-timeline-ends'),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The report as the app's mark: an outer ring of the time each segment
/// really took and a thinner inner ring of the plan, both running
/// clockwise from three o'clock to end at the cross.
class ReportRing extends StatelessWidget {
  final ServiceReport report;
  final double size;
  const ReportRing({super.key, required this.report, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final r = report, pieces = ReportPieces(r);
    final variance = r.totalMs == null ? null : r.totalMs! - r.plannedMs;
    final actual = r.totalMs == null
        ? 'Not recorded'
        : durationLabel(r.totalMs!);
    final words = variance == null ? 'No total' : outcomeLabel(variance);
    final geometry = DialGeometry(size);
    return Semantics(
      label: 'Actual $actual, $words, planned ${durationLabel(r.plannedMs)}',
      child: SizedBox.square(
        key: const ValueKey('report-ring'),
        dimension: size,
        child: ExcludeSemantics(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: ReportRingPainter(
                    pieces: pieces,
                    over: {
                      for (final (i, row) in r.rows.indexed)
                        if (!row.skipped &&
                            row.actualMs != null &&
                            row.actualMs! - row.plannedMs >= reportOverrunMs)
                          i,
                    },
                    ran: _ran(colors),
                    warning: colors.warning,
                    plan: _plan(colors),
                    track: colors.track,
                    mark: colors.text,
                    muted: colors.muted,
                    label:
                        Theme.of(context).textTheme.bodySmall ??
                        const TextStyle(),
                  ),
                ),
              ),
              Center(
                child: SizedBox(
                  width: geometry.inner * 1.5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ACTUAL',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          color: colors.muted,
                        ),
                      ),
                      SizedBox(
                        height: size * .13,
                        child: FittedBox(
                          child: Text(
                            actual,
                            key: const ValueKey('report-ring-actual'),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w400,
                              color: colors.text,
                              fontFeatures: _figures,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        words,
                        key: const ValueKey('report-ring-variance'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: variance == null
                              ? colors.muted
                              : _tone(colors, variance),
                          fontFeatures: _figures,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'planned ${durationLabel(r.plannedMs)}',
                        key: const ValueKey('report-ring-planned'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.muted,
                          fontFeatures: _figures,
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
    );
  }
}

class ReportRingPainter extends CustomPainter {
  final ReportPieces pieces;

  /// Rows that ran over by a minute or more.
  final Set<int> over;
  final Color ran, warning, plan, track, mark, muted;

  /// The app's text style, for the segment numbers.
  final TextStyle label;
  const ReportRingPainter({
    required this.pieces,
    required this.over,
    required this.ran,
    required this.warning,
    required this.plan,
    required this.track,
    required this.mark,
    required this.muted,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = DialGeometry(size.width);
    final total = pieces.scaleMs;
    const stroke = DialGeometry.line;
    final outer = Rect.fromCircle(center: g.centre, radius: g.outer);
    final inner = Rect.fromCircle(center: g.centre, radius: g.inner);
    final thin = math.max(5.0, size.width * .014);
    const end = math.pi * 1.5;
    // What is left of the scale after each ring's last segment.
    void rest(Rect ring, int ms, double width) {
      final from = DialGeometry.angle(ms, total);
      if (end - from > .01)
        canvas.drawArc(ring, from, end - from, false, stroke(track, width));
    }

    rest(outer, pieces.actualMs, g.stroke);
    rest(inner, pieces.plannedMs, thin);
    for (final (i, start, length) in pieces.actual) {
      final (a0, sweep) = g.arc(start, length, total);
      canvas.drawArc(
        outer,
        a0,
        sweep,
        false,
        stroke(over.contains(i) ? warning : ran, g.stroke),
      );
      // The segment's number, as in the table, where there is room.
      if (sweep * g.outer >= 15)
        g.paintNumber(
          canvas,
          a0 + sweep / 2,
          '${i + 1}',
          label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        );
    }
    for (final (_, start, length) in pieces.planned) {
      final (a0, sweep) = g.arc(start, length, total, radius: g.inner);
      canvas.drawArc(inner, a0, sweep, false, stroke(plan, thin));
    }
    g.paintCross(canvas, mark);
  }

  @override
  bool shouldRepaint(ReportRingPainter old) =>
      old.pieces != pieces ||
      old.ran != ran ||
      old.warning != warning ||
      old.plan != plan ||
      old.track != track ||
      old.mark != mark;
}

/// Every segment with its planned and actual time, how far apart they
/// were, and a bar showing that either side of a centre line.
class ReportSegmentTable extends StatelessWidget {
  final ServiceReport report;
  const ReportSegmentTable({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final r = report;
    int? varianceOf(ReportRow row) => row.skipped || row.actualMs == null
        ? null
        : row.actualMs! - row.plannedMs;
    // The longest bar is the largest difference, and at least a minute so
    // a few seconds do not fill the column.
    final widest = r.rows.fold<int>(
      reportOverrunMs,
      (n, row) => math.max(n, (varianceOf(row) ?? 0).abs()),
    );
    final head = TextStyle(fontSize: 12, color: colors.muted);
    const figures = TextStyle(fontSize: 14, fontFeatures: _figures);
    final rule = Divider(height: 1, thickness: 1, color: colors.border);
    return LayoutBuilder(
      builder: (context, space) {
        final bar = (space.maxWidth * .2).clamp(84.0, 240.0);
        Widget line({
          Key? key,
          required Widget number,
          required Widget name,
          required Widget planned,
          required Widget actual,
          required Widget variance,
          required Widget picture,
          double vertical = 8,
        }) => Padding(
          key: key,
          padding: EdgeInsets.symmetric(vertical: vertical),
          child: Row(
            children: [
              SizedBox(width: 30, child: number),
              Expanded(child: name),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: Align(alignment: Alignment.centerRight, child: planned),
              ),
              SizedBox(
                width: 112,
                child: Align(alignment: Alignment.centerRight, child: actual),
              ),
              SizedBox(
                width: 128,
                child: Align(alignment: Alignment.centerRight, child: variance),
              ),
              const SizedBox(width: 20),
              SizedBox(width: bar, child: picture),
            ],
          ),
        );
        final total = r.totalMs == null ? null : r.totalMs! - r.plannedMs;
        return Column(
          key: const ValueKey('report-table'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line(
              vertical: 6,
              number: Text('#', style: head),
              name: Text('Segment', style: head),
              planned: Text('Planned', style: head),
              actual: Text('Actual', style: head),
              variance: Text('Variance', style: head),
              picture: Row(
                children: [
                  Expanded(child: Text('Under', style: head)),
                  Text('Over', style: head),
                ],
              ),
            ),
            rule,
            for (final (i, row) in r.rows.indexed) ...[
              if (i > 0) rule,
              () {
                final variance = varianceOf(row);
                final segment =
                    r.program != null && i < r.program!.segments.length
                    ? r.program!.segments[i]
                    : null;
                final more = [
                  if (segment?.speaker.isNotEmpty == true) segment!.speaker,
                  if (row.pausedMs != 0)
                    'Paused ${durationLabel(row.pausedMs)}',
                  if (row.adjustmentMs != 0)
                    'Adjusted ${row.adjustmentMs > 0 ? '+' : '−'}${durationLabel(row.adjustmentMs)}',
                  if (segment?.notes.isNotEmpty == true)
                    'Private note: ${segment!.notes}',
                  if (row.actualMs == null && !row.skipped)
                    'No recorded duration',
                ].join(' · ');
                return line(
                  key: ValueKey('report-row-$i'),
                  number: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.muted,
                      fontFeatures: _figures,
                    ),
                  ),
                  name: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: row.skipped ? colors.muted : null,
                        ),
                      ),
                      if (more.isNotEmpty)
                        Tooltip(
                          message: more,
                          child: Text(
                            more,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ),
                    ],
                  ),
                  planned: Text(durationLabel(row.plannedMs), style: figures),
                  actual: Text(
                    row.skipped
                        ? 'Skipped'
                        : row.actualMs == null
                        ? 'Not recorded'
                        : durationLabel(row.actualMs!),
                    style: figures.copyWith(
                      color: row.skipped || row.actualMs == null
                          ? colors.muted
                          : null,
                    ),
                  ),
                  variance: Text(
                    variance == null ? '—' : outcomeLabel(variance),
                    style: figures.copyWith(
                      color: variance == null
                          ? colors.muted
                          : _tone(colors, variance),
                    ),
                  ),
                  picture: VarianceBar(variance: variance, widest: widest),
                );
              }(),
            ],
            Divider(height: 1, thickness: 1, color: colors.muted),
            line(
              key: const ValueKey('report-row-total'),
              number: const SizedBox.shrink(),
              name: const Text(
                'Total',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              planned: Text(
                durationLabel(r.plannedMs),
                style: figures.copyWith(fontWeight: FontWeight.w700),
              ),
              actual: Text(
                r.totalMs == null ? 'Not recorded' : durationLabel(r.totalMs!),
                style: figures.copyWith(
                  fontWeight: FontWeight.w700,
                  color: r.totalMs == null ? colors.muted : null,
                ),
              ),
              variance: Text(
                total == null ? '—' : outcomeLabel(total),
                style: figures.copyWith(
                  fontWeight: FontWeight.w700,
                  color: total == null ? colors.muted : _tone(colors, total),
                ),
              ),
              picture: const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

/// Under plan to the left of the centre line, over to the right, as a
/// share of [widest].
class VarianceBar extends StatelessWidget {
  final int? variance;
  final int widest;
  const VarianceBar({super.key, required this.variance, required this.widest});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final v = variance ?? 0;
    final share = (v.abs() / math.max(1, widest)).clamp(0.0, 1.0);
    Widget half(bool show, Alignment alignment, Color color) => Expanded(
      child: Align(
        alignment: alignment,
        child: show && v.abs() >= 1000
            ? FractionallySizedBox(
                widthFactor: math.max(.03, share),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            half(v < 0, Alignment.centerRight, colors.info),
            Container(
              width: 1,
              height: 18,
              color: variance == null ? colors.border : colors.muted,
            ),
            half(v > 0, Alignment.centerLeft, colors.warning),
          ],
        ),
      ),
    );
  }
}

/// Everything recorded during the service, in order, opened out for the
/// pane beside a report in a large window. The same events as
/// [ReportActivityTile].
class ReportActivityList extends StatelessWidget {
  final ServiceReport report;
  const ReportActivityList({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final r = report;
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    String two(int n) => n.toString().padLeft(2, '0');
    return Column(
      key: const ValueKey('report-activity-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: PaneLabel('Activity timeline')),
            Text('${r.events.length} recorded events', style: muted),
          ],
        ),
        const SizedBox(height: 8),
        Text('Controller acceptance is not visual confirmation.', style: muted),
        const SizedBox(height: 8),
        if (r.events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No activity events were recorded for this service.',
              style: muted,
            ),
          ),
        for (final (i, event) in r.events.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    '${clockLabel(event.wall)}:${two(DateTime.fromMillisecondsSinceEpoch(event.wall).second)}',
                    style: muted.copyWith(fontFeatures: _figures),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 10),
                  child: Icon(
                    event.kind == 'failed' || event.kind == 'hold'
                        ? Icons.warning_amber
                        : event.kind == 'accepted'
                        ? Icons.check_circle_outline
                        : Icons.history,
                    size: 16,
                    color: event.kind == 'failed' || event.kind == 'hold'
                        ? colors.warning
                        : colors.muted,
                  ),
                ),
                Expanded(
                  child: Text(
                    event.message,
                    style: const TextStyle(fontSize: 14, height: 1.3),
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
