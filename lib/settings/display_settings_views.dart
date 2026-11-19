import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/main.dart';

IconData connectionIcon(DisplayConnection state) => switch (state) {
  DisplayConnection.simulator => Icons.monitor_outlined,
  DisplayConnection.connected => Icons.wifi,
  DisplayConnection.disconnected => Icons.wifi_off,
  DisplayConnection.stageConnected => Icons.tablet_mac,
  DisplayConnection.stageWaiting => Icons.add_to_queue,
  DisplayConnection.stageDisconnected => Icons.portable_wifi_off,
};

extension RefinedSettings on HomeState {
  Widget settingsRow(
    IconData icon,
    String title,
    String summary,
    VoidCallback? action,
  ) => ListTile(
    contentPadding: appLayout(context).tileInsets,
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
              if (i > 0) const AppDivider(),
              rows[i],
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
  );

  /// The parts of Display settings, in the order they are listed: rows
  /// that each open a page on a phone, and the sections of one page in a
  /// wide window.
  List<DisplaySection> displaySections() => [
    DisplaySection(
      'connection',
      'Sign',
      connectionIcon(c.displayConnection),
      'Display connection',
      c.displayConnection.label,
      connectionSettings,
    ),
    DisplaySection(
      'profile',
      'Sign',
      Icons.grid_on_outlined,
      'Display profile',
      c.hardware.profile == null
          ? '32 × 16 preview · connect to read the sign'
          : '${c.hardware.profile!['width']} × ${c.hardware.profile!['height']} · red monochrome · W2',
      displayProfile,
    ),
    DisplaySection(
      'clock',
      'Content & preview',
      Icons.schedule,
      'Clock format',
      c.state.clockFormat == '12h' ? '12-hour · AM/PM' : '24-hour',
      clockFormatSettings,
    ),
    DisplaySection(
      'shape',
      'Content & preview',
      Icons.apps,
      'LED preview shape',
      c.state.pixelShape == 'square' ? 'Square LEDs' : 'Circular LEDs',
      ledShapeSettings,
    ),
    DisplaySection(
      'fonts',
      'Content & preview',
      Icons.text_fields,
      'Display fonts',
      'Matrix, Sq-Matrix and bundled Tinos',
      displayFonts,
    ),
    DisplaySection(
      'zero',
      'Content & preview',
      Icons.timer_off_outlined,
      'At zero',
      '${c.state.defaults.zero?.text ?? '00:00'} · shared across all services',
      sharedZeroSettings,
    ),
    DisplaySection(
      'end',
      'Content & preview',
      Icons.flag_outlined,
      'Default end screen',
      '${c.state.defaults.end.text} · for new programs',
      defaultEndSettings,
    ),
  ];

  static const displaySettingsNote =
      'Each program keeps its own end screen. Manage shared warnings under Warnings & alerts in Settings.';

