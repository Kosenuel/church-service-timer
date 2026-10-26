part of 'main.dart';

class ProgramChooser extends StatefulWidget {
  final AppController controller;
  final VoidCallback onCreate;
  const ProgramChooser({
    super.key,
    required this.controller,
    required this.onCreate,
  });
  @override
  State<ProgramChooser> createState() => _ProgramChooserState();
}

class _ProgramChooserState extends State<ProgramChooser> {
  String query = '', filter = 'all';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final programs = c.state.programLibrary.find(
        c.state.templates,
        query,
        filter,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose a program to load into Ready. Timing begins only when you start the first segment.',
          ),
          SizedBox(height: appLayout(context).gap),
          TextField(
            key: const ValueKey('start-program-search'),
            decoration: const InputDecoration(
              labelText: 'Search programs',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          ProgramFilters(
            value: filter,
            onChanged: (v) => setState(() => filter = v),
          ),
          const SizedBox(height: 8),
          AppMenuList(
            key: const ValueKey('start-service-programs'),
            children: [
              for (final p in programs)
                ListTile(
                  key: ValueKey('start-program:${p.name}'),
                  title: Text(p.name),
                  subtitle: Text(templateSummary(p)),
                  leading: c.state.programLibrary.favourites.contains(p.name)
                      ? const Icon(Icons.star)
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.busy ? null : () => Navigator.pop(context, p),
                ),
            ],
          ),
          if (programs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No programs match. Try All or another search.'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create Program'),
          ),
        ],
      );
    },
  );
}

class ProgramFilters extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const ProgramFilters({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final e in {
        'all': 'All programs',
        'favourites': 'Favourites',
        'recent': 'Recent',
      }.entries)
        ChoiceChip(
          label: Text(e.value),
          selected: value == e.key,
          onSelected: (_) => onChanged(e.key),
        ),
    ],
  );
}

extension Update21Views on _HomeState {
  void toggleExportSelection(Set<String> selected, String id) {
    if (!selected.remove(id)) selected.add(id);
  }

