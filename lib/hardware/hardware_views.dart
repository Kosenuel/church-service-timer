import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

extension HardwareViews on HomeState {
  Future<void> restoreSign() async {
    final s = c.state.session;
    final revision = s.revision;
    int? seconds;
    if (s.uncertain && s.active) {
      seconds = await showDialog<int>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) =>
            VerifyDisplayTimeDialog(initial: s.remaining(c.now) ~/ 1000),
      );
      if (seconds == null) return;
    } else if (!await confirm(
      s.phase == 'ended' ? 'Restore end output?' : 'Restore current timer?',
      s.phase == 'ended'
          ? 'Replace the sign’s current output with this service’s end screen. Scrolling plays on the controller; a brief blink is expected.'
          : '${s.timeline!.segments[s.index].name} · ${s.formatted(c.now)} remaining${s.paused ? ' · paused' : ''}.\n\nReplace any cue on the sign. The current remaining time will be sent; the segment will not restart. A brief blink is expected.',
      'Restore output',
    )) {
      return;
    }
    if (!await c.restoreHardware(
          verifiedSeconds: seconds,
          revision: revision,
        ) &&
        mounted) {
      await showError(
        c.error ??
            'Connect the display, then review the current service again.',
      );
    }
  }

  Widget hardwareStatusPanel() => c.hardware.connected && !c.hardware.held
      ? panel(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                c.hardware.sending
                    ? Icons.upload_outlined
                    : Icons.check_circle_outline,
                color: appColors(context).accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.hardware.status,
                  key: const ValueKey('hardware-delivery-status'),
                ),
              ),
            ],
          ),
        )
      : panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.hardware.connected
                    ? c.hardware.status
                    : 'Display disconnected',
                key: const ValueKey('hardware-delivery-status'),
                style: TextStyle(
                  color: c.hardware.connected
                      ? appColors(context).accent
                      : appColors(context).warning,
                ),
              ),

              if (c.hardware.held &&
                  c.hardware.connected &&
                  (c.state.session.active ||
                      c.state.session.phase == 'ended')) ...[
                const SizedBox(height: 12),
                button(
                  'Restore current output',
                  Icons.restore,
                  c.busy || c.hardware.sending ? null : restoreSign,
                  primary: true,
                ),
              ],
              if (!c.hardware.connected) ...[
                const SizedBox(height: 12),
                button(
                  c.hardware.rememberedId.isEmpty
                      ? 'Connect display'
                      : 'Reconnect display',
                  Icons.wifi,
                  reconnectDisplay,
                ),
              ],
            ],
          ),
        );

  Future<void> reconnectDisplay() async {
    if (c.destination != 'led' && !await c.selectDestination('led')) return;
    if (!mounted) return;
    final connected = await reconnectLedDisplay(context, c);
    if (connected == null) return;
    if (connected) {
      if (mounted)
        await connectionSuccess(
          context,
          c.hardware.rememberedName,
          c.hardware.held,
        );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        navigatePage(0);
      }
      return;
    }
    if (mounted) await openHardwareConnection();
  }

  Future<void> openHardwareConnection() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => HardwareConnectionPage(controller: c)),
    );
    if (mounted && c.hardware.connected) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      navigatePage(0);
    }
  }
}

Future<void> connectionSuccess(
  BuildContext context,
  String name,
  bool held, {
  String actionLabel = 'Return to Live',
}) => showDialog<void>(
  context: context,
  animationStyle: reduceAppMotion(context) ? AnimationStyle.noAnimation : null,
  builder: (ctx) => AlertDialog(
    title: const Text('Display connected'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: 1),
          duration: reduceAppMotion(ctx)
              ? Duration.zero
              : const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Icon(
            Icons.check_circle,
            size: 72,
            color: appColors(ctx).accent,
          ),
        ),
        const SizedBox(height: 16),
        Text(name, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          held
              ? 'Output unchanged. Start a service or restore the current output from Live.'
              : 'Current service output restored.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text(actionLabel),
      ),
    ],
  ),
);

