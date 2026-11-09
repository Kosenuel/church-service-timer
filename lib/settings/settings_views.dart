import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/live/practice_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/feedback/feedback_page.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/backup_secret_views.dart';
import 'package:church_service_timer/settings/whats_new_page.dart';
import 'package:church_service_timer/settings/diagnostics_views.dart';
export 'package:church_service_timer/settings/church_profile_page.dart';

extension SettingsViews on HomeState {
  Future<void> openSettingsDetail(
    String title,
    Widget Function() content, {
    bool showLiveShortcut = false,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: c.liveSession.active
              ? RunningServiceBar.forContext(context, controller: c)
              : null,
          actions: showLiveShortcut
              ? [
                  TextButton.icon(
                    onPressed: () {
                      navigatePage(0);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.sensors, size: 20),
                    label: const Text('Go to Live'),
                  ),
                  const SizedBox(width: 8),
                ]
              : null,
        ),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([c, settingsRefresh]),
            builder: (context, _) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget settingsHub() {
    Widget entry(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback action,
    ) => ListTile(
      contentPadding: appLayout(context).tileInsets,
      leading: Icon(icon, color: appColors(context).accent, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: appColors(context).muted),
      ),
      trailing: const Icon(Icons.chevron_right, size: 22),
      onTap: c.busy ? null : action,
    );
    Widget group(String name, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(name),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Your church, your workspace, your display.',
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('settings-search'),
          initialValue: settingsQuery,
          decoration: const InputDecoration(
            labelText: 'Search settings',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => refreshHome(() => settingsQuery = v),
        ),
        const SizedBox(height: 16),
        if (settingsQuery.trim().isNotEmpty)
          settingsSearchResults()
        else ...[
          group('Personalization', [
            entry(
              Icons.church_outlined,
              'Church profile',
              c.state.churchName.isEmpty
                  ? 'Church name and banner'
                  : c.state.churchName,
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChurchProfilePage(controller: c),
                ),
              ),
            ),
            entry(
              Icons.palette_outlined,
              'Appearance',
              paletteFor(c.state.themeId).name,
              () async {
                try {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppearancePage(controller: c),
                    ),
                  );
                } finally {
                  if (mounted) {
                    c.previewTheme(null);
                    c.previewAppearance(null);
                  }
                }
              },
            ),
          ]),
          group('Service & display', [
            entry(
              Icons.notifications_active_outlined,
              'Warnings & alerts',
              'Shared thresholds, phone notifications and sound',
              () => openSettingsDetail('Warnings & alerts', warningsSettings),
            ),
            entry(
              Icons.display_settings_outlined,
              'Display settings',
              'Connection, profile, end screens, fonts and LEDs',
              () => openSettingsDetail('Display settings', displaySettings),
            ),
            Padding(
              padding: appLayout(context).tileInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Keep screen awake',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      'Prevent sleep while the app is visible.',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: c.state.keepScreenAwake,
                    onChanged: c.busy
                        ? null
                        : (value) => c.commit(
                            (draft, _) => draft.keepScreenAwake = value,
                          ),
                  ),
                  if (c.deviceSettingsError != null) ...[
                    Text(
                      c.deviceSettingsError!,
                      style: TextStyle(color: appColors(context).warning),
                    ),
                    TextButton(
                      onPressed: () async {
                        await c.syncDeviceSettings();
                        settingsRefresh.value++;
                      },
                      child: const Text('Retry screen setting'),
                    ),
                  ],
                ],
              ),
            ),
          ]),
          group('Service tools', [
            entry(
              Icons.message_outlined,
              'Quick message presets',
              'Saved messages for phone or tablet stage screens',
              () => openSettingsDetail(
                'Quick message presets',
                quickPresetSettings,
              ),
            ),
            entry(
              Icons.chat_bubble_outline,
              'Stage cues',
              'Create, format and reorder your Live buttons',
              () => openSettingsDetail('Stage cues', stageCueSettings),
            ),
            entry(
              Icons.devices,
              'Screens & devices',
              'Stage screens, viewers and second operators',
              () => openSettingsDetail(
                'Screens & devices',
                pairedDeviceSettings,
                showLiveShortcut: true,
              ),
            ),
            entry(
              Icons.router_outlined,
              'LED device management',
              'LED sign Wi-Fi and connection credentials',
              () =>
                  openSettingsDetail('LED device management', deviceManagement),
            ),
          ]),
          group('Data & app', [
            entry(
              Icons.backup_outlined,
              'Backup & restore',
              'Programs, stage cues, reports and preferences',
              () => openSettingsDetail('Backup & restore', backupSettings),
            ),
            entry(
              Icons.feedback_outlined,
              'Feedback Center',
              'Share a complaint or suggestion by email',
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FeedbackCenterPage(controller: c),
                ),
              ),
            ),
            entry(
              Icons.lock_outline,
              'Settings PIN',
              c.state.settingsLock == null
                  ? 'Off · anyone can change settings or delete'
                  : 'On · locks Settings, deleting and sign administration',
              () => openSettingsDetail('Settings PIN', settingsPinSettings),
            ),
            entry(
              Icons.info_outline,
              'About',
              '$appName · ${c.appVersion}',
              () => openSettingsDetail('About', aboutSettings),
            ),
          ]),
        ],
      ],
    );
  }

  Widget backupSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.backup_outlined, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Keep your setup safe.',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Save your programs, cue formatting, display defaults, service reports, church profile and appearance in one JSON file. You choose where it is stored.',
            ),
            const SizedBox(height: 12),
            Text(
              'Backups exclude the current running service and phone permissions. Saved sign passwords are included only if you choose, encrypted with a passphrase. Private operator notes are included in programs.',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: c.busy ? null : exportSavedSetup,
              icon: const Icon(Icons.save_alt),
              label: const Text('Export backup'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restore a saved setup',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Restore replaces the saved data on this phone. Export a backup first if you want to keep the current setup. You will review the file before confirming.',
            ),
            const SizedBox(height: 16),
            if (c.state.session.active || c.state.session.phase == 'ready')
              Text(
                'End or cancel the loaded service before restoring.',
                style: TextStyle(color: appColors(context).warning),
              ),
            OutlinedButton.icon(
              onPressed:
                  c.busy ||
                      c.state.session.active ||
                      c.state.session.phase == 'ready'
                  ? null
                  : restoreSavedSetup,
              icon: const Icon(Icons.restore),
              label: const Text('Choose backup to restore'),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> exportSavedSetup() async {
    try {
      final secrets = await c.backupSecrets();
      if (!mounted) return;
      final choice = await showDialog<BackupExportChoice>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) =>
            BackupExportDialog(hasPasswords: c.hasBackupSecrets(secrets)),
      );
      if (choice == null || !mounted) return;
      final sealed = choice.includePasswords
          ? await sealBackupSecrets(secrets, choice.passphrase)
          : null;
      await c.port.exportFile(
        'Church-Service-Timer-backup-${c.now.wall}.json',
        exportBackup(c.state, c.now, savedPasswords: sealed),
      );
    } catch (e) {
      if (mounted) await showError('Backup could not be exported: $e');
    }
  }

  /// After a restore, offers to unseal and restore the backup's passwords.
  Future<void> restoreSavedPasswords(Map<String, dynamic> sealed) async {
    String? error;
    while (true) {
      if (!mounted) return;
      final passphrase = await showDialog<String>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) => BackupPassphraseDialog(error: error),
      );
      if (passphrase == null || !mounted) return;
      final secrets = await openBackupSecrets(sealed, passphrase);
      if (secrets == null) {
        error = 'That passphrase is not correct.';
        continue;
      }
      final count = await c.restoreBackupSecrets(secrets);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Restored ${plural(count, 'saved password')}. Connect to the sign to use them.',
            ),
          ),
        );
      return;
    }
  }

  Future<void> restoreSavedSetup() async {
    try {
      final file = await c.port.pickBackup();
      if (file == null || !mounted) return;
      final restored = importBackup(file['content'] as String, c.now);
      await NativeDisplayFonts.prepareState(restored);
      final okay = await confirm(
        'Replace this phone’s saved setup?',
        '${file['name']}\n\n${restored.templates.length} programs · ${restored.stageCues.length} stage cues · ${restored.reports.length} reports\nChurch: ${restored.churchName.isEmpty ? 'Not set' : restored.churchName}\nTheme: ${paletteFor(restored.themeId).name}\n\nThis replaces your current saved programs, cues, reports and preferences. The timer returns to idle. This cannot be undone without another backup.',
        'Restore and replace',
        destructive: true,
      );
      if (!okay || !mounted) return;
      final saved = await c.restoreBackup(restored);
      if (!mounted) return;
      if (!saved) {
        await showError(c.error ?? 'Could not restore this backup.');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup restored. Ready for a new service.'),
        ),
      );
      final sealed = backupSavedPasswords(file['content'] as String);
      if (sealed != null) await restoreSavedPasswords(sealed);
    } catch (e) {
      if (mounted) await showError('Backup not restored: $e');
    }
  }

  Widget aboutSettings() {
    final colors = appColors(context);
    Widget detail(String title, String body, {Widget? action}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(body, style: const TextStyle(fontSize: 15, height: 1.45)),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    );
    Widget row(
      IconData icon,
      String title,
      String summary,
      VoidCallback onTap, {
      Key? key,
    }) => ListTile(
      key: key,
      contentPadding: appLayout(context).tileInsets,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: colors.accent),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        summary,
        style: TextStyle(fontSize: 13, color: colors.muted),
      ),
      trailing: const Icon(Icons.chevron_right, size: 22),
      onTap: onTap,
    );
    final rows = [
      row(
        Icons.auto_awesome_outlined,
        'What’s new',
        'Release notes for ${c.appVersion.split(' ').first} and earlier',
        () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WhatsNewPage())),
        key: const ValueKey('about-whats-new'),
      ),
      row(
        Icons.storage_outlined,
        'Your data',
        'Stored only on this phone · backups you choose',
        () => openSettingsDetail(
          'Your data',
          () => detail(
            'Your data',
            'Saved services, reports and preferences stay on this device. There is no in-app account or cloud sync. Exported files go to the location you choose; keep backups somewhere you trust. Sign passwords and pairings are encrypted on this phone. Pairings are never included in backups; saved sign passwords are included only if you choose, encrypted with a passphrase.',
          ),
        ),
      ),
      row(
        Icons.developer_board_outlined,
        'Display and hardware',
        'Simulator, W2 sign limits and recovery',
        () => openSettingsDetail(
          'Display and hardware',
          () => detail(
            'Display and hardware',
            '32 × 16 simulator and W2 Wi-Fi output: native countdown, pause/resume, time adjustments and automatic warnings with scrolling. Hardware updates may blink briefly. The active-service notification supports locked-screen operation; after connection loss or process termination, reconnect and review the output.',
          ),
        ),
      ),
      row(
        Icons.text_fields,
        'Fonts and licences',
        'I-Proton Matrix, Sq-Matrix and Tinos (SIL OFL 1.1)',
        () => openSettingsDetail(
          'Fonts and licences',
          () => detail(
            'Fonts and licences',
            'I-Proton Matrix and I-Proton Sq-Matrix preserve the original Matrix glyphs. Tinos includes four bundled faces under SIL Open Font License 1.1.',
            action: OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: c.appVersion,
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Open-source licenses'),
            ),
          ),
        ),
      ),
      row(
        Icons.feedback_outlined,
        'Send feedback',
        'Opens an email draft to the developer',
        () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FeedbackCenterPage(controller: c)),
        ),
      ),
      row(
        Icons.school_outlined,
        'Guided practice',
        c.state.practisedWall == null
            ? 'Learn the controls in a few minutes, on the Simulator'
            : 'Practised on ${shortDate(c.state.practisedWall!)} · practise again',
        startPractice,
        key: const ValueKey('about-practice'),
      ),
      row(
        Icons.monitor_heart_outlined,
        'Diagnostics',
        c.state.recordMetrics || c.metrics.recording
            ? 'Recording service metrics'
            : 'Record performance during a service, for troubleshooting',
        openDiagnostics,
        key: const ValueKey('about-diagnostics'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(
          child: Row(
            children: [
              ChurchTimerMark(size: 64, logo: c.state.churchLogo),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      appName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Version ${c.appVersion}',
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          'Created by I-Proton',
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                    if (c.state.churchName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          c.state.churchName,
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'A calm workspace for timing services, cueing the stage, warning the operator and learning from every report.',
          style: TextStyle(fontSize: 15, height: 1.45),
        ),
        const SizedBox(height: 16),
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
      ],
    );
  }
}

class AppearancePage extends StatefulWidget {
  final AppController controller;
  const AppearancePage({super.key, required this.controller});
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late String selected = widget.controller.state.themeId;
  late AppearancePreferences appearance = widget.controller.state.appearance;
  bool saving = false;
  String? error;
  List<AppPalette> get choices => [
    ...appPalettes,
    if (selected.startsWith('custom:')) paletteFor(selected),
  ];
  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    final saved = await widget.controller.commit((draft, _) {
      draft.themeId = selected;
      draft.appearance = appearance;
    });
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.controller.error ?? 'Could not save. Try again.';
      });
    }
  }

  Future<void> createCustom() async {
    final value = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => CustomThemeEditor(initial: selected),
    );
    if (value != null && mounted) {
      setState(() => selected = value);
      widget.controller.previewTheme(value);
    }
  }

  Widget themeTile(AppPalette p) {
    final colors = appColors(context);
    final on = selected == p.id;
    return Material(
      key: ValueKey('theme-${p.id}'),
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: on ? colors.accent : colors.border,
          width: on ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: saving
            ? null
            : () {
                setState(() => selected = p.id);
                widget.controller.previewTheme(p.id);
              },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 34,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: ColoredBox(color: p.background)),
                      Expanded(flex: 2, child: ColoredBox(color: p.surface)),
                      Expanded(child: ColoredBox(color: p.accent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (on)
                    Icon(Icons.check_circle, size: 18, color: colors.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final palette = paletteFor(selected);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Appearance'),
          bottom: widget.controller.liveSession.active
              ? RunningServiceBar.forContext(
                  context,
                  controller: widget.controller,
                )
              : null,
        ),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The pinned preview follows the tab: colours on Theme,
                  // spacing and dividers on Layout & accessibility.
                  Builder(
                    builder: (context) {
                      final tabs = DefaultTabController.of(context);
                      return AnimatedBuilder(
                        animation: tabs,
                        builder: (context, _) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: AnimatedSwitcher(
                            duration: reduceAppMotion(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            child: tabs.index == 0
                                ? ThemePreviewCard(
                                    key: const ValueKey('preview-theme'),
                                    name: palette.name,
                                  )
                                : const AppearanceSample(
                                    key: ValueKey('preview-layout'),
                                    compact: true,
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                  TabBar(
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    indicatorColor: colors.accent,
                    labelColor: colors.text,
                    unselectedLabelColor: colors.muted,
                    tabs: const [
                      Tab(text: 'Theme'),
                      Tab(text: 'Layout & accessibility'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            LayoutBuilder(
                              builder: (context, space) {
                                final columns = space.maxWidth >= 520 ? 3 : 2;
                                final width =
                                    (space.maxWidth - 10 * (columns - 1)) /
                                    columns;
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final p in choices)
                                      SizedBox(
                                        width: width,
                                        child: themeTile(p),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Create custom theme'),
                              onPressed: saving ? null : createCustom,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              palette.description,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: AppearanceControls(
                            value: appearance,
                            onChanged: saving
                                ? null
                                : (value) {
                                    setState(() => appearance = value);
                                    widget.controller.previewAppearance(value);
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: saving ? null : save,
                          child: const Text('Save appearance'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomThemeEditor extends StatefulWidget {
  final String initial;
  const CustomThemeEditor({super.key, required this.initial});
  @override
  State<CustomThemeEditor> createState() => _CustomThemeEditorState();
}

class _CustomThemeEditorState extends State<CustomThemeEditor> {
  late final AppPalette base = paletteFor(widget.initial);
  late final fields = [
    base.accent,
    base.background,
    base.surface,
  ].map((c) => TextEditingController(text: hex(c))).toList();
  static String hex(Color c) => c.toARGB32().toRadixString(16).substring(2);
  String get id =>
      'custom:${fields.map((f) => f.text.toLowerCase().replaceAll('#', '')).join(':')}';
  String? validation() {
    try {
      themeIdValue(id);
    } on RuleError catch (e) {
      return e.toString();
    }
    final p = paletteFor(id);
    if (contrast(p.text, p.surface) < 4.5 ||
        contrast(p.text, p.background) < 4.5)
      return 'Choose a background and panel with similar brightness so text stays readable.';
    return null;
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = validation();
    final p = error == null ? paletteFor(id) : base;
    return AlertDialog(
      title: const Text('Create custom theme'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose colors or enter hex values. Text and accent contrast are adjusted for readability.',
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < fields.length; i++) ...[
                TextField(
                  controller: fields[i],
                  maxLength: 7,
                  decoration: InputDecoration(
                    labelText: ['Accent', 'Background', 'Panels'][i],
                    prefixText: '# ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Wrap(
                  spacing: 8,
                  children:
                      (i == 0
                              ? [
                                  0xff165aab,
                                  0xff345d48,
                                  0xff9a47d3,
                                  0xff9e4059,
                                  0xffc9f96c,
                                  0xffd89928,
                                ]
                              : [
                                  0xffedf5fc,
                                  0xfff9fcff,
                                  0xfff3f2e9,
                                  0xffe5eee5,
                                  0xff0a1210,
                                  0xff131d1a,
                                  0xff0b1426,
                                  0xff15233b,
                                ])
                          .map(
                            (value) => IconButton(
                              tooltip: 'Use #${hex(Color(value))}',
                              onPressed: () => setState(
                                () => fields[i].text = hex(Color(value)),
                              ),
                              icon: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(value),
                                  border: Border.all(
                                    color: appColors(context).muted,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox(width: 24, height: 24),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 12),
              ],
              Theme(
                data: appTheme(error == null ? id : widget.initial),
                child: Container(
                  color: p.background,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const ChurchTimerMark(size: 56),
                      const SizedBox(height: 12),
                      Text(
                        'Sunday Service',
                        style: TextStyle(
                          color: p.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        color: p.surface,
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '08:59 remaining',
                          style: TextStyle(color: p.accent, fontSize: 24),
                        ),
                      ),
                      Text(
                        'Warning · Overtime',
                        style: TextStyle(color: p.error),
                      ),
                    ],
                  ),
                ),
              ),
              if (error != null)
                Text(error, style: TextStyle(color: appColors(context).error)),
            ],
          ),
        ),
      ),
      actions: [
        StackedDialogActions(
          children: [
            FilledButton(
              onPressed: error == null
                  ? () => Navigator.pop(context, id)
                  : null,
              child: const Text('Use theme'),
            ),
            OutlinedButton(
              onPressed: () => setState(() {
                final colors = [base.accent, base.background, base.surface];
                for (var i = 0; i < 3; i++) {
                  fields[i].text = hex(colors[i]);
                }
              }),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
