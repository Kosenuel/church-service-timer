part of 'main.dart';

extension MobileDisplayViews on _HomeState {
  Future<void> chooseDisplay() =>
      openSettingsDetail('Choose display', displayChoices);

  Future<void> chooseDestination(String target) async {
    var restoreUnblank = false;
    if (controlsLocked || !c.pairing.localControl) return;
    if (c.destination == 'led' && target != 'led' && c.hardware.connected) {
      final blank = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave the LED sign?'),
          content: const Text(
            'The sign can keep its current output after disconnecting. Blank it before switching?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Leave output'),
            ),
            FilledButton(
              onPressed:
                  c.state.session.active || c.state.session.phase == 'ended'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Blank previous sign'),
            ),
          ],
        ),
      );
      if (blank == null || !mounted) return;
      restoreUnblank = blank && !c.state.session.outputBlank;
      if (blank && !await c.blankBeforeSwitch()) {
        if (mounted)
          await showError(
            c.error ??
                'The sign did not acknowledge blanking. You can switch with Leave output.',
          );
        return;
      }
    }
    if (!await c.selectDestination(target)) {
      if (mounted)
        await showError(c.error ?? 'Finish the current action first.');
      return;
    }
    if (restoreUnblank && c.state.session.outputBlank) await c.act('blank');
    if (!mounted) return;
    if (target == 'led') {
      await reconnectDisplay();
    } else if (target == 'mobile') {
      await openSettingsDetail('Stage screens', stageScreenSettings);
    } else {
      await c.act('connect');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Widget displayChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Where should your stage output appear?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Choose one destination. Your service timing continues when you switch.',
      ),
      const SizedBox(height: 24),
      for (final choice in [
        (
          'led',
          Icons.signpost_outlined,
          'LED sign',
          'Connect to your Wi-Fi LED controller',
        ),
        (
          'mobile',
          Icons.tablet_mac_outlined,
          'Phone or tablet',
          'Use another device as your stage screen',
        ),
        (
          'simulator',
          Icons.monitor_outlined,
          'Simulator',
          'Preview without an external display',
        ),
      ]) ...[
        Material(
          color: c.destination == choice.$1
              ? appColors(context).accent.withValues(alpha: .12)
              : appColors(context).surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: c.destination == choice.$1
                  ? appColors(context).accent
                  : appColors(context).border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: ValueKey('destination-${choice.$1}'),
            contentPadding: const EdgeInsets.all(18),
            leading: Icon(choice.$2, size: 34),
            title: Text(
              choice.$3,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(choice.$4),
            ),
            trailing: Icon(
              c.destination == choice.$1
                  ? Icons.check_circle
                  : Icons.chevron_right,
            ),
            onTap: c.busy || c.reportSavePending
                ? null
                : () => chooseDestination(choice.$1),
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (c.destination == 'led')
        TextButton.icon(
          onPressed: () =>
              openSettingsDetail('LED connection', connectionSettings),
          icon: const Icon(Icons.info_outline),
          label: const Text('LED connection details'),
        ),
    ],
  );

  Future<void> startStageSharing() async {
    try {
      if (!c.pairing.hosting)
        await c.pairing.host(await c.port.localNetworkAddress());
      c.pairing.setStageSharing(true);
      await c.syncActiveService();
      if (mounted) settingsRefresh.value++;
    } catch (_) {
      if (mounted)
        await showError(
          'Could not start sharing. Connect both devices to Wi-Fi that allows them to communicate.',
        );
    }
  }

  Widget stageScreenSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Your stage, on another screen',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
      const Text(
        'Put both devices on the same Wi-Fi. On the second device, open Paired devices, join this host and choose Stage display. Some sign hotspots isolate phones.',
      ),
      const SizedBox(height: 16),
      if (!c.pairing.hosting || !c.pairing.stageSharingEnabled)
        FilledButton.icon(
          onPressed: startStageSharing,
          icon: const Icon(Icons.cast),
          label: const Text('Start stage sharing'),
        ),
      if (c.pairing.hosting && c.pairing.stageSharingEnabled) ...[
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('Pair a screen'),
              const SizedBox(height: 12),
              SelectableText(
                c.pairing.pinAvailable
                    ? '${c.pairing.pin.substring(0, 3)} ${c.pairing.pin.substring(3)}'
                    : 'Code expired',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 38,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => PairQrDialog(hub: c.pairing),
                    ),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Show QR code'),
                  ),
                  TextButton(
                    onPressed: c.pairing.newCode,
                    child: const Text('New code'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        pairedDeviceList(screensOnly: true),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: c.stageConnected ? testStageScreen : null,
          icon: const Icon(Icons.connected_tv),
          label: const Text('Test screen'),
        ),
        TextButton(
          onPressed: stopStageSharing,
          child: const Text('Stop stage sharing'),
        ),
      ],
      if (!c.pairing.hosting || !c.pairing.stageSharingEnabled)
        pairedDeviceList(screensOnly: true),
    ],
  );

  Future<void> testStageScreen() async {
    final ok = await c.sendQuickMessage(
      const QuickMessage(
        headline: 'SCREEN TEST',
        body: 'Church Service Timer\nThis is your stage screen.',
        seconds: 5,
        palette: 'sky',
      ),
      test: true,
    );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Test sent for five seconds. Check that it appears on the intended screen.'
                : c.error ?? 'Screen unavailable.',
          ),
        ),
      );
  }

  Future<void> stopStageSharing() async {
    if (await confirm(
      'Stop stage sharing?',
      'Stage screens will stop receiving output. Paired operators and your running service remain connected.',
      'Stop sharing',
    ))
      await c.stopStageSharing();
  }

  ButtonStyle stopSharingButtonStyle() => FilledButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.errorContainer,
    foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    textStyle: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
  );

  Widget stageSharingControls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: controlsLocked
            ? null
            : () => openSettingsDetail('Stage screens', stageScreenSettings),
        icon: const Icon(Icons.devices),
        label: Text(
          c.pairing.stagePeers.isEmpty ? 'Pair screen' : 'Manage screens',
        ),
      ),
      if (c.pairing.hosting && c.pairing.stageSharingEnabled)
        FilledButton.icon(
          style: stopSharingButtonStyle(),
          onPressed: controlsLocked ? null : stopStageSharing,
          icon: const Icon(Icons.stop_screen_share_outlined),
          label: const Text('Stop sharing'),
        ),
      if (c.pairing.hosting && !c.pairing.stageSharingEnabled)
        TextButton(
          onPressed: controlsLocked ? null : startStageSharing,
          child: const Text('Start sharing'),
        ),
      TextButton(
        onPressed: controlsLocked ? null : chooseDisplay,
        child: const Text('Change display'),
      ),
    ],
  );

  Widget mobileStagePreview() {
    final peers = c.pairing.stagePeers;
    final acknowledged =
        peers.where((p) => p.acknowledgedSnapshot != null).toList()
          ..sort((a, b) => b.lastAck.compareTo(a.lastAck));
    final data = acknowledged.isEmpty
        ? null
        : acknowledged.first.acknowledgedSnapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.black,
              child: data == null
                  ? const Center(
                      child: Text(
                        'Waiting for a stage screen',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : StageSurface(data: data, stale: !c.stageConnected),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          c.stageConnected
              ? '${c.pairing.syncedStagePeers.map((p) => p.name).join(', ')} · Synced'
              : !c.pairing.stageSharingEnabled
              ? 'Sharing stopped'
              : data != null
              ? 'Disconnected · last received content'
              : 'Pair and approve a stage screen',
          style: TextStyle(fontSize: 12, color: appColors(context).muted),
        ),
        if (c.state.session.outputBlank)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Screen intentionally blanked'),
          ),
      ],
    );
  }

  Widget quickMessagePanel() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: label('Quick message')),
            TextButton(
              onPressed: controlsLocked
                  ? null
                  : () => openSettingsDetail(
                      'Quick message presets',
                      quickPresetSettings,
                    ),
              child: const Text(
                'Manage presets',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        const Text('For your stage screen · keep it short and easy to read.'),
        const SizedBox(height: 16),
        QuickMessageComposer(
          key: const ValueKey('live-quick-message'),
          initial: quickDraft,
          presets: c.state.quickMessages,
          onChanged: (value) => quickDraft = value,
          onSavePreset: controlsLocked
              ? null
              : (message) => c.saveQuickPreset(message),
          onSend:
              c.stageConnected &&
                  c.state.session.active &&
                  !c.busy &&
                  !controlsLocked &&
                  !c.reportSavePending &&
                  c.pairing.localControl
              ? c.sendQuickMessage
              : null,
        ),
        if (!c.stageConnected)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Connect a stage screen to send. Your draft stays here.',
            ),
          ),
        if (c.currentQuickMessage != null)
          TextButton.icon(
            onPressed: controlsLocked ? null : () => c.act('timer'),
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Return to timer'),
          ),
      ],
    ),
  );

  Future<void> editQuickPreset([int? index]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(
              index == null ? 'New message preset' : 'Edit message preset',
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              QuickMessageComposer(
                initial: index == null
                    ? const QuickMessage(body: '')
                    : c.state.quickMessages[index],
                saveLabel: 'Save preset',
                onSavePreset: (message) async {
                  final ok = await c.saveQuickPreset(message, index: index);
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                  return ok;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget quickPresetSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Saved wording and formatting for your phone or tablet stage screen.',
      ),
      const SizedBox(height: 12),
      for (final e in c.state.quickMessages.asMap().entries) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            e.value.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${e.value.length}/160 characters · ${e.value.seconds == 0 ? 'Until cleared' : '${e.value.seconds} seconds'}',
          ),
          onTap: () => editQuickPreset(e.key),
          trailing: IconButton(
            tooltip: 'Delete preset',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(
                'Delete this preset?',
                e.value.name,
                'Delete preset',
              ))
                await c.commit(
                  (draft, _) => draft.quickMessages.removeAt(e.key),
                );
            },
          ),
        ),
        const Divider(height: 1),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: c.state.quickMessages.length < 50
            ? () => editQuickPreset()
            : null,
        icon: const Icon(Icons.add),
        label: const Text('New preset'),
      ),
    ],
  );
}

