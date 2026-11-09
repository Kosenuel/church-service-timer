import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

class DeviceManagementPanel extends StatefulWidget {
  final AppController controller;
  const DeviceManagementPanel({super.key, required this.controller});
  @override
  State<DeviceManagementPanel> createState() => _DeviceManagementPanelState();
}

class _DeviceManagementPanelState extends State<DeviceManagementPanel>
    with WidgetsBindingObserver {
  String? revealed, revealedWifi, status;
  Json network = {};
  bool get wifiConnected => network['wifiConnected'] == true;
  bool busy = false;
  AppController get c => widget.controller;
  Future<void> operation(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (_) {
      if (mounted)
        setState(
          () => status =
              'Could not complete this action. Review the connection and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get adminSupported =>
      c.hardware.connected &&
      c.hardware.profile?['supported'] == true &&
      c.hardware.profile?['firmware'] == 'HD_W2 V6.02.232' &&
      c.hardware.profile?['pwdComplexity'] == 1;
  String? get adminUnavailable => busy
      ? 'Wait for the current change to finish.'
      : !c.hardware.connected
      ? 'Connect the LED display first.'
      : !wifiConnected
      ? 'Connect to the sign’s Wi-Fi first.'
      : c.state.session.active
      ? 'End the service to edit this.'
      : c.pairing.hosting
      ? 'Stop sharing before changing LED settings.'
      : !adminSupported
      ? 'This controller does not support administration.'
      : null;
  Future<void> changeSetting(String kind, String label) async {
    if (!adminSupported ||
        !wifiConnected ||
        c.state.session.active ||
        c.pairing.hosting ||
        busy)
      return;
    final value = TextEditingController(), repeated = TextEditingController();
    String? problem;
    final password = kind != 'ssid';
    final generation = c.hardware.generation;
    final next = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text('Change ${label.toLowerCase()}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                password
                    ? 'Use 8–16 printable characters, without spaces, repeated-only characters or a simple sequence. Keep the new password somewhere safe.'
                    : 'Use 4–16 letters, digits, underscores or hyphens.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: value,
                obscureText: password,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 16,
                decoration: InputDecoration(
                  labelText: password ? 'New password' : 'New Wi-Fi name',
                ),
              ),
              if (password)
                TextField(
                  controller: repeated,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 16,
                  decoration: const InputDecoration(
                    labelText: 'Repeat new password',
                  ),
                ),
              if (problem != null)
                Text(
                  problem!,
                  style: TextStyle(color: appColors(context).error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = value.text;
                final valid = password
                    ? text.length >= 8 &&
                          text.length <= 16 &&
                          text.codeUnits.every((n) => n >= 33 && n <= 126) &&
                          text == repeated.text &&
                          !List.generate(
                            text.length - 2,
                            (i) =>
                                text.codeUnitAt(i + 1) - text.codeUnitAt(i) ==
                                text.codeUnitAt(i + 2) - text.codeUnitAt(i + 1),
                          ).every((v) => v)
                    : RegExp(r'^[A-Za-z0-9_-]{4,16}$').hasMatch(text);
                if (!valid) {
                  update(
                    () => problem = password
                        ? 'Check the password rules and make both entries match.'
                        : 'Use 4–16 allowed characters.',
                  );
                  return;
                }
                Navigator.pop(ctx, text);
              },
              child: const Text('Review change'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      value.clear();
      repeated.clear();
      value.dispose();
      repeated.dispose();
    });
    if (next == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: Text('Change the sign’s ${label.toLowerCase()}?'),
        content: Text(
          'Display: ${c.hardware.rememberedName}.\n\n${kind == 'ssid' ? 'New Wi-Fi name: $next.\n\n' : ''}${kind == 'devicePassword' ? 'The saved connection password on this phone will be removed.' : 'The phone and paired devices may lose Wi-Fi. Join the sign again using its new details.'}\n\nThe connection will close after this request. Other password settings are not cleared. If no acknowledgement arrives, check the sign before retrying.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply and disconnect'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await operation(() async {
      require(
        !c.state.session.active &&
            !c.pairing.hosting &&
            generation == c.hardware.generation &&
            c.hardware.connected,
        'Connection or service changed. Review again.',
      );
      final result = await c.port.administerDisplay(kind, next, generation);
      await c.hardware.disconnect();
      if (mounted)
        setState(() {
          revealed = null;
          status = result['acknowledged'] == true
              ? 'Controller acknowledged the change. Rejoin Wi-Fi if necessary, then reconnect to verify.'
              : 'No acknowledgement. The setting may have changed. Rejoin using the new details first; if they fail, try the previous details. Do not repeatedly apply this change.';
        });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => readNetwork());
  }

  Future<void> readNetwork({bool requestName = false}) async {
    try {
      final next = await c.port.displayNetworkInfo(requestName: requestName);
      if (mounted) setState(() => network = next);
    } catch (_) {
      if (mounted)
        setState(
          () => status =
              'Wi-Fi details unavailable. Check Android Wi-Fi settings.',
        );
    }
  }

  Future<void> connectFromSettings() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final connected = await reconnectLedDisplay(context, c);
      if (connected == null) return;
      if (connected) {
        if (mounted)
          await connectionSuccess(
            context,
            c.hardware.rememberedName,
            c.hardware.held,
            actionLabel: 'Continue',
          );
      } else if (mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                HardwareConnectionPage(controller: c, returnToLive: false),
          ),
        );
      }
      await readNetwork();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveKnownWifiPassword() async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Wi-Fi password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Stores your entry encrypted on this phone. It does not read or change the sign’s password.',
            ),
            TextField(
              controller: field,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 128,
              decoration: const InputDecoration(labelText: 'Wi-Fi password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (field.text.isNotEmpty) Navigator.pop(ctx, field.text);
            },
            child: const Text('Save on phone'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    if (value != null)
      await operation(() async {
        await c.port.saveDisplayPassword(
          'wifi:${c.hardware.rememberedId}',
          value,
        );
        if (mounted)
          setState(() {
            revealedWifi = null;
            status = 'Wi-Fi password saved on this phone.';
          });
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted)
      setState(() {
        revealed = null;
        revealedWifi = null;
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    revealed = null;
    super.dispose();
  }

  Future<void> toggleSecret({required bool wifi}) => operation(() async {
    if ((wifi ? revealedWifi : revealed) != null) {
      setState(() => wifi ? revealedWifi = null : revealed = null);
      return;
    }
    final secret = await c.port.savedDisplayPassword(
      wifi ? 'wifi:${c.hardware.rememberedId}' : c.hardware.rememberedId,
    );
    if (mounted)
      setState(() {
        if (wifi) {
          revealedWifi = secret;
        } else {
          revealed = secret;
        }
        status = secret == null
            ? (wifi
                  ? 'No Wi-Fi password saved on this phone.'
                  : 'No password saved on this phone.')
            : null;
      });
  });

  Future<void> forgetSign() async {
    final yes = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this sign?'),
        content: const Text(
          'Disconnect, remove its saved passwords from this phone and return to the simulator. The physical sign keeps its current output.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructiveFilled(),
            child: const Text('Forget this sign'),
          ),
        ],
      ),
    );
    if (yes == true)
      await operation(() async {
        await c.hardware.disconnect(simulator: true);
        await c.port.forgetDisplayPassword('wifi:${c.hardware.rememberedId}');
        await c.port.forgetDisplay();
        await c.hardware.initialize();
        if (mounted)
          setState(() {
            revealed = null;
            revealedWifi = null;
          });
      });
  }

  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
    child: Text(text.toUpperCase(), style: sectionLabelStyle(context)),
  );

  Widget card(List<Widget> rows) => Material(
    color: appColors(context).surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: appColors(context).border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const AppDivider(),
          rows[i],
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final saved = c.hardware.rememberedId.isNotEmpty;
    final connected = c.hardware.connected;
    final profile = c.hardware.profile;
    final ssid = network['ssid'] as String? ?? '';
    final adminReady =
        adminSupported &&
        wifiConnected &&
        !c.state.session.active &&
        !c.pairing.hosting &&
        !busy;
    final tone = connected ? colors.accent : colors.muted;
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('led-status-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.developer_board, color: tone, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          saved
                              ? c.hardware.rememberedName
                              : 'No LED sign saved',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile == null
                              ? 'W2 controller · connect to read its details'
                              : '${profile['width']} × ${profile['height']} · ${profile['firmware']}',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      connected ? 'Connected' : 'Not connected',
                      style: TextStyle(
                        color: tone,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: busy
                          ? null
                          : () => operation(() => c.port.openWifiSettings()),
                      icon: const Icon(Icons.wifi),
                      label: const Text(
                        'Open Wi-Fi',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Once connected, Details is no more important than
                    // Open Wi-Fi, so both are outlined.
                    child: connected
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed:
                                busy || c.hardware.busy || c.hardware.sending
                                ? null
                                : connectFromSettings,
                            icon: const Icon(Icons.connected_tv),
                            label: const Text('Details'),
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed:
                                busy || c.hardware.busy || c.hardware.sending
                                ? null
                                : connectFromSettings,
                            icon: const Icon(Icons.connected_tv),
                            label: Text(
                              saved
                                  ? 'Reconnect LED display'
                                  : 'Connect LED display',
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    wifiConnected ? Icons.wifi : Icons.wifi_off,
                    size: 16,
                    color: colors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ssid.isNotEmpty
                          ? ssid
                          : wifiConnected
                          ? 'Android has not shared the Wi-Fi name'
                          : 'No Wi-Fi connection',
                      style: muted,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Read Wi-Fi name',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: busy
                        ? null
                        : () => readNetwork(requestName: true),
                  ),
                ],
              ),
            ],
          ),
        ),
        sectionLabel('Saved on this phone'),
        card([
          ListTile(
            key: const ValueKey('led-saved-wifi'),
            leading: Icon(Icons.wifi_password, color: colors.muted),
            title: const Text('Wi-Fi password'),
            subtitle: revealedWifi != null
                ? SelectableText(revealedWifi!)
                : Text('Encrypted on this phone', style: muted),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: busy || !saved
                      ? null
                      : () => toggleSecret(wifi: true),
                  child: Text(revealedWifi == null ? 'Show' : 'Hide'),
                ),
                PopupMenuButton<void>(
                  key: const ValueKey('led-saved-wifi-menu'),
                  tooltip: 'More',
                  enabled: !busy && saved,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: saveKnownWifiPassword,
                      child: const Text('Change saved password'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey('led-saved-device'),
            leading: Icon(Icons.lock_outline, color: colors.muted),
            title: const Text('Connection password'),
            subtitle: revealed != null
                ? SelectableText(revealed!)
                : Text(
                    'Encrypted on this phone · the sign never reveals it',
                    style: muted,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: busy || !saved
                      ? null
                      : () => toggleSecret(wifi: false),
                  child: Text(revealed == null ? 'Show' : 'Hide'),
                ),
                PopupMenuButton<void>(
                  key: const ValueKey('led-saved-device-menu'),
                  tooltip: 'More',
                  enabled: !busy && saved,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => operation(() async {
                        await c.port.forgetDisplayPassword(
                          c.hardware.rememberedId,
                        );
                        if (mounted)
                          setState(() {
                            revealed = null;
                            status =
                                'Saved password removed. The sign’s password is unchanged.';
                          });
                      }),
                      child: Text(
                        'Forget saved password',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: colors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Android needs location permission to read the Wi-Fi name; it is not used for tracking.',
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
        ]),
        sectionLabel('Sign settings'),
        card([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(
                  adminReady ? Icons.lock_open : Icons.lock_outline,
                  size: 18,
                  color: adminReady ? colors.accent : colors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !connected
                        ? 'Connect the LED display to change these.'
                        : !wifiConnected
                        ? 'Join the sign’s Wi-Fi to change these.'
                        : !adminSupported
                        ? 'This controller does not report the supported administration capability.'
                        : c.state.session.active
                        ? 'End the current service to change these.'
                        : c.pairing.hosting
                        ? 'Stop sharing this service to change these.'
                        : 'Ready to manage this W2 controller.',
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
          for (final item in [
            ('ssid', 'Wi-Fi name', Icons.wifi),
            ('wifiPassword', 'Wi-Fi password', Icons.wifi_password),
            ('devicePassword', 'Connection password', Icons.password),
          ])
            UnavailableAction(
              reason: adminUnavailable,
              child: ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                trailing: const Icon(Icons.chevron_right),
                enabled: adminReady,
                onTap: () => changeSetting(item.$1, item.$2),
              ),
            ),
        ]),
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(status!, style: TextStyle(color: colors.warning)),
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error.withValues(alpha: .5)),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy || !saved ? null : forgetSign,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Forget this sign'),
        ),
      ],
    );
  }
}
