import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:church_service_timer/web_stage/web_stage_views.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:church_service_timer/pairing/pairing_pin.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/programs/send_program_views.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/reconnect_banner.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/best_effort.dart';
import 'package:church_service_timer/main.dart';

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
        'End this phone’s current service before joining a host.',
      );
      return;
    }
    if (c.pairing.hosting &&
        !await confirm(
          'Join another host?',
          'This phone will stop sharing with its paired devices when you join.',
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
          Text(
            'Waiting for a device. On the other phone, join this host with the six-digit code or QR code.',
            style: TextStyle(color: colors.muted),
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
      'Put both devices on the same Wi-Fi or this phone’s hotspot.',
      'On the other device, tap Join as stage screen on Live.',
      'Enter the six-digit code shown here, then approve it.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                        'Some sign hotspots and church networks keep devices apart. If joining fails, use the host phone’s hotspot. Other apps such as LedArt are outside this control system.',
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
                      : 'Share this service',
                  Icons.cast_connected,
                  shareFromScreens,
                  primary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: bigButton(
                  'Join another phone',
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
                          ? 'Control: this phone'
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
                    TextButton.icon(
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

class JoinDevicePage extends StatefulWidget {
  final AppController controller;
  final String initialRole;
  const JoinDevicePage({
    super.key,
    required this.controller,
    this.initialRole = 'viewer',
  });
  @override
  State<JoinDevicePage> createState() => _JoinDevicePageState();
}

class _JoinDevicePageState extends State<JoinDevicePage>
    with WidgetsBindingObserver {
  final code = TextEditingController(),
      name = TextEditingController(text: 'Second device'),
      wifiPassword = TextEditingController();
  late String role;
  String wifiName = '', wifiKind = 'church';
  bool rememberWifi = true, storeWifiPassword = true;
  bool busy = false, discovering = false;
  String? error, discoveryError, selected;
  nsd.Discovery? discovery;
  int discoveryGeneration = 0;

  String serviceKey(nsd.Service s) => '${s.name}:${s.port}';
  String? serviceAddress(nsd.Service s) {
    for (final address in s.addresses ?? []) {
      if (localPairAddress(address.address)) return address.address;
    }
    return s.host != null && localPairAddress(s.host!) ? s.host : null;
  }

  List<nsd.Service> get hosts => (discovery?.services ?? <nsd.Service>[])
      .where(
        (s) =>
            serviceAddress(s) != null &&
            s.port != null &&
            s.port! > 0 &&
            s.port! <= 65535,
      )
      .toList();
  Future<void> readWifi() async {
    try {
      final info = await widget.controller.port.displayNetworkInfo(
        requestName: true,
      );
      if (mounted) setState(() => wifiName = info['ssid'] as String? ?? '');
    } catch (_) {
      /* Wi-Fi name unavailable; rejoin stays off for this join. */
    }
  }

  /// Remembers only the network used for this join, never other networks.
  Future<void> rememberJoinedWifi() async {
    final hub = widget.controller.pairing;
    if (!rememberWifi || wifiName.isEmpty || hub.remoteHostId.isEmpty) {
      hub.rejoinSsid = '';
      return;
    }
    final password = wifiPassword.text;
    wifiPassword.clear();
    final port = widget.controller.port;
    try {
      final previous = await port.pairWifiProfile(hub.remoteHostId);
      final kept =
          previous['passwordSaved'] == true && previous['ssid'] == wifiName;
      final secured = password.isNotEmpty || kept;
      await port.savePairWifi({
        'host': hub.remoteHostId,
        'ssid': wifiName,
        'security': secured ? 'wpa2' : 'open',
        'kind': wifiKind,
        'password': password.isEmpty ? null : password,
        'store': storeWifiPassword,
      });
      // Without a password the app cannot join a secured network itself;
      // Android may still rejoin a network it already knows.
      hub.rejoinSsid = secured ? wifiName : '';
    } catch (_) {
      hub.rejoinSsid = '';
    }
  }

  @override
  void initState() {
    super.initState();
    role = widget.initialRole;
    WidgetsBinding.instance.addPostFrameCallback((_) => readWifi());
    WidgetsBinding.instance.addObserver(this);
    unawaited(findHosts());
  }

  void changed() {
    if (!mounted) return;
    setState(() {
      final available = hosts;
      if (!available.any((s) => serviceKey(s) == selected)) {
        selected = available.length == 1 ? serviceKey(available.single) : null;
      }
    });
  }

  Future<void> stopDiscovery() async {
    discoveryGeneration++;
    final previous = discovery;
    discovery = null;
    previous?.removeListener(changed);
    if (previous != null) {
      await bestEffort('stop discovery', () => nsd.stopDiscovery(previous));
    }
  }

  Future<void> findHosts() async {
    await stopDiscovery();
    if (!mounted) return;
    final generation = ++discoveryGeneration;
    setState(() {
      discovering = true;
      discoveryError = null;
      selected = null;
    });
    try {
      final result = await nsd.startDiscovery(
        '_cstimer._tcp',
        ipLookupType: nsd.IpLookupType.v4,
      );
      if (!mounted || generation != discoveryGeneration) {
        await nsd.stopDiscovery(result);
        return;
      }
      discovery = result..addListener(changed);
      changed();
    } catch (_) {
      if (mounted && generation == discoveryGeneration)
        setState(() {
          discoveryError = 'Nearby discovery is unavailable. Try the QR code.';
        });
    } finally {
      if (mounted && generation == discoveryGeneration)
        setState(() => discovering = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(stopDiscovery());
    if (state == AppLifecycleState.resumed) unawaited(findHosts());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stopDiscovery());
    code.dispose();
    name.dispose();
    wifiPassword.clear();
    wifiPassword.dispose();
    super.dispose();
  }

  Future<void> join({String? qr}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      require(
        !widget.controller.state.session.active &&
            !widget.controller.reportSavePending,
        'End this phone’s local service first.',
      );
      final host = hosts.where((s) => serviceKey(s) == selected).firstOrNull;
      require(
        qr != null || (host != null && validPairPin(code.text)),
        'Choose a nearby host and enter its six-digit code.',
      );
      final address = await widget.controller.port.localNetworkAddress();
      await widget.controller.hardware.disconnect();
      if (qr != null) {
        await widget.controller.pairing.join(
          qr,
          name.text.trim(),
          role,
          sourceAddress: address,
        );
      } else {
        await widget.controller.pairing.joinPin(
          serviceAddress(host!)!,
          host.port!,
          code.text,
          name.text.trim(),
          role,
          sourceAddress: address,
        );
      }
      code.clear();
      await rememberJoinedWifi();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not join. Check the six-digit code or refresh the QR code on the host. After five code attempts, create a new code. Both devices need Wi-Fi that allows them to communicate.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget wifiRejoinSection() {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    return Container(
      key: const ValueKey('wifi-rejoin'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              value: rememberWifi && wifiName.isNotEmpty,
              onChanged: busy || wifiName.isEmpty
                  ? null
                  : (v) => setState(() => rememberWifi = v),
              title: const Text('Rejoin this Wi-Fi automatically'),
              subtitle: Text(
                wifiName.isEmpty
                    ? 'Wi-Fi name unavailable. Allow nearby Wi-Fi access to use this.'
                    : 'This phone is on $wifiName. If the link drops, only this network is rejoined.',
                style: muted,
              ),
            ),
            if (rememberWifi && wifiName.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in const {
                      'church': 'Church Wi-Fi',
                      'hotspot': 'Host’s hotspot',
                      'sign': 'Sign’s Wi-Fi',
                    }.entries)
                      ChoiceChip(
                        label: Text(kind.value),
                        selected: wifiKind == kind.key,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => wifiKind = kind.key),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  key: const ValueKey('wifi-rejoin-password'),
                  controller: wifiPassword,
                  enabled: !busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 63,
                  decoration: const InputDecoration(
                    labelText: 'Wi-Fi password (optional)',
                    helperText:
                        'Leave empty if Android already rejoins this network by itself.',
                    helperMaxLines: 2,
                  ),
                ),
              ),
              CheckboxListTile(
                value: storeWifiPassword,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: busy
                    ? null
                    : (v) => setState(() => storeWifiPassword = v ?? true),
                title: const Text('Save the password on this phone'),
                subtitle: Text(
                  'Encrypted. Used only to rejoin $wifiName for this host.',
                  style: muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.initialRole == 'stage'
            ? 'Join as stage screen'
            : 'Join a service',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Use the same Wi-Fi as the host. Choose it below and enter its six-digit code, or scan its QR code. The host approves every new device.',
        ),
        const SizedBox(height: 16),
        if (widget.controller.pairing.hasSavedHost &&
            (widget.initialRole != 'stage' ||
                widget.controller.pairing.canResumeAsStage)) ...[
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await stopDiscovery();
                    await widget.controller.hardware.disconnect();
                    await widget.controller.pairing.resumeSavedHost();
                    if (widget.initialRole == 'stage')
                      widget.controller.pairing.showStage(true);
                    if (mounted && context.mounted) Navigator.of(context).pop();
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Reconnect saved host'),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: name,
          maxLength: 60,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        ChoiceField<String>(
          value: role,
          decoration: const InputDecoration(labelText: 'Use this device as'),
          options: const [
            ChoiceOption(value: 'viewer', label: 'Service viewer'),
            ChoiceOption(value: 'stage', label: 'Stage display'),
            ChoiceOption(value: 'operator', label: 'Additional operator'),
          ],
          onChanged: busy ? null : (v) => setState(() => role = v!),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Nearby hosts',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Refresh nearby hosts',
              onPressed: busy || discovering ? null : findHosts,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (discovering) const LinearProgressIndicator(),
        if (hosts.isEmpty)
          Text(
            discoveryError ??
                'Looking for a host… Tap Share to stage screens on the host phone. If it does not appear, try QR pairing.',
          ),
        for (final host in hosts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              selected == serviceKey(host)
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(host.name ?? 'Church Service Timer'),
            subtitle: Text(serviceAddress(host)!),
            onTap: busy
                ? null
                : () => setState(() => selected = serviceKey(host)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: code,
          enabled: !busy,
          maxLength: 6,
          keyboardType: TextInputType.number,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 26, letterSpacing: 5),
          decoration: const InputDecoration(
            labelText: 'Six-digit code',
            hintText: '000000',
          ),
        ),
        wifiRejoinSection(),
        const SizedBox(height: 12),
        if (error != null)
          Text(error!, style: TextStyle(color: appColors(context).error)),
        FilledButton(
          onPressed: busy || selected == null || !validPairPin(code.text)
              ? null
              : join,
          child: Text(busy ? 'Connecting…' : 'Join service'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final qr = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const PairScannerPage()),
                  );
                  if (qr != null && mounted) await join(qr: qr);
                },
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan QR code instead'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Some sign hotspots isolate phones. If pairing fails, use a shared router or another hotspot.',
        ),
      ],
    ),
  );
}

class PairQrDialog extends StatefulWidget {
  final PairHub hub;
  const PairQrDialog({super.key, required this.hub});
  @override
  State<PairQrDialog> createState() => _PairQrDialogState();
}

class _PairQrDialogState extends State<PairQrDialog> {
  Timer? timer;
  bool closing = false;
  late Set<PairPeer> existing;
  @override
  void initState() {
    super.initState();
    existing = widget.hub.peers.toSet();
    widget.hub.addListener(refresh);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void refresh() {
    final pending = widget.hub.peers
        .where(
          (p) =>
              !existing.contains(p) &&
              !p.approved &&
              !p.wire.closed &&
              !p.suspended,
        )
        .firstOrNull;
    if (mounted && !closing && pending != null) {
      closing = true;
      final navigator = Navigator.of(context), hub = widget.hub;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !navigator.mounted) return;
        navigator.pop();
        final approve = await showDialog<bool>(
          context: navigator.context,
          builder: (ctx) => AlertDialog(
            title: const Text('Approve paired device?'),
            content: Text(
              '${pending.name}\n${pending.role == 'operator' ? 'Operator · control requires a separate handover' : 'Stage / service viewer'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Approve'),
              ),
            ],
          ),
        );
        if (!hub.hosting || pending.wire.closed || !hub.peers.contains(pending))
          return;
        try {
          if (approve == true) await hub.approve(pending);
          if (approve == false) await hub.forgetDevice(pending.id);
        } catch (_) {
          if (navigator.mounted)
            ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
              const SnackBar(
                content: Text(
                  'Device unavailable. Review the paired devices list.',
                ),
              ),
            );
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.hub.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invitation = widget.hub.code;
    final valid =
        invitation != null &&
        invitation.expires > DateTime.now().millisecondsSinceEpoch;
    return AlertDialog(
      title: const Text('Pair with QR code'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (valid)
                QrImageView(
                  data: invitation.encode(),
                  size: 250,
                  backgroundColor: Colors.white,
                  semanticsLabel:
                      'Private pairing invitation. Scan from the second device.',
                )
              else
                const Text('This invitation expired. Generate a new code.'),
              const SizedBox(height: 12),
              const Text(
                'On the second device, choose Scan QR code instead. Keep this invitation private; it expires after 10 minutes. You still approve the device.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.hub.hosting ? widget.hub.newCode : null,
          child: const Text('New code'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class PairScannerPage extends StatefulWidget {
  const PairScannerPage({super.key});
  @override
  State<PairScannerPage> createState() => _PairScannerPageState();
}

class _PairScannerPageState extends State<PairScannerPage> {
  final scanner = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool done = false;
  String? error;
  @override
  void dispose() {
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan host QR code')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: scanner,
            onDetect: (capture) {
              if (done || !mounted) return;
              final raw = capture.barcodes.firstOrNull?.rawValue;
              try {
                PairCode.parse(raw ?? '');
                done = true;
                Navigator.pop(context, raw);
              } catch (_) {
                setState(
                  () => error =
                      'Use a current Church Service Timer QR code from the host.',
                );
              }
            },
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable. Allow camera access in Android settings, or go back and enter the six-digit code.',
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            error ?? 'Point the camera at the QR code on the host phone.',
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Use six-digit code instead'),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

class PairedScreen extends StatefulWidget {
  final AppController controller;
  const PairedScreen({super.key, required this.controller});
  @override
  State<PairedScreen> createState() => _PairedScreenState();
}

class _PairedScreenState extends State<PairedScreen> {
  AppController get controller => widget.controller;

  /// After about a minute, suggest checking the Wi-Fi connection.
  bool longHostWait(PairHub hub) {
    final since = hub.reconnectingSince;
    return since != null &&
        DateTime.now().difference(since) >= const Duration(seconds: 60);
  }

  bool _stage = false, _showTools = true;
  Timer? _hideTools;
  @override
  void initState() {
    super.initState();
    controller.pairing.addListener(updateMode);
    updateMode();
  }

  void updateMode() {
    final next = controller.pairing.mode == 'stage';
    if (_stage == next) return;
    _stage = next;
    unawaited(
      SystemChrome.setPreferredOrientations(
        next
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [],
      ),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    if (next) revealTools();
  }

  void revealTools() {
    _hideTools?.cancel();
    if (mounted) setState(() => _showTools = true);
    _hideTools = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showTools = false);
    });
  }

  @override
  void dispose() {
    controller.pairing.removeListener(updateMode);
    _hideTools?.cancel();
    if (_stage) {
      unawaited(SystemChrome.setPreferredOrientations([]));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  Future<void> leave() async {
    if (controller.pairing.canControl) {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave paired service?'),
          content: const Text(
            'Control returns to the host. Its service keeps running.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await controller.pairing.stop();
  }

  Widget leaveButton() => Tooltip(
    message: 'Leave paired service',
    child: TextButton(
      onPressed: leave,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.close, size: 22),
          Text('Leave', style: TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
  Future<void> action(
    BuildContext context,
    String label,
    String action, [
    dynamic value,
  ]) async {
    final revision = controller.pairing.snapshot?['revision'] as int?;
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: Text('$label?'),
        content: const Text('Apply this action to the host’s running service.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await controller.pairing.sendCommand(
          action,
          value,
          expectedRevision: revision,
        );
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Control unavailable. Reconnect and request control.',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = controller.pairing, data = controller.pairing.snapshot;
    final stage = hub.mode == 'stage', stale = hub.stale;
    final rows = (data?['rundown'] as List?) ?? [];
    if (stage)
      return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: revealTools,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: data == null
                      ? Text(
                          hub.status,
                          style: const TextStyle(color: Colors.white),
                        )
                      : StageSurface(data: data, stale: stale),
                ),
              ),
              if (data?['quickMessage'] is Map &&
                  data!['quickMessage']['requestSeen'] == true &&
                  data['blank'] != true &&
                  data['stageSharing'] == true)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: stale || data['messageSeen'] == true
                            ? null
                            : () async {
                                try {
                                  await hub.acknowledgeMessage();
                                } catch (_) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Message is no longer available.',
                                        ),
                                      ),
                                    );
                                }
                              },
                        icon: Icon(
                          data['messageSeen'] == true
                              ? Icons.done_all
                              : Icons.check,
                        ),
                        label: Text(
                          data['messageSeen'] == true ? 'Seen' : 'Mark Seen',
                        ),
                      ),
                    ),
                  ),
                ),
              if (_showTools || stale)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => hub.showStage(false),
                          icon: const Icon(Icons.view_list),
                          label: const Text('Back to service overview'),
                        ),
                        const Spacer(),
                        leaveButton(),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
              if (hub.reconnecting)
                const SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: ReconnectingChip(
                        key: ValueKey('stage-reconnecting'),
                        label: 'Reconnecting to host…',
                      ),
                    ),
                  ),
                )
              else if (stale)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      hub.pausedByHost
                          ? 'Session paused by host'
                          : 'Host disconnected · last received display',
                      style: TextStyle(
                        color: Colors.amber,
                        backgroundColor: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!stage) ReceivedProgramCards(controller: controller),
        Text(data?['church'] ?? '', textAlign: TextAlign.center),
        Text(
          data?['service'] ?? 'Waiting for host',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (!stage)
          Text(
            data?['segment'] ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
          ),
        const SizedBox(height: 20),
        if (data != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                if (data['blank'] == true)
                  const SizedBox(
                    height: 150,
                    child: Center(
                      child: Text(
                        'Display blank',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                if (data['blank'] != true && stage)
                  StageMessage(data: data, stale: stale),
                if (data['blank'] != true && !stage)
                  SelectableText(
                    data['remaining'] ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: stage ? 54 : 64,
                      color: !stage && data['overtime'] == true
                          ? Colors.redAccent
                          : Colors.white,
                      fontWeight: data['bold'] == true
                          ? FontWeight.bold
                          : FontWeight.w400,
                      fontStyle: data['italic'] == true
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                if (!stage && data['displayText'] != data['remaining'])
                  Text(
                    'Stage: ${data['displayText']}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (data['paused'] == true)
                  const Text('PAUSED', style: TextStyle(color: Colors.amber)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          data == null
              ? hub.status
              : stale
              ? 'Connection stale · showing last received state'
              : hub.status,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: stale ? appColors(context).error : appColors(context).accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!stage && data != null) ...[
          Text(
            'LED sign: ${data['connection'] ?? 'Unknown'}',
            textAlign: TextAlign.center,
          ),
          if (hub.mode == 'operator' && !hub.canControl)
            OutlinedButton(
              onPressed: stale ? null : () => hub.requestControl(),
              child: const Text('Request control'),
            ),
          if (hub.canControl) ...[
            const Text(
              'You control this service. The host phone must stay connected.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in [
                    ('−2 min', 'adjust', -120),
                    (
                      data['paused'] == true ? 'Resume' : 'Pause',
                      'pause',
                      null,
                    ),
                    ('+2 min', 'adjust', 120),
                    ('Next segment', 'advance', false),
                    ('Show timer', 'timer', null),
                    (
                      data['blank'] == true ? 'Unblank screen' : 'Blank screen',
                      'blank',
                      null,
                    ),
                  ])
                    SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed:
                            data['phase'] == 'active' ||
                                (item.$2 == 'blank' && data['phase'] == 'ended')
                            ? () => action(context, item.$1, item.$2, item.$3)
                            : null,
                        child: item.$2 == 'pause'
                            ? Tooltip(
                                message: item.$1,
                                child: Icon(
                                  data['paused'] == true
                                      ? Icons.play_arrow
                                      : Icons.pause,
                                  semanticLabel: item.$1,
                                ),
                              )
                            : Text(item.$1, textAlign: TextAlign.center),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Stage cues',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e
                      in ((data['cues'] as List?) ?? []).asMap().entries)
                    SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: data['phase'] == 'active'
                            ? () async {
                                try {
                                  await hub.sendCommand('cue', {
                                    'session': data['session'],
                                    'segment': data['index'],
                                    'index': e.key,
                                    'version':
                                        (data['cueVersions'] as List? ??
                                        [])[e.key],
                                  });
                                } catch (_) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cue not sent. Check the host connection and request control.',
                                        ),
                                      ),
                                    );
                                }
                              }
                            : null,
                        child: Text(
                          e.value as String,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: appColors(context).error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 52),
              ),
              onPressed: data['phase'] == 'active'
                  ? () => action(context, 'End service', 'end')
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End service'),
            ),
            const SizedBox(height: 12),
            Text(hub.requestResult),
          ],
          for (final e in rows.asMap().entries)
            ListTile(
              title: Text(
                e.value['name'],
                style: TextStyle(
                  fontWeight: e.key == data['index']
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '${durationLabel(((e.value['minutes'] as int) * 60 + (e.value['seconds'] as int? ?? 0)) * 1000)} · ${e.value['speaker']}${e.value['notes'] == null ? '' : '\nPrivate: ${e.value['notes']}'}',
              ),
            ),
        ],
      ],
    );
    return Scaffold(
      appBar: stage
          ? null
          : AppBar(
              title: Text(
                hub.mode == 'operator' ? 'Paired operator' : 'Service viewer',
              ),
              actions: [leaveButton()],
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (hub.reconnecting) ...[
              ReconnectingBanner(
                key: const ValueKey('host-reconnecting'),
                title: 'Reconnecting to host device',
                attempt: hub.reconnectAttempt,
                detail: hub.rejoiningWifi
                    ? 'Rejoining ${hub.rejoinSsid}…'
                    : longHostWait(hub)
                    ? 'Still trying. Make sure this phone is on the same Wi-Fi or hotspot as the host. Controls return when the host answers.'
                    : 'Controls are paused until the host answers. The host keeps the service running.',
                actions: [
                  if (longHostWait(hub))
                    OutlinedButton.icon(
                      key: const ValueKey('open-wifi-settings'),
                      onPressed: () => controller.port.openWifiSettings(),
                      icon: const Icon(Icons.wifi),
                      label: const Text('Open Wi-Fi settings'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            // Commands cannot reach the host while reconnecting, so the
            // controls are dimmed and ignore taps until it answers.
            IgnorePointer(
              ignoring: hub.reconnecting,
              child: AnimatedOpacity(
                opacity: hub.reconnecting ? .45 : 1,
                duration: reduceAppMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                child: content,
              ),
            ),
            const SizedBox(height: 24),
            if (hub.mode != 'operator')
              FilledButton.icon(
                onPressed: () => hub.showStage(!stage),
                icon: Icon(stage ? Icons.view_list : Icons.fullscreen),
                label: Text(
                  stage ? 'Back to service overview' : 'Open stage display',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Smooth local animation between host snapshots; freezes when the link is stale.
class StageMessage extends StatefulWidget {
  final Json data;
  final bool stale, fullscreen;
  const StageMessage({
    super.key,
    required this.data,
    required this.stale,
    this.fullscreen = false,
  });
  @override
  State<StageMessage> createState() => _StageMessageState();
}

class _StageMessageState extends State<StageMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  double elapsed = 0;
  int previousTick = 0;
  bool get animates =>
      !widget.stale &&
      (widget.data['effect'] == 'scroll' || widget.data['effect'] == 'flash');
  void syncTicker() {
    if (animates && !ticker.isAnimating) {
      previousTick = 0;
      ticker.repeat();
    } else if (!animates && ticker.isAnimating) {
      ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    ticker =
        AnimationController(vsync: this, duration: const Duration(hours: 24))
          ..addListener(() {
            final tick = ticker.lastElapsedDuration?.inMilliseconds ?? 0;
            if (!widget.stale) elapsed += (tick - previousTick) / 1000;
            previousTick = tick;
            if (mounted) setState(() {});
          });
    syncTicker();
  }

  @override
  void didUpdateWidget(StageMessage old) {
    super.didUpdateWidget(old);
    if (old.data['displayText'] != widget.data['displayText'] ||
        old.data['effect'] != widget.data['effect'])
      elapsed = 0;
    syncTicker();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final text = widget.data['displayText'] as String? ?? '';
      final effect = widget.data['effect'];
      final fullHeight = widget.fullscreen && space.maxHeight.isFinite;
      final previewSize = (space.maxWidth / 7).clamp(
        42.0,
        widget.fullscreen ? 260.0 : 130.0,
      );
      final style = TextStyle(
        // Start at screen height; static text then fits proportionally to width.
        // This keeps short cues large without cropping a long countdown.
        fontSize: fullHeight ? space.maxHeight * .9 : previewSize,
        height: fullHeight ? 1.1 : null,
        color: Colors.white,
        fontWeight: widget.data['bold'] == true
            ? FontWeight.bold
            : FontWeight.w500,
        fontStyle: widget.data['italic'] == true
            ? FontStyle.italic
            : FontStyle.normal,
      );
      if (effect == 'scroll') {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final travel = space.maxWidth + painter.width;
        final speed =
            ((widget.data['speed'] as num?) ?? 12).toDouble() *
            6 *
            (style.fontSize! / previewSize);
        final x = space.maxWidth - (elapsed * speed) % travel;
        final height = fullHeight ? space.maxHeight : painter.height + 24;
        final top = (height - painter.height) / 2;
        painter.dispose();
        return SizedBox(
          height: height,
          width: space.maxWidth,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: x,
                  top: top,
                  child: Text(
                    text,
                    style: style,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Opacity(
        opacity: effect == 'flash' && (elapsed * 2).floor() % 2 == 1 ? 0 : 1,
        child: SizedBox(
          height: fullHeight ? space.maxHeight : 170,
          width: space.maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: widget.data['outputMode'] == 'Clock'
                ? ClockText(
                    text: text,
                    style: style,
                    blink: widget.data['clockBlink'] != false,
                    stale: widget.stale,
                  )
                : Text(
                    text,
                    style: style,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
      );
    },
  );
}
