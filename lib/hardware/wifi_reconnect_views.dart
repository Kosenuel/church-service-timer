import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

/// false opens manual connection; null is an intentional cancellation.
Future<bool?> reconnectLedDisplay(BuildContext context, AppController c) async {
  if (c.destination != 'led' && !await c.selectDestination('led')) return null;
  if (!context.mounted) return null;
  if (c.hardware.rememberedId.isEmpty) return false;
  if (c.hardware.connected) return true;
  try {
    if (!await c.hardware.hasReconnectCredential()) return false;
  } catch (_) {
    return false;
  }
  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => WifiReconnectDialog(controller: c),
  );
}

Future<bool> editSignWifiProfile(BuildContext context, AppController c) async {
  final id = c.hardware.rememberedId;
  if (id.isEmpty) return false;
  Json profile;
  try {
    profile = await c.port.signWifiProfile(id);
  } catch (_) {
    profile = {};
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) =>
            SignWifiProfileDialog(controller: c, id: id, profile: profile),
      ) ??
      false;
}

class SignWifiProfileDialog extends StatefulWidget {
  final AppController controller;
  final String id;
  final Json profile;
  const SignWifiProfileDialog({
    super.key,
    required this.controller,
    required this.id,
    required this.profile,
  });
  @override
  State<SignWifiProfileDialog> createState() => _SignWifiProfileDialogState();
}

class _SignWifiProfileDialogState extends State<SignWifiProfileDialog> {
  late final ssid = TextEditingController(
    text: widget.profile['ssid'] as String? ?? '',
  );
  final password = TextEditingController();
  late String security = widget.profile['security'] as String? ?? 'wpa2';
  bool saving = false, reveal = false;
  String? error;
  @override
  void dispose() {
    ssid.dispose();
    password.clear();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Wi-Fi reconnect details'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Wi-Fi network for ${widget.controller.hardware.rememberedName}. These details are saved on this phone; they do not change the sign.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ssid,
            enabled: !saving,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Sign Wi-Fi name',
              hintText: 'GloryArenaTimer',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: 12),
          ChoiceField<String>(
            value: security,
            decoration: const InputDecoration(labelText: 'Wi-Fi security'),
            options: const [
              ChoiceOption(value: 'wpa2', label: 'WPA2'),
              ChoiceOption(value: 'wpa3', label: 'WPA3'),
              ChoiceOption(value: 'open', label: 'Open'),
            ],
            onChanged: saving ? null : (v) => setState(() => security = v!),
          ),
          if (security != 'open') ...[
            const SizedBox(height: 12),
            TextField(
              controller: password,
              enabled: !saving,
              obscureText: !reveal,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Wi-Fi password',
                helperText: widget.profile['passwordSaved'] == true
                    ? 'Leave empty to keep the saved Wi-Fi password.'
                    : 'This may differ from the device connection password.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: reveal
                      ? 'Hide Wi-Fi password'
                      : 'Show Wi-Fi password',
                  onPressed: () => setState(() => reveal = !reveal),
                  icon: Icon(reveal ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Stored encrypted on this phone. Android asks for approval when joining this network for the first time.',
            style: TextStyle(fontSize: 12),
          ),
          if (error != null)
            Text(error!, style: TextStyle(color: appColors(context).error)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                setState(() {
                  saving = true;
                  error = null;
                });
                try {
                  require(
                    ssid.text.trim().isNotEmpty,
                    'Enter the sign’s Wi-Fi name.',
                  );
                  await widget.controller.port.saveSignWifiProfile({
                    'id': widget.id,
                    'ssid': ssid.text.trim(),
                    'security': security,
                    'password': password.text.isEmpty ? null : password.text,
                    // Do not keep an old AP identity when the operator edits its name.
                    'bssid': ssid.text.trim() == widget.profile['ssid']
                        ? widget.profile['bssid'] ?? ''
                        : '',
                  });
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (mounted)
                    setState(
                      () => error = e is PlatformException ? e.message : '$e',
                    );
                } finally {
                  if (mounted) setState(() => saving = false);
                }
              },
        child: const Text('Save Wi-Fi details'),
      ),
    ],
  );
}

