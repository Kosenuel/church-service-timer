import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

/// Starting, advancing and cueing the service from Live.
extension LiveActions on HomeState {
  Future<void> chooseService() async {
    final picked = await showAppSelection<Timeline>(
      context,
      title: 'Start a service',
      builder: (ctx) => ProgramChooser(
        controller: c,
        onCreate: () async {
          Navigator.pop(ctx);
          await editTemplate();
          if (mounted) await chooseService();
        },
      ),
    );
    if (!mounted || picked == null) return;
    try {
      c.state.templateIndex(picked);
      await c.act('load', value: picked);
    } catch (e) {
      if (mounted) await showError('$e');
    }
  }

  /// Swaps the program in Ready for another, keeping the start time and
  /// service mode, with a short Undo for a wrong tap.
  Future<void> changeProgram() async {
    final previous = c.state.session.timeline;
    if (previous == null || c.state.session.phase != 'ready') return;
    final picked = await showAppSelection<Timeline>(
      context,
      title: 'Change program',
      builder: (ctx) => ProgramChooser(
        controller: c,
        current: previous.name,
        onCreate: () async {
          Navigator.pop(ctx);
          await editTemplate();
          if (mounted) await changeProgram();
        },
      ),
    );
    if (!mounted || picked == null || picked.name == previous.name) return;
    try {
      c.state.templateIndex(picked);
      if (!await c.act('load', value: picked)) {
        if (mounted) await showError(c.error ?? 'Could not change program.');
        return;
      }
    } catch (e) {
      if (mounted) await showError('$e');
      return;
    }
    if (mounted)
      offerUndo('Switched to ${picked.name}', () async {
        // Nothing to undo once the service started or the setup was cancelled.
        if (c.state.session.phase != 'ready') return true;
        return c.act('load', value: previous);
      });
  }

