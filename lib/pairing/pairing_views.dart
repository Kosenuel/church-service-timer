import 'package:church_service_timer/windows/stage_output.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'dart:async';
import 'package:church_service_timer/web_stage/web_stage_views.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/main.dart';

export 'package:church_service_timer/pairing/join_device_page.dart';
export 'package:church_service_timer/pairing/pair_qr_views.dart';
export 'package:church_service_timer/pairing/paired_screen.dart';

extension PairingViews on HomeState {
  Future<void> shareServiceSetup() async {
    if (c.pairing.hosting) {
      await openSettingsDetail(
        'Screens & devices',
        pairedDeviceSettings,
        showLiveShortcut: true,
      );
    } else {
      // Use the existing destination flow, including its LED-switch confirmation.
      await chooseDestination('mobile');
    }
  }

  Future<void> joinAsStageScreen() async {
    if (c.state.session.active || c.reportSavePending) {
      await showError(
        deviceText('End this phone’s current service before joining a host.'),
      );
      return;
    }
    if (c.pairing.hosting &&
        !await confirm(
          'Join another host?',
          deviceText(
            'This phone will stop sharing with its paired devices when you join.',
          ),
          'Continue',
        ))
      return;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => JoinDevicePage(controller: c, initialRole: 'stage'),
      ),
    );
  }

  Future<void> changePairedDevice(String id, String action) async {
    final hub = c.pairing;
    if (!hub.changingDevices.add(id)) return;
    hub.changed();
    try {
      switch (action) {
        case 'approve':
          final peer = hub.peerFor(id);
          if (peer != null) await hub.approve(peer);
        case 'disconnect':
          await hub.disconnectDevice(id);
        case 'reconnect':
          if (!hub.hosting) await hub.host(await c.port.localNetworkAddress());
          final available = await hub.reconnectDevice(id);
          if (!available && mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Open Church Service Timer on the saved device and connect it to the same Wi-Fi.',
                ),
              ),
            );
        case 'forget':
          if (await confirm(
            'Forget device?',
            'Remove its saved approval? It will need to pair again with a new code and your approval.',
            'Forget device',
            destructive: true,
          )) {
            await hub.forgetDevice(id);
          }
        case 'reject':
          await hub.forgetDevice(id);
        case 'control':
          final peer = hub.peerFor(id);
          if (peer != null &&
              await confirm(
                'Give ${peer.name} control?',
                'This operator can run the timer, send cues and end the service. Private notes become visible. You can take control back at any time.',
                'Give control',
              ))
            hub.grant(peer);
      }
    } catch (_) {
      if (mounted)
        await showError(
          'Could not update this connection. Check Wi-Fi and try again.',
        );
    } finally {
      hub.changingDevices.remove(id);
      hub.changed();
    }
  }

  Future<void> screenOptions(SavedPairDevice device) async {
    var group = device.group, layout = device.layout;
    final save = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(device.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChoiceField<String>(
                  value: group,
                  decoration: const InputDecoration(labelText: 'Screen group'),
                  options: [
                    for (final e in screenGroups.entries)
                      ChoiceOption(value: e.key, label: e.value),
                  ],
                  onChanged: (v) => refresh(() => group = v ?? group),
                ),
                const SizedBox(height: 16),
                ChoiceField<String>(
                  value: layout,
                  decoration: const InputDecoration(labelText: 'Screen layout'),
                  options: [
                    for (final e in screenLayouts.entries)
                      ChoiceOption(value: e.key, label: e.value),
                  ],
                  onChanged: (v) => refresh(() => layout = v ?? layout),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Messages temporarily replace this layout. Private notes are never shown.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    try {
      await c.pairing.configureScreen(device.id, group: group, layout: layout);
    } catch (_) {
      if (mounted)
        await showError(
          'Could not save screen options. Take control and try again.',
        );
    }
  }

  Widget pairedDeviceList({bool screensOnly = false}) {
    final hub = c.pairing;
    final colors = appColors(context);
    bool included(String role) => !screensOnly || role != 'operator';
    final pending = hub.peers
        .where((p) => !p.approved && included(p.role))
        .toList();
    final saved = hub.savedDevices.where((p) => included(p.role)).toList()
      ..sort(
        (x, y) =>
            (hub.connectedDevice(y.id) ? 1 : 0) -
            (hub.connectedDevice(x.id) ? 1 : 0),
      );
    String roleName(String role) => switch (role) {
      'stage' => 'Stage screen',
      'operator' => 'Operator',
      _ => 'Viewer',
    };
    Widget chip(String text, Color tone) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tone,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    Widget device(SavedPairDevice d) {
      final connected = hub.connectedDevice(d.id), peer = hub.peerFor(d.id);
      final changing = hub.changingDevices.contains(d.id);
      final seen = DateTime.fromMillisecondsSinceEpoch(d.lastSeen).toLocal();
      final stamp =
          '${seen.day}/${seen.month} ${seen.hour.toString().padLeft(2, '0')}:${seen.minute.toString().padLeft(2, '0')}';
      final controls = hub.owner == d.id;
      return ListTile(
        key: ValueKey('paired-${d.id}'),
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.muted.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            d.role == 'operator'
                ? Icons.person_outline
                : d.role == 'stage'
                ? Icons.tv_outlined
                : Icons.smartphone,
            size: 20,
          ),
        ),
        title: Text(
          d.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${roleName(d.role)} · ${connected ? (controls ? 'Controls service' : 'Connected') : (d.suspended ? 'Disconnected' : 'Unavailable')}',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            if (!connected)
              Text(
                'Last seen $stamp',
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
            if (peer?.requestedControl == true && connected)
              Text(
                'This operator requests control.',
                style: TextStyle(fontSize: 12, color: colors.warning),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (changing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.hourglass_top, size: 18),
              )
            else if (connected)
              chip(controls ? 'In control' : 'Connected', colors.accent)
            else
              TextButton(
                onPressed: () => changePairedDevice(d.id, 'reconnect'),
                child: const Text('Reconnect'),
              ),
            PopupMenuButton<String>(
              tooltip: 'Device actions',
              enabled: !changing,
              onSelected: (action) => action == 'options'
                  ? screenOptions(d)
                  : changePairedDevice(d.id, action),
              itemBuilder: (ctx) => appMenuEntries(ctx, [
                if (connected) const AppMenuAction('disconnect', 'Disconnect'),
                if (connected && d.role == 'operator' && !controls)
                  const AppMenuAction('control', 'Give control'),
                if (d.role != 'operator' && hub.localControl)
                  const AppMenuAction('options', 'Screen options'),
                const AppMenuAction(
                  'forget',
                  'Forget device',
                  destructive: true,
                ),
              ]),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hub.memoryNotice.isNotEmpty) ...[
          Text(hub.memoryNotice, style: TextStyle(color: colors.warning)),
          TextButton(
            onPressed: () async {
              try {
                await hub.retrySavingDevices();
              } catch (_) {
                if (mounted)
                  await showError('Could not save paired devices. Try again.');
              }
            },
            child: const Text('Retry saving devices'),
          ),
        ],
        for (final p in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.accent.withValues(alpha: .5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${roleName(p.role)} · Awaiting your approval',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: hub.changingDevices.contains(p.id)
                        ? null
                        : () => changePairedDevice(p.id, 'reject'),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed: hub.changingDevices.contains(p.id)
                        ? null
                        : () => changePairedDevice(p.id, 'approve'),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
          ),
        if (saved.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: label('Saved devices'),
          ),
          const SizedBox(height: 8),
          panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < saved.length; i++) ...[
                  if (i > 0) const AppDivider(),
                  device(saved[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Disconnect keeps a device saved; Reconnect restores its session without a new approval. Forget device removes it.',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
        ],
        if (pending.isEmpty && saved.isEmpty && hub.hosting)
          // In a box like the cards around it, not loose text.
          DecoratedBox(
            key: const ValueKey('waiting-for-device'),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: colors.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Waiting for a device. On the other phone, join this host with the six-digit code or QR code.',
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget pairedDeviceSettings() => screensAndDevices();

  Future<void> shareFromScreens() async {
    if (c.destination == 'mobile') {
      await startStageSharing();
      return;
    }
    try {
      await c.pairing.host(await c.port.localNetworkAddress());
    } catch (_) {
      if (mounted)
        await showError('Could not share. Check your Wi-Fi connection.');
    }
  }

  /// A PC only: the stage output, full screen, on a projector or second
  /// monitor plugged into this computer.
  Widget secondScreenPanel() {
    final window = c.port.stageOutput!;
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final screens = window.monitors();
    final others = screens.where((s) => !s.primary).toList();
    String size(StageMonitor s) =>
        '${s.rect[2] - s.rect[0]} × ${s.rect[3] - s.rect[1]}';
    return panel(
      child: Column(
        key: const ValueKey('second-screen'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Second screen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Look for screens again',
                onPressed: () => refreshHome(() {}),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            'Show the stage output full screen on a projector or second monitor plugged into this computer. It works with any display choice and needs no network.',
            style: muted,
          ),
          const SizedBox(height: 8),
          if (others.isEmpty)
            Text(
              'No second screen found. Plug one in and set Windows to Extend (press Windows + P), then look again. With Duplicate, the second screen simply copies this one.',
              style: TextStyle(color: colors.warning),
            ),
          for (final screen in others)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                window.monitor == screen.index
                    ? Icons.connected_tv
                    : Icons.tv_outlined,
                color: window.monitor == screen.index ? colors.accent : null,
              ),
              title: Text('Screen ${screen.index + 1} · ${size(screen)}'),
              subtitle: Text(
                window.monitor != screen.index
                    ? 'Not showing'
                    : window.connected
                    ? 'Showing the stage output · Esc on that screen closes it'
                    : 'Opening…',
                style: muted,
              ),
              trailing: window.monitor == screen.index
                  ? OutlinedButton(
                      key: ValueKey('second-screen-stop-${screen.index}'),
                      onPressed: controlsLocked ? null : window.close,
                      child: const Text('Stop'),
                    )
                  : FilledButton(
                      key: ValueKey('second-screen-show-${screen.index}'),
                      onPressed: controlsLocked
                          ? null
                          : () => window.show(screen),
                      child: const Text('Show'),
                    ),
            ),
          if (window.error != null)
            Text(window.error!, style: TextStyle(color: colors.error)),
        ],
      ),
    );
  }

  Widget screensAndDevices() {
    final hub = c.pairing;
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    Widget bigButton(
      String text,
      IconData icon,
      VoidCallback? onPressed, {
      bool primary = false,
      Key? key,
    }) {
      final child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center),
        ],
      );
      final style = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(72)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return primary
          ? FilledButton(
              key: key,
              style: style,
              onPressed: onPressed,
              child: child,
            )
          : OutlinedButton(
              key: key,
              style: style,
              onPressed: onPressed,
              child: child,
            );
    }

    final steps = [
      deviceText('Put both devices on the same Wi-Fi or this phone’s hotspot.'),
      'On the other device, tap Join a service on Live.',
      'Enter the six-digit code shown here, then approve it.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.port.stageOutput != null) ...[
          secondScreenPanel(),
          const SizedBox(height: 16),
        ],
        if (!hub.hosting) ...[
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.destination == 'mobile'
                      ? 'Your stage, on another screen'
                      : 'Share with other phones and screens',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: .16),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              steps[i],
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Some sign hotspots and church networks keep devices apart. If joining fails, use the host device’s hotspot. Other apps such as LedArt are outside this control system.',
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: bigButton(
                  c.destination == 'mobile'
                      ? 'Share to stage screens'
                      : 'Share to screens',
                  Icons.cast_connected,
                  shareFromScreens,
                  primary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: bigButton(
                  'Join a service',
                  Icons.smartphone,
                  c.state.session.active
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => JoinDevicePage(controller: c),
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (c.state.session.active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'End this local service before joining a different host.',
                style: muted,
              ),
            ),
        ] else ...[
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: label('Pair a device')),
                    Text(
                      hub.localControl
                          ? deviceText('Control: this phone')
                          : 'Control: paired operator',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hub.localControl
                            ? colors.accent
                            : colors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Semantics(
                  label: 'Six-digit pairing code',
                  child: SelectableText(
                    hub.pinAvailable
                        ? '${hub.pin.substring(0, 3)} ${hub.pin.substring(3)}'
                        : 'Code unavailable',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: hub.pinAvailable ? 40 : 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hub.pinAvailable
                      ? 'On the other device, choose this host and enter these six digits. Codes expire after 10 minutes.'
                      : 'The code expired or reached its attempt limit. Create a new code.',
                  textAlign: TextAlign.center,
                  style: muted,
                ),
                if (hub.discoveryNotice.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      hub.discoveryNotice,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: colors.warning),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        animationStyle: reduceAppMotion(context)
                            ? AnimationStyle.noAnimation
                            : null,
                        builder: (_) => PairQrDialog(hub: hub),
                      ),
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Show QR code'),
                    ),
                    OutlinedButton.icon(
                      onPressed: hub.newCode,
                      icon: const Icon(Icons.refresh),
                      label: const Text('New code'),
                    ),
                  ],
                ),
                if (!hub.localControl) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      if (await confirm(
                        'Take back control?',
                        'The paired operator will become a viewer. The running timer is unchanged.',
                        'Take control',
                      ))
                        hub.reclaim();
                    },
                    child: const Text('Take back control'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (c.destination == 'mobile' && !hub.stageSharingEnabled)
            OutlinedButton.icon(
              onPressed: startStageSharing,
              icon: const Icon(Icons.cast),
              label: const Text('Share to stage screens'),
            ),
          if (c.stageConnected)
            OutlinedButton.icon(
              onPressed: testStageScreen,
              icon: const Icon(Icons.connected_tv),
              label: const Text('Test screen'),
            ),
        ],
        const SizedBox(height: 20),
        pairedDeviceList(),
        if (hub.hosting) ...[const SizedBox(height: 16), webScreensPanel()],
        const SizedBox(height: 16),
        stageRequestsPanel(),
        if (hub.hosting) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            style: stopSharingButtonStyle(),
            onPressed: stopServiceSharing,
            icon: const Icon(Icons.stop_screen_share_outlined),
            label: const Text('Stop sharing'),
          ),
        ],
      ],
    );
  }
}