  /// Display settings. A wide window shows the sections down the left and
  /// the chosen one, [section], beside them.
  Widget displaySettings({String section = 'connection'}) {
    final sections = displaySections();
    Widget rows(String group) => settingsGroup(group, [
      for (final s in sections)
        if (s.group == group)
          settingsRow(
            s.icon,
            s.title,
            s.summary,
            // On a phone the connection row goes straight to the choices.
            s.key == 'connection'
                ? chooseDisplay
                : () => openSettingsDetail(s.title, s.content),
          ),
    ]);
    return SettingsWide(
      body: (context) => DisplaySettingsDesk(home: this, initial: section),
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rows('Sign'),
          rows('Content & preview'),
          Text(
            displaySettingsNote,
            style: TextStyle(color: appColors(context).muted),
          ),
        ],
      ),
    );
  }

  /// Opens one part of Display settings: its own page on a phone, and
  /// Display settings with that section chosen in a wide window.
  Future<void> openDisplaySection(String key) {
    if (isWideWindow(context)) {
      return openSettingsDetail(
        'Display settings',
        () => displaySettings(section: key),
      );
    }
    final section = displaySections().firstWhere((s) => s.key == key);
    return openSettingsDetail(section.title, section.content);
  }

  Widget defaultEndSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedMatrix(pixels: renderPixels(c.state.defaults.end, 0)),
        const SizedBox(height: 16),
        Text(styleSummary(c.state.defaults.end)),
        const SizedBox(height: 12),
        const Text(
          'Used when creating a new program. Existing programs and the loaded service retain their end screens.',
        ),
        const SizedBox(height: 16),
        ordinarySize(
          context,
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
        ),
      ],
    ),
  );

  Widget displayProfile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingsGroup(
        c.hardware.profile == null
            ? 'Preview profile'
            : 'Connected display profile',
        [
          settingsRow(
            Icons.aspect_ratio,
            'Resolution',
            c.hardware.profile == null
                ? '32 × 16 pixels · preview'
                : '${c.hardware.profile!['width']} × ${c.hardware.profile!['height']} pixels · read from controller',
            null,
          ),
          settingsRow(
            Icons.palette_outlined,
            'Colour capability',
            c.hardware.profile == null
                ? 'Monochrome · preview'
                : 'Red monochrome · read from controller',
            null,
          ),
          settingsRow(
            Icons.timer_outlined,
            'Countdown',
            'I-Proton Matrix · 14 pixels tall',
            null,
          ),
        ],
      ),
      settingsGroup('Physical sign', [
        settingsRow(
          Icons.developer_board_outlined,
          'Controller',
          c.hardware.profile == null
              ? 'Connect a display to read its profile'
              : 'Huidu W2',
          null,
        ),
        settingsRow(
          Icons.info_outline,
          'Device details',
          c.hardware.profile == null
              ? 'No properties read in this app session'
              : '${c.hardware.profile!['firmware']} · ${c.hardware.profile!['address']}',
          null,
        ),
      ]),
      const Text(
        'The connected display supplies its profile. Wi-Fi and password controls are in Settings / Device management. Panel wiring, firmware and brightness are not editable.',
      ),
    ],
  );

  Widget displayFonts() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingsGroup('Built-in display fonts', [
        settingsRow(
          Icons.grid_on,
          'I-Proton Matrix',
          'Original bitmap font · unchanged',
          null,
        ),
        settingsRow(
          Icons.grid_4x4,
          'I-Proton Sq-Matrix',
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
      Text(
        deviceText(
          'Choose a font when editing a cue, warning or end screen. Tinos is drawn on the phone and converted to LED pixels. No font import or internet connection is required.',
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Tall (14 px) gives Tinos the clearest detail. Long messages scroll across the 32 × 16 display. Find Open-source licenses on the About page.',
      ),
      if (!NativeDisplayFonts.available) ...[
        const SizedBox(height: 12),
        Text(
          desktopWording
              ? 'Bundled Tinos could not be loaded. Reinstall the app to restore its fonts.'
              : 'Bundled Tinos is unavailable in this runtime. Android is required for its native rasterizer.',
          style: TextStyle(color: appColors(context).warning),
        ),
      ],
    ],
  );

  Widget connectionSettings() {
    final s = c.state.session;
    final output = c.hardware.enabled
        ? c.hardware.status
        : s.disconnected
        ? 'No updates while disconnected'
        : s.held
        ? 'Held for operator review'
        : c.simulator.signature.isEmpty
        ? 'No output published yet'
        : 'Latest local frame rendered';
    return SettingsWide(
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          settingsGroup('Connection', [
            settingsRow(
              connectionIcon(c.displayConnection),
              c.displayConnection.label,
              c.hardware.enabled
                  ? 'Adapter: W2 over Wi-Fi'
                  : 'Adapter: local 32 × 16 simulator',
              null,
            ),
            settingsRow(Icons.update, 'Output status', output, null),
            settingsRow(
              Icons.verified_outlined,
              'Physical delivery',
              c.hardware.enabled
                  ? c.hardware.acceptedLabel
                  : 'Available after connecting a supported W2 display',
              null,
            ),
          ]),
          const Text(
            'Connection and delivery are separate. “Controller accepted” means the final upload was acknowledged; check the sign to confirm its appearance.',
          ),
          const SizedBox(height: 16),
          ordinarySize(
            context,
            button(
              'Connect a display',
              Icons.wifi,
              c.busy ? null : chooseDisplay,
              primary: true,
            ),
          ),
          const SizedBox(height: 12),
          if (!c.hardware.enabled)
            ordinarySize(
              context,
              button(
                s.disconnected ? 'Reconnect simulator' : 'Disconnect simulator',
                s.disconnected ? Icons.link : Icons.link_off,
                c.busy || c.corrupt
                    ? null
                    : () => c.act(s.disconnected ? 'connect' : 'disconnect'),
              ),
            ),
          if (c.hardware.enabled && c.hardware.connected)
            ordinarySize(
              context,
              button(
                'Disconnect display',
                Icons.link_off,
                c.hardware.sending ? null : () => c.hardware.disconnect(),
              ),
            ),
          if (s.held || (c.hardware.enabled && c.hardware.held))
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Return to Live to review and restore held output.'),
            ),
        ],
      ),
      side: (context) => displayNowPane(),
    );
  }

  List<ReadinessCheck> readinessChecks() {
    final s = c.state.session;
    final timeline = s.timeline;
    final connection = c.displayConnection;
    final displayOk =
        connection != DisplayConnection.disconnected &&
        connection != DisplayConnection.stageDisconnected;
    final warningsOn = c.notificationState['enabled'] == true;
    final rules = c.state.defaults.warnings;
    final enabledRules = rules.where((w) => w.enabled).length;
    final battery = c.batteryUnrestricted;
    return <ReadinessCheck>[
      ReadinessCheck(
        key: 'program',
        title: 'Program loaded',
        detail: timeline == null
            ? 'Choose a program from Live or Programs'
            : '${timeline.name} · ${templateSummary(timeline)}',
        ok: timeline != null,
      ),
      ReadinessCheck(
        key: 'display',
        title: 'Display',
        detail:
            '${connection.label}${(c.hardware.enabled ? c.hardware.held : s.held) ? ' · output held' : ''}',
        ok: displayOk,
        fix: displayOk ? null : 'Connect',
        onFix: () => openDisplaySection('connection'),
      ),
      ReadinessCheck(
        key: 'warnings',
        title: c.port.isDesktop
            ? 'Warnings on this computer'
            : 'Phone warnings',
        detail: c.port.isDesktop
            ? (c.notificationState['sound'] == true
                  ? 'Windows notifications on · with sound'
                  : 'Windows notifications on · no sound')
            : warningsOn
            ? (c.notificationState['sound'] == true
                  ? 'Notifications and sound on'
                  : 'Notifications on · channel sound off')
            : 'Notifications are off',
        ok: warningsOn,
        fix: warningsOn ? null : 'Turn on',
        onFix: c.enablePhoneWarnings,
      ),
      if (battery != null)
        ReadinessCheck(
          key: 'battery',
          title: 'Battery',
          detail: battery
              ? 'Unrestricted · warnings keep running with the screen off'
              : 'Optimised · Android may pause warnings with the screen off',
          ok: battery,
          fix: battery ? null : 'Allow',
          onFix: c.port.openBatterySettings,
        ),
      ReadinessCheck(
        key: 'rules',
        title: 'Warning rules',
        detail:
            '$enabledRules of ${rules.length} enabled · shared across services',
        ok: enabledRules > 0,
        fix: enabledRules > 0 ? null : 'Review',
        onFix: () => openSettingsDetail('Warnings & alerts', warningsSettings),
      ),
    ];
  }

  Widget readinessSettings() {
    final colors = appColors(context);
    final timeline = c.state.session.timeline;
    final checks = readinessChecks();
    final issues = checks.where((x) => !x.ok).length;
    final name = timeline?.name ?? 'The service';
    final tone = issues == 0 ? colors.accent : colors.warning;
    Future<void> run(Future<void> Function() fix) async {
      try {
        await fix();
      } catch (e) {
        if (mounted) await showError('$e');
      }
    }

    return SettingsWide(
      side: (context) => readinessProgramPane(),
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('readiness-verdict'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: tone.withValues(alpha: .4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                  child: issues == 0
                      ? Icon(Icons.check, color: colors.surface, size: 24)
                      : Text(
                          '$issues',
                          style: TextStyle(
                            color: colors.surface,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issues == 0
                            ? 'All set'
                            : '${plural(issues, 'thing')} to check',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeline == null
                            ? 'Load a program, then check again.'
                            : issues == 0
                            ? '$name is ready to start.'
                            : '$name is ready to start. Fix ${issues == 1 ? 'this' : 'these'} for a smoother service.',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < checks.length; i++) ...[
                  if (i > 0) const AppDivider(),
                  readinessRow(checks[i], run),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: previewTestCue,
                  child: const Text('Preview test cue'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () => run(c.port.testNotification),
                  child: Text(
                    c.port.isDesktop
                        ? 'Test notification'
                        : 'Test warning sound',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tests never change the timer or the sign. Sound also depends on phone volume and Do Not Disturb. To check the sign itself, run a short rehearsal.',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
        ],
      ),
    );
  }

  /// Beside Ready for service in a wide window: the program that is
  /// loaded, so the operator can see it is the right one before starting.
  Widget readinessProgramPane() {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final timeline = c.state.session.timeline;
    if (timeline == null) {
      return const SidePane(
        title: 'Program to run',
        note:
            'No program is loaded yet. Choose one from Live or Programs and its segments are listed here.',
        children: [],
      );
    }
    return SidePane(
      title: 'Program to run',
      note: 'Check this is the right program before you start.',
      children: [
        Text(
          timeline.name,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          templateSummary(timeline),
          style: text.bodyMedium?.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 14),
        for (final (i, segment) in timeline.segments.indexed) ...[
          const AppDivider(indent: 0, endIndent: 0),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    style: text.bodyMedium?.copyWith(color: colors.muted),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        segment.name,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (segment.speaker.isNotEmpty)
                        Text(
                          segment.speaker,
                          style: text.bodySmall?.copyWith(color: colors.muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  segment.durationText,
                  style: text.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget readinessRow(
    ReadinessCheck check,
    Future<void> Function(Future<void> Function()) run,
  ) {
    final colors = appColors(context);
    final tone = check.ok ? colors.accent : colors.warning;
    final fix = check.fix;
    return ListTile(
      key: ValueKey('ready-${check.key}'),
      contentPadding: appLayout(context).tileInsets,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .16),
          shape: BoxShape.circle,
        ),
        child: Icon(
          check.ok ? Icons.check : Icons.priority_high,
          size: 16,
          color: tone,
        ),
      ),
      title: Text(
        check.title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        check.detail,
        style: TextStyle(fontSize: 12, color: colors.muted),
      ),
      trailing: fix == null
          ? null
          : fixButton(context, fix, c.busy ? null : () => run(check.onFix!)),
      onTap: fix == null || c.busy ? null : () => run(check.onFix!),
    );
  }

  void previewTestCue() => showDialog<void>(
    context: context,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
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
  );
}

/// One part of Display settings.
class DisplaySection {
  final String key, group, title;
  final IconData icon;

  /// The current state, in words.
  final String summary;
  final Widget Function() content;
  const DisplaySection(
    this.key,
    this.group,
    this.icon,
    this.title,
    this.summary,
    this.content,
  );
}

/// Display settings in a wide window: the sections down the left, each
/// with its current state, and the chosen section beside them.
class DisplaySettingsDesk extends StatefulWidget {
  final HomeState home;
  final String initial;
  const DisplaySettingsDesk({
    super.key,
    required this.home,
    this.initial = 'connection',
  });
  @override
  State<DisplaySettingsDesk> createState() => _DisplaySettingsDeskState();
}

class _DisplaySettingsDeskState extends State<DisplaySettingsDesk> {
  late String chosen = widget.initial;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final sections = widget.home.displaySections();
    final section = sections.firstWhere(
      (s) => s.key == chosen,
      orElse: () => sections.first,
    );
    Widget entry(DisplaySection s) {
      final on = s.key == section.key;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: on ? colors.accent.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('display-section-${s.key}'),
            onTap: () => setState(() => chosen = s.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    s.icon,
                    size: 22,
                    color: on ? colors.accent : colors.muted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final groups = <String>[];
    for (final s in sections) {
      if (!groups.contains(s.group)) groups.add(s.group);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).width * .24).clamp(300.0, 400.0),
          child: ColoredBox(
            color: colors.surface,
            child: ListView(
              key: const ValueKey('display-sections'),
              primary: false,
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
              children: [
                for (final group in groups) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      group == groups.first ? 0 : 20,
                      12,
                      10,
                    ),
                    child: PaneLabel(group),
                  ),
                  for (final s in sections)
                    if (s.group == group) entry(s),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                  child: Text(
                    RefinedSettings.displaySettingsNote,
                    style: text.bodySmall?.copyWith(
                      color: colors.muted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.border),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey('display-detail-${section.key}'),
            primary: false,
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 32),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      section.title,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.summary,
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                    const SizedBox(height: 20),
                    section.key == 'clock'
                        ? widget.home.clockFormatSettings(titled: false)
                        : section.content(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReadinessCheck {
  final String key;
  final String title;
  final String detail;
  final bool ok;
  final String? fix;
  final Future<void> Function()? onFix;
  const ReadinessCheck({
    required this.key,
    required this.title,
    required this.detail,
    required this.ok,
    this.fix,
    this.onFix,
  });
}