  Widget exportSelectionBar({
    required bool programs,
    required Set<String> shown,
  }) {
    final selecting = programs ? selectingPrograms : selectingReports;
    final selected = programs ? selectedProgramExports : selectedReportExports;
    final available = programs
        ? c.state.templates.map((p) => p.name).toSet()
        : c.state.reports.map((r) => r.id).toSet();
    final chosen = selected.intersection(available);
    final hidden = chosen.difference(shown).length;
    void toggleMode() => refreshHome(() {
      if (programs)
        selectingPrograms = !selectingPrograms;
      else {
        selectingReports = !selectingReports;
        reportView = 'list';
      }
      selected.clear();
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: !selecting
          ? Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: ValueKey('select-${programs ? 'programs' : 'reports'}'),
                onPressed: available.isEmpty ? null : toggleMode,
                icon: const Icon(Icons.checklist),
                label: const Text('Select'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${chosen.length} selected${hidden == 0 ? '' : ' · $hidden hidden by filters'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: toggleMode,
                      child: const Text('Done'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: shown.isEmpty
                          ? null
                          : () => refreshHome(() => selected.addAll(shown)),
                      child: const Text('Select all shown'),
                    ),
                    TextButton(
                      onPressed: chosen.isEmpty
                          ? null
                          : () => refreshHome(selected.clear),
                      child: const Text('Clear selection'),
                    ),
                    UnavailableAction(
                      reason: chosen.isEmpty
                          ? 'Select at least one item to export.'
                          : null,
                      child: FilledButton.icon(
                        key: ValueKey(
                          'export-selected-${programs ? 'programs' : 'reports'}',
                        ),
                        onPressed: chosen.isEmpty || c.busy
                            ? null
                            : () async {
                                if (programs)
                                  await exportAllPrograms(
                                    selected: c.state.templates
                                        .where((p) => chosen.contains(p.name))
                                        .toList(),
                                  );
                                else
                                  await exportAllReports(
                                    selected: c.state.reports
                                        .where((r) => chosen.contains(r.id))
                                        .toList(),
                                  );
                              },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Export selected'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  String unavailableReason(String action) {
    if (controlsLocked) return 'Unlock operator controls first.';
    if (c.corrupt) return 'Resolve the saved-data issue before making changes.';
    if (c.busy) return 'Wait for the current change to finish saving.';
    if (c.reportSavePending) return 'Save the completed service report first.';
    if (!c.pairing.localControl)
      return 'Take back control from the paired operator first.';
    if (action == '+2 min')
      return 'Use Custom to stay within the 59:59 segment limit.';
    if (action == '−2 min') return 'There is no remaining time to remove.';
    if (action.contains('Undo'))
      return 'There is no segment change available to undo.';
    if (action.contains('Next') || action.contains('Jump'))
      return 'There are no later segments in this service.';
    if (action.contains('Export'))
      return 'Save at least one item before exporting.';
    if (action.contains('Show timer') || action.contains('Return to'))
      return 'The timer is already selected, or no active service is loaded.';
    if (c.state.session.phase == 'idle' || c.state.session.phase == 'ready')
      return 'Start the first segment to use this control.';
    if (!c.destinationConnected)
      return c.destination == 'mobile'
          ? 'Connect a stage screen first.'
          : 'Connect a display first.';
    return 'This action is unavailable in the current service state.';
  }

  Widget settingsSearchResults() {
    final entries = <(String, String, IconData, VoidCallback)>[
      (
        'Clock format',
        'clock time 12 hour 24 hour blinking colon',
        Icons.schedule,
        () => openSettingsDetail('Clock format', clockFormatSettings),
      ),
      (
        'LED device management',
        'password wifi network reconnect credentials router',
        Icons.router_outlined,
        () => openSettingsDetail('LED device management', deviceManagement),
      ),
      (
        'Display fonts',
        'font tinos matrix typography',
        Icons.text_fields,
        () => openSettingsDetail('Display fonts', displayFonts),
      ),
      (
        'Warnings & alerts',
        'warning notifications sound threshold alerts',
        Icons.notifications_outlined,
        () => openSettingsDetail('Warnings & alerts', warningsSettings),
      ),
      (
        'Appearance',
        'theme density compact comfortable spacious dividers contrast motion picker feedback sound haptics',
        Icons.palette_outlined,
        () async {
          try {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AppearancePage(controller: c)),
            );
          } finally {
            c.previewTheme(null);
            c.previewAppearance(null);
          }
        },
      ),
      (
        'Church profile',
        'church name image banner',
        Icons.church_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChurchProfilePage(controller: c)),
        ),
      ),
      (
        'Display settings',
        'display screen led connection simulator',
        Icons.display_settings_outlined,
        () => openSettingsDetail('Display settings', displaySettings),
      ),
      (
        'LED preview shape',
        'square circular pixels',
        Icons.apps,
        () => openSettingsDetail('LED preview shape', ledShapeSettings),
      ),
      (
        'At Zero',
        'zero overtime elapsed end countdown',
        Icons.timer_off_outlined,
        () => openSettingsDetail('At Zero', sharedZeroSettings),
      ),
      (
        'Default end screen',
        'end screen hallelujah',
        Icons.flag_outlined,
        () => openSettingsDetail('Default end screen', defaultEndSettings),
      ),
      (
        'Stage cues',
        'cue message format text',
        Icons.chat_bubble_outline,
        () => openSettingsDetail('Stage cues', stageCueSettings),
      ),
      (
        'Quick message presets',
        'quick announcement message presets',
        Icons.message_outlined,
        () => openSettingsDetail('Quick message presets', quickPresetSettings),
      ),
      (
        'Paired devices',
        'pair qr pin host share tablet mobile stage screen control',
        Icons.devices,
        () => openSettingsDetail(
          'Paired devices',
          pairedDeviceSettings,
          showLiveShortcut: true,
        ),
      ),
      (
        'Backup & restore',
        'backup restore export import data',
        Icons.backup_outlined,
        () => openSettingsDetail('Backup & restore', backupSettings),
      ),
      (
        'Keep screen awake',
        'sleep awake screen lock',
        Icons.wb_sunny_outlined,
        () => openSettingsDetail(
          'Keep screen awake',
          () => SwitchListTile(
            title: const Text('Keep screen awake'),
            value: c.state.keepScreenAwake,
            onChanged: c.busy
                ? null
                : (v) => c.commit((d, _) => d.keepScreenAwake = v),
          ),
        ),
      ),
      (
        'Feedback Center',
        'feedback complaint contact email',
        Icons.feedback_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FeedbackCenterPage(controller: c)),
        ),
      ),
      (
        'About',
        'version author i proton software licence license',
        Icons.info_outline,
        () => openSettingsDetail('About', aboutSettings),
      ),
    ];
    final words = settingsQuery.toLowerCase().trim().split(RegExp(r'\s+'));
    final found = entries
        .where((e) => words.every('${e.$1} ${e.$2}'.toLowerCase().contains))
        .toList();
    return panel(
      padding: EdgeInsets.zero,
      child: AppMenuList(
        children: [
          if (found.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No matching settings. Try clock, password, font or warning.',
              ),
            ),
          for (final e in found)
            ListTile(
              leading: Icon(e.$3),
              title: Text(e.$1),
              trailing: const Icon(Icons.chevron_right),
              onTap: e.$4,
            ),
        ],
      ),
    );
  }

  bool reportMatches(ServiceReport r) {
    if (reportFilter != 'all' &&
        (reportFilter == 'rehearsal' ? !r.rehearsal : r.rehearsal))
      return false;
    final text =
        '${r.name} ${r.churchName} ${r.rows.map((s) => s.name).join(' ')}'
            .toLowerCase();
    if (!reportQuery
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains))
      return false;
    final date = DateTime.fromMillisecondsSinceEpoch(
      r.startedWall ?? r.endedWall,
    );
    return reportDates == null ||
        (!date.isBefore(reportDates!.start) &&
            date.isBefore(
              DateTime(
                reportDates!.end.year,
                reportDates!.end.month,
                reportDates!.end.day + 1,
              ),
            ));
  }

  bool get useMasterDetail =>
      MediaQuery.sizeOf(context).width >= 1000 &&
      MediaQuery.textScalerOf(context).scale(16) <= 24;
  Widget masterDetail(Widget list, Widget detail) => SizedBox(
    key: const ValueKey('master-detail'),
    height:
        (MediaQuery.sizeOf(context).height - (c.liveSession.active ? 280 : 210))
            .clamp(400, 1200),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 4, child: SingleChildScrollView(child: list)),
        const SizedBox(width: 20),
        Expanded(
          flex: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: detail,
          ),
        ),
      ],
    ),
  );
  Widget programsResponsive() => !useMasterDetail
      ? templates()
      : masterDetail(
          templates(),
          !c.state.programLibrary
                  .find(c.state.templates, programQuery, programFilter)
                  .any((p) => p.name == selectedProgram)
              ? panel(
                  child: const Center(
                    child: Text('Select a program to view its details.'),
                  ),
                )
              : programDetails(selectedProgram!, embedded: true),
        );
  Widget reportsResponsive() {
    if (!useMasterDetail || reportView == 'graph') return reports();
    final r = c.state.reports
        .where((r) => r.id == selectedReport && reportMatches(r))
        .firstOrNull;
    return masterDetail(
      reports(),
      r == null
          ? panel(
              child: const Center(
                child: Text('Select a service to view its report.'),
              ),
            )
          : ReportDetailPage(
              key: ValueKey(r.id),
              report: r,
              embedded: true,
              onExport: (format) => exportReport(r, format),
              onPrint: () => printServiceSheet(r.program, report: r),
              onDelete: () => confirmClearReports(record: r),
            ),
    );
  }

  Future<void> toggleFavourite(Timeline p) async {
    final ok = await c.commit((draft, _) {
      draft.templateIndex(p);
      if (!draft.programLibrary.favourites.remove(p.name))
        draft.programLibrary.favourites.add(p.name);
    });
    if (!ok && mounted) await showError(c.error ?? 'Could not save favourite.');
  }

  Widget programSearch() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: const ValueKey('program-search'),
        initialValue: programQuery,
        decoration: const InputDecoration(
          labelText: 'Search programs',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => refreshHome(() => programQuery = v),
      ),
      const SizedBox(height: 8),
      ProgramFilters(
        value: programFilter,
        onChanged: (v) => refreshHome(() => programFilter = v),
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget cueDeliveryFeedback() {
    final s = c.liveSession, cue = s.intended(c.now);
    if (!s.hasManualCue(c.now) &&
        !s.hasAutomaticCue(c.now) &&
        c.currentQuickMessage == null)
      return const SizedBox.shrink();
    String status;
    if (s.outputBlank) {
      status = 'Not sent · screen intentionally blank';
    } else if (c.destination == 'led') {
      status = c.hardware.sending
          ? 'Sending…'
          : c.hardware.currentOutputAccepted
          ? 'Controller accepted'
          : 'Not sent';
    } else if (c.destination == 'mobile') {
      final peers = c.pairing.syncedStagePeers
          .where(
            (p) =>
                c.currentQuickMessage == null ||
                c.quickRecipients.contains(p.id),
          )
          .toList();
      final received = peers.where((p) {
        final ack = p.acknowledgedSnapshot;
        if (ack == null || ack['blank'] == true) return false;
        if (c.currentQuickMessage != null) {
          return c.quickRecipients.contains(p.id) &&
              ack['messageId'] == c.quickMessageId;
        }
        return ack['session'] == s.id &&
            ack['index'] == s.index &&
            ack['displayText'] == cue?.text &&
            ack['outputMode'] == s.outputMode(c.now) &&
            ack['bold'] == cue?.bold &&
            ack['italic'] == cue?.italic &&
            ack['effect'] == cue?.effect &&
            ack['speed'] == cue?.speed;
      }).length;
      status = peers.isEmpty
          ? 'Not sent · no stage screen'
          : received == peers.length
          ? 'Stage screens received'
          : 'Sending to stage screens…';
    } else {
      status = c.destinationConnected && !s.held
          ? 'Shown in simulator'
          : 'Not sent';
    }
    final remaining = c.messageReturnSeconds;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            key: const ValueKey('cue-delivery-feedback'),
            style: TextStyle(
              color: status.startsWith('Not sent')
                  ? appColors(context).warning
                  : appColors(context).accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (remaining != null && s.active && !s.showClock && !s.outputBlank)
            Text(
              'Returns to timer in ${remaining}s',
              style: TextStyle(color: appColors(context).muted),
            ),
          if (c.destination == 'led' && status == 'Controller accepted')
            const Text(
              'Controller acknowledgement; appearance is not visually verified.',
              style: TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}
