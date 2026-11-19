import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/live/practice_views.dart';
import 'package:church_service_timer/live/quick_timer_sheet.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// Live before a service, in a wide window. The same three panes as a
/// running service, so nothing jumps when one starts: programs to load on
/// the left, the start card in the middle, the stage and cues on the right.
extension StandingByDesktop on HomeState {
  Widget standingByDesktop({
    required List<Widget> notices,
    required Widget header,
    required Widget start,
    required Widget display,
    required Widget cues,
  }) {
    final colors = appColors(context);
    final line = VerticalDivider(width: 1, thickness: 1, color: colors.border);
    return LayoutBuilder(
      builder: (context, space) {
        final side = (space.maxWidth * .25).clamp(320.0, 460.0);
        final stage = (space.maxWidth * .28).clamp(372.0, 540.0);
        final tall = space.maxHeight >= 900;
        return Row(
          key: const ValueKey('standing-by-desktop'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: side,
              child: ColoredBox(color: colors.surface, child: programsPane()),
            ),
            line,
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('standing-by-start-pane'),
                primary: false,
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...notices,
                        standingByClock(header),
                        const SizedBox(height: 20),
                        if (standingByProgram case final program?)
                          nextServiceCard(program)
                        else
                          start,
                        if (c.state.reports.isNotEmpty) lastServiceCard(),
                        practicePrompt(),
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
                  key: const ValueKey('standing-by-stage-pane'),
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FlatPanels(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        display,
                        const AppDivider(),
                        cues,
                        if (c.destination == 'mobile') ...[
                          const AppDivider(),
                          quickMessagePanel(),
                        ],
                        if (tall) ...[const AppDivider(), screensSection()],
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

  /// Every program, pinned ones first, then the most recently used. A click
  /// loads one into Ready, exactly as Start service does.
  Widget programsPane() {
    final colors = appColors(context);
    final lib = c.state.programLibrary;
    final programs = standingByPrograms;
    final disabled =
        c.busy || c.corrupt || c.reportSavePending || controlsLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
          child: Row(
            children: [
              Expanded(child: label('Choose a program')),
              TextButton(
                key: const ValueKey('standing-by-all-programs'),
                onPressed: controlsLocked ? null : () => goToPage(1),
                child: const Text('Edit programs'),
              ),
            ],
          ),
        ),
        Expanded(
          child: programs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'No programs yet. Create one in Programs, then load it here.',
                    style: TextStyle(color: colors.muted),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('standing-by-programs'),
                  primary: false,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: programs.length,
                  separatorBuilder: (_, _) => const AppDivider(),
                  itemBuilder: (context, i) {
                    final p = programs[i];
                    final pinned = lib.favourites.contains(p.id);
                    final chosen = p.id == standingByProgram?.id;
                    return Material(
                      color: chosen
                          ? colors.accent.withValues(alpha: .12)
                          : Colors.transparent,
                      child: InkWell(
                        key: ValueKey('standing-by-program:${p.name}'),
                        onTap: () =>
                            refreshHome(() => standingByProgramId = p.id),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: chosen
                                    ? colors.accent
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(17, 12, 8, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      templateSummary(p),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: colors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              if (pinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 16,
                                    color: colors.muted,
                                    semanticLabel: 'Pinned',
                                  ),
                                ),
                              IconButton(
                                key: ValueKey('quick-load:${p.name}'),
                                tooltip: 'Load ${p.name}',
                                onPressed: disabled
                                    ? null
                                    : () => loadStandingByProgram(p),
                                icon: const Icon(Icons.play_circle_outline),
                                color: colors.accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Programs in the order they are offered: pinned first, then the most
  /// recently used.
  List<Timeline> get standingByPrograms {
    final lib = c.state.programLibrary;
    return [...c.state.templates]..sort((a, b) {
      final pinA = lib.favourites.contains(a.id) ? 0 : 1;
      final pinB = lib.favourites.contains(b.id) ? 0 : 1;
      if (pinA != pinB) return pinA - pinB;
      return (lib.recent[b.id] ?? 0).compareTo(lib.recent[a.id] ?? 0);
    });
  }

  /// The program shown in the middle: the one clicked, or else the first
  /// offered.
  Timeline? get standingByProgram {
    final programs = standingByPrograms;
    if (programs.isEmpty) return null;
    return programs.firstWhere(
      (p) => p.id == standingByProgramId,
      orElse: () => programs.first,
    );
  }

  Future<void> loadStandingByProgram(Timeline p) async {
    try {
      c.state.templateIndex(p);
      await c.act('load', value: p);
    } catch (e) {
      if (mounted) await showError('$e');
    }
  }

  /// The time of day, large, with the date: what an operator watches
  /// while waiting for a service to begin.
  Widget standingByClock(Widget header) {
    final colors = appColors(context);
    final now = DateTime.fromMillisecondsSinceEpoch(c.now.wall).toLocal();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final starts = c.state.session.startsAtWall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              clockLabel(c.now.wall),
              key: const ValueKey('standing-by-clock'),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w300,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      starts == null
                          ? 'No service running'
                          : 'Service starts at ${clockLabel(starts)}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The chosen program's order of service, and the buttons that begin.
  Widget nextServiceCard(Timeline p) {
    final colors = appColors(context);
    final disabled =
        c.busy || c.corrupt || c.reportSavePending || controlsLocked;
    final total = p.segments.fold<int>(0, (sum, s) => sum + s.durationMs);
    const shown = 8;
    final rows = p.segments.take(shown).toList();
    final text = Theme.of(context).textTheme;
    Widget quiet(Key? key, String name, IconData icon, VoidCallback? action) =>
        OutlinedButton.icon(
          key: key,
          onPressed: action,
          icon: Icon(icon, size: 18),
          label: Text(name),
        );
    return AppPanel(
      child: Column(
        key: const ValueKey('standing-by-next-service'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label('Order of service'),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                templateSummary(p),
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('standing-by-print'),
                tooltip: 'Print order of service',
                visualDensity: VisualDensity.compact,
                color: colors.muted,
                onPressed: controlsLocked ? null : () => printServiceSheet(p),
                icon: const Icon(Icons.print_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Each segment's share of the service.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final (i, s) in p.segments.indexed)
                    Expanded(
                      flex: (s.durationMs / 1000).round().clamp(1, 1 << 20),
                      child: Container(
                        margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                        color: colors.accent.withValues(
                          alpha: i.isEven ? .75 : .4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final (i, s) in rows.indexed) ...[
            if (i > 0) const AppDivider(indent: 0, endIndent: 0),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${i + 1}'.padLeft(2, '0'),
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: s.name,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          if (s.speaker.isNotEmpty)
                            TextSpan(
                              text: '   ${s.speaker}',
                              style: text.bodyMedium?.copyWith(
                                color: colors.muted,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    s.durationText,
                    style: text.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (p.segments.length > shown)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'and ${plural(p.segments.length - shown, 'more segment')}',
                style: text.bodySmall?.copyWith(color: colors.muted),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Planned to run ${durationLabel(total)}. Start service opens Ready, where you check the display and start the first segment.',
                  style: text.bodySmall?.copyWith(color: colors.muted),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                key: const ValueKey('standing-by-load'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: disabled ? null : () => loadStandingByProgram(p),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start service'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const AppDivider(indent: 0, endIndent: 0),
          const SizedBox(height: 12),
          Text(
            'Or, without a program',
            style: text.bodySmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              quiet(
                const ValueKey('quick-timer-live'),
                'Quick timer',
                Icons.timer_outlined,
                quickTimerAvailable ? openQuickTimer : null,
              ),
              quiet(
                const ValueKey('share-service-live'),
                c.pairing.hosting ? 'Manage sharing' : 'Share to screens',
                Icons.cast_connected,
                disabled ? null : shareServiceSetup,
              ),
              quiet(
                null,
                'Join a service',
                Icons.tablet_mac_outlined,
                disabled || !c.pairing.localControl ? null : joinAsStageScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
