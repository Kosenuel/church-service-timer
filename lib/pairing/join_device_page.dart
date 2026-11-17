import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import 'package:church_service_timer/pairing/pairing_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/best_effort.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing_views.dart';

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
      // One name for joining, whichever role is chosen below.
      title: const Text('Join a service'),
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
          // No "13/60" counter jammed against the next field; the limit
          // still applies.
          decoration: const InputDecoration(
            labelText: 'Device name',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
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
                'Looking for a host… Tap Share to stage screens on the host device. If it does not appear, try QR pairing.',
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
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
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
        // A PC has no camera scanner; the six-digit code does the same job.
        if (!widget.controller.port.isDesktop) const SizedBox(height: 8),
        if (!widget.controller.port.isDesktop)
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final qr = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => const PairScannerPage(),
                      ),
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
