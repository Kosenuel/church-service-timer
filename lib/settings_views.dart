part of 'main.dart';

extension SettingsViews on _HomeState {
  Future<void> openSettingsDetail(String title, Widget Function() content) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(title)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
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
                if (mounted) c.previewTheme(null);
              }
            },
          ),
        ]),
        group('Service & display', [
          entry(
            Icons.display_settings_outlined,
            'Display settings',
            'End screens, At Zero, warnings, fonts and LEDs',
            () => openSettingsDetail('Display settings', displaySettings),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Keep screen awake',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
        group('Data & app', [
          entry(
            Icons.backup_outlined,
            'Backup & restore',
            'Templates, stage cues, reports and preferences',
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
            Icons.info_outline,
            'About',
            '$appName · ${c.appVersion}',
            () => openSettingsDetail('About', aboutSettings),
          ),
        ]),
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
              'Save your templates, cue formatting, display defaults, service reports, church profile and appearance in one JSON file. You choose where it is stored.',
            ),
            const SizedBox(height: 12),
            Text(
              'Backups exclude the current running service, phone permissions and imported font files. Reimport Times New Roman in Display settings on a new phone before restoring a backup that uses it.',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: c.busy
                  ? null
                  : () async {
                      try {
                        await c.port.exportFile(
                          'Church-Service-Timer-backup-${c.now.wall}.json',
                          exportBackup(c.state, c.now),
                        );
                      } catch (e) {
                        if (mounted)
                          await showError('Backup could not be exported: $e');
                      }
                    },
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

  Future<void> restoreSavedSetup() async {
    try {
      final file = await c.port.pickBackup();
      if (file == null || !mounted) return;
      final restored = importBackup(file['content'] as String, c.now);
      await NativeDisplayFonts.prepareState(restored);
      final okay = await confirm(
        'Replace this phone’s saved setup?',
        '${file['name']}\n\n${restored.templates.length} templates · ${restored.stageCues.length} stage cues · ${restored.reports.length} reports\nChurch: ${restored.churchName.isEmpty ? 'Not set' : restored.churchName}\nTheme: ${paletteFor(restored.themeId).name}\n\nThis replaces your current saved templates, cues, reports and preferences. The timer returns to idle. This cannot be undone without another backup.',
        'Restore and replace',
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
    } catch (e) {
      if (mounted) await showError('Backup not restored: $e');
    }
  }

  Widget aboutSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel(
        child: Column(
          children: [
            const ChurchTimerMark(size: 80),
            const SizedBox(height: 16),
            const Text(
              appName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Version ${c.appVersion}'),
            if (c.state.churchName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.state.churchName, textAlign: TextAlign.center),
              ),
            const SizedBox(height: 20),
            const Text(
              'Created by I-Proton',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'A calm workspace for church service timing, stage cues, automatic warnings, rehearsals and after-service reports.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Prototype · simulator'),
            const SizedBox(height: 10),
            const Text(
              '32 × 16 monochrome display simulator. Physical LED sign delivery is not yet implemented or tested. Simulator status is never a hardware connection confirmation.',
            ),
            const SizedBox(height: 16),
            label('Your data'),
            const SizedBox(height: 10),
            const Text(
              'Saved services, reports and preferences stay on this device. There is no in-app account or cloud sync. Exported files go to the location you choose; keep backups somewhere you trust.',
            ),
            const SizedBox(height: 16),
            label('Display fonts'),
            const SizedBox(height: 10),
            const Text(
              'Service Matrix and Service Sq-Matrix preserve the original Matrix glyphs. Times New Roman uses a font file you import on your device.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: c.appVersion,
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Font and software licenses'),
            ),
          ],
        ),
      ),
    ],
  );
}

class ChurchProfilePage extends StatefulWidget {
  final AppController controller;
  const ChurchProfilePage({super.key, required this.controller});
  @override
  State<ChurchProfilePage> createState() => _ChurchProfilePageState();
}

class _ChurchProfilePageState extends State<ChurchProfilePage> {
  late final TextEditingController name = TextEditingController(
    text: widget.controller.state.churchName,
  );
  late String banner = widget.controller.state.churchBanner;
  String? imageError;
  bool picking = false;
  Future<void> pickBanner() async {
    setState(() {
      picking = true;
      imageError = null;
    });
    try {
      final value = await widget.controller.port.pickChurchBanner();
      if (value != null) {
        await validateBannerPixels(value);
        if (mounted) setState(() => banner = value);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => imageError =
              'Could not use this image. Choose a JPEG, PNG or WebP up to 5 MB and 40 megapixels.',
        );
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  String? error;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Church profile')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  label: 'Choose church banner',
                  child: InkWell(
                    key: const ValueKey('choose-church-banner'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: saving || picking ? null : pickBanner,
                    child: ChurchProfileBanner(image: banner),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Recommended: 1200 × 400 px (3:1). JPEG, PNG or WebP, maximum 5 MB and 40 megapixels. Images are cropped from the centre without stretching. Keep important details near the centre.',
                  style: TextStyle(
                    color: appColors(context).muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  banner.isEmpty
                      ? 'Built-in banner'
                      : 'Your banner preview · save below to keep it',
                  style: TextStyle(
                    color: appColors(context).muted,
                    fontSize: 12,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: saving || picking ? null : pickBanner,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        picking ? 'Preparing image…' : 'Choose banner',
                      ),
                    ),
                    if (banner.isNotEmpty)
                      TextButton(
                        onPressed: saving || picking
                            ? null
                            : () => setState(() {
                                banner = '';
                                imageError = null;
                              }),
                        child: const Text('Use built-in banner'),
                      ),
                  ],
                ),
                if (imageError != null)
                  Text(
                    imageError!,
                    style: TextStyle(color: appColors(context).warning),
                  ),
                const SizedBox(height: 24),
                TextField(
                  controller: name,
                  enabled: !saving && !picking,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Church name (optional)',
                    hintText: 'e.g. Grace Community Church',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Shown in the app header, opening screen and new service reports. Loaded services keep the church name they started with. Older reports keep their original name.',
                  style: TextStyle(color: appColors(context).muted),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving || picking
                      ? null
                      : () async {
                          String value;
                          try {
                            value = churchNameValue(name.text);
                          } catch (e) {
                            setState(() => error = '$e');
                            return;
                          }
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          final saved = await widget.controller.commit((
                            draft,
                            _,
                          ) {
                            draft.churchName = value;
                            draft.churchBanner = banner;
                          });
                          if (!mounted) return;
                          if (saved) {
                            Navigator.pop(context);
                          } else {
                            setState(() {
                              saving = false;
                              error =
                                  widget.controller.error ??
                                  'Could not save. Try again.';
                            });
                          }
                        },
                  child: const Text('Save church profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AppearancePage extends StatefulWidget {
  final AppController controller;
  const AppearancePage({super.key, required this.controller});
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late String selected = widget.controller.state.themeId;
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appearance')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose your atmosphere.',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap a theme to preview it. Save to keep it, or go back to discard. Warning and overdue cues retain their meaning; LED colors are unchanged.',
                  style: TextStyle(color: appColors(context).muted),
                ),
                const SizedBox(height: 20),
                ...appPalettes.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: p.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: selected == p.id ? p.accent : p.border,
                          width: selected == p.id ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: ValueKey('theme-${p.id}'),
                        selected: selected == p.id,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: p.accent,
                          child: Icon(
                            Icons.palette_outlined,
                            color: p.light ? Colors.white : p.background,
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            color: p.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          p.description,
                          style: TextStyle(color: p.muted),
                        ),
                        trailing: Icon(
                          selected == p.id
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: p.accent,
                        ),
                        onTap: saving
                            ? null
                            : () {
                                setState(() => selected = p.id);
                                widget.controller.previewTheme(p.id);
                              },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: appColors(context).error),
                  ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          final saved = await widget.controller.commit(
                            (draft, _) => draft.themeId = selected,
                          );
                          if (!mounted) return;
                          if (saved) {
                            Navigator.pop(context);
                          } else {
                            setState(() {
                              saving = false;
                              error =
                                  widget.controller.error ??
                                  'Could not save. Try again.';
                            });
                          }
                        },
                  child: const Text('Save appearance'),
                ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
