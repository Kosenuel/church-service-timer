import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/live/practice_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// Live before a service, in a wide window. The same three panes as a
/// running service, so nothing jumps when one starts: programs to load on
/// the left, the start card in the middle, the stage and cues on the right.
extension StandingByDesktop on HomeState {
  Widget standingByDesktop({
    required List<Widget> notices,
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
                        start,
                        practicePrompt(),
                        if (c.state.reports.isNotEmpty) lastServiceCard(),
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
    final programs = [...c.state.templates]
      ..sort((a, b) {
        final pinA = lib.favourites.contains(a.id) ? 0 : 1;
        final pinB = lib.favourites.contains(b.id) ? 0 : 1;
        if (pinA != pinB) return pinA - pinB;
        return (lib.recent[b.id] ?? 0).compareTo(lib.recent[a.id] ?? 0);
      });
    final disabled =
        c.busy || c.corrupt || c.reportSavePending || controlsLocked;
    Future<void> load(Timeline p) async {
      try {
        c.state.templateIndex(p);
        await c.act('load', value: p);
      } catch (e) {
        if (mounted) await showError('$e');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
          child: Row(
            children: [
              Expanded(child: label('Programs')),
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
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('quick-load:${p.name}'),
                        onTap: disabled ? null : () => load(p),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
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
                                    const SizedBox(height: 6),
                                    Text(
                                      p.segments.map((s) => s.name).join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: colors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (pinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 16,
                                    color: colors.muted,
                                    semanticLabel: 'Pinned',
                                  ),
                                ),
                              Icon(
                                Icons.play_circle_outline,
                                color: disabled ? colors.muted : colors.accent,
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
}
