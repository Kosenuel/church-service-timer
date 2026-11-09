import 'package:church_service_timer/app/practice_controller.dart';
import 'package:church_service_timer/live/practice_pointer.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

String shortDate(int wall) {
  final d = DateTime.fromMillisecondsSinceEpoch(wall);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// The display that was chosen before practice switched to the Simulator,
/// offered back when practice ends.
String? practiceReturnTo;

extension PracticeViews on HomeState {
  /// Wraps [child] with the animated practice pointer while the current
  /// step needs it ([id] as in PracticeController.pointer).
  Widget practiceSpot(
    String id,
    Widget child, {
    double radius = 16,
    String label = 'Tap',
    bool enabled = true,
  }) => PracticePointer(
    active: enabled && c.practice.pointer == id,
    radius: radius,
    label: label,
    child: child,
  );

  /// Starts practice, switching to the Simulator first if needed.
  Future<void> startPractice() async {
    final reason = c.practice.blocker;
    if (reason != null) {
      await showError(reason);
      return;
    }
    if (c.destination != 'simulator') {
      final name = c.destinationName;
      if (!await confirm(
        'Practise on the Simulator?',
        'Practice runs on this phone’s Simulator, so nothing appears on stage. $name stops receiving output until you switch back; you can do that when practice ends.',
        'Switch and practise',
      ))
        return;
      final previous = c.destination;
      if (!await c.selectDestination('simulator')) {
        if (mounted) await showError(c.error ?? 'Could not switch display.');
        return;
      }
      practiceReturnTo = previous;
    }
    if (!await c.practice.start() && mounted)
      await showError(c.error ?? 'Could not start practice.');
    if (mounted) goToPage(0);
  }

  /// The invitation on Live while standing by, until hidden.
  Widget practicePrompt() {
    if (!c.state.practicePrompt ||
        practicePromptSnoozed ||
        c.practice.blocker != null)
      return const SizedBox.shrink();
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: panel(
        child: Row(
          children: [
            Icon(Icons.school_outlined, color: colors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New to this? Practise running a service',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'A few minutes on the Simulator, step by step. Nothing is saved or shown on stage.',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You can also start it any time from Settings › About › Guided practice.',
                    key: const ValueKey('practice-prompt-where'),
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonal(
                        key: const ValueKey('start-practice'),
                        onPressed: controlsLocked ? null : startPractice,
                        child: const Text('Start practice'),
                      ),
                      TextButton(
                        key: const ValueKey('snooze-practice-prompt'),
                        onPressed: () =>
                            refreshHome(() => practicePromptSnoozed = true),
                        child: const Text('Not now'),
                      ),
                      TextButton(
                        key: const ValueKey('hide-practice-prompt'),
                        onPressed: c.busy
                            ? null
                            : () => c.commit(
                                (draft, _) => draft.practicePrompt = false,
                              ),
                        child: const Text('Don’t show again'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The banner and coach card while practising.
  Widget practiceCoach() {
    final colors = appColors(context);
    final step = c.practice.current;
    final total = practiceSteps.length;
    final number = step == null ? total : practiceSteps.indexOf(step) + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        key: const ValueKey('practice-coach'),
        color: colors.accent.withValues(alpha: .1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.accent.withValues(alpha: .6)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.school_outlined, size: 18, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Practice · nothing is shown on stage · $practiceRate× speed',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${c.practice.completed} of $total done',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c.practice.completed / total,
                  minHeight: 5,
                  color: colors.accent,
                  backgroundColor: colors.track,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                step == null
                    ? 'All steps tried. End the service when you’re ready.'
                    : 'Step $number · ${step.title}',
                key: const ValueKey('practice-step'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (step != null) ...[
                const SizedBox(height: 2),
                Text(step.how, style: TextStyle(color: colors.muted)),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (step != null && step.id != 'end')
                    TextButton(
                      key: const ValueKey('practice-skip'),
                      onPressed: c.practice.skip,
                      child: const Text('Skip step'),
                    ),
                  TextButton(
                    key: const ValueKey('practice-leave'),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    onPressed: c.busy
                        ? null
                        : () async {
                            if (await confirm(
                              'Leave practice?',
                              'This practice run is discarded. Nothing was saved.',
                              'Leave practice',
                              destructive: true,
                            ))
                              await c.practice.leave();
                            if (mounted) await offerReturnDisplay();
                          },
                    child: const Text('Leave practice'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown once when a practice run ends with End service.
  Future<void> showPracticeSummary() async {
    final f = c.practice.finished;
    if (f == null) return;
    c.practice.finished = null;
    final minutes = (f.ms / 60000).ceil().clamp(1, 600);
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('practice-summary'),
        icon: const Icon(Icons.verified_outlined),
        title: const Text('Practice complete'),
        content: Text(
          '${f.done} of ${f.total} steps done · about $minutes min.\n\nNo report was saved. You can practise again any time from Settings › About.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Practise again'),
          ),
          FilledButton(
            key: const ValueKey('practice-done'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true) {
      await startPractice();
      return;
    }
    await offerReturnDisplay();
  }

  /// Offers to switch back to the display used before practice.
  Future<void> offerReturnDisplay() async {
    final previous = practiceReturnTo;
    practiceReturnTo = null;
    if (previous == null || previous == c.destination || !mounted) return;
    final name = previous == 'led' ? 'the LED sign' : 'stage screens';
    if (await confirm(
      'Switch back to $name?',
      'Practice used the Simulator. Switch the display back to $name now?',
      'Switch back',
    ))
      await chooseDestination(previous);
  }
}
