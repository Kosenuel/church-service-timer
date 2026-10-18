part of 'main.dart';

extension PairingViews on _HomeState {
  Widget pairedDeviceSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Keep both devices on the same local Wi-Fi. This phone hosts the timer and sign connection; only one operator controls it at a time. Other apps such as LedArt are outside this control system.',
      ),
      const SizedBox(height: 16),
      if (!c.pairing.hosting) ...[
        FilledButton.icon(
          onPressed: () async {
            try {
              await c.pairing.host(await c.port.localNetworkAddress());
            } catch (e) {
              if (mounted) await showError('Could not share: $e');
            }
          },
          icon: const Icon(Icons.cast_connected),
          label: const Text('Share this service'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: c.state.session.active
              ? null
              : () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => JoinDevicePage(controller: c),
                    ),
                  );
                },
          icon: const Icon(Icons.devices),
          label: const Text('Join another operator'),
        ),
        if (c.state.session.active)
          const Text('End this local service before joining a different host.'),
      ] else ...[
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.pairing.localControl
                    ? 'Control: this phone'
                    : 'Control: paired operator',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep this host phone running. Pairing codes expire after 10 minutes; approved connections last until disconnected.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  c.pairing.newCode();
                  await Clipboard.setData(
                    ClipboardData(text: c.pairing.code!.encode()),
                  );
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New pairing code copied. Paste it on the second device. Keep the code private.',
                        ),
                      ),
                    );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy new pairing code'),
              ),
              if (!c.pairing.localControl)
                FilledButton(
                  onPressed: () async {
                    if (await confirm(
                      'Take back control?',
                      'The paired operator will become a viewer. The running timer is unchanged.',
                      'Take control',
                    ))
                      c.pairing.reclaim();
                  },
                  child: const Text('Take back control'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (c.pairing.peers.isEmpty)
          const Text(
            'Waiting for a device to join. Paste the pairing code on its Paired devices page.',
          ),
        for (final peer in List<PairPeer>.of(c.pairing.peers))
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  peer.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${peer.role} · ${peer.approved ? (c.pairing.owner == peer.id ? 'Controls service' : 'Approved') : 'Awaiting your approval'}',
                ),
                if (peer.requestedControl)
                  const Text('This operator requests control.'),
                Wrap(
                  spacing: 8,
                  children: [
                    if (!peer.approved)
                      FilledButton(
                        onPressed: () => c.pairing.approve(peer),
                        child: const Text('Approve'),
                      ),
                    if (peer.approved &&
                        peer.role == 'operator' &&
                        c.pairing.owner != peer.id)
                      OutlinedButton(
                        onPressed: () async {
                          if (await confirm(
                            'Give ${peer.name} control?',
                            'This device can operate timer, cues and End service. Private rundown notes become visible. This host continues running the service and may take control back.',
                            'Give control',
                          ))
                            c.pairing.grant(peer);
                        },
                        child: const Text('Give control'),
                      ),
                    TextButton(
                      onPressed: () => c.pairing.remove(peer),
                      child: Text(peer.approved ? 'Disconnect' : 'Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: () async {
            if (await confirm(
              'Stop sharing?',
              'All paired screens and operators will disconnect. The local service and sign keep running.',
              'Stop sharing',
            ))
              await c.pairing.stop();
          },
          child: const Text('Stop sharing'),
        ),
      ],
    ],
  );
}

class JoinDevicePage extends StatefulWidget {
  final AppController controller;
  const JoinDevicePage({super.key, required this.controller});
  @override
  State<JoinDevicePage> createState() => _JoinDevicePageState();
}

