import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/reconnect_banner.dart';

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
      s.endsOnClock
          ? 'Replace the sign’s current output with the clock, as this service has no end screen. A brief blink is expected.'
          : s.phase == 'ended'
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

  Widget hardwareStatusPanel() => c.hardware.reconnecting
      ? ReconnectingBanner(
          key: const ValueKey('sign-reconnecting'),
          title: c.hardware.connected
              ? 'Checking the LED sign connection'
              : 'Reconnecting to LED sign',
          attempt: c.hardware.reconnectAttempt,
          detail:
              'Timing, phone warnings and stage screens keep running. Cues you send now will show on the sign when it reconnects.${(c.hardware.offlineMs ?? 0) >= 60000 ? deviceText(' Check the sign is powered on and this phone is on its Wi-Fi.') : ''}',
          actions: [
            if (!c.hardware.connected)
              OutlinedButton.icon(
                key: const ValueKey('sign-reconnect-display'),
                onPressed: c.hardware.busy ? null : reconnectDisplay,
                icon: const Icon(Icons.wifi),
                label: const Text('Reconnect display'),
              ),
            TextButton(
              key: const ValueKey('sign-stop-trying'),
              onPressed: () => c.hardware.disconnect(),
              child: const Text('Stop trying'),
            ),
          ],
        )
      : c.hardware.connected && !c.hardware.held
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

  Future<void> useSimulator() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Use the simulator instead?'),
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
            child: const Text('Use simulator'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!await c.selectDestination('simulator')) return;
    if (c.state.session.disconnected) await c.act('connect');
    if (mounted) Navigator.pop(context);
  }

  Future<void> connectSelected() async {
    final h = c.hardware;
    final id = selected!;
    setState(() => credentialBusy = true);
    try {
      final secret = useSaved ? cachedSavedPassword : password.text;
      password.clear();
      if (secret == null)
        throw RuleError('Saved password unavailable. Enter it again.');
      if (c.destination != 'led' && !await c.selectDestination('led')) return;
      final ok = await h.connect(id, secret);
      if (ok && rememberPassword) await c.port.saveDisplayPassword(id, secret);
      if (ok && mounted) {
        password.clear();
        await connectionSuccess(
          context,
          h.rememberedName,
          h.held,
          actionLabel: widget.returnToLive ? 'Return to Live' : 'Continue',
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted)
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
  }

  Widget step(
    int number,
    String title, {
    required bool done,
    required bool active,
    Widget? trailing,
    List<Widget> children = const [],
  }) {
    final colors = appColors(context);
    final tone = done ? colors.accent : colors.muted;
    return Material(
      key: ValueKey('connect-step-$number'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: active && !done
              ? colors.accent.withValues(alpha: .6)
              : colors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? colors.accent : tone.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: done
                  ? Icon(Icons.check, size: 16, color: colors.surface)
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? colors.accent : colors.muted,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: active || done ? null : colors.muted,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final h = c.hardware;
      final colors = appColors(context);
      final disabled = h.busy || h.sending || c.busy || credentialBusy;
      final muted = TextStyle(fontSize: 13, color: colors.muted);
      final found = h.devices.isNotEmpty;
      return Scaffold(
        appBar: AppBar(
          flexibleSpace: finishBar(context),
          title: const Text('Connect the LED sign'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'More options',
              enabled: !disabled,
              onSelected: (value) async {
                switch (value) {
                  case 'wifi':
                    await editSignWifiProfile(context, c);
                  case 'disconnect':
                    await h.disconnect();
                  case 'simulator':
                    await useSimulator();
                }
              },
              itemBuilder: (ctx) => appMenuEntries(ctx, [
                if (h.rememberedId.isNotEmpty)
                  const AppMenuAction('wifi', 'Wi-Fi reconnect details'),
                if (h.connected)
                  const AppMenuAction('disconnect', 'Disconnect display'),
                const AppMenuAction('simulator', 'Use simulator instead'),
              ]),
            ),
          ],
          bottom: c.liveSession.active
              ? RunningServiceBar.forContext(context, controller: c)
              : null,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'W2 · 32 × 16 red. The sign keeps showing its current output until you choose to send.',
              style: muted,
            ),
            if (h.rememberedId.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
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
                label: Text('Reconnect ${h.rememberedName}'),
              ),
            ],
            const SizedBox(height: 14),
            step(
              1,
              'Join the sign’s Wi-Fi',
              done: found || h.connected,
              active: true,
              trailing: TextButton(
                onPressed: disabled ? null : () => c.port.openWifiSettings(),
                child: const Text('Wi-Fi settings'),
              ),
              children: [
                Text(
                  deviceText(
                    'Connect this phone to the sign’s network in Android, then come back.',
                  ),
                  style: muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            step(
              2,
              'Choose the sign',
              done: selected != null || h.connected,
              active: true,
              trailing: TextButton(
                key: const ValueKey('scan-displays'),
                onPressed: disabled
                    ? null
                    : () async {
                        setState(() => selected = null);
                        await h.discover();
                      },
                child: Text(found ? 'Scan again' : 'Scan for displays'),
              ),
              children: [
                if (!found)
                  Text(
                    h.rememberedName.isEmpty
                        ? 'Scan to find signs on this Wi-Fi.'
                        : 'Remembered: ${h.rememberedName}. Scan to find it.',
                    style: muted,
                  ),
                for (final device in h.devices)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Material(
                      color: selected == device['id']
                          ? colors.accent.withValues(alpha: .1)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: selected == device['id']
                              ? colors.accent
                              : colors.border,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(
                          selected == device['id']
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected == device['id']
                              ? colors.accent
                              : null,
                        ),
                        title: Text(device['name'] as String),
                        subtitle: Text(
                          '${device['firmware']} · ${device['width']} × ${device['height']}${device['id'] == h.rememberedId ? ' · remembered' : ''}\n${device['address']}${device['supported'] == true ? '' : ' · unsupported display profile'}',
                          style: muted,
                        ),
                        onTap: disabled || device['supported'] != true
                            ? null
                            : () => select(device['id'] as String),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            step(
              3,
              'Sign in',
              done: h.connected,
              active: selected != null,
              children: [
                if (selected == null)
                  Text('Choose a sign first.', style: muted)
                else ...[
                  if (hasSaved)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Use saved password'),
                      value: useSaved,
                      onChanged: disabled
                          ? null
                          : (v) => setState(() => useSaved = v!),
                    ),
                  if (!useSaved) ...[
                    const SizedBox(height: 10),
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
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(deviceText('Remember password on this phone')),
                    subtitle: Text(
                      'Encrypted for easier reconnection.',
                      style: muted,
                    ),
                    value: rememberPassword,
                    onChanged: disabled ? null : (v) => setRememberPassword(v!),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: disabled || selected == null ? null : connectSelected,
              child: const Text('Connect selected display'),
            ),
            const SizedBox(height: 10),
            if (h.busy || h.sending) const LinearProgressIndicator(),
            if (h.status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  h.status,
                  key: const ValueKey('connection-result'),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              h.connected
                  ? 'Connected. Return to Live to start or restore the timer.'
                  : 'After connecting, output stays held until you review and restore it. Recovery retries the remembered sign while the app runs.',
              style: muted,
              textAlign: TextAlign.center,
            ),
            if (h.diagnostics.isNotEmpty)
              ExpansionTile(
                title: const Text('Connection diagnostics'),
                children: [
                  for (final entry in h.diagnostics)
                    ListTile(dense: true, title: Text(entry)),
                ],
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
