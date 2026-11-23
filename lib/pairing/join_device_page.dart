import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import 'package:church_service_timer/pairing/pairing_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
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
        deviceText('End this phone’s local service first.'),
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
    return FinishCard(
      key: const ValueKey('wifi-rejoin'),
      radius: 16,
      flat: (child) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
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
                      : deviceText(
                          'This phone is on $wifiName. If the link drops, only this network is rejoined.',
                        ),
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
                  title: Text(deviceText('Save the password on this phone')),
                  subtitle: Text(
                    'Encrypted. Used only to rejoin $wifiName for this host.',
                    style: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get canResume =>
      widget.controller.pairing.hasSavedHost &&
      (widget.initialRole != 'stage' ||
          widget.controller.pairing.canResumeAsStage);

  Widget resumeButton() => OutlinedButton.icon(
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
  );

  Widget nameField() => TextField(
    controller: name,
    maxLength: 60,
    enabled: !busy,
    // No "13/60" counter jammed against the next field; the limit
    // still applies.
    decoration: const InputDecoration(
      labelText: 'Device name',
      counterText: '',
    ),
  );

  Widget roleField() => ChoiceField<String>(
    value: role,
    decoration: const InputDecoration(labelText: 'Use this device as'),
    options: const [
      ChoiceOption(value: 'viewer', label: 'Service viewer'),
      ChoiceOption(value: 'stage', label: 'Stage display'),
      ChoiceOption(value: 'operator', label: 'Additional operator'),
    ],
    onChanged: busy ? null : (v) => setState(() => role = v!),
  );

  Widget hostTile(nsd.Service host, {EdgeInsets padding = EdgeInsets.zero}) =>
      ListTile(
        contentPadding: padding,
        leading: Icon(
          selected == serviceKey(host)
              ? Icons.radio_button_checked
              : Icons.radio_button_off,
        ),
        title: Text(host.name ?? 'Church Service Timer'),
        subtitle: Text(serviceAddress(host)!),
        onTap: busy ? null : () => setState(() => selected = serviceKey(host)),
      );

  Widget codeField({bool large = false}) => TextField(
    controller: code,
    enabled: !busy,
    maxLength: 6,
    keyboardType: TextInputType.number,
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (_) => setState(() {}),
    style: TextStyle(fontSize: large ? 34 : 26, letterSpacing: large ? 10 : 5),
    decoration: const InputDecoration(
      labelText: 'Six-digit code',
      hintText: '000000',
      counterText: '',
    ),
  );

  Widget joinButton() => FilledButton(
    onPressed: busy || selected == null || !validPairPin(code.text)
        ? null
        : join,
    child: Text(busy ? 'Connecting…' : 'Join service'),
  );

  Widget scanButton() => OutlinedButton.icon(
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
  );

  /// A numbered heading for one step of joining.
  Widget step(int number, String title) {
    final colors = appColors(context);
    return Row(
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
            '$number',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// What is still missing before Join service can be pressed.
  String get joinHint => busy
      ? 'Waiting for the host to approve this device.'
      : selected == null
      ? 'Choose a host on the left first.'
      : !validPairPin(code.text)
      ? 'Enter all six digits to join.'
      : 'Ready. The host approves this device after you join.';

  /// A wide window: the hosts to pick from on the left, then this device's
  /// name and the code, in the order they are done.
  Widget wideBody() {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: colors.muted, height: 1.4);
    final found = hosts;
    final desktop = widget.controller.port.isDesktop;
    return SplitPage(
      sideFirst: true,
      sideShare: .3,
      sideMin: 360,
      sideMax: 520,
      mainMaxWidth: 640,
      side: Column(
        key: const ValueKey('join-hosts-pane'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: step(1, 'Choose the host'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 12, 0),
            child: Row(
              children: [
                const Expanded(child: PaneLabel('Nearby hosts')),
                TextButton.icon(
                  onPressed: busy || discovering ? null : findHosts,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Search again'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              discovering
                  ? 'Searching for hosts…'
                  : discoveryError != null
                  ? 'Search unavailable'
                  : found.isEmpty
                  ? 'No host found yet'
                  : found.length == 1
                  ? '1 host found'
                  : '${found.length} hosts found',
              key: const ValueKey('join-hosts-status'),
              style: text.bodySmall?.copyWith(color: colors.muted),
            ),
          ),
          SizedBox(
            height: 2,
            child: discovering
                ? const LinearProgressIndicator(minHeight: 2)
                : ColoredBox(color: colors.border),
          ),
          Expanded(
            child: ListView(
              primary: false,
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Text(
                      discoveryError ??
                          (discovering
                              ? 'Hosts on this Wi-Fi appear here as they answer.'
                              : 'On the host device, open Live and choose Share to screens. Then choose Search again here.'),
                      style: text.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                for (final host in found)
                  Material(
                    type: MaterialType.transparency,
                    child: hostTile(
                      host,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PaneLabel('If the host is not listed'),
                      const SizedBox(height: 8),
                      Text(
                        'Both devices must be on the same Wi-Fi, and the host must be sharing.',
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Some sign hotspots isolate phones. If pairing fails, use a shared router or another hotspot.',
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      main: SingleChildScrollView(
        key: const ValueKey('join-form-pane'),
        primary: false,
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                'Follow or help run a service that another device is hosting. The host approves every new device.',
                style: text.bodyMedium?.copyWith(
                  color: colors.muted,
                  height: 1.4,
                ),
              ),
            ),
            if (canResume) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  resumeButton(),
                  Text('Joined before? This skips the steps.', style: muted),
                ],
              ),
            ],
            const SizedBox(height: 28),
            step(2, 'Name this device'),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nameField(),
                  const SizedBox(height: 12),
                  roleField(),
                ],
              ),
            ),
            const SizedBox(height: 32),
            step(3, 'Enter the code shown on the host'),
            const SizedBox(height: 14),
            SizedBox(width: 300, child: codeField(large: true)),
            if (!desktop) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: wifiRejoinSection(),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(error!, style: TextStyle(color: colors.error)),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180),
                  child: joinButton(),
                ),
                // A PC has no camera scanner; the code does the same job.
                if (!desktop) scanButton(),
                Text(joinHint, key: const ValueKey('join-hint'), style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: finishBar(context),
      // One name for joining, whichever role is chosen below.
      title: const Text('Join a service'),
    ),
    body: isWideWindow(context) ? wideBody() : narrowBody(),
  );

  Widget narrowBody() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Use the same Wi-Fi as the host. Choose it below and enter its six-digit code, or scan its QR code. The host approves every new device.',
      ),
      const SizedBox(height: 16),
      if (canResume) ...[resumeButton(), const SizedBox(height: 12)],
      nameField(),
      const SizedBox(height: 12),
      roleField(),
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
      for (final host in hosts) hostTile(host),
      const SizedBox(height: 12),
      codeField(),
      const SizedBox(height: 12),
      // Windows rejoins its own known networks; the app never switches.
      if (!widget.controller.port.isDesktop) wifiRejoinSection(),
      const SizedBox(height: 12),
      if (error != null)
        Text(error!, style: TextStyle(color: appColors(context).error)),
      joinButton(),
      // A PC has no camera scanner; the six-digit code does the same job.
      if (!widget.controller.port.isDesktop) const SizedBox(height: 8),
      if (!widget.controller.port.isDesktop) scanButton(),
      const SizedBox(height: 12),
      const Text(
        'Some sign hotspots isolate phones. If pairing fails, use a shared router or another hotspot.',
      ),
    ],
  );
}
