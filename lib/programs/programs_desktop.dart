import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';

/// Puts the floating New program button at the foot of the list column
/// instead of the window's right edge.
class ListColumnButtonLocation extends FloatingActionButtonLocation {
  /// Where the list column ends, from the window's left edge; set each
  /// time the page is laid out.
  double? columnRight;
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final end = FloatingActionButtonLocation.endFloat.getOffset(
      scaffoldGeometry,
    );
    final right = columnRight;
    if (right == null) return end;
    return Offset(
      math.max(0, right - 16 - scaffoldGeometry.floatingActionButtonSize.width),
      end.dy,
    );
  }
}

/// Programs in a desktop layout: the list on the left, the chosen program
/// as a table in the middle and its summary on the right. Each column
/// scrolls on its own. The list, the actions and the editor are the same
/// ones the phone uses.
extension ProgramsDesktop on HomeState {
  Widget programsDesktop() {
    final colors = appColors(context);
    final line = finishRule(
      context,
      VerticalDivider(width: 1, thickness: 1, color: colors.border),
    );
    // A column: the plain surface in Flat, and with a finish a panel of its
    // material, as Live's columns are, so nothing sits on the bare wall.
    final finished = finishLook(context).active;
    Widget column(Widget child, {bool surface = true}) => finished
        ? FinishPane(child: child)
        : surface
        ? Material(color: colors.surface, child: child)
        : child;
    // The program stays open only while the search and filter show it,
    // as on the tablet page.
    final shown = c.state.programLibrary.find(
      c.state.templates,
      programsPage.query,
      programsPage.filter,
    );
    final open = shown.where((p) => p.name == programsPage.open).firstOrNull;
    void select(String name) => refreshHome(() => programsPage.open = name);
    return LayoutBuilder(
      builder: (context, space) {
        // A finish's panel takes a margin and an edge from the column, so
        // the list is wider by as much, and its title and buttons keep
        // their room.
        final list =
            (space.maxWidth * .22).clamp(300.0, 360.0) + (finished ? 28 : 0);
        final summary = (space.maxWidth * .22).clamp(320.0, 380.0);
        // The page starts after the side rail, when there is one.
        programsButtonLocation.columnRight =
            MediaQuery.sizeOf(context).width - space.maxWidth + list;
        return Row(
          key: const ValueKey('programs-desktop'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: list,
              child: column(
                SingleChildScrollView(
                  key: const ValueKey('programs-list-pane'),
                  primary: false,
                  padding: const EdgeInsets.only(top: 12),
                  // The list ends with room for New program, which
                  // floats over the foot of this column.
                  child: FlatPanels(child: templates()),
                ),
              ),
            ),
            line,
            Expanded(
              child: column(
                surface: false,
                open == null
                    ? programsDesktopEmpty()
                    : programTable(open, select),
              ),
            ),
            line,
            SizedBox(
              width: summary,
              child: column(
                SingleChildScrollView(
                  key: const ValueKey('programs-summary-pane'),
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: open == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            label('Summary'),
                            const SizedBox(height: 10),
                            Text(
                              'The total time, the shape of the service and what past reports say show here.',
                              style: TextStyle(color: colors.muted),
                            ),
                          ],
                        )
                      : programSummary(open, context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget programsDesktopEmpty() {
    final colors = appColors(context);
    final none = c.state.templates.isEmpty;
    return Center(
      key: const ValueKey('programs-table-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_timeline_outlined, size: 40, color: colors.muted),
            const SizedBox(height: 14),
            Text(
              none ? 'Nothing to show yet' : 'Choose a program on the left',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              none
                  ? 'Create or import a program on the left. Its segments show here.'
                  : 'Its segments, speakers and private notes show here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }

  /// The chosen program: its name and actions, then one row per segment.
  Widget programTable(Timeline t, ValueChanged<String> select) {
    final colors = appColors(context);
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    const figures = [FontFeature.tabularFigures()];
    final total = t.segments.fold<int>(0, (sum, s) => sum + s.durationMs);
    void edit() {
      if (!c.busy && !c.corrupt) editProgram(t, select: select);
    }

    // #, Segment, Minutes, Speaker, Private note.
    Widget cells(List<Widget> cell, {double vertical = 10}) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: vertical),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 34, child: cell[0]),
          Expanded(flex: 5, child: cell[1]),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Align(alignment: Alignment.topRight, child: cell[2]),
          ),
          const SizedBox(width: 24),
          Expanded(flex: 4, child: cell[3]),
          const SizedBox(width: 12),
          Expanded(flex: 6, child: cell[4]),
        ],
      ),
    );
    Widget heading(String text) => Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: sectionLabelStyle(context),
    );
    Widget optional(String text, {int lines = 2}) => text.isEmpty
        ? Text('–', style: muted)
        : Tooltip(
            message: text,
            waitDuration: const Duration(milliseconds: 600),
            child: Text(
              text,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: muted.copyWith(color: colors.text),
            ),
          );
    return Column(
      key: const ValueKey('program-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      key: const ValueKey('program-table-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${t.type == 'rehearsal' ? 'Rehearsal' : 'Service'} · ${templateSummary(t)} · ${lastUsedLabel(c.state.programLibrary.recent[t.id])}',
                      style: muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              editProgramButton(t, select: select, height: 44),
              const SizedBox(width: 4),
              ...programActionButtons(
                t,
                select: select,
                onDeleted: () => refreshHome(() => programsPage.open = null),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: colors.border),
        cells([
          heading('#'),
          heading('Segment'),
          heading('Minutes'),
          heading('Speaker'),
          heading('Private note'),
        ]),
        Divider(height: 1, thickness: 1, color: colors.border),
        Expanded(
          child: ListView(
            key: const ValueKey('program-table-rows'),
            primary: false,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (var i = 0; i < t.segments.length; i++) ...[
                // Double-click opens the program editor; the table itself
                // only shows the saved program.
                InkWell(
                  key: ValueKey('program-table-row-$i'),
                  onDoubleTap: edit,
                  child: cells([
                    Text(
                      '${i + 1}',
                      style: muted.copyWith(fontFeatures: figures),
                    ),
                    Text(
                      t.segments[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      t.segments[i].durationText,
                      style: const TextStyle(fontFeatures: figures),
                    ),
                    optional(t.segments[i].speaker),
                    optional(t.segments[i].notes, lines: 3),
                  ], vertical: 12),
                ),
                Divider(height: 1, thickness: 1, color: colors.border),
              ],
              // The total ends where the Minutes column ends, with the
              // Segment column's room to its left for a long figure.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: LayoutBuilder(
                  builder: (context, row) => Row(
                    children: [
                      SizedBox(
                        width: 130 + (row.maxWidth - 166) / 3,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const SizedBox(width: 34),
                            Text('Total', style: muted),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                durationLabel(total),
                                key: const ValueKey('program-table-total'),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: figures,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Text(
                  'Double-click a segment to open the program editor.',
                  style: muted.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Load into Live, the shape of the program, its times, what past
  /// reports say, the end screen and the warnings.
  Widget programSummary(Timeline t, BuildContext pageContext) {
    final colors = appColors(context);
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    final total = t.segments.fold<int>(0, (sum, s) => sum + s.durationMs);
    // A start time set in Live stays when another program is loaded, so
    // the finish it would give this program is worth showing.
    final session = c.state.session;
    final startsAt = session.phase == 'ready' ? session.startsAtWall : null;
    final insights = durationInsights(t, c.state.reports);
    final rule = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(height: 1, thickness: 1, color: colors.border),
    );
    Widget figure(String name, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(name, style: muted)),
          const SizedBox(width: 12),
          Text(
            value,
            key: key,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    final longest = t.segments.reduce(
      (a, b) => b.durationMs > a.durationMs ? b : a,
    );
    return Column(
      key: const ValueKey('program-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        loadIntoLiveButton(t, pageContext),
        if (c.state.session.active)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'End the current service before loading another program.',
              style: muted.copyWith(fontSize: 12),
            ),
          ),
        rule,
        label('Shape'),
        const SizedBox(height: 12),
        SegmentBar(program: t, height: 12),
        const SizedBox(height: 8),
        Text(
          t.segments.length == 1
              ? 'One segment.'
              : 'Longest: ${longest.name}, ${longest.durationText} of ${durationLabel(total)}.',
          style: muted.copyWith(fontSize: 12),
        ),
        rule,
        label('Time'),
        const SizedBox(height: 4),
        figure(
          'Total time',
          durationLabel(total),
          key: const ValueKey('program-summary-total'),
        ),
        figure('Segments', '${t.segments.length}'),
        if (startsAt != null) ...[
          figure(
            'Planned finish',
            clockLabel(startsAt + total),
            key: const ValueKey('program-summary-finish'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'For the ${clockLabel(startsAt)} start set in Live.',
              style: muted.copyWith(fontSize: 12),
            ),
          ),
        ],
        rule,
        label('Past services'),
        if (insights.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              t.type == 'rehearsal'
                  ? 'Rehearsals are not compared.'
                  : 'Not enough comparable services yet. Three finished services with this program are needed.',
              style: muted,
            ),
          )
        else
          for (final i in insights)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ran over in ${i.exceeded} of ${i.samples} services · planned ${i.currentMinutes} min · suggested ${i.suggestedMinutes} min',
                    style: muted,
                  ),
                ],
              ),
            ),
        rule,
        label('End screen'),
        const SizedBox(height: 10),
        Text(
          endScreenTitle(t),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(endScreenLine(t), style: muted.copyWith(fontSize: 12)),
        rule,
        label('Warnings'),
        const SizedBox(height: 10),
        Text(programWarningsLine, style: muted.copyWith(fontSize: 12)),
      ],
    );
  }
}
