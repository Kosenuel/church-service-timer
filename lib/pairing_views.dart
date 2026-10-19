part of 'main.dart';

extension PairingViews on _HomeState {
  Widget pairedDeviceSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Use Wi-Fi that lets the devices communicate; some sign hotspots isolate phones. This phone hosts the timer and sign. Only one operator controls it at a time; other apps such as LedArt are outside this control system.',
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
                'Keep this host phone running. Pairing codes expire after 10 minutes. Approved devices reconnect automatically during this host session; control must be granted again after a lost link.',
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Six-digit pairing code',
                child: SelectableText(
                  c.pairing.pinAvailable
                      ? '${c.pairing.pin.substring(0, 3)} ${c.pairing.pin.substring(3)}'
                      : 'Code unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: c.pairing.pinAvailable ? 36 : 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Text(
                c.pairing.pinAvailable
                    ? 'Choose this host on the second device and enter these six digits.'
                    : 'The code expired or reached its attempt limit. Create a new code below.',
              ),
              if (c.pairing.discoveryNotice.isNotEmpty)
                Text(c.pairing.discoveryNotice),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => PairQrDialog(hub: c.pairing),
                    ),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Show QR code'),
                  ),
                  TextButton.icon(
                    onPressed: c.pairing.newCode,
                    icon: const Icon(Icons.refresh),
                    label: const Text('New code'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
            'Waiting for a device. On its Paired devices page, choose Join another operator and enter the six-digit code or scan the QR code.',
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

class _JoinDevicePageState extends State<JoinDevicePage>
    with WidgetsBindingObserver {
  final code = TextEditingController(),
      name = TextEditingController(text: 'Second device');
  String role = 'viewer';
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
  @override
  void initState() {
    super.initState();
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
      try {
        await nsd.stopDiscovery(previous);
      } catch (_) {}
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
    super.dispose();
  }

  Future<void> join({String? qr}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      require(
        !widget.controller.state.session.active,
        'End this phone’s local service first.',
      );
      final host = hosts.where((s) => serviceKey(s) == selected).firstOrNull;
      require(
        qr != null || (host != null && validPairPin(code.text)),
        'Choose a nearby host and enter its six-digit code.',
      );
      final address = await widget.controller.port.localNetworkAddress();
      if (widget.controller.hardware.connected)
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Join a service')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Use the same Wi-Fi as the host. Choose it below and enter its six-digit code, or scan its QR code. The host approves every new device.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          maxLength: 60,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
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
                'Looking for a host… Tap Share this service on the other phone. If it does not appear, try QR pairing.',
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
  @override
  void initState() {
    super.initState();
    widget.hub.addListener(refresh);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void refresh() {
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
                      : data['blank'] == true
                      ? const SizedBox.expand()
                      : StageMessage(
                          data: data,
                          stale: stale,
                          fullscreen: true,
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
              if (stale)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Host disconnected · last received display',
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
              actions: [leaveButton()],
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            content,
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
            child: Text(
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
