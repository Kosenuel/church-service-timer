import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/main.dart';

extension MobileDisplayViews on HomeState {
  Future<void> chooseDisplay() =>
      openSettingsDetail('Choose display', displayChoices);

  Future<void> chooseDestination(String target) async {
    var restoreUnblank = false;
    if (controlsLocked || !c.pairing.localControl) return;
    if (c.destination == 'led' && target != 'led' && c.hardware.connected) {
      final blank = await showDialog<bool>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave the LED sign?'),
          content: const Text(
            'The sign can keep its current output after disconnecting. Blank it before switching?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Leave output'),
            ),
            FilledButton(
              onPressed:
                  c.state.session.active || c.state.session.phase == 'ended'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Blank previous sign'),
            ),
          ],
        ),
      );
      if (blank == null || !mounted) return;
      restoreUnblank = blank && !c.state.session.outputBlank;
      if (blank && !await c.blankBeforeSwitch()) {
        if (mounted)
          await showError(
            c.error ??
                'The sign did not acknowledge blanking. You can switch with Leave output.',
          );
        return;
      }
    }
    if (!await c.selectDestination(target)) {
      if (mounted)
        await showError(c.error ?? 'Finish the current action first.');
      return;
    }
    if (restoreUnblank && c.state.session.outputBlank) await c.act('blank');
    if (!mounted) return;
    if (target == 'led') {
      await reconnectDisplay();
    } else if (target == 'mobile') {
      await openSettingsDetail(
        'Screens & devices',
        stageScreenSettings,
        showLiveShortcut: true,
      );
    } else {
      await c.act('connect');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  /// A short live status for each destination, so the choice says what is
  /// already connected before it is made.
  String destinationStatus(String id) {
    switch (id) {
      case 'led':
        return c.destination == 'led' ? c.displayConnection.label : '';
      case 'mobile':
        final paired = c.pairing.syncedStagePeers.length;
        final web = c.webStage.syncedStageDevices.length;
        if (paired + web == 0)
          return c.destination == 'mobile' ? 'Waiting for a screen' : '';
        final parts = [
          if (paired > 0) '$paired paired',
          if (web > 0) '$web web',
        ];
        return '${parts.join(' · ')} connected';
      default:
        return c.destination == 'simulator' ? 'Showing on this device' : '';
    }
  }

  Widget displayChoices() {
    final colors = appColors(context);
    final locked = c.busy || c.reportSavePending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Where should your stage output appear?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose one destination. Your service timing continues when you switch.',
          style: TextStyle(color: colors.muted),
        ),
        const SizedBox(height: 20),
        for (final choice in [
          (
            'led',
            Icons.signpost_outlined,
            'LED sign',
            'Your Wi-Fi LED controller at the front of the church',
          ),
          (
            'mobile',
            Icons.devices_outlined,
            'Phone, tablet or web screens',
            'Paired phones and tablets, or any browser on this Wi-Fi',
          ),
          (
            'simulator',
            Icons.monitor_outlined,
            'Simulator',
            'Preview on this device without an external display',
          ),
        ]) ...[
          Builder(
            builder: (context) {
              final chosen = c.destination == choice.$1;
              final status = destinationStatus(choice.$1);
              return Material(
                color: chosen
                    ? colors.accent.withValues(alpha: .12)
                    : colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: chosen ? colors.accent : colors.border,
                    width: chosen ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('destination-${choice.$1}'),
                  onTap: locked ? null : () => chooseDestination(choice.$1),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: chosen
                                ? colors.accent.withValues(alpha: .2)
                                : colors.border.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(choice.$2, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                choice.$3,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                choice.$4,
                                style: TextStyle(color: colors.muted),
                              ),
                              if (status.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: chosen
                                          ? colors.accent
                                          : colors.muted,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        status,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          chosen ? Icons.check_circle : Icons.chevron_right,
                          color: chosen ? colors.accent : colors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (c.destination == 'led')
          TextButton.icon(
            onPressed: () =>
                openSettingsDetail('LED connection', connectionSettings),
            icon: const Icon(Icons.info_outline),
            label: const Text('LED connection details'),
          ),
        if (c.destination == 'mobile')
          TextButton.icon(
            onPressed: () => openSettingsDetail(
              'Screens & devices',
              stageScreenSettings,
              showLiveShortcut: true,
            ),
            icon: const Icon(Icons.devices),
            label: const Text('Manage screens'),
          ),
      ],
    );
  }

  Future<void> startStageSharing() async {
    try {
      if (!c.pairing.hosting)
        await c.pairing.host(await c.port.localNetworkAddress());
      c.pairing.setStageSharing(true);
      await c.syncActiveService();
      if (mounted) settingsRefresh.value++;
    } catch (_) {
      if (mounted)
        await showError(
          'Could not start sharing. Connect both devices to Wi-Fi that allows them to communicate.',
        );
    }
  }

  Widget stageScreenSettings() => screensAndDevices();

  Future<void> testStageScreen() async {
    final ok = await c.sendQuickMessage(
      const QuickMessage(
        headline: 'SCREEN TEST',
        body: 'Church Service Timer\nThis is your stage screen.',
        seconds: 5,
        palette: 'sky',
      ),
      test: true,
    );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Test sent for five seconds. Check that it appears on the intended screen.'
                : c.error ?? 'Screen unavailable.',
          ),
        ),
      );
  }

  Future<void> stopServiceSharing() async {
    if (await confirm(
      'Stop sharing?',
      'All paired screens and operators will disconnect. Your local timer and LED sign keep running. Saved devices remain available to reconnect later.',
      'Stop sharing',
    ))
      await c.stopSharing();
  }

  ButtonStyle stopSharingButtonStyle() => FilledButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.errorContainer,
    foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    textStyle: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
  );

  Widget stageSharingControls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: controlsLocked
            ? null
            : () => openSettingsDetail(
                'Screens & devices',
                stageScreenSettings,
                showLiveShortcut: true,
              ),
        icon: const Icon(Icons.devices),
        label: Text(
          !c.pairing.hosting
              ? 'Share to stage screens'
              : c.pairing.stagePeers.isEmpty &&
                    c.webStage.syncedStageDevices.isEmpty
              ? 'Pair screen'
              : 'Manage screens',
        ),
      ),
      if (c.pairing.hosting && c.pairing.stageSharingEnabled)
        FilledButton.icon(
          style: stopSharingButtonStyle(),
          onPressed: controlsLocked ? null : stopServiceSharing,
          icon: const Icon(Icons.stop_screen_share_outlined),
          label: const Text('Stop sharing'),
        ),
      if (c.pairing.hosting && !c.pairing.stageSharingEnabled)
        TextButton(
          onPressed: controlsLocked ? null : startStageSharing,
          child: const Text('Share to stage screens'),
        ),
      TextButton(
        onPressed: controlsLocked ? null : chooseDisplay,
        child: const Text('Change display'),
      ),
    ],
  );

  Widget mobileStagePreview() {
    final peers = c.pairing.stagePeers;
    final web = c.webStage.syncedStageDevices;
    // Paired screens show what they last confirmed; web Stage displays show
    // the host's current output, with the message only if they receive it.
    final screens = [
      for (final p in peers) (id: p.id, name: p.name),
      for (final d in web) (id: 'web:${d.token}', name: '${d.label} (web)'),
    ];
    final chosen =
        screens.where((s) => s.id == previewScreenId).firstOrNull ??
        screens.firstOrNull;
    final selected = peers.where((p) => p.id == chosen?.id).firstOrNull;
    final isWeb = chosen != null && chosen.id.startsWith('web:');
    Json? data = selected?.acknowledgedSnapshot;
    if (isWeb) {
      data = c.pairedSnapshot(false)..['stageLayout'] = 'timer';
      if (!c.quickRecipients.contains(chosen.id)) {
        data
          ..remove('quickMessage')
          ..['blank'] = c.state.session.outputBlank;
      }
    }
    final fresh =
        isWeb ||
        (selected != null && c.pairing.syncedStagePeers.contains(selected));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (screens.length > 1) ...[
          ChoiceField<String>(
            value: chosen?.id,
            decoration: const InputDecoration(labelText: 'Preview screen'),
            options: [
              for (final s in screens) ChoiceOption(value: s.id, label: s.name),
            ],
            onChanged: (id) => refreshHome(() => previewScreenId = id),
          ),
          const SizedBox(height: 12),
        ],
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.black,
              child: data == null
                  ? const Center(
                      child: Text(
                        'Waiting for a stage screen',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : StageSurface(data: data, stale: !fresh),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          fresh
              ? '${chosen!.name} · Synced'
              : !c.pairing.stageSharingEnabled
              ? 'Sharing stopped'
              : data != null
              ? 'Disconnected · last received content'
              : 'Pair and approve a stage screen',
          style: TextStyle(fontSize: 12, color: appColors(context).muted),
        ),
        if (c.state.session.outputBlank && c.currentQuickMessage == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Screen intentionally blanked'),
          ),
      ],
    );
  }

  Set<String> get selectedMessageRecipients => c.stageScreens
      .where((p) {
        if (quickAudience == 'all') return true;
        if (quickAudience.startsWith('device:'))
          return p.id == quickAudience.substring(7);
        // Web displays have no group; they get "all" or their own entry.
        if (p.id.startsWith('web:')) return false;
        final profile = c.pairing.savedDevices
            .where((d) => d.id == p.id)
            .firstOrNull;
        return quickAudience == 'group:${profile?.group ?? 'general'}';
      })
      .map((p) => p.id)
      .toSet();

  String get stageRecipientSummary {
    final ids = selectedMessageRecipients;
    final names = c.stageScreens
        .where((p) => ids.contains(p.id))
        .map((p) => p.name)
        .join(', ');
    return ids.isEmpty
        ? 'No selected stage screens are connected'
        : 'Sending to ${ids.length}: $names';
  }

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
      options: [
        const ChoiceOption(value: 'all', label: 'All connected stage screens'),
        for (final group in screenGroups.entries)
          ChoiceOption(
            value: 'group:${group.key}',
            label: '${group.value} screens',
          ),
        for (final d in c.pairing.savedDevices.where(
          (d) => d.role != 'operator',
        ))
          ChoiceOption(value: 'device:${d.id}', label: d.name),
        for (final w in c.stageScreens.where((s) => s.id.startsWith('web:')))
          ChoiceOption(value: 'device:${w.id}', label: w.name),
        if (quickAudience.startsWith('device:') &&
            !c.pairing.savedDevices.any(
              (d) => quickAudience == 'device:${d.id}',
            ) &&
            !c.stageScreens.any((s) => quickAudience == 'device:${s.id}'))
          ChoiceOption(value: quickAudience, label: 'Unavailable screen'),
      ],
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
                child: const Text('Presets'),
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
                      )
                    : null,
                onSend: canSendQuickMessage ? sendLiveQuickMessage : null,
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

