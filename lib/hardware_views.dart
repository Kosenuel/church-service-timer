part of 'main.dart';

extension HardwareViews on _HomeState {
  Future<void> restoreSign() async {
    final s = c.state.session;
    final revision = s.revision;
    int? seconds;
    if (s.uncertain && s.active) {
      seconds = await showDialog<int>(
        context: context,
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
                c.hardware.status,
                key: const ValueKey('hardware-delivery-status'),
                style: TextStyle(
                  color: c.hardware.connected
                      ? appColors(context).accent
                      : appColors(context).warning,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign updates may blink briefly. A countdown runs on the sign; a static cue can remain there if the connection is lost.',
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
                  'Connect display',
                  Icons.wifi,
                  () => openHardwareConnection(),
                ),
              ],
            ],
          ),
        );

  Future<void> openHardwareConnection() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => HardwareConnectionPage(controller: c)),
  );
}

class HardwareConnectionPage extends StatefulWidget {
  final AppController controller;
  const HardwareConnectionPage({super.key, required this.controller});
  @override
  State<HardwareConnectionPage> createState() => _HardwareConnectionPageState();
}

class _HardwareConnectionPageState extends State<HardwareConnectionPage> {
  final password = TextEditingController();
  String? selected;
  AppController get c => widget.controller;
  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final h = c.hardware;
      final disabled = h.busy || h.sending || c.busy;
      return Scaffold(
        appBar: AppBar(title: const Text('Connect a display')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'W2 · 32 × 16 red monochrome',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Join the sign’s Wi-Fi.\n2. Scan and select your display.\n3. Enter its device password and connect.\n\nConnecting reads the profile and signs in. It does not replace what is on the sign.',
            ),
            const SizedBox(height: 16),
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
                    '${device['firmware']} · ${device['width']} × ${device['height']}\n${device['address']}${device['id'] == h.rememberedId ? ' · remembered' : ''}${device['supported'] == true ? '' : '\nUnsupported profile for this milestone'}',
                  ),
                  selected: selected == device['id'],
                  onTap: disabled || device['supported'] != true
                      ? null
                      : () => setState(() => selected = device['id'] as String),
                ),
              ),
            if (selected != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 128,
                decoration: const InputDecoration(
                  labelText: 'Display device password',
                  helperText:
                      'Not saved. This may differ from the Wi-Fi password.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: disabled
                    ? null
                    : () async {
                        final secret = password.text;
                        password.clear();
                        await h.connect(selected!, secret);
                      },
                child: const Text('Connect selected display'),
              ),
            ],
            const SizedBox(height: 20),
            if (h.busy || h.sending) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(h.status, key: const ValueKey('connection-result')),
            if (h.connected) ...[
              const SizedBox(height: 12),
              const Text(
                'Connected. Return to Live to start a service, or review and restore the current timer.',
              ),
              OutlinedButton(
                onPressed: disabled ? null : () => h.disconnect(),
                child: const Text('Disconnect display'),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'First hardware milestone',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Normal speed · up to 59:59 remaining. Countdown uses the original Matrix font. Cues retain their font and formatting; scrolling frames play on the controller.\n\nThe active-service notification supports warning delivery and return to the timer while the phone is locked. If it cannot start, keep the app open. Connection loss or stopping the app requires review before restoring. A cue or paused frame may remain on the sign.\n\nAt Zero applies when a segment expires; each template owns its end screen. Each program change can cause one brief blink.',
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: disabled
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
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
                      await h.disconnect(simulator: true);
                      if (c.state.session.disconnected) await c.act('connect');
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('Use Simulator instead'),
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
  late final minutes = TextEditingController(text: '${widget.initial ~/ 60}');
  late final seconds = TextEditingController(text: '${widget.initial % 60}');
  String? error;
  @override
  void dispose() {
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minutes'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: seconds,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seconds'),
                ),
              ),
            ],
          ),
          if (error != null) Text(error!),
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
          final m = int.tryParse(minutes.text), s = int.tryParse(seconds.text);
          if (m == null || s == null || m < 0 || m > 59 || s < 0 || s > 59) {
            setState(() => error = 'Enter a time from 00:00 to 59:59.');
            return;
          }
          Navigator.pop(context, m * 60 + s);
        },
        child: const Text('Verify & restore'),
      ),
    ],
  );
}
