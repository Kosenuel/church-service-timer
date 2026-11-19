import 'dart:async';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

extension LiveTimingViews on HomeState {
  Future<void> confirmPause() async {
    final s = c.state.session;
    final paused = s.paused, revision = s.revision;
    if (await confirmTimer(
      revision: revision,
      title:
          '${paused ? 'Resume' : 'Pause'} ${s.timeline!.segments[s.index].name}?',
      action: paused ? 'Confirm resume' : 'Confirm pause',
      content: () => Text(
        '${paused ? 'Continue from' : 'Hold the timer at'} ${operatorTimeDescription(c.state.session.balance(c.now))}.${paused ? '' : ' It stays paused until you resume.'}\n\nAny stage cue stays visible. Service elapsed time includes pauses.',
      ),
    ))
      await c.act('pause', revision: revision);
  }

  Widget timingOverview() {
    final s = c.state.session;
    final projected = s.projectedTotal(c.now);
    final eta =
        c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round();
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(
            s.rehearsal
                ? 'Rehearsal timing · ${s.rate}×'
                : 'Service timing overview',
          ),
          const SizedBox(height: 10),
          if (s.run == null)
            const Text(
              'This service started before timing reports were available. Start a new service to track its full duration.',
            )
          else ...[
            Text(
              varianceLabel(projected - s.plannedMs),
              style: TextStyle(
                fontSize: 24,
                color: projected > s.plannedMs + 999
                    ? appColors(context).warning
                    : appColors(context).accent,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                Text('Planned ${durationLabel(s.plannedMs)}'),
                Text('Elapsed ${durationLabel(s.totalElapsed(c.now))}'),
                Text('This segment ${durationLabel(s.currentElapsed(c.now))}'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              s.phase == 'ended'
                  ? 'Final duration recorded in Reports.'
                  : 'Estimated finish ${clockLabel(eta)}${s.paused ? ' · if resumed now' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              s.rehearsal
                  ? 'Durations are simulated at ${s.rate}×; finish time is real clock time. Advances remain manual.'
                  : 'Includes pauses and time spent at zero. Assumes remaining segments use their planned duration.',
              style: TextStyle(color: appColors(context).muted, fontSize: 12),
            ),
            if (s.uncertain)
              Text(
                'Timing is uncertain after recovery.',
                style: TextStyle(color: appColors(context).warning),
              ),
          ],
          if (s.phase == 'ended')
            TextButton.icon(
              onPressed: () => navigatePage(2),
              icon: const Icon(Icons.assessment_outlined),
              label: const Text('Open reports'),
            ),
        ],
      ),
    );
  }

  Future<void> jumpToSegment() async {
    final s = c.state.session;
    final target = await showAppSelection<int>(
      context,
      title: 'Jump to segment',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = s.index + 1; i < s.timeline!.segments.length; i++) ...[
            if (i > s.index + 1) const AppDivider(),
            ListTile(
              onTap: () => Navigator.pop(ctx, i),
              leading: Text('${i + 1}'.padLeft(2, '0')),
              title: Text(s.timeline!.segments[i].name),
              subtitle: Text(s.timeline!.segments[i].durationText),
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
        ],
      ),
    );
    if (target == null || !mounted) return;
    await confirmJump(target, session: s);
  }

  /// Asks before jumping to the later segment at [target]. [session] is
  /// the service as it was when the segment was picked, so a change made
  /// meanwhile is caught by the confirmation.
  Future<void> confirmJump(int target, {Session? session}) async {
    final s = session ?? c.state.session, revision = s.revision;
    final skipped = s.timeline!.segments
        .sublist(s.index + 1, target)
        .map((e) => e.name)
        .join(', ');
    if (await confirmTimer(
      revision: revision,
      title: 'Jump to ${s.timeline!.segments[target].name}?',
      action: 'Jump to segment',
      content: () => Text(
        'Finish ${s.timeline!.segments[s.index].name}. ${skipped.isEmpty ? 'No segments are bypassed.' : 'Mark as skipped: $skipped.'}\n\nStart with ${s.timeline!.segments[target].durationText}. ${s.paused ? 'The timer stays paused.' : 'The timer starts counting.'}',
      ),
    ))
      await c.act('jump', value: target, revision: revision);
  }

  Widget focusedTimingOverview() {
    final s = c.state.session,
        projected = c.state.session.projectedTotal(c.now);
    final eta =
        c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round();
    return panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: const ValueKey('focused-timing-overview'),
        // The same 24 px insets as the cards around it.
        tilePadding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text(
          'Service timing overview',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${varianceLabel(projected - s.plannedMs)}\nElapsed ${durationLabel(s.totalElapsed(c.now))} · Finish ${clockLabel(eta)}${s.paused ? ' if resumed now' : ''}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: timingOverview(),
          ),
        ],
      ),
    );
  }
}
