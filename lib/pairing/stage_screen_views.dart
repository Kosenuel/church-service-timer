import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/main.dart';

export 'package:church_service_timer/pairing/quick_message_views.dart';
export 'package:church_service_timer/pairing/stage_surface.dart';
export 'package:church_service_timer/pairing/quick_message_composer.dart';

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
      destructive: true,
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

  List<ChoiceOption<String>> quickAudienceOptions() => quickAudienceChoices(
    screens: c.stageScreens,
    current: quickAudience,
    groupOf: (id) =>
        c.pairing.savedDevices.where((d) => d.id == id).firstOrNull?.group ??
        'general',
    savedName: (id) =>
        c.pairing.savedDevices.where((d) => d.id == id).firstOrNull?.name,
  );

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
}
