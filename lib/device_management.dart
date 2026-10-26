part of 'main.dart';

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
          title: Text('Change $label'),
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
                decoration: InputDecoration(labelText: 'New $label'),
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
        title: Text('Apply $label change?'),
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
      if (!c.hardware.connected &&
          c.hardware.rememberedId.isNotEmpty &&
          await c.hardware.reconnectSaved()) {
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
        title: const Text('Save known Wi-Fi password'),
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
              decoration: const InputDecoration(
                labelText: 'Known Wi-Fi password',
              ),
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
            status = 'Known Wi-Fi password saved on this phone.';
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'LED sign settings',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Manage the LED sign’s Wi-Fi and connection credentials here. Phone and tablet screens are managed under Stage screens / Paired devices.',
      ),
      const SizedBox(height: 20),
      Text(
        c.hardware.rememberedName.isEmpty
            ? 'No remembered display'
            : c.hardware.rememberedName,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(c.hardware.connected ? 'Connected' : 'Disconnected'),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.wifi),
        title: const Text('Current Wi-Fi name'),
        subtitle: Text(
          (network['ssid'] as String? ?? '').isNotEmpty
              ? network['ssid'] as String
              : wifiConnected
              ? 'Android has not shared the Wi-Fi name'
              : 'No Wi-Fi connection',
        ),
        trailing: IconButton(
          tooltip: 'Read Wi-Fi name',
          icon: const Icon(Icons.refresh),
          onPressed: busy ? null : () => readNetwork(requestName: true),
        ),
      ),
      const Text(
        'Android requires location permission to reveal the Wi-Fi name. The app uses it only for this detail, not location tracking.',
      ),
      const Divider(height: 24),
      const Text(
        'Wi-Fi password · saved on this phone',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      if (revealedWifi != null) SelectableText(revealedWifi!),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton.icon(
            icon: Icon(
              revealedWifi == null
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            label: Text(
              revealedWifi == null
                  ? 'Show saved Wi-Fi password'
                  : 'Hide Wi-Fi password',
            ),
            onPressed: busy || c.hardware.rememberedId.isEmpty
                ? null
                : () => operation(() async {
                    if (revealedWifi != null) {
                      setState(() => revealedWifi = null);
                      return;
                    }
                    final secret = await c.port.savedDisplayPassword(
                      'wifi:${c.hardware.rememberedId}',
                    );
                    if (mounted)
                      setState(() {
                        revealedWifi = secret;
                        status = secret == null
                            ? 'No Wi-Fi password saved on this phone.'
                            : null;
                      });
                  }),
          ),
          TextButton(
            onPressed: busy || c.hardware.rememberedId.isEmpty
                ? null
                : saveKnownWifiPassword,
            child: const Text('Save known password'),
          ),
        ],
      ),
      const Divider(height: 24),
      const Text(
        'Device connection password · saved on this phone',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      if (c.hardware.profile != null)
        Text(
          '${c.hardware.profile!['firmware']} · ${c.hardware.profile!['width']} × ${c.hardware.profile!['height']}',
        ),
      const SizedBox(height: 8),
      const Text(
        'Only a password saved on this phone can be shown. The controller does not provide its existing device password in readable form.',
      ),
      if (revealed != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SelectableText(revealed!),
        ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy || c.hardware.rememberedId.isEmpty
                ? null
                : () => operation(() async {
                    if (revealed != null) {
                      setState(() {
                        revealed = null;
                        revealedWifi = null;
                      });
                      return;
                    }
                    final secret = await c.port.savedDisplayPassword(
                      c.hardware.rememberedId,
                    );
                    if (mounted)
                      setState(() {
                        revealed = secret;
                        status = secret == null
                            ? 'No password saved on this phone.'
                            : null;
                      });
                  }),
            icon: Icon(
              revealed == null
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            label: Text(
              revealed == null ? 'Show saved password' : 'Hide password',
            ),
          ),
          TextButton(
            onPressed: busy || c.hardware.rememberedId.isEmpty
                ? null
                : () => operation(() async {
                    await c.port.forgetDisplayPassword(c.hardware.rememberedId);
                    if (mounted)
                      setState(() {
                        revealed = null;
                        status =
                            'Saved password removed. The sign’s password is unchanged.';
                      });
                  }),
            child: const Text('Forget saved password'),
          ),
        ],
      ),
      const Divider(height: 32),
      const Text(
        'LED controller administration',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'To change these settings, connect this phone to the sign’s Wi-Fi and connect the display in the app. End the service and stop sharing with paired devices first.',
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, space) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: space.maxWidth < 280
                  ? space.maxWidth
                  : (space.maxWidth - 10) / 2,
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => operation(() => c.port.openWifiSettings()),
                icon: const Icon(Icons.wifi),
                label: const Text('Open Wi-Fi', textAlign: TextAlign.center),
              ),
            ),
            SizedBox(
              width: space.maxWidth < 280
                  ? space.maxWidth
                  : (space.maxWidth - 10) / 2,
              child: FilledButton.tonalIcon(
                onPressed: busy || c.hardware.busy || c.hardware.sending
                    ? null
                    : connectFromSettings,
                icon: const Icon(Icons.connected_tv),
                label: Text(
                  c.hardware.connected
                      ? 'Connection details'
                      : c.hardware.rememberedId.isEmpty
                      ? 'Connect LED display'
                      : 'Reconnect LED display',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        !c.hardware.connected
            ? 'Connect the LED display to enable changes.'
            : !wifiConnected
            ? 'Wi-Fi is unavailable. Reconnect to the sign’s Wi-Fi.'
            : !adminSupported
            ? 'This controller does not report the supported administration capability.'
            : c.state.session.active
            ? 'End the current service to enable changes.'
            : c.pairing.hosting
            ? 'Stop sharing this service to enable changes.'
            : 'Ready to manage this W2 controller.',
      ),
      TextButton.icon(
        onPressed: busy ? null : () => readNetwork(),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh connection details'),
      ),
      for (final item in [
        ('ssid', 'Wi-Fi name', Icons.wifi),
        ('wifiPassword', 'Wi-Fi password', Icons.wifi_password),
        ('devicePassword', 'Device connection password', Icons.password),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(item.$3),
          title: Text(item.$2),
          trailing: const Icon(Icons.chevron_right),
          enabled:
              adminSupported &&
              wifiConnected &&
              !c.state.session.active &&
              !c.pairing.hosting &&
              !busy,
          onTap: () => changeSetting(item.$1, item.$2),
        ),
      if (status != null) Text(status!),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: busy || c.hardware.rememberedId.isEmpty
              ? null
              : () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    animationStyle: reduceAppMotion(context)
                        ? AnimationStyle.noAnimation
                        : null,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Forget this display?'),
                      content: const Text(
                        'Disconnect, remove its saved credential and return to the simulator. The physical sign retains its current output.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Forget display'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true)
                    await operation(() async {
                      await c.hardware.disconnect(simulator: true);
                      await c.port.forgetDisplayPassword(
                        'wifi:${c.hardware.rememberedId}',
                      );
                      await c.port.forgetDisplay();
                      await c.hardware.initialize();
                      if (mounted)
                        setState(() {
                          revealed = null;
                          revealedWifi = null;
                        });
                    });
                },
          child: const Text('Forget display'),
        ),
      ),
    ],
  );
}