class HardwareConnectionPage extends StatefulWidget {
  final AppController controller;
  final bool returnToLive;
  const HardwareConnectionPage({
    super.key,
    required this.controller,
    this.returnToLive = true,
  });
  @override
  State<HardwareConnectionPage> createState() => _HardwareConnectionPageState();
}

class _HardwareConnectionPageState extends State<HardwareConnectionPage> {
  final password = TextEditingController();
  String? selected;
  bool rememberPassword = true, hasSaved = false, useSaved = false;
  bool credentialBusy = false;
  String? cachedSavedPassword;
  @override
  void initState() {
    super.initState();
    if (c.hardware.rememberedId.isNotEmpty)
      WidgetsBinding.instance.addPostFrameCallback((_) => scanRemembered());
  }

  Future<void> select(String id) async {
    if (!mounted) return;
    setState(() {
      selected = id;
      hasSaved = useSaved = false;
      rememberPassword = true;
      cachedSavedPassword = null;
      password.clear();
    });
    try {
      final saved = await c.port.savedDisplayPassword(id);
      if (mounted && selected == id)
        setState(() {
          hasSaved = saved != null;
          useSaved = hasSaved;
          cachedSavedPassword = saved;
        });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved password unavailable. Enter it again.'),
          ),
        );
    }
  }

  Future<void> scanRemembered() async {
    await c.hardware.discover();
    if (c.hardware.devices.any((d) => d['id'] == c.hardware.rememberedId))
      await select(c.hardware.rememberedId);
  }

  AppController get c => widget.controller;
  Future<void> setRememberPassword(bool remember) async {
    final id = selected;
    if (id == null || credentialBusy) return;
    setState(() => credentialBusy = true);
    try {
      if (!remember) await c.port.forgetDisplayPassword(id);
      if (mounted && selected == id)
        setState(() => rememberPassword = remember);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not remove the saved password. Please try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => credentialBusy = false);
    }
  }

  @override
  void dispose() {
    cachedSavedPassword = null;
    password.clear();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final h = c.hardware;
      final disabled = h.busy || h.sending || c.busy || credentialBusy;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Connect a display'),
          bottom: c.liveSession.active
              ? RunningServiceBar.forContext(context, controller: c)
              : null,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'W2 · 32 × 16 red monochrome',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Join the sign’s Wi-Fi, select your display and connect. Its current output stays unchanged.',
            ),
            const SizedBox(height: 16),
            if (h.rememberedId.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () async {
                        final ok = await reconnectLedDisplay(context, c);
                        if (ok == true && context.mounted)
                          await connectionSuccess(
                            context,
                            h.rememberedName,
                            h.held,
                          );
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect saved display'),
              ),
              TextButton.icon(
                onPressed: disabled
                    ? null
                    : () => editSignWifiProfile(context, c),
                icon: const Icon(Icons.wifi_password),
                label: const Text('Wi-Fi reconnect details'),
              ),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled ? null : () => c.port.openWifiSettings(),
                  icon: const Icon(Icons.wifi),
                  label: const Text('Wi-Fi settings'),
                ),
                FilledButton.icon(
                  onPressed: disabled
                      ? null
                      : () async {
                          setState(() => selected = null);
                          await h.discover();
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('Scan for displays'),
                ),
              ],
            ),
            if (h.rememberedName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Remembered display: ${h.rememberedName}'),
              ),
            for (final device in h.devices)
              Card(
                child: ListTile(
                  leading: Icon(
                    selected == device['id']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(device['name'] as String),
                  subtitle: Text(
                    '${device['firmware']} · ${device['width']} × ${device['height']}\n${device['address']}${device['id'] == h.rememberedId ? ' · remembered' : ''}${device['supported'] == true ? '' : '\nUnsupported display profile'}',
                  ),
                  selected: selected == device['id'],
                  onTap: disabled || device['supported'] != true
                      ? null
                      : () => select(device['id'] as String),
                ),
              ),
            if (selected != null) ...[
              const SizedBox(height: 16),
              if (hasSaved)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use saved password'),
                  value: useSaved,
                  onChanged: disabled
                      ? null
                      : (v) => setState(() => useSaved = v!),
                ),
              if (!useSaved)
                TextField(
                  controller: password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 128,
                  decoration: const InputDecoration(
                    labelText: 'Display device password',
                    helperText: 'This may differ from the Wi-Fi password.',
                    helperMaxLines: 3,
                  ),
                ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Remember password on this phone'),
                subtitle: const Text(
                  'Stored securely for easier reconnection.',
                ),
                value: rememberPassword,
                onChanged: disabled ? null : (v) => setRememberPassword(v!),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: disabled
                    ? null
                    : () async {
                        final id = selected!;
                        setState(() => credentialBusy = true);
                        try {
                          final secret = useSaved
                              ? cachedSavedPassword
                              : password.text;
                          password.clear();
                          if (secret == null)
                            throw RuleError(
                              'Saved password unavailable. Enter it again.',
                            );
                          if (c.destination != 'led' &&
                              !await c.selectDestination('led'))
                            return;
                          final ok = await h.connect(id, secret);
                          if (ok && rememberPassword)
                            await c.port.saveDisplayPassword(id, secret);
                          if (ok && context.mounted) {
                            password.clear();
                            await connectionSuccess(
                              context,
                              h.rememberedName,
                              h.held,
                              actionLabel: widget.returnToLive
                                  ? 'Return to Live'
                                  : 'Continue',
                            );
                            if (context.mounted) Navigator.pop(context);
                          }
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not use or save the credential. Review the connection status and enter it again.',
                                ),
                              ),
                            );
                        } finally {
                          if (mounted) setState(() => credentialBusy = false);
                        }
                      },
                child: const Text('Connect selected display'),
              ),
            ],
            const SizedBox(height: 20),
            if (h.busy || h.sending) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(h.status, key: const ValueKey('connection-result')),
            const SizedBox(height: 12),
            const Text(
              'Connection recovery retries the remembered display while this app is running. Disconnect or switch to Simulator to stop retries. After an app restart, review the output before restoring it.',
            ),
            if (h.diagnostics.isNotEmpty)
              ExpansionTile(
                title: const Text('Connection diagnostics'),
                children: [
                  for (final entry in h.diagnostics)
                    ListTile(dense: true, title: Text(entry)),
                ],
              ),
            if (h.connected) ...[
              const SizedBox(height: 12),
              const Text(
                'Connected. Return to Live to start or restore the timer.',
              ),
              OutlinedButton(
                onPressed: disabled ? null : () => h.disconnect(),
                child: const Text('Disconnect display'),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.desktop_windows_outlined),
              onPressed: disabled
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        animationStyle: reduceAppMotion(context)
                            ? AnimationStyle.noAnimation
                            : null,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Switch to Simulator?'),
                          content: const Text(
                            'The physical sign keeps its existing program. This app will send no further updates until you reconnect the display.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Use Simulator'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      if (!await c.selectDestination('simulator')) return;
                      if (c.state.session.disconnected) await c.act('connect');
                      if (context.mounted) Navigator.pop(context);
                    },
              label: const Text('Use simulator instead'),
            ),
          ],
        ),
      );
    },
  );
}

class VerifyDisplayTimeDialog extends StatefulWidget {
  final int initial;
  const VerifyDisplayTimeDialog({super.key, required this.initial});
  @override
  State<VerifyDisplayTimeDialog> createState() =>
      _VerifyDisplayTimeDialogState();
}

class _VerifyDisplayTimeDialogState extends State<VerifyDisplayTimeDialog> {
  late int selected = widget.initial.clamp(0, 3599);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify remaining time'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Timing was recovered with uncertainty. Check and correct the remaining time before sending it to the sign. The service report will retain its uncertainty marker.',
          ),
          const SizedBox(height: 16),
          TimeWheels(
            value: selected,
            onChanged: (v) => setState(() => selected = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.pop(context, selected);
        },
        child: const Text('Verify & restore'),
      ),
    ],
  );
}
