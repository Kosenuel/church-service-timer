import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

/// Quick messages on Live: sending, the composer page and presets.
extension QuickMessageViews on HomeState {
  Future<bool?> sendLiveQuickMessage(QuickMessage message) async {
    final recipients = selectedMessageRecipients;
    final ended = c.state.session.phase == 'ended';
    final id = c.state.session.id, epoch = c.pairing.epoch;
    if (ended) {
      if (!await confirm(
        'Send message after service?',
        'This service has ended. Send this message to the connected stage screens?\n\n$stageRecipientSummary',
        'Send message',
      ))
        return null;
      if (!mounted ||
          c.state.session.phase != 'ended' ||
          c.state.session.id != id ||
          c.pairing.epoch != epoch) {
        if (mounted)
          await showError(
            'The service or operator control changed. Review the message again.',
          );
        return false;
      }
    }
    await c.flushEditDrafts();
    final ok = await c.sendQuickMessage(
      message,
      confirmedEndedSession: ended ? id : null,
      recipientIds: recipients,
    );
    if (ok) c.queueEditDraft('quick-message', null);
    return ok;
  }

  /// The first thing stopping a send, in words the operator can act on.
  String? get quickSendBlocker {
    if (!c.pairing.localControl)
      return 'Operator control is on another device.';
    if (!c.stageConnected)
      return 'Connect a stage screen to send. Your draft stays here.';
    if (selectedMessageRecipients.isEmpty)
      return 'None of the screens in "Send to" are connected. Choose All connected stage screens or another screen.';
    if (!c.state.session.active && c.state.session.phase != 'ended')
      return 'Start or end a service to send. Use Test to try it now.';
    if (c.reportSavePending) return 'Saving the service report…';
    if (c.busy || controlsLocked) return 'Wait a moment and try again.';
    return null;
  }

  bool get canSendQuickMessage =>
      c.stageConnected &&
      selectedMessageRecipients.isNotEmpty &&
      (c.state.session.active || c.state.session.phase == 'ended') &&
      !c.busy &&
      !controlsLocked &&
      !c.reportSavePending &&
      c.pairing.localControl;