  /// The loaded program's name with a one-tap way to switch it.
  Widget readyProgramRow(Timeline t) => Row(
    key: const ValueKey('ready-program'),
    children: [
      Icon(Icons.event_note_outlined, color: appColors(context).muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          t.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      TextButton.icon(
        key: const ValueKey('change-program'),
        onPressed:
            c.busy || controlsLocked || !c.pairing.localControl || c.corrupt
            ? null
            : changeProgram,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Change'),
      ),
    ],
  );

  /// Starting while the pre-service countdown is still running asks first.
  Future<bool> confirmEarlyStart() async {
    final at = c.state.session.startsAtWall;
    if (at == null) return true;
    final left = at - c.now.wall;
    if (left <= 0) return true;
    final wait = left >= 3600000
        ? '${left ~/ 3600000} h ${(left % 3600000) ~/ 60000} min'
        : formatTime(left);
    final start = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('early-start'),
        title: Text('The service is scheduled for ${wallTime(at)}'),
        content: Text(
          'That is $wait from now. Start now? The countdown on the display stops and the first segment begins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start now'),
          ),
        ],
      ),
    );
    return start == true;
  }

  Future<void> startFirst() async {
    if (!await confirmEarlyStart() || !mounted) return;
    final s = c.state.session, revision = c.state.session.revision;
    final problems = readinessChecks()
        .where((x) => !x.ok && x.key != 'program')
        .toList();
    if (c.destinationConnected && problems.isEmpty) {
      await startWithUndo(revision);
      return;
    }
    final start = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AnimatedBuilder(
        animation: c,
        builder: (ctx, _) {
          final colors = appColors(ctx);
          return AlertDialog(
            title: Text(
              !c.destinationConnected
                  ? 'No display connected'
                  : problems.length == 1
                  ? problems.single.detail
                  : '${plural(problems.length, 'thing')} to check',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You can still start ${s.timeline!.segments.first.name}.',
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(connectionIcon(c.displayConnection)),
                  title: Text('Display: ${c.destinationName}'),
                  subtitle: Text(c.displayConnection.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(ctx, false);
                    await chooseDisplay();
                  },
                ),
                for (final p in problems)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.priority_high, color: colors.warning),
                    title: Text(p.title),
                    subtitle: Text(p.detail),
                    trailing: p.fix == null
                        ? null
                        : TextButton(
                            onPressed: () async {
                              Navigator.pop(ctx, false);
                              await p.onFix?.call();
                            },
                            child: Text(p.fix!),
                          ),
                  ),
                if (s.rehearsal) Text('Rehearsal · ${s.rate}× speed'),
              ],
            ),
            actions: [
              StackedDialogActions(
                children: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      c.destinationConnected
                          ? 'Start first segment'
                          : 'Start without a display',
                    ),
                  ),
                  if (!c.destinationConnected)
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx, false);
                        await chooseDisplay();
                      },
                      child: const Text('Connect display'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (start == true) await startWithUndo(revision);
  }

  /// Starts the loaded service and offers a short Undo for accidental taps.
  Future<void> startWithUndo(int revision) async {
    if (!await c.act('start', revision: revision) || !mounted) return;
    final id = c.state.session.id;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('undo-start'),
        duration: const Duration(seconds: 8),
        // An action normally keeps a snackbar up until tapped.
        persist: false,
        content: Text(
          '${c.state.session.timeline!.segments.first.name} started',
        ),
        action: SnackBarAction(
          label: 'Undo start',
          onPressed: () async {
            if (c.state.session.id != id || !c.state.session.active) return;
            if (await c.act('unstart')) return;
            final message = c.error ?? 'Could not undo the start.';
            c.dismissError();
            if (mounted) await showError(message);
          },
        ),
      ),
    );
  }

  Future<void> advance() async {
    final s = c.state.session, revision = c.state.session.revision;
    final next = s.timeline!.segments[s.index + 1];
    var keepBlank = false;
    if (await confirmTimer(
      revision: revision,
      title: 'Start ${next.name}?',
      action: 'Start ${next.name}',
      content: () => StatefulBuilder(
        builder: (context, update) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Finish ${s.timeline!.segments[s.index].name} and start ${next.name} · ${next.durationText}. Previous cues are cleared and the new countdown is sent.${c.hardware.held ? ' This also restores the reviewed output on the connected display.' : ''}',
            ),
            if (s.outputBlank)
              CheckboxListTile(
                title: const Text('Keep the display blank'),
                value: keepBlank,
                onChanged: (v) => update(() => keepBlank = v!),
              ),
          ],
        ),
      ),
    ))
      await c.act('advance', value: keepBlank, revision: revision);
  }

  Future<void> undo() async {
    final s = c.state.session, revision = c.state.session.revision;
    if (s.undo == null) return;
    if (await confirmTimer(
      revision: revision,
      title: 'Undo segment change?',
      action: 'Restore previous segment',
      content: () => Text(
        'Return to ${s.timeline!.segments[s.undo!.index].name} with ${operatorTimeDescription(s.undoBalance(c.now))} of ${formatTime(s.undoAllocatedMs)} allocated. ${s.undo!.paused ? 'Its timer will remain paused.' : 'Its timer will resume, accounting for time since the segment change.'}\n\nChanges made to ${s.timeline!.segments[s.index].name} will be discarded. The active stage cue stays visible.${s.uncertain ? '\nTiming is uncertain after recovery.' : ''}',
      ),
    ))
      await c.act('undo', revision: revision);
  }

  Future<TextLayout?> compose(
    TextLayout initial,
    String title,
    String button, {
    Future<bool> Function()? onDelete,
  }) => showDialog<TextLayout>(
    context: context,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => TextComposer(
      initial: initial,
      title: title,
      button: button,
      onDelete: onDelete,
    ),
  );
  Future<void> sendCue(TextLayout layout, {int? cueIndex}) async {
    final revision = c.state.session.revision;
    final result = await compose(
      layout,
      cueIndex == null ? 'New stage cue' : 'Edit stage cue',
      'Send',
      onDelete: cueIndex == null
          ? null
          : () async {
              if (!await confirm(
                'Delete this saved cue?',
                'Remove “${layout.text}” from the cues shared across all services? A cue already showing on stage stays visible until replaced or dismissed.',
                'Delete cue',
                destructive: true,
              ))
                return false;
              final ok = await c.deleteStageCue(cueIndex, layout);
              if (!ok && mounted)
                await showError(c.error ?? 'The cue could not be deleted.');
              return ok;
            },
    );
    if (result != null) {
      await c.sendAndSaveCue(result, index: cueIndex, revision: revision);
    }
  }
}