class WifiReconnectDialog extends StatefulWidget {
  final AppController controller;
  const WifiReconnectDialog({super.key, required this.controller});
  @override
  State<WifiReconnectDialog> createState() => _WifiReconnectDialogState();
}

class _WifiReconnectDialogState extends State<WifiReconnectDialog> {
  AppController get c => widget.controller;
  bool running = true, cancelled = false;
  String? failure;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<bool> joinWifi() async {
    if (!mounted || cancelled || c.destination != 'led') return false;
    var profile = await c.port.signWifiProfile(c.hardware.rememberedId);
    if (profile['supported'] != true)
      throw RuleError(
        'Open Android Wi-Fi settings to join the sign, then retry.',
      );
    if (profile['wifiEnabled'] == false)
      throw RuleError(
        'Wi-Fi is off. Open Wi-Fi settings, turn it on, then retry.',
      );
    if ((profile['ssid'] as String? ?? '').isEmpty ||
        (profile['security'] != 'open' && profile['passwordSaved'] != true)) {
      if (!mounted || cancelled || !await editSignWifiProfile(context, c))
        return false;
      profile = await c.port.signWifiProfile(c.hardware.rememberedId);
    }
    if (!mounted || cancelled) return false;
    if (c.pairing.hosting || c.pairing.joined) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch Wi-Fi for the LED sign?'),
          content: const Text(
            'Joining the sign’s Wi-Fi may disconnect paired phones and tablets from this service. The timer will keep running.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Join sign Wi-Fi'),
            ),
          ],
        ),
      );
      if (approved != true) return false;
    }
    if (!mounted || cancelled || c.destination != 'led') return false;
    c.hardware.status = 'Joining ${profile['ssid']}…';
    c.hardware.changed();
    try {
      return await c.port.joinSignWifi(c.hardware.rememberedId);
    } on PlatformException catch (e) {
      throw RuleError(
        e.message ?? 'Wi-Fi connection failed. Review the saved Wi-Fi details.',
      );
    }
  }

  Future<void> run() async {
    if (!mounted || cancelled) return;
    setState(() {
      running = true;
      failure = null;
    });
    final ok = await c.hardware.reconnectSaved(joinWifi: joinWifi);
    if (!mounted || cancelled) return;
    if (ok) {
      setState(() => running = false);
      Navigator.pop(context, true);
      return;
    }
    // Failed manual attempts do not keep silently scanning behind this dialog.
    c.hardware.autoReconnect = false;
    try {
      await c.port.setDisplayAutoReconnect(false);
    } catch (_) {
      await c.port.cancelSignWifi();
    }
    if (mounted)
      setState(() {
        running = false;
        failure = c.hardware.status.replaceFirst(' · retrying…', '');
        c.hardware.status = failure!;
      });
  }

  Future<void> cancel([bool? result]) async {
    if (cancelled) return;
    cancelled = true;
    setState(() => running = false);
    await c.hardware.disconnect();
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !running,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(cancel());
    },
    child: AnimatedBuilder(
      animation: c.hardware,
      builder: (context, _) => AlertDialog(
        title: const Text('Reconnect display'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (running) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              failure ?? c.hardware.status,
              key: const ValueKey('wifi-reconnect-progress'),
            ),
            // Retry and Cancel stay as the dialog's two actions; the other
            // ways to connect are a short list, not three more buttons.
            if (!running) ...[
              const SizedBox(height: 16),
              Text(
                'Other ways to connect',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final (icon, label, action) in [
                (Icons.wifi, 'Open Wi-Fi settings', c.port.openWifiSettings),
                (
                  Icons.edit_outlined,
                  'Edit reconnect details',
                  () => editSignWifiProfile(context, c),
                ),
                (Icons.password, 'Connect manually', () => cancel(false)),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(icon),
                  title: Text(label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: action,
                ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => cancel(), child: const Text('Cancel')),
          if (!running)
            FilledButton(onPressed: run, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
