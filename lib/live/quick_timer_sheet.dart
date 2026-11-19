import 'dart:async';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:flutter/material.dart';

/// What the Quick timer sheet asks for.
class QuickTimerRequest {
  final QuickTimerChoice choice;
  final bool saveReport;
  const QuickTimerRequest(this.choice, {this.saveReport = false});
}

extension QuickTimerViews on HomeState {
  /// Quick timer is for when nothing is loaded: standing by, or after a
  /// service has ended.
  bool get quickTimerAvailable {
    final s = c.liveSession;
    return c.ready &&
        !c.busy &&
        !c.corrupt &&
        !controlsLocked &&
        c.pairing.localControl &&
        !c.reportSavePending &&
        (s.phase == 'idle' || s.phase == 'ended');
  }

  /// Opens the Quick timer sheet and starts the chosen timer.
  Future<void> openQuickTimer() async {
    final request = await showAppSheet<QuickTimerRequest>(
      context,
      useSafeArea: true,
      builder: (_) => QuickTimerSheet(recent: c.state.recentQuickTimers),
    );
    if (request == null || !mounted) return;
    if (!await c.startQuickTimer(
          request.choice,
          saveReport: request.saveReport,
        ) &&
        mounted) {
      await showError(c.error ?? 'Could not start the quick timer.');
    }
  }
}

class QuickTimerSheet extends StatefulWidget {
  final List<QuickTimerChoice> recent;
  const QuickTimerSheet({super.key, this.recent = const []});
  @override
  State<QuickTimerSheet> createState() => _QuickTimerSheetState();
}

class _QuickTimerSheetState extends State<QuickTimerSheet> {
  final name = TextEditingController();
  int seconds = 10 * 60;
  bool custom = false, saveReport = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void start(QuickTimerChoice choice) =>
      Navigator.pop(context, QuickTimerRequest(choice, saveReport: saveReport));

  Future<void> pickCustom() async {
    final value = await showWheelTimePicker(
      context,
      title: 'Quick timer length',
      initial: seconds,
      maximum: quickTimerMaxSeconds,
    );
    if (value != null && mounted) {
      setState(() {
        seconds = value;
        custom = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Padding(
      key: const ValueKey('quick-timer-sheet'),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Quick timer', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'A single countdown on the sign and every paired screen, for a prayer meeting, a break or a talk. It starts straight away.',
              style: TextStyle(color: colors.muted),
            ),
            if (widget.recent.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Recent', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, r) in widget.recent.indexed)
                    ActionChip(
                      key: ValueKey('quick-timer-recent-$i'),
                      avatar: const Icon(Icons.history, size: 18),
                      label: Text(
                        '${r.title} · ${durationLabel(r.seconds * 1000)}',
                      ),
                      onPressed: () => start(r),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Length', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in quickTimerMinutes)
                  ChoiceChip(
                    key: ValueKey('quick-timer-$m'),
                    label: Text(durationLabel(m * 60000)),
                    selected: !custom && seconds == m * 60,
                    onSelected: (_) => setState(() {
                      seconds = m * 60;
                      custom = false;
                    }),
                  ),
                ChoiceChip(
                  key: const ValueKey('quick-timer-custom'),
                  label: Text(
                    custom
                        ? 'Custom · ${durationLabel(seconds * 1000)}'
                        : 'Custom…',
                  ),
                  selected: custom,
                  onSelected: (_) => unawaited(pickCustom()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('quick-timer-name'),
              controller: name,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Prayer meeting',
              ),
            ),
            SwitchListTile(
              key: const ValueKey('quick-timer-save-report'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Save as a report'),
              subtitle: Text(
                saveReport
                    ? 'Saved in Reports, marked Quick timer'
                    : 'Nothing is saved when it ends',
              ),
              value: saveReport,
              onChanged: (v) => setState(() => saveReport = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: const ValueKey('quick-timer-start'),
                onPressed: () =>
                    start(QuickTimerChoice(name.text.trim(), seconds)),
                icon: const Icon(Icons.play_arrow),
                label: Text('Start ${durationLabel(seconds * 1000)} timer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