class StageSurface extends StatelessWidget {
  final Json data;
  final bool stale;
  const StageSurface({super.key, required this.data, required this.stale});
  @override
  Widget build(BuildContext context) {
    if (data['stageSharing'] == false)
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Stage sharing stopped',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    if (data['blank'] == true) return const ColoredBox(color: Colors.black);
    if (data['quickMessage'] is Map)
      return RichStageMessage(
        message: QuickMessage.fromJson(
          Map<String, dynamic>.from(data['quickMessage']),
        ),
      );
    final layout = data['stageLayout'] ?? 'timer';
    final timer = StageMessage(data: data, stale: stale, fullscreen: true);
    final showSegment = data['displayIsTimer'] == true && layout != 'timer';
    final text = layout == 'next'
        ? (data['nextSegment'] == ''
              ? 'Final segment'
              : 'Next: ${data['nextSegment'] ?? ''}')
        : '${data['segment'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: !showSegment
          ? timer
          : Column(
              children: [
                Expanded(child: timer),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class RichStageMessage extends StatelessWidget {
  final QuickMessage message;
  const RichStageMessage({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    final colors = switch (message.palette) {
      'amber' => (const Color(0xffffdc8b), const Color(0xff261b09)),
      'sky' => (const Color(0xffc4e6ff), const Color(0xff071b2c)),
      'mint' => (const Color(0xffbcf4da), const Color(0xff08271c)),
      _ => (Colors.white, const Color(0xff10151c)),
    };
    final align = switch (message.align) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    // One fixed-aspect canvas is shared by the composer, operator preview and stage.
    // Fit the canvas uniformly; never distort individual text or auto-scroll it.
    TextStyle headlineStyle(double fit) => TextStyle(
      fontFamily: 'Roboto',
      color: colors.$1,
      fontSize: 42 * message.scale * fit,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    TextStyle bodyStyle(double fit) => TextStyle(
      fontFamily: 'Roboto',
      color: colors.$1,
      fontSize: (message.length > 100 ? 38 : 48) * message.scale * fit,
      height: 1.2,
      fontWeight: message.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: message.italic ? FontStyle.italic : FontStyle.normal,
    );
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: align,
        textDirection: Directionality.of(context),
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: 864);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var fit = 1.0;
    while (fit > .4 &&
        (measure(message.body, bodyStyle(fit)) +
                (message.headline.isEmpty
                    ? 0
                    : measure(message.headline, headlineStyle(fit)) + 24)) >
            476) {
      fit -= .025;
    }
    return ColoredBox(
      color: colors.$2,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 960,
              height: 540,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message.headline.isNotEmpty) ...[
                      Text(
                        message.headline,
                        textAlign: align,
                        textScaler: TextScaler.noScaling,
                        style: headlineStyle(fit),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Flexible(
                      child: Text(
                        message.body,
                        textAlign: align,
                        textScaler: TextScaler.noScaling,
                        style: bodyStyle(fit),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickMessageComposer extends StatefulWidget {
  final QuickMessage initial;
  final List<QuickMessage> presets;
  final ValueChanged<QuickMessage>? onChanged;
  final Future<bool?> Function(QuickMessage)? onSend;
  final Future<bool> Function(QuickMessage)? onSavePreset;
  final String saveLabel;

  /// Widgets shown between the preview and the fields (recipients, banners).
  final List<Widget> header;
  final String? previewLabel;

  /// Fills its parent with a scrolling body and a pinned action bar.
  final bool sticky;
  final Future<bool?> Function(QuickMessage)? onTest;
  const QuickMessageComposer({
    super.key,
    required this.initial,
    this.presets = const [],
    this.onChanged,
    this.onSend,
    this.onSavePreset,
    this.saveLabel = 'Save as preset',
    this.header = const [],
    this.previewLabel,
    this.sticky = false,
    this.onTest,
  });
  @override
  State<QuickMessageComposer> createState() => _QuickMessageComposerState();
}

class _QuickMessageComposerState extends State<QuickMessageComposer> {
  late final TextEditingController headline, body;
  late QuickMessage style;
  bool busy = false;
  int? selectedPreset;
  String? error;
  QuickMessage get value => QuickMessage(
    headline: headline.text.trim(),
    body: body.text.trim(),
    bold: style.bold,
    italic: style.italic,
    align: style.align,
    palette: style.palette,
    seconds: style.seconds,
    scale: style.scale,
    requestSeen: style.requestSeen,
  );
  @override
  void initState() {
    super.initState();
    style = widget.initial;
    headline = TextEditingController(text: style.headline);
    body = TextEditingController(text: style.body);
  }

  @override
  void dispose() {
    headline.dispose();
    body.dispose();
    super.dispose();
  }

  void changed({
    bool? bold,
    bool? italic,
    bool? requestSeen,
    String? align,
    String? palette,
    int? seconds,
    double? scale,
  }) {
    setState(() {
      selectedPreset = null;
      style = QuickMessage(
        body: body.text,
        bold: bold ?? style.bold,
        italic: italic ?? style.italic,
        requestSeen: requestSeen ?? style.requestSeen,
        align: align ?? style.align,
        palette: palette ?? style.palette,
        seconds: seconds ?? style.seconds,
        scale: scale ?? style.scale,
      );
      error = null;
    });
    widget.onChanged?.call(value);
  }

  Future<void> run(
    Future<bool?> Function(QuickMessage) action,
    String success,
  ) async {
    try {
      value.validate();
    } catch (e) {
      setState(() => error = '$e');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await action(value);
      if (mounted)
        setState(
          () => error = ok == null
              ? null
              : ok
              ? success
              : 'Could not complete the action. Check the connection or storage and try again.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not complete the action. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get styleSummary {
    final size = switch (style.scale) {
      < .9 => 'Comfortable',
      > 1.1 => 'Extra large',
      _ => 'Large',
    };
    final align = switch (style.align) {
      'left' => 'left',
      'right' => 'right',
      _ => 'centred',
    };
    return [
      size,
      align,
      style.palette,
      if (style.bold) 'bold',
      if (style.italic) 'italic',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final content = <Widget>[
      if (widget.previewLabel != null) ...[
        Text(
          widget.previewLabel!.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1,
            color: colors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
      ],
      ClipRRect(
        key: const ValueKey('quick-message-preview'),
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RichStageMessage(message: value),
        ),
      ),
      const SizedBox(height: 14),
      ...widget.header,
      if (widget.presets.isNotEmpty) ...[
        ChoiceField<int>(
          key: ValueKey(widget.presets.length),
          value: selectedPreset,
          decoration: const InputDecoration(labelText: 'Choose a preset'),
          options: [
            for (var i = 0; i < widget.presets.length; i++)
              ChoiceOption(value: i, label: widget.presets[i].name),
          ],
          onChanged: (i) {
            if (i == null) return;
            setState(() {
              selectedPreset = i;
              style = widget.presets[i];
              headline.text = style.headline;
              body.text = style.body;
              error = null;
            });
            widget.onChanged?.call(value);
          },
        ),
        const SizedBox(height: 14),
      ],
      TextField(
        controller: headline,
        maxLength: 48,
        decoration: const InputDecoration(
          labelText: 'Headline (optional)',
          counterText: '',
        ),
        onChanged: (_) => changed(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: body,
        minLines: 2,
        maxLines: 5,
        maxLength: 160,
        decoration: const InputDecoration(
          labelText: 'Message',
          hintText: 'A discreet message for the person on stage',
          counterText: '',
        ),
        onChanged: (_) => changed(),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${value.length}/160 characters',
            style: TextStyle(
              fontSize: 12,
              color: value.length > 160 ? colors.error : colors.muted,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        child: Column(
          children: [
            ExpansionTile(
              key: const ValueKey('quick-message-style'),
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(Icons.format_paint_outlined, color: colors.muted),
              title: const Text('Style'),
              subtitle: Text(styleSummary, style: muted),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Bold'),
                      selected: style.bold,
                      onSelected: (v) => changed(bold: v),
                    ),
                    FilterChip(
                      label: const Text('Italic'),
                      selected: style.italic,
                      onSelected: (v) => changed(italic: v),
                    ),
                    for (final a in ['left', 'center', 'right'])
                      IconButton(
                        tooltip: 'Align $a',
                        isSelected: style.align == a,
                        onPressed: () => changed(align: a),
                        icon: Icon(
                          a == 'left'
                              ? Icons.format_align_left
                              : a == 'right'
                              ? Icons.format_align_right
                              : Icons.format_align_center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in ['white', 'amber', 'sky', 'mint'])
                      ChoiceChip(
                        label: Text(p[0].toUpperCase() + p.substring(1)),
                        selected: style.palette == p,
                        onSelected: (_) => changed(palette: p),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ChoiceField<double>(
                  key: ValueKey('size-${style.scale}'),
                  value: style.scale,
                  decoration: const InputDecoration(labelText: 'Text size'),
                  options: const [
                    ChoiceOption(value: .85, label: 'Comfortable'),
                    ChoiceOption(value: 1.0, label: 'Large'),
                    ChoiceOption(value: 1.15, label: 'Extra large'),
                  ],
                  onChanged: (v) => changed(scale: v),
                ),
              ],
            ),
            const AppDivider(),
            ListTile(
              leading: Icon(Icons.timer_outlined, color: colors.muted),
              title: const Text('Show for'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    style.seconds == 0
                        ? 'Until cleared'
                        : formatTime(style.seconds * 1000),
                    style: TextStyle(color: colors.muted),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              onTap: busy
                  ? null
                  : () async {
                      final value = await showWheelTimePicker(
                        context,
                        title: 'Message duration · 00:00 means Until cleared',
                        initial: style.seconds,
                        allowZero: true,
                      );
                      if (value != null && mounted) changed(seconds: value);
                    },
            ),
            const AppDivider(),
            CheckboxListTile(
              value: style.requestSeen,
              onChanged: busy ? null : (v) => changed(requestSeen: v),
              secondary: Icon(Icons.done_all, color: colors.muted),
              title: const Text('Request Seen acknowledgement'),
              subtitle: Text(
                'The recipient taps Seen on a paired stage screen. Web screens show the message without asking.',
                style: muted,
              ),
            ),
          ],
        ),
      ),
      if (value.length > 100 && style.seconds > 0 && style.seconds < 15)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'For a longer message, consider 15 or 30 seconds.',
            style: TextStyle(color: colors.warning, fontSize: 12),
          ),
        ),
      if (error != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!)),
    ];
    final sendable = widget.saveLabel == 'Save as preset';
    final send = UnavailableAction(
      reason: busy
          ? 'Wait for the current message to finish.'
          : widget.onSend == null
          ? 'Connect a stage screen and enable operator controls first.'
          : null,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: busy || widget.onSend == null
            ? null
            : () => run(widget.onSend!, 'Message sent.'),
        icon: const Icon(Icons.send),
        label: const Text('Send message'),
      ),
    );
    final savePreset = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
      onPressed: busy || widget.onSavePreset == null
          ? null
          : () => run(widget.onSavePreset!, 'Preset saved.'),
      icon: const Icon(Icons.bookmark_add_outlined),
      label: Text(sendable ? 'Save preset' : widget.saveLabel),
    );
    final actions = sendable
        ? Row(
            children: [
              if (widget.onTest != null) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: busy
                      ? null
                      : () => run(widget.onTest!, 'Test sent for 5 seconds.'),
                  child: const Text('Test 5 s'),
                ),
                const SizedBox(width: 8),
              ],
              IconButton.outlined(
                tooltip: 'Save as preset',
                onPressed: busy || widget.onSavePreset == null
                    ? null
                    : () => run(widget.onSavePreset!, 'Preset saved.'),
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(child: send),
            ],
          )
        : savePreset;
    if (!widget.sticky)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...content, const SizedBox(height: 16), actions],
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: content,
          ),
        ),
        Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: actions,
            ),
          ),
        ),
      ],
    );
  }
}