class StageSurface extends StatelessWidget {
  final Json data;
  final bool stale;
  const StageSurface({super.key, required this.data, required this.stale});
  @override
  Widget build(BuildContext context) {
    if (data['stageSharing'] == false)
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Stage sharing stopped',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    if (data['blank'] == true) return const ColoredBox(color: Colors.black);
    if (data['quickMessage'] is Map)
      return RichStageMessage(
        message: QuickMessage.fromJson(
          Map<String, dynamic>.from(data['quickMessage']),
        ),
      );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: StageMessage(data: data, stale: stale, fullscreen: true),
    );
  }
}

class RichStageMessage extends StatelessWidget {
  final QuickMessage message;
  const RichStageMessage({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    final colors = switch (message.palette) {
      'amber' => (const Color(0xffffdc8b), const Color(0xff261b09)),
      'sky' => (const Color(0xffc4e6ff), const Color(0xff071b2c)),
      'mint' => (const Color(0xffbcf4da), const Color(0xff08271c)),
      _ => (Colors.white, const Color(0xff10151c)),
    };
    final align = switch (message.align) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    // One fixed-aspect canvas is shared by the composer, operator preview and stage.
    // Fit the canvas uniformly; never distort individual text or auto-scroll it.
    TextStyle headlineStyle(double fit) => TextStyle(
      fontFamily: 'Roboto',
      color: colors.$1,
      fontSize: 42 * message.scale * fit,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    TextStyle bodyStyle(double fit) => TextStyle(
      fontFamily: 'Roboto',
      color: colors.$1,
      fontSize: (message.length > 100 ? 38 : 48) * message.scale * fit,
      height: 1.2,
      fontWeight: message.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: message.italic ? FontStyle.italic : FontStyle.normal,
    );
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: align,
        textDirection: Directionality.of(context),
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: 864);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var fit = 1.0;
    while (fit > .4 &&
        (measure(message.body, bodyStyle(fit)) +
                (message.headline.isEmpty
                    ? 0
                    : measure(message.headline, headlineStyle(fit)) + 24)) >
            476) {
      fit -= .025;
    }
    return ColoredBox(
      color: colors.$2,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 960,
              height: 540,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message.headline.isNotEmpty) ...[
                      Text(
                        message.headline,
                        textAlign: align,
                        textScaler: TextScaler.noScaling,
                        style: headlineStyle(fit),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Flexible(
                      child: Text(
                        message.body,
                        textAlign: align,
                        textScaler: TextScaler.noScaling,
                        style: bodyStyle(fit),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickMessageComposer extends StatefulWidget {
  final QuickMessage initial;
  final List<QuickMessage> presets;
  final ValueChanged<QuickMessage>? onChanged;
  final Future<bool> Function(QuickMessage)? onSend, onSavePreset;
  final String saveLabel;
  const QuickMessageComposer({
    super.key,
    required this.initial,
    this.presets = const [],
    this.onChanged,
    this.onSend,
    this.onSavePreset,
    this.saveLabel = 'Save as preset',
  });
  @override
  State<QuickMessageComposer> createState() => _QuickMessageComposerState();
}

class _QuickMessageComposerState extends State<QuickMessageComposer> {
  late final TextEditingController headline, body;
  late QuickMessage style;
  bool busy = false;
  String? error;
  QuickMessage get value => QuickMessage(
    headline: headline.text.trim(),
    body: body.text.trim(),
    bold: style.bold,
    italic: style.italic,
    align: style.align,
    palette: style.palette,
    seconds: style.seconds,
    scale: style.scale,
  );
  @override
  void initState() {
    super.initState();
    style = widget.initial;
    headline = TextEditingController(text: style.headline);
    body = TextEditingController(text: style.body);
  }

  @override
  void dispose() {
    headline.dispose();
    body.dispose();
    super.dispose();
  }

  void changed({
    bool? bold,
    bool? italic,
    String? align,
    String? palette,
    int? seconds,
    double? scale,
  }) {
    setState(() {
      style = QuickMessage(
        body: body.text,
        bold: bold ?? style.bold,
        italic: italic ?? style.italic,
        align: align ?? style.align,
        palette: palette ?? style.palette,
        seconds: seconds ?? style.seconds,
        scale: scale ?? style.scale,
      );
      error = null;
    });
    widget.onChanged?.call(value);
  }

  Future<void> run(
    Future<bool> Function(QuickMessage) action,
    String success,
  ) async {
    try {
      value.validate();
    } catch (e) {
      setState(() => error = '$e');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await action(value);
      if (mounted)
        setState(
          () => error = ok
              ? success
              : 'Could not complete the action. Check the connection or storage and try again.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not complete the action. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.presets.isNotEmpty) ...[
        DropdownButtonFormField<int>(
          key: ValueKey(widget.presets.length),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Choose a preset'),
          items: [
            for (var i = 0; i < widget.presets.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  widget.presets[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (i) {
            if (i == null) return;
            setState(() {
              style = widget.presets[i];
              headline.text = style.headline;
              body.text = style.body;
              error = null;
            });
            widget.onChanged?.call(value);
          },
        ),
        const SizedBox(height: 16),
      ],
      TextField(
        controller: headline,
        maxLength: 48,
        decoration: const InputDecoration(
          labelText: 'Headline (optional)',
          counterText: '',
        ),
        onChanged: (_) => changed(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: body,
        minLines: 2,
        maxLines: 5,
        maxLength: 160,
        decoration: const InputDecoration(
          labelText: 'Message',
          hintText: 'A discreet message for the person on stage',
          counterText: '',
        ),
        onChanged: (_) => changed(),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          '${value.length}/160 characters',
          style: TextStyle(
            color: value.length > 160
                ? appColors(context).error
                : appColors(context).muted,
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const Text('Bold'),
            selected: style.bold,
            onSelected: (v) => changed(bold: v),
          ),
          FilterChip(
            label: const Text('Italic'),
            selected: style.italic,
            onSelected: (v) => changed(italic: v),
          ),
          for (final a in ['left', 'center', 'right'])
            IconButton(
              tooltip: 'Align $a',
              isSelected: style.align == a,
              onPressed: () => changed(align: a),
              icon: Icon(
                a == 'left'
                    ? Icons.format_align_left
                    : a == 'right'
                    ? Icons.format_align_right
                    : Icons.format_align_center,
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in ['white', 'amber', 'sky', 'mint'])
            ChoiceChip(
              label: Text(p[0].toUpperCase() + p.substring(1)),
              selected: style.palette == p,
              onSelected: (_) => changed(palette: p),
            ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<double>(
        key: ValueKey('size-${style.scale}'),
        initialValue: style.scale,
        decoration: const InputDecoration(labelText: 'Text size'),
        items: const [
          DropdownMenuItem(value: .85, child: Text('Comfortable')),
          DropdownMenuItem(value: 1.0, child: Text('Large')),
          DropdownMenuItem(value: 1.15, child: Text('Extra large')),
        ],
        onChanged: (v) => changed(scale: v),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey('duration-${style.seconds}'),
        initialValue: style.seconds,
        decoration: const InputDecoration(labelText: 'Show for'),
        items: [
          for (final d in [5, 10, 15, 30, 0])
            DropdownMenuItem(
              value: d,
              child: Text(d == 0 ? 'Until cleared' : '$d seconds'),
            ),
        ],
        onChanged: (v) => changed(seconds: v),
      ),
      if (value.length > 100 && style.seconds > 0 && style.seconds < 15)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('For a longer message, consider 15 or 30 seconds.'),
        ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RichStageMessage(message: value),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (widget.saveLabel == 'Save as preset')
            FilledButton.icon(
              onPressed: busy || widget.onSend == null
                  ? null
                  : () => run(widget.onSend!, 'Message sent.'),
              icon: const Icon(Icons.send),
              label: const Text('Send message'),
            ),
          OutlinedButton.icon(
            onPressed: busy || widget.onSavePreset == null
                ? null
                : () => run(widget.onSavePreset!, 'Preset saved.'),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(widget.saveLabel),
          ),
        ],
      ),
      if (error != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!)),
    ],
  );
}
