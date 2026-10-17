part of 'main.dart';

IconData connectionIcon(DisplayConnection state) => switch (state) {
  DisplayConnection.simulator => Icons.monitor_outlined,
  DisplayConnection.connected => Icons.wifi,
  DisplayConnection.disconnected => Icons.wifi_off,
};

extension RefinedSettings on _HomeState {
  Widget settingsRow(
    IconData icon,
    String title,
    String summary,
    VoidCallback? action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(icon, size: 22, color: appColors(context).accent),
    title: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      summary,
      style: TextStyle(fontSize: 13, color: appColors(context).muted),
    ),
    trailing: action == null ? null : const Icon(Icons.chevron_right, size: 22),
    onTap: c.busy ? null : action,
  );

  Widget settingsGroup(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      label(title),
      const SizedBox(height: 10),
      panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              rows[i],
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget displaySettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingsGroup('Sign', [
        settingsRow(
          connectionIcon(c.displayConnection),
          'Display connection',
          c.displayConnection.label,
          () => openSettingsDetail('Display connection', connectionSettings),
        ),
        settingsRow(
          Icons.grid_on_outlined,
          'Display profile',
          '32 × 16 · monochrome · not verified on hardware',
          () => openSettingsDetail('Display profile', displayProfile),
        ),
      ]),
      settingsGroup('Content & preview', [
        settingsRow(
          Icons.apps,
          'LED preview shape',
          c.state.pixelShape == 'square' ? 'Square LEDs' : 'Circular LEDs',
          () => openSettingsDetail('LED preview shape', ledShapeSettings),
        ),
        settingsRow(
          Icons.text_fields,
          'Display fonts',
          'Matrix, Sq-Matrix and bundled Tinos',
          () => openSettingsDetail('Display fonts', displayFonts),
        ),
        settingsRow(
          Icons.timer_off_outlined,
          'At Zero',
          '${c.state.defaults.zero?.text ?? '00:00'} · shared across all services',
          () => openSettingsDetail('At Zero', sharedZeroSettings),
        ),
        settingsRow(
          Icons.flag_outlined,
          'Default end screen',
          '${c.state.defaults.end.text} · for new templates',
          () => openSettingsDetail('Default end screen', defaultEndSettings),
        ),
      ]),
      Text(
        'Each template keeps its own end screen. Manage shared warnings under Warnings & alerts in Settings.',
        style: TextStyle(color: appColors(context).muted),
      ),
    ],
  );

  Widget defaultEndSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedMatrix(pixels: renderPixels(c.state.defaults.end, 0)),
        const SizedBox(height: 16),
        Text(styleSummary(c.state.defaults.end)),
        const SizedBox(height: 12),
        const Text(
          'Used when creating a new template. Existing templates and the loaded service retain their end screens.',
        ),
        const SizedBox(height: 16),
        button(
          'Edit end screen',
          Icons.edit_outlined,
          c.busy
              ? null
              : () async {
                  final next = await compose(
                    c.state.defaults.end,
                    'End screen',
                    'Save end screen',
                  );
                  if (next != null &&
                      !await c.commit(
                        (draft, _) =>
                            draft.defaults = draft.defaults.withEnd(next),
                      ) &&
                      mounted)
                    await showError(c.error ?? 'Could not save end screen.');
                },
        ),
      ],
    ),
  );

  Widget displayProfile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingsGroup('Simulator profile', [
        settingsRow(
          Icons.aspect_ratio,
          'Resolution',
          '32 × 16 pixels · simulator assumption',
          null,
        ),
        settingsRow(
          Icons.palette_outlined,
          'Color capability',
          'Monochrome · simulator assumption',
          null,
        ),
        settingsRow(
          Icons.timer_outlined,
          'Countdown',
          'Service Matrix · 14 pixels tall',
          null,
        ),
      ]),
      settingsGroup('Physical sign · not verified', [
        settingsRow(
          Icons.developer_board_outlined,
          'Controller',
          'Unknown · waiting for the sign',
          null,
        ),
        settingsRow(
          Icons.info_outline,
          'Device details',
          'No properties have been read from hardware',
          null,
        ),
      ]),
      const Text(
        'The preview profile is for testing. Hardware resolution, controller details, brightness and delivery verification will be added after connecting and testing the sign.',
      ),
    ],
  );

  Widget displayFonts() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingsGroup('Built-in display fonts', [
        settingsRow(
          Icons.grid_on,
          'Service Matrix',
          'Original bitmap font · unchanged',
          null,
        ),
        settingsRow(
          Icons.grid_4x4,
          'Service Sq-Matrix',
          'Square-pixel bitmap font · unchanged',
          null,
        ),
        settingsRow(
          Icons.text_fields,
          'Tinos',
          'Regular, Bold, Italic and Bold Italic · bundled',
          null,
        ),
      ]),
      const Text(
        'Choose a font when editing a cue, warning or end screen. Tinos is drawn on the phone and converted to LED pixels. No font import or internet connection is required.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Tall (14 px) gives Tinos the clearest detail. Long messages scroll across the 32 × 16 display. Find Open-source licenses on the About page.',
      ),
      if (!NativeDisplayFonts.available) ...[
        const SizedBox(height: 12),
        Text(
          'Bundled Tinos is unavailable in this runtime. Android is required for its native rasterizer.',
          style: TextStyle(color: appColors(context).warning),
        ),
      ],
    ],
  );

  Widget connectionSettings() {
    final s = c.state.session;
    final output = s.disconnected
        ? 'No updates while disconnected'
        : s.held
        ? 'Held for operator review'
        : c.simulator.signature.isEmpty
        ? 'No output published yet'
        : 'Latest local frame rendered';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsGroup('Connection', [
          settingsRow(
            connectionIcon(c.displayConnection),
            c.displayConnection.label,
            'Adapter: local 32 × 16 simulator',
            null,
          ),
          settingsRow(Icons.update, 'Output status', output, null),
          settingsRow(
            Icons.verified_outlined,
            'Physical delivery',
            'Not available · no hardware adapter',
            null,
          ),
        ]),
        const Text(
          'A connection status does not confirm that a physical sign received an update. This build only renders local simulated frames.',
        ),
        const SizedBox(height: 16),
        button(
          s.disconnected ? 'Reconnect simulator' : 'Disconnect simulator',
          s.disconnected ? Icons.link : Icons.link_off,
          c.busy || c.corrupt
              ? null
              : () => c.act(s.disconnected ? 'connect' : 'disconnect'),
        ),
        if (s.held)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Return to Live to review and restore held output.'),
          ),
      ],
    );
  }

  Widget readinessSettings() {
    final s = c.state.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'A quick optional check before you start. Your timer and current display output remain unchanged.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        settingsGroup('Service checklist', [
          settingsRow(
            Icons.view_timeline_outlined,
            'Selected service',
            s.timeline == null
                ? 'Choose a template from Live or Templates'
                : '${s.timeline!.name} · ${s.timeline!.segments.length} segments',
            null,
          ),
          settingsRow(
            connectionIcon(c.displayConnection),
            'Display connection',
            '${c.displayConnection.label}${s.held ? ' · output held' : ''}',
            () => openSettingsDetail('Display connection', connectionSettings),
          ),
          settingsRow(
            Icons.notifications_outlined,
            'Phone warnings',
            c.notificationState['enabled'] == true
                ? (c.notificationState['sound'] == true
                      ? 'Notifications and sound enabled'
                      : 'Notifications enabled · channel sound off')
                : 'Notifications disabled',
            () => openSettingsDetail('Warnings & alerts', warningsSettings),
          ),
          settingsRow(
            Icons.alarm,
            'Warning rules',
            '${c.state.defaults.warnings.where((w) => w.enabled).length} enabled · shared across services',
            () => openSettingsDetail('Warnings & alerts', warningsSettings),
          ),
        ]),
        button(
          'Preview test cue',
          Icons.preview_outlined,
          () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Isolated simulator test'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LedMatrix(
                      pixels: renderPixels(
                        const TextLayout('AMEN', effect: 'static'),
                        0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Test preview only. The current stage output and timing have not changed.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        button('Test notification sound', Icons.volume_up_outlined, () async {
          try {
            await c.port.testNotification();
          } catch (e) {
            if (mounted) await showError('$e');
          }
        }),
        const SizedBox(height: 12),
        const Text(
          'Sound also depends on phone volume and Do Not Disturb. Physical sign testing will be available after the hardware is verified.',
        ),
      ],
    );
  }

  Future<void> chooseStageCue() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a stage cue'),
        children: [
          for (var i = 0; i < c.state.stageCues.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(c.state.stageCues[i].text),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Write a new cue'),
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == -1) {
      await sendCue(const TextLayout(''));
    } else if (selected < c.state.stageCues.length) {
      await sendCue(c.state.stageCues[selected], cueIndex: selected);
    }
  }
}
