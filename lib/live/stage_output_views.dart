import 'dart:async';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:flutter/material.dart';

extension StageOutputViews on HomeState {
  bool get outputControlsEnabled =>
      !c.busy &&
      !c.corrupt &&
      !controlsLocked &&
      c.pairing.localControl &&
      !c.reportSavePending &&
      // While the LED sign recovers automatically, cues still apply to the
      // service and paired screens; the sign gets current output on return.
      (c.destinationConnected ||
          (c.destination == 'led' && c.hardware.reconnecting)) &&
      (c.state.session.active || c.state.session.phase == 'ended');

  Future<void> sendStageMessage() async {
    final revision = c.state.session.revision;
    final layout = await compose(
      c.state.session.alert ?? const TextLayout('Thank you'),
      'Send message',
      'Continue',
    );
    if (layout == null || !mounted) return;
    var duration = 0;
    final send = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            c.state.session.phase == 'ended'
                ? 'Send after service ended?'
                : 'Send stage message?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(layout.text),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show for'),
                subtitle: Text(
                  duration == 0
                      ? 'Until cleared'
                      : durationLabel(duration * 1000),
                ),
                trailing: const Icon(Icons.expand_more),
                onTap: () async {
                  final v = await showWheelTimePicker(
                    ctx,
                    title: 'Message duration · 00:00 means Until cleared',
                    initial: duration,
                    allowZero: true,
                  );
                  if (v != null && ctx.mounted) update(() => duration = v);
                },
              ),
              if (duration != 0)
                TextButton(
                  onPressed: () => update(() => duration = 0),
                  child: const Text('Until cleared'),
                ),
              Text(
                c.state.session.phase == 'ended'
                    ? 'This replaces the end screen or clock. The completed report stays unchanged.'
                    : 'Timing continues while the message is displayed.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send message'),
            ),
          ],
        ),
      ),
    );
    if (send == true &&
        !await c.act(
          'message',
          value: StageOutputMessage(layout, seconds: duration),
          revision: revision,
        ) &&
        mounted)
      await showError(c.error ?? 'The message could not be sent.');
  }

  String unavailableReason(String action) {
    if (controlsLocked) return 'Unlock operator controls first.';
    if (c.corrupt) return 'Resolve the saved-data issue before making changes.';
    if (c.busy) return 'Wait for the current change to finish saving.';
    if (c.reportSavePending) return 'Save the completed service report first.';
    if (!c.pairing.localControl)
      return 'Take back control from the paired operator first.';
    if (action == '+2 min')
      return 'Use Custom to stay within the 59:59 segment limit.';
    if (action == '−2 min') return 'There is no remaining time to remove.';
    if (action.contains('Undo'))
      return 'There is no segment change available to undo.';
    if (action.contains('Next') || action.contains('Jump'))
      return 'There are no later segments in this service.';
    if (action.contains('Export'))
      return 'Save at least one item before exporting.';
    if (action.contains('Show timer') || action.contains('Return to'))
      return 'The timer is already selected, or no active service is loaded.';
    if (c.state.session.phase == 'idle' || c.state.session.phase == 'ready')
      return 'Start the first segment to use this control.';
    if (!c.destinationConnected)
      return c.destination == 'mobile'
          ? 'Connect a stage screen first.'
          : 'Connect a display first.';
    return 'This action is unavailable in the current service state.';
  }

  Widget cueDeliveryFeedback() {
    final s = c.liveSession, cue = s.intended(c.now);
    if (!s.hasManualCue(c.now) &&
        !s.hasAutomaticCue(c.now) &&
        c.currentQuickMessage == null)
      return const SizedBox.shrink();
    String status;
    if (s.outputBlank) {
      status = 'Not sent · screen intentionally blank';
    } else if (c.destination == 'led') {
      status = c.hardware.sending
          ? 'Sending…'
          : c.hardware.currentOutputAccepted
          ? 'Controller accepted'
          : 'Not sent';
    } else if (c.destination == 'mobile') {
      final peers = c.pairing.syncedStagePeers
          .where(
            (p) =>
                c.currentQuickMessage == null ||
                c.quickRecipients.contains(p.id),
          )
          .toList();
      final received = peers.where((p) {
        final ack = p.acknowledgedSnapshot;
        if (ack == null || ack['blank'] == true) return false;
        if (c.currentQuickMessage != null) {
          return c.quickRecipients.contains(p.id) &&
              ack['messageId'] == c.quickMessageId;
        }
        return ack['session'] == s.id &&
            ack['index'] == s.index &&
            ack['displayText'] == cue?.text &&
            ack['outputMode'] == s.outputMode(c.now) &&
            ack['bold'] == cue?.bold &&
            ack['italic'] == cue?.italic &&
            ack['effect'] == cue?.compatibleEffect &&
            ack['speed'] == cue?.speed &&
            ack['screenSpeed'] == cue?.screenSpeed;
      }).length;
      final web = c.webStage.syncedStageDevices.length;
      status = peers.isEmpty
          ? (web > 0
                ? 'Sent to ${web == 1 ? '1 web stage display' : '$web web stage displays'}'
                : 'Not sent · no stage screen')
          : received == peers.length
          ? 'Stage screens received'
          : 'Sending to stage screens…';
    } else {
      status = c.destinationConnected && !s.held
          ? 'Shown in simulator'
          : 'Not sent';
    }
    final remaining = c.messageReturnSeconds;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            key: const ValueKey('cue-delivery-feedback'),
            style: TextStyle(
              color: status.startsWith('Not sent')
                  ? appColors(context).warning
                  : appColors(context).accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (remaining != null && s.active && !s.showClock && !s.outputBlank)
            Text(
              'Returns to timer in ${remaining}s',
              style: TextStyle(color: appColors(context).muted),
            ),
          if (c.destination == 'led' && status == 'Controller accepted')
            const Text(
              'Controller acknowledgement; appearance is not visually verified.',
              style: TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}