class _JoinDevicePageState extends State<JoinDevicePage> {
  final code = TextEditingController(),
      name = TextEditingController(text: 'Second device');
  String role = 'viewer';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Join a service')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Copy a pairing code from the host, then paste it here. The host must approve this device. End any local service first.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        TextField(
          controller: code,
          maxLength: 1000,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Pairing code',
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Use this device as'),
          items: const [
            DropdownMenuItem(value: 'viewer', child: Text('Service viewer')),
            DropdownMenuItem(value: 'stage', child: Text('Stage display')),
            DropdownMenuItem(
              value: 'operator',
              child: Text('Additional operator'),
            ),
          ],
          onChanged: busy ? null : (v) => setState(() => role = v!),
        ),
        const SizedBox(height: 16),
        if (error != null)
          Text(error!, style: TextStyle(color: appColors(context).error)),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    require(
                      !widget.controller.state.session.active,
                      'End this phone’s local service first.',
                    );
                    final address = await widget.controller.port
                        .localNetworkAddress();
                    if (widget.controller.hardware.connected)
                      await widget.controller.hardware.disconnect();
                    await widget.controller.pairing.join(
                      code.text.trim(),
                      name.text.trim(),
                      role,
                      sourceAddress: address,
                    );
                    code.clear();
                    if (context.mounted)
                      Navigator.of(context).popUntil((r) => r.isFirst);
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => error =
                            'Could not join. Check the code, host approval and shared Wi-Fi.',
                      );
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? 'Connecting…' : 'Join service'),
        ),
      ],
    ),
  );
}

class PairedScreen extends StatelessWidget {
  final AppController controller;
  const PairedScreen({super.key, required this.controller});
  Future<void> action(
    BuildContext context,
    String label,
    String action, [
    dynamic value,
  ]) async {
    final revision = controller.pairing.snapshot?['revision'] as int?;
    final ok = await showDialog<bool>(
      context: context,
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
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            'Stage connection: ${data['connection'] ?? 'Unknown'}',
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in [
                  ('−2 min', 'adjust', -120),
                  (data['paused'] == true ? 'Resume' : 'Pause', 'pause', null),
                  ('+2 min', 'adjust', 120),
                  ('Next segment', 'advance', false),
                  ('Show timer', 'timer', null),
                  ('Blank sign', 'blank', null),
                  ('End service', 'end', null),
                ])
                  OutlinedButton(
                    onPressed: data['phase'] == 'active'
                        ? () => action(context, item.$1, item.$2, item.$3)
                        : null,
                    child: Text(item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final e in ((data['cues'] as List?) ?? []).asMap().entries)
                  FilledButton(
                    onPressed: data['phase'] == 'active'
                        ? () async {
                            try {
                              await hub.sendCommand('cue', e.key);
                            } catch (_) {}
                          }
                        : null,
                    child: Text(e.value as String),
                  ),
              ],
            ),
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
                '${e.value['minutes']} min · ${e.value['speaker']}${e.value['notes'] == null ? '' : '\nPrivate: ${e.value['notes']}'}',
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
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            content,
            const SizedBox(height: 24),
            if (hub.mode != 'operator')
              TextButton.icon(
                onPressed: () => hub.showStage(!stage),
                icon: Icon(stage ? Icons.view_list : Icons.fullscreen),
                label: Text(stage ? 'Service view' : 'Use as stage display'),
              ),
            OutlinedButton(
              onPressed: () => hub.stop(),
              child: const Text('Leave paired service'),
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
  final bool stale;
  const StageMessage({super.key, required this.data, required this.stale});
  @override
  State<StageMessage> createState() => _StageMessageState();
}

class _StageMessageState extends State<StageMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  double elapsed = 0;
  int previousTick = 0;
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
          })
          ..repeat();
  }

  @override
  void didUpdateWidget(StageMessage old) {
    super.didUpdateWidget(old);
    if (old.data['displayText'] != widget.data['displayText'] ||
        old.data['effect'] != widget.data['effect'])
      elapsed = 0;
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
      final style = TextStyle(
        fontSize: (space.maxWidth / 7).clamp(42.0, 130.0),
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
        final speed = ((widget.data['speed'] as num?) ?? 12).toDouble() * 6;
        final x = space.maxWidth - (elapsed * speed) % travel;
        final height = painter.height + 24;
        painter.dispose();
        return SizedBox(
          height: height,
          width: space.maxWidth,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: x,
                  top: 12,
                  child: Text(text, style: style, softWrap: false),
                ),
              ],
            ),
          ),
        );
      }
      return Opacity(
        opacity: effect == 'flash' && (elapsed * 2).floor() % 2 == 1 ? 0 : 1,
        child: SizedBox(
          height: 170,
          width: space.maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, style: style, textAlign: TextAlign.center),
          ),
        ),
      );
    },
  );
}
