import 'package:church_service_timer/app/stage_request_controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

IconData stageRequestIcon(String kind) => switch (kind) {
  'time' => Icons.more_time,
  'finish' => Icons.flag_outlined,
  _ => Icons.mic_off_outlined,
};

extension StageRequestViews on HomeState {
  /// Settings → Screens & devices: switch requests on or off.
  Widget stageRequestsPanel() {
    final colors = appColors(context);
    return panel(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        key: const ValueKey('stage-requests-switch'),
        value: c.state.stageRequests,
        onChanged: c.busy || controlsLocked
            ? null
            : (v) => c.commit((draft, _) => draft.stageRequests = v),
        title: const Text(
          'Requests from the stage',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'During a service, paired stage screens and team web Stage displays can send: ${stageRequestKinds.values.join(', ')}. You decide what happens; nothing changes the timing by itself.',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ),
    );
  }

  /// The operator's cards on Live, newest first.
  Widget stageRequestCards() {
    final open = c.stageRequests.open;
    if (open.isEmpty) return const SizedBox.shrink();
    final colors = appColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in open)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              key: ValueKey('stage-request-${r.id}'),
              color: colors.warning.withValues(alpha: .14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: colors.warning.withValues(alpha: .6)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(stageRequestIcon(r.kind), color: colors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.label,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${r.screenName} · ${agoLabel(c.now.mono - r.atMono)}',
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          key: ValueKey('dismiss-request-${r.id}'),
                          onPressed: controlsLocked
                              ? null
                              : () => c.stageRequests.dismiss(r.id),
                          child: const Text('Dismiss'),
                        ),
                        if (r.kind == 'time')
                          OutlinedButton.icon(
                            key: ValueKey('add-request-time-${r.id}'),
                            onPressed:
                                controlsLocked ||
                                    c.busy ||
                                    !c.pairing.localControl
                                ? null
                                : () async {
                                    if (!await c.stageRequests.addTime(r.id) &&
                                        mounted)
                                      await showError(
                                        c.error ?? 'Could not add time.',
                                      );
                                  },
                            icon: const Icon(Icons.add),
                            label: const Text('Add 2 min'),
                          ),
                        FilledButton(
                          key: ValueKey('ack-request-${r.id}'),
                          onPressed: controlsLocked
                              ? null
                              : () => c.stageRequests.acknowledge(r.id),
                          child: const Text('Acknowledge'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String agoLabel(int ms) => ms < 10000
    ? 'just now'
    : ms < 60000
    ? '${ms ~/ 1000} s ago'
    : '${ms ~/ 60000} min ago';

/// On a paired stage screen: a small Request button with the three fixed
/// choices, then "Sent" and "Seen by operator".
class StageRequestButton extends StatelessWidget {
  final Map<String, dynamic>? status;
  final bool enabled;
  final Future<void> Function(String kind) onSend;
  const StageRequestButton({
    super.key,
    required this.status,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final state = status?['state'];
    final note = switch (state) {
      'sent' => 'Sent · ${status!['label']}',
      'seen' => 'Seen by operator',
      'added' => '2 minutes added',
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              note,
              key: const ValueKey('stage-request-status'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        OutlinedButton.icon(
          key: const ValueKey('stage-request-button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
          ),
          onPressed: !enabled
              ? null
              : () async {
                  // A compact dialog, not a sheet: stage screens are often
                  // held landscape, where a sheet ran off the screen. Its
                  // choices scroll if space is still short.
                  final kind = await showDialog<String>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      key: const ValueKey('stage-request-choices'),
                      title: const Text('Ask the operator'),
                      children: [
                        for (final k in stageRequestKinds.entries)
                          SimpleDialogOption(
                            key: ValueKey('send-request-${k.key}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            onPressed: () => Navigator.pop(ctx, k.key),
                            child: Row(
                              children: [
                                Icon(stageRequestIcon(k.key)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    k.value,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const ValueKey('cancel-stage-request'),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (kind != null) await onSend(kind);
                },
          icon: const Icon(Icons.front_hand_outlined, size: 18),
          label: const Text('Request'),
        ),
      ],
    );
  }
}