  List<Widget> quickMessageHeader() => [
    if (!quickDraftReviewed && c.state.editDrafts.containsKey('quick-message'))
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: MaterialBanner(
          content: const Text(
            'An unsent message draft is saved on this phone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                refreshHome(() {
                  quickDraft = messageFromDraft(
                    c.state.editDrafts['quick-message']!,
                  );
                  quickDraftReviewed = true;
                  quickDraftGeneration++;
                });
              },
              child: const Text('Restore draft'),
            ),
            TextButton(
              onPressed: () {
                refreshHome(() => quickDraftReviewed = true);
                c.queueEditDraft('quick-message', null);
              },
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    if (c.draftError != null)
      TextButton(onPressed: c.flushEditDrafts, child: Text(c.draftError!)),
    ChoiceField<String>(
      value: quickAudience,
      decoration: const InputDecoration(labelText: 'Send to'),
      options: quickAudienceOptions(),
      onChanged: controlsLocked
          ? null
          : (v) => refreshHome(() => quickAudience = v ?? 'all'),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Text(
        c.stageConnected
            ? stageRecipientSummary
            : 'Connect a stage screen to send. Your draft stays here.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: c.stageConnected ? null : appColors(context).warning,
        ),
      ),
    ),
  ];

  Future<void> openQuickMessage() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (ctx) => AnimatedBuilder(
        animation: Listenable.merge([c, settingsRefresh]),
        builder: (ctx, _) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: const Text('Quick message'),
            actions: [
              TextButton(
                onPressed: controlsLocked
                    ? null
                    : () => openSettingsDetail(
                        'Quick message presets',
                        quickPresetSettings,
                      ),
                // Opens preset management; choosing one is the "Choose a
                // preset" field in the form.
                child: const Text('Manage presets'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: QuickMessageComposer(
                key: ValueKey('live-quick-message-$quickDraftGeneration'),
                sticky: true,
                previewLabel:
                    'Preview · ${plural(selectedMessageRecipients.length, 'stage screen')}',
                header: quickMessageHeader(),
                initial: quickDraft,
                presets: c.state.quickMessages,
                onChanged: (value) {
                  quickDraft = value;
                  quickDraftReviewed = true;
                  c.queueEditDraft('quick-message', value.toJson());
                },
                onSavePreset: controlsLocked
                    ? null
                    : (message) => c.saveQuickPreset(message),
                onTest: c.stageConnected && !controlsLocked
                    ? (message) => c.sendQuickMessage(
                        QuickMessage(
                          headline: message.headline,
                          body: message.body,
                          bold: message.bold,
                          italic: message.italic,
                          align: message.align,
                          palette: message.palette,
                          scale: message.scale,
                          seconds: 5,
                        ),
                        test: true,
                        // The same screens a real send would reach.
                        recipientIds: selectedMessageRecipients,
                      )
                    : null,
                sendUnavailableReason: quickSendBlocker,
                failureReason: () => c.error,
                onSend: canSendQuickMessage
                    ? (message) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await sendLiveQuickMessage(message);
                        // Sent: back to Live, where the message shows as On
                        // stage with Return to timer and the Seen status.
                        if (ok == true && ctx.mounted) {
                          final count = c.quickRecipients.length;
                          Navigator.pop(ctx);
                          messenger.showSnackBar(
                            SnackBar(
                              key: const ValueKey('quick-message-sent'),
                              content: Text(
                                'Message sent to ${plural(count, 'stage screen')}',
                              ),
                            ),
                          );
                        }
                        return ok;
                      }
                    : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget quickMessagePanel() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label('Quick message'),
        const SizedBox(height: 8),
        Text(
          c.currentQuickMessage != null
              ? 'On stage: ${c.currentQuickMessage!.headline.isNotEmpty ? c.currentQuickMessage!.headline : c.currentQuickMessage!.body}'
              : c.state.editDrafts.containsKey('quick-message') ||
                    quickDraft.body.isNotEmpty
              ? 'Draft saved on this phone'
              : c.stageConnected
              ? stageRecipientSummary
              : 'Connect a stage screen to send messages.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          key: const ValueKey('open-quick-message'),
          onPressed: controlsLocked ? null : openQuickMessage,
          icon: const Icon(Icons.edit_note),
          label: const Text('Write a message'),
        ),
        if (c.currentQuickMessage?.requestSeen == true) ...[
          // Web screens have no Seen button, so they are listed as showing
          // the message and are not counted as awaiting.
          if (c.quickRecipientNames.keys.any(
            (id) => !id.startsWith('web:'),
          )) ...[
            const SizedBox(height: 12),
            Text(
              'Seen ${c.quickSeen.length} of ${c.quickRecipientNames.keys.where((id) => !id.startsWith('web:')).length}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ] else
            const SizedBox(height: 12),
          Text(
            c.quickRecipientNames.entries
                .map(
                  (e) =>
                      '${e.value}: ${!c.quickRecipients.contains(e.key)
                          ? 'Disconnected'
                          : e.key.startsWith('web:')
                          ? 'On screen (web, no Seen)'
                          : c.quickSeen.contains(e.key)
                          ? 'Seen'
                          : 'Awaiting Seen'}',
                )
                .join(' · '),
          ),
        ],
        if (c.currentQuickMessage != null)
          TextButton.icon(
            onPressed: controlsLocked ? null : c.dismissQuickMessage,
            icon: Icon(
              c.state.session.phase == 'ended'
                  ? Icons.clear
                  : Icons.timer_outlined,
            ),
            label: Text(
              c.state.session.phase == 'ended'
                  ? 'Clear message'
                  : 'Return to timer',
            ),
          ),
      ],
    ),
  );

  Future<void> editQuickPreset([int? index]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(
              index == null ? 'New message preset' : 'Edit message preset',
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              QuickMessageComposer(
                initial: index == null
                    ? const QuickMessage(body: '')
                    : c.state.quickMessages[index],
                saveLabel: 'Save preset',
                onSavePreset: (message) async {
                  final ok = await c.saveQuickPreset(message, index: index);
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                  return ok;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget quickPresetSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Saved wording and formatting for your phone or tablet stage screen.',
      ),
      const SizedBox(height: 12),
      for (final e in c.state.quickMessages.asMap().entries) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            e.value.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${e.value.length}/160 characters · ${e.value.seconds == 0 ? 'Until cleared' : '${e.value.seconds} seconds'}',
          ),
          onTap: () => editQuickPreset(e.key),
          trailing: IconButton(
            tooltip: 'Delete preset',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(
                'Delete this preset?',
                e.value.name,
                'Delete preset',
                destructive: true,
              ))
                await c.commit(
                  (draft, _) => draft.quickMessages.removeAt(e.key),
                );
            },
          ),
        ),
        const Divider(height: 1),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: c.state.quickMessages.length < 50
            ? () => editQuickPreset()
            : null,
        icon: const Icon(Icons.add),
        label: const Text('New preset'),
      ),
    ],
  );
}
