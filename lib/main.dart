import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'pairing_pin.dart';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'church_banner.dart';
import 'feedback_page.dart';
import 'controller.dart';
import 'domain.dart';
import 'pixels.dart';
import 'platform.dart';
import 'native_fonts.dart';
import 'display_connection.dart';
import 'pairing.dart';

part 'feature_views.dart';
part 'report_views.dart';
part 'live_views.dart';
part 'template_views.dart';
part 'settings_views.dart';
part 'refined_settings.dart';
part 'hardware_views.dart';
part 'operator_settings.dart';
part 'planning_views.dart';
part 'pairing_views.dart';
part 'device_management.dart';

String styleSummary(TextLayout l) =>
    '${l.text} · ${displayFontNames[l.font]} · ${l.bold ? 'bold · ' : ''}${l.italic ? 'italic · ' : ''}${l.height * 7}px · ${l.align} · ${l.effect}${l.effect == 'scroll' ? ' ${l.speed}px/s' : ''}';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tinos',
    ], await rootBundle.loadString('assets/licenses/OFL-Tinos.txt'));
  });
  runApp(TimerApp(controller: AppController(AndroidPort())));
}

class TimerApp extends StatelessWidget {
  final AppController controller;
  const TimerApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: controller.themeSelection,
    builder: (context, themeId, _) => MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => LedAppearance(
          shape: controller.ready ? controller.state.pixelShape : 'square',
          child: child!,
        ),
      ),
      theme: appTheme(themeId),
      home: Home(controller: controller),
    ),
  );
}

class Home extends StatefulWidget {
  final AppController controller;
  const Home({super.key, required this.controller});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  AppController get c => widget.controller;
  int page = 0;
  bool focused = false, controlsLocked = false;
  void setFocused(bool value) => setState(() {
    focused = value;
    page = 0;
  });
  final settingsRefresh = ValueNotifier<int>(0);

  String reportFilter = 'all', reportView = 'list';
  void selectReportFilter(String value) => setState(() => reportFilter = value);
  void selectReportView(String value) => setState(() => reportView = value);
  void navigatePage(int value) => setState(() => page = value);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!c.ready) {
      c.initialize().catchError((Object e) {
        if (mounted) showError('Could not initialize Android services: $e');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    settingsRefresh.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) c.suspend();
    if (state == AppLifecycleState.resumed) c.resume();
  }

  Future<void> showError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Please review'),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Future<bool> confirm(String title, String body, String button) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(button),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> chooseService() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a service'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose a timeline to load into Ready. Timing begins only when you start the first segment.',
                ),
                const SizedBox(height: 16),
                ...c.state.templates.asMap().entries.map(
                  (e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value.name),
                    subtitle: Text(
                      '${e.value.segments.length} segments · ${e.value.segments.fold<int>(0, (a, s) => a + s.minutes)} min',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, e.key),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, -1),
                  icon: const Icon(Icons.add),
                  label: const Text('Create timeline'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == -1) {
      await editTemplate();
      if (mounted) await chooseService();
    } else {
      await c.act('load', value: c.state.templates[picked]);
    }
  }

  Future<void> startFirst() async {
    final s = c.state.session, revision = c.state.session.revision;
    final stageWarnings = s.timeline!.display.warnings.where(
      (w) => w.enabled && w.destination == 'stage',
    );
    final warningSummary = stageWarnings.isEmpty
        ? ''
        : '\n\nAutomatic stage warnings:\n${stageWarnings.map((w) => '${formatTime(w.seconds * 1000)} — ${styleSummary(w.cue)}').join('\n')}';
    if (await confirm(
      'Start ${s.timeline!.segments.first.name}?',
      c.hardware.enabled
          ? '${c.hardware.connected ? 'Send the countdown to ${c.hardware.rememberedName}.' : 'The display is disconnected. Timing will start locally; connect and restore the timer to send it.'}\n\nNormal speed and up to 59:59 remaining are supported. Updates may blink briefly. Automatic stage warnings return to the current countdown. A persistent notification keeps connected-display timing active when the phone locks. Connection loss or stopping the app requires review; a cue may remain until restored.'
          : '${s.rehearsal ? 'REHEARSAL: time will run ${s.rate}× faster. Reports will be marked as rehearsal.\n\n' : ''}This session uses the simulator only.$warningSummary\n\n${s.disconnected ? 'The simulator is disconnected. Timing will start, but its output will stay unchanged.\n\n' : ''}Accept these layouts for this simulated service?',
      'Start first segment',
    ))
      await c.act('start', revision: revision);
  }

  Future<void> advance() async {
    final s = c.state.session, revision = c.state.session.revision;
    final next = s.timeline!.segments[s.index + 1];
    var keepBlank = false;
    if (await confirmTimer(
      revision: revision,
      title: 'Start ${next.name}?',
      action: 'Start ${next.name}',
      content: () => StatefulBuilder(
        builder: (context, update) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Finish ${s.timeline!.segments[s.index].name} and start ${next.name} · ${next.minutes} min. Previous cues are cleared and the new countdown is sent.${c.hardware.held ? ' This also restores the reviewed output on the connected display.' : ''}',
            ),
            if (s.outputBlank)
              CheckboxListTile(
                title: const Text('Keep the display blank'),
                value: keepBlank,
                onChanged: (v) => update(() => keepBlank = v!),
              ),
          ],
        ),
      ),
    ))
      await c.act('advance', value: keepBlank, revision: revision);
  }

  Future<void> undo() async {
    final s = c.state.session, revision = c.state.session.revision;
    if (s.undo == null) return;
    if (await confirmTimer(
      revision: revision,
      title: 'Undo segment change?',
      action: 'Restore previous segment',
      content: () => Text(
        'Return to ${s.timeline!.segments[s.undo!.index].name} with ${operatorTimeDescription(s.undoBalance(c.now))} of ${formatTime(s.undoAllocatedMs)} allocated. ${s.undo!.paused ? 'Its timer will remain paused.' : 'Its timer will resume, accounting for time since the segment change.'}\n\nChanges made to ${s.timeline!.segments[s.index].name} will be discarded. The active stage cue stays visible.${s.uncertain ? '\nTiming is uncertain after recovery.' : ''}',
      ),
    ))
      await c.act('undo', revision: revision);
  }

  Future<TextLayout?> compose(
    TextLayout initial,
    String title,
    String button, {
    Future<bool> Function()? onDelete,
  }) => showDialog<TextLayout>(
    context: context,
    builder: (_) => TextComposer(
      initial: initial,
      title: title,
      button: button,
      onDelete: onDelete,
    ),
  );
  Future<void> sendCue(TextLayout layout, {int? cueIndex}) async {
    final revision = c.state.session.revision;
    final result = await compose(
      layout,
      cueIndex == null ? 'New stage cue' : 'Edit stage cue',
      'Send',
      onDelete: cueIndex == null
          ? null
          : () async {
              if (!await confirm(
                'Delete this saved cue?',
                'Remove “${layout.text}” from the cues shared across all services? A cue already showing on stage stays visible until replaced or dismissed.',
                'Delete cue',
              ))
                return false;
              final ok = await c.deleteStageCue(cueIndex, layout);
              if (!ok && mounted)
                await showError(c.error ?? 'The cue could not be deleted.');
              return ok;
            },
    );
    if (result != null) {
      await c.sendAndSaveCue(result, index: cueIndex, revision: revision);
    }
  }

  Future<Timeline?> editTemplate({int? index}) async {
    final initial = index == null
        ? Timeline('', [], c.state.defaults)
        : c.state.templates[index];
    final result = await Navigator.of(context).push<Timeline>(
      MaterialPageRoute(
        builder: (_) => TemplateEditor(
          initial: initial,
          defaultEnd: c.state.defaults.end,
          existingNames: c.state.templates
              .asMap()
              .entries
              .where((e) => e.key != index)
              .map((e) => e.value.name.toLowerCase())
              .toSet(),
        ),
      ),
    );
    if (result == null) return null;
    final ok = await c.commit(
      (draft, _) => draft.saveTemplate(
        result,
        replacing: index == null ? null : draft.templateIndex(initial),
      ),
    );
    if (!ok) {
      if (mounted)
        await showError(c.error ?? 'The template could not be saved.');
      return null;
    }
    return result;
  }

  Future<void> importFile() async {
    try {
      final file = await c.port.pickFile();
      if (file == null || !mounted) return;
      final candidate = importTemplate(
        file['content'] as String,
        file['name'] as String,
        c.state.defaults,
      );
      for (final l in [
        ...candidate.display.cues,
        ...candidate.display.warnings.map((w) => w.cue),
        candidate.display.end,
        if (candidate.display.zero != null) candidate.display.zero!,
      ]) {
        await NativeDisplayFonts.prepare(l);
      }
      validateTimelinePixels(candidate);
      final name = TextEditingController(text: candidate.name);
      String? error;
      bool validName() {
        try {
          final n = nameValue(name.text, 'Template name');
          require(
            !c.state.templates.any(
              (e) => e.name.toLowerCase() == n.toLowerCase(),
            ),
            'This name already exists. Rename the incoming template.',
          );
          error = null;
          return true;
        } catch (e) {
          error = e.toString();
          return false;
        }
      }

      validName();
      final accepted = await showDialog<Timeline>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Preview import'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Template name',
                      ),
                      onChanged: (_) => update(() {
                        validName();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${candidate.segments.length} segments · ${candidate.segments.fold<int>(0, (a, s) => a + s.minutes)} minutes',
                    ),
                    Text(
                      (file['name'] as String).toLowerCase().endsWith('.csv')
                          ? 'CSV supplies the timeline only. These current defaults have been captured for this import:'
                          : 'JSON includes these display settings:',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cues:\n${candidate.display.cues.map(styleSummary).join('\n')}\nZero: ${candidate.display.zero == null ? '00:00' : styleSummary(candidate.display.zero!)}\nEnd: ${styleSummary(candidate.display.end)}\nWarnings:\n${candidate.display.warnings.isEmpty ? 'None' : candidate.display.warnings.map((w) => '${w.enabled ? 'On' : 'Off'} · ${formatTime(w.seconds * 1000)} · ${w.destination} · ${styleSummary(w.cue)}').join('\n')}',
                    ),
                    const SizedBox(height: 12),
                    ...candidate.segments.map(
                      (s) => Text('${s.name} — ${s.minutes} min'),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(color: appColors(context).warning),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !validName()
                    ? null
                    : () {
                        try {
                          final t = candidate.renamed(name.text);
                          require(
                            !c.state.templates.any(
                              (e) =>
                                  e.name.toLowerCase() == t.name.toLowerCase(),
                            ),
                            'This name already exists. Rename the incoming template.',
                          );
                          Navigator.pop(ctx, t);
                        } catch (e) {
                          update(() => error = e.toString());
                        }
                      },
                child: const Text('Accept import'),
              ),
            ],
          ),
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), name.dispose);
      if (accepted != null)
        await c.commit((draft, _) {
          draft.saveTemplate(accepted);
          draft.addStageCues(accepted.display.cues);
        });
    } catch (e) {
      if (mounted) await showError(e.toString());
    }
  }

  Future<void> export(Timeline t, String type) async {
    if (type == 'csv' &&
        !await confirm(
          'Export segments only?',
          'CSV includes names, order and durations. Cue formatting, zero and end screens are omitted. Choose JSON to preserve the full template.',
          'Export CSV',
        ))
      return;
    try {
      await c.port.exportFile(
        '${t.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$type',
        type == 'json' ? exportJson(t) : exportCsv(t),
      );
    } catch (e) {
      if (mounted) showError('Export failed: $e');
    }
  }

  Widget panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) => Material(
    color: appColors(context).surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: appColors(context).border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(padding: padding, child: child),
  );
  Widget label(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: appColors(context).muted,
      letterSpacing: 1.6,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
  Widget button(
    String text,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: controlsLocked ? null : action,
          icon: Icon(icon, size: 20),
          label: Text(text),
        )
      : OutlinedButton.icon(
          onPressed: controlsLocked ? null : action,
          icon: Icon(icon, size: 20),
          label: Text(text),
        );

  Widget live() {
    final s = c.state.session, t = s.timeline;
    final enabled =
        s.active &&
        !c.busy &&
        !c.corrupt &&
        !controlsLocked &&
        c.pairing.localControl;
    final phase = s.phase == 'active'
        ? (s.paused ? 'Paused' : 'Live')
        : s.phase == 'ready'
        ? 'Ready'
        : s.phase == 'ended'
        ? 'Service ended'
        : 'Standing by';
    final timerPanel = panel(
      child: Column(
        key: const ValueKey('timer-card-content'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label(t?.name ?? 'Live production')),
              Chip(
                label: Text(s.rehearsal ? '$phase · ${s.rate}×' : phase),
                avatar: Icon(
                  s.active && !s.paused ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: appColors(context).accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t?.segments[s.index].name ?? 'Your next service,\nunder control.',
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (t != null) ...[
            const SizedBox(height: 12),
            Text(
              s.index + 1 < t.segments.length
                  ? 'NEXT  ${t.segments[s.index + 1].name} · ${t.segments[s.index + 1].minutes} min'
                  : 'FINAL SEGMENT',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 6),
            if (t.segments[s.index].speaker.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Speaker: ${t.segments[s.index].speaker}'),
              ),
            if (t.segments[s.index].notes.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline, size: 18),
                title: const Text('Private operator notes'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(t.segments[s.index].notes),
                  ),
                ],
              ),
            SegmentGauge(session: s, now: c.now),
          ] else ...[
            const SizedBox(height: 18),
            Text(
              'Load a timeline, keep the room on time, and send discreet cues to the stage.',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 24),
          ],
          if (!s.active && s.phase != 'ready')
            button(
              'Start service',
              Icons.play_arrow,
              c.busy || c.corrupt ? null : chooseService,
              primary: true,
            ),
          if (s.phase == 'ready') ...[
            DropdownButtonFormField<int>(
              key: ValueKey('speed-${s.id}'),
              initialValue: s.rate,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Service mode'),
              items: [1, 5, 10, 30, 60]
                  .map(
                    (rate) => DropdownMenuItem(
                      value: rate,
                      child: Text(
                        rate == 1
                            ? 'Live timing · 1×'
                            : 'Fast rehearsal · $rate×',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: c.busy ? null : (v) => c.act('rate', value: v),
            ),
            const SizedBox(height: 12),
            Text(
              'Timing has not started. The display retains its previous output.',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                button(
                  'Start first segment',
                  Icons.play_arrow,
                  c.busy ? null : startFirst,
                  primary: true,
                ),
                button(
                  'Cancel setup',
                  Icons.close,
                  c.busy ? null : () => c.act('cancelReady'),
                ),
              ],
            ),
          ],
          if (s.active) ...[
            liveControls(enabled),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('end-service'),
              onPressed: enabled
                  ? () async {
                      final rev = s.revision;
                      if (await confirmTimer(
                        revision: rev,
                        title: 'End ${t!.name}?',
                        action: 'End service',
                        content: () => Text(
                          c.hardware.enabled
                              ? c.hardware.held || !c.hardware.connected
                                    ? 'Finish this service and save its report. The sign will keep its last program until you reconnect and restore output.'
                                    : 'Finish this service and save its report. The sign will show this service’s end screen, including its scrolling effect. A brief blink is expected.'
                              : 'Finish this service, save its report, clear the active cue and show “${t.display.end.text}”.',
                        ),
                      ))
                        await c.act('end', revision: rev);
                    }
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End service'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffa73238),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final displayPanel = panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DisplayPreviewHeader(connection: c.displayConnection),
          const SizedBox(height: 14),
          LedMatrix(
            pixels: c.hardware.enabled
                ? c.hardware.preview(c.now)
                : c.simulator.pixels,
            hardware: c.hardware.enabled,
            stale: c.hardware.enabled
                ? c.hardware.held || !c.hardware.connected
                : s.held || s.disconnected,
          ),
          const SizedBox(height: 12),
          Text(
            '32 × 16 · ${c.state.pixelShape == 'square' ? 'Square' : 'Circular'} LEDs',
            style: TextStyle(color: appColors(context).muted, fontSize: 12),
          ),
          if (s.held || s.disconnected) ...[
            const SizedBox(height: 8),
            Text(
              s.disconnected
                  ? 'Output unavailable · showing the last simulated frame'
                  : 'Output held · review before restoring',
              style: TextStyle(color: appColors(context).error),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Intended: ${s.outputBlank ? 'Blank' : s.intended(c.now)?.text ?? 'No new output'}',
            style: TextStyle(color: appColors(context).muted),
          ),
          Text(
            c.hardware.enabled
                ? 'Last accepted: ${c.hardware.acceptedLabel}'
                : 'Simulated: ${c.simulator.delivered?.text ?? 'Blank'}',
            style: TextStyle(color: appColors(context).muted),
          ),
          const SizedBox(height: 8),
          Text(
            c.hardware.enabled
                ? 'Preview is an estimate of the last accepted program, not a live camera view of the sign.'
                : 'Simulator only · connect a display in Settings for physical output.',
            style: TextStyle(color: appColors(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          button(
            c.hardware.enabled
                ? 'Display connection'
                : s.disconnected
                ? 'Reconnect simulator'
                : 'Disconnect simulator',
            s.disconnected ? Icons.link : Icons.link_off,
            c.busy || c.corrupt
                ? null
                : c.hardware.enabled
                ? () => openSettingsDetail(
                    'Display connection',
                    connectionSettings,
                  )
                : () => c.act(s.disconnected ? 'connect' : 'disconnect'),
          ),
        ],
      ),
    );
    final cuePanel = panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label('Stage cues')),
              if (s.alert != null)
                Icon(
                  Icons.chat_bubble_outline,
                  color: appColors(context).accent,
                  size: 18,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.outputBlank
                ? (s.paused
                      ? 'Display blank · timer paused'
                      : 'Display blank · timing continues')
                : s.hasAutomaticCue(c.now)
                ? 'Warning on display: ${s.automaticCue!.text}'
                : s.alert == null
                ? 'The right words, at the right moment.'
                : '${c.hardware.enabled ? 'Selected cue' : 'On display'}: ${s.alert!.text}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            s.alert == null
                ? 'Tap a prepared cue to send it. Manage text and formatting in Settings / Stage cues.'
                : s.paused
                ? 'The underlying timer is paused.'
                : 'The countdown continues underneath this cue.',
            style: TextStyle(color: appColors(context).muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: c.state.stageCues
                .asMap()
                .entries
                .map(
                  (e) => button(
                    e.value.text,
                    Icons.chat_bubble_outline,
                    enabled && !c.hardware.sending
                        ? () => sendPreparedCue(e.value)
                        : null,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              button(
                'Manage cues',
                Icons.edit_outlined,
                controlsLocked
                    ? null
                    : () => openSettingsDetail('Stage cues', stageCueSettings),
              ),
              button(
                'Show timer',
                Icons.timer_outlined,
                enabled &&
                        (s.outputBlank ||
                            s.alert != null ||
                            s.hasAutomaticCue(c.now))
                    ? () => c.act('timer')
                    : null,
                primary: s.alert != null || s.outputBlank,
              ),
              button(
                'Show cue',
                Icons.chat_bubble_outline,
                enabled ? chooseStageCue : null,
              ),
              button(
                'Blank sign',
                Icons.tv_off_outlined,
                enabled && !s.outputBlank
                    ? () async {
                        final revision = s.revision;
                        if (await confirmTimer(
                          revision: revision,
                          title: 'Blank the display?',
                          action: c.hardware.enabled
                              ? 'Blank display'
                              : 'Blank simulator',
                          content: () => Text(
                            'Clear the ${c.hardware.enabled ? 'display' : 'simulator'} while timing continues. Automatic stage cues stay hidden until you choose Show timer or send a cue. Phone warnings remain enabled.',
                          ),
                        ))
                          await c.act('blank', revision: revision);
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (s.active)
                  TextButton.icon(
                    key: const ValueKey('control-lock'),
                    onPressed: controlsLocked
                        ? null
                        : () => setState(() => controlsLocked = true),
                    icon: Icon(controlsLocked ? Icons.lock : Icons.lock_open),
                    label: Text(
                      controlsLocked ? 'Controls locked' : 'Lock controls',
                    ),
                  ),
                if (controlsLocked)
                  Semantics(
                    label: 'Hold to unlock controls',
                    child: OutlinedButton(
                      key: const ValueKey('unlock-controls'),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Press and hold to unlock controls.',
                              ),
                            ),
                          ),
                      onLongPress: () => setState(() => controlsLocked = false),
                      child: const Text('Hold to unlock'),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setFocused(!focused),
                  icon: Icon(
                    focused ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                  label: Text(
                    focused ? 'Exit focused view' : 'Focused operator view',
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                if (!focused)
                  TextButton.icon(
                    onPressed: controlsLocked
                        ? null
                        : () => openSettingsDetail(
                            'Ready for service',
                            readinessSettings,
                          ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text(
                      'Ready for service',
                      style: TextStyle(decoration: TextDecoration.underline),
                    ),
                  ),
              ],
            ),
          ),
          if (c.displayConnection == DisplayConnection.disconnected &&
              (s.active || s.phase == 'ended'))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                key: const ValueKey('display-disconnected-banner'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: appColors(context).surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_off, color: appColors(context).error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Display disconnected',
                            style: TextStyle(
                              color: appColors(context).error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${c.hardware.enabled ? 'The sign may retain its last accepted output.' : 'Simulator output is paused.'} ${s.active
                                ? s.paused
                                      ? 'The timer is paused.'
                                      : 'Timing continues.'
                                : 'The service has ended.'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (c.hardware.enabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: hardwareStatusPanel(),
            ),
          if (!c.hardware.enabled && s.held && (s.active || s.phase == 'ended'))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review before restoring output',
                      style: TextStyle(
                        color: appColors(context).warning,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${t!.name}\nLast activity: ${DateTime.fromMillisecondsSinceEpoch(s.checkpoint.wall).toLocal()}\n${s.uncertain ? 'Elapsed time is uncertain after a reboot or clock change. ' : ''}The timer continues locally. Confirm before replacing the simulator output.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        button(
                          s.phase == 'ended'
                              ? 'Send end screen'
                              : 'Resume output',
                          Icons.play_arrow,
                          c.busy ? null : () => c.act('release'),
                          primary: true,
                        ),
                        if (s.alert != null)
                          button(
                            'Dismiss alert & show timer',
                            Icons.timer,
                            c.busy ? null : () => c.act('releaseTimer'),
                          ),
                        button(
                          'Keep disconnected',
                          Icons.link_off,
                          c.busy ? null : () => c.act('disconnect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (focused) ...[
            timerPanel,
            const SizedBox(height: 16),
            panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DisplayPreviewHeader(connection: c.displayConnection),
                  const SizedBox(height: 12),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: LedMatrix(
                        pixels: c.hardware.enabled
                            ? c.hardware.preview(c.now)
                            : c.simulator.pixels,
                        hardware: c.hardware.enabled,
                        stale: c.hardware.enabled
                            ? c.hardware.held || !c.hardware.connected
                            : s.held || s.disconnected,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.outputBlank
                        ? (s.paused
                              ? 'Blanked · timer paused'
                              : 'Blanked · timing continues')
                        : c.hardware.enabled
                        ? c.hardware.acceptedLabel
                        : 'Simulator · ${s.intended(c.now)?.text ?? 'No new output'}',
                  ),
                ],
              ),
            ),
          ] else if (constraints.maxWidth >= 850)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: timerPanel),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: displayPanel),
              ],
            )
          else ...[
            timerPanel,
            const SizedBox(height: 16),
            displayPanel,
          ],
          const SizedBox(height: 20),
          if (!focused && (s.active || s.phase == 'ended')) ...[
            timingOverview(),
            const SizedBox(height: 16),
          ],
          if (s.warningNotice != null) ...[
            panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Automatic warning'),
                  const SizedBox(height: 8),
                  Text(
                    s.warningNotice!,
                    style: TextStyle(color: appColors(context).warning),
                  ),
                  if (c.hardware.enabled)
                    Text(
                      c.hardware.held || !c.hardware.connected
                          ? 'Stage output is held. Reconnect and review before restoring.'
                          : 'Stage warnings return to the current countdown. Updates may blink briefly.',
                    ),
                  TextButton(
                    onPressed: c.busy ? null : () => c.act('dismissWarning'),
                    child: const Text('Dismiss warning'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          cuePanel,
          if (t != null) ...[
            const SizedBox(height: 20),
            panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Service rundown · snapshot'),
                  if (s.active)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: enabled ? editUpcoming : null,
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: const Text('Edit upcoming'),
                        ),
                        TextButton.icon(
                          onPressed: enabled ? finishPlanning : null,
                          icon: const Icon(Icons.schedule),
                          label: const Text('Plan finish'),
                        ),
                        TextButton.icon(
                          onPressed: controlsLocked
                              ? null
                              : () => printServiceSheet(t),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Service sheet'),
                        ),
                      ],
                    ),
                  if (s.targetFinishWall != null)
                    Text(
                      'Target finish ${clockLabel(s.targetFinishWall!)} · actual finish depends on manual advances',
                    ),
                  const SizedBox(height: 12),
                  ...t.segments.asMap().entries.map((e) {
                    final current = e.key == s.index;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: current
                            ? appColors(context).accent.withValues(alpha: .14)
                            : null,
                        border: current
                            ? Border(
                                left: BorderSide(
                                  color: appColors(context).accent,
                                  width: 4,
                                ),
                              )
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          key: ValueKey('rundown-${e.key}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: Text('${e.key + 1}'.padLeft(2, '0')),
                          title: Text(
                            e.value.name,
                            style: TextStyle(
                              fontWeight: current
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            '${e.value.minutes} min${current ? ' · Current' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => SafeArea(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      e.value.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Segment ${e.key + 1} of ${t.segments.length} · ${e.value.minutes} minutes planned',
                                    ),
                                    if (current)
                                      Text(
                                        '${operatorTimeDescription(s.balance(c.now))} · ${formatTime(s.allocatedMs)} allocated',
                                      ),
                                    if (s.run?.actualMs[e.key] != null)
                                      Text(
                                        'Recorded duration: ${durationLabel(s.run!.actualMs[e.key]!)}',
                                      ),
                                    if (e.value.speaker.isNotEmpty)
                                      Text('Speaker: ${e.value.speaker}'),
                                    const Divider(height: 32),
                                    const Text(
                                      'Private operator note',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      e.value.notes.isEmpty
                                          ? 'No private note for this segment.'
                                          : e.value.notes,
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  double headerHeight(BuildContext context) => math.max(
    76,
    MediaQuery.textScalerOf(context).scale(18) * 2.4 +
        ((c.ready ? c.state.churchName : c.loadingChurchName).isNotEmpty
            ? MediaQuery.textScalerOf(context).scale(12) * 1.3
            : 0) +
        8,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => c.pairing.joined
        ? PairedScreen(controller: c)
        : Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  clipBehavior: Clip.antiAlias,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(26),
                    ),
                  ),
                  flexibleSpace: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(26),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(
                                appColors(
                                  context,
                                ).accent.withValues(alpha: .04),
                                appColors(context).surface,
                              ).withValues(alpha: .84),
                              appColors(context).surface.withValues(alpha: .92),
                            ],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  actions: [
                    if (c.ready)
                      IconButton(
                        key: const ValueKey('header-connection'),
                        tooltip:
                            '${c.displayConnection.label} · connection details',
                        onPressed: () =>
                            (controlsLocked || !c.pairing.localControl)
                            ? null
                            : openSettingsDetail(
                                'Display connection',
                                connectionSettings,
                              ),
                        icon: Icon(
                          connectionIcon(c.displayConnection),
                          color:
                              c.displayConnection ==
                                  DisplayConnection.disconnected
                              ? appColors(context).error
                              : appColors(context).accent,
                        ),
                      ),
                    const SizedBox(width: 8),
                  ],
                  toolbarHeight: headerHeight(context),
                  title: Row(
                    children: [
                      const ChurchTimerMark(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              appName,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if ((c.ready
                                    ? c.state.churchName
                                    : c.loadingChurchName)
                                .isNotEmpty)
                              Tooltip(
                                message: c.ready
                                    ? c.state.churchName
                                    : c.loadingChurchName,
                                child: Text(
                                  c.ready
                                      ? c.state.churchName
                                      : c.loadingChurchName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: appColors(context).muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!c.ready)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ChurchTimerMark(size: 84),
                            const SizedBox(height: 20),
                            const Text(
                              appName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (c.loadingChurchName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  c.loadingChurchName,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            const SizedBox(height: 24),
                            const CircularProgressIndicator(),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (c.pairing.hosting)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: panel(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            c.pairing.localControl
                                                ? 'This phone controls the service · ${c.pairing.peers.where((p) => p.approved).length} paired devices'
                                                : 'Control is with a paired operator. This phone remains the service host.',
                                          ),
                                          TextButton(
                                            onPressed: () => openSettingsDetail(
                                              'Paired devices',
                                              pairedDeviceSettings,
                                            ),
                                            child: const Text(
                                              'Manage devices and control',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (c.backgroundError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      c.backgroundError!,
                                      style: TextStyle(
                                        color: appColors(context).error,
                                      ),
                                    ),
                                  ),
                                if (c.error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: panel(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.error!,
                                            style: TextStyle(
                                              color: appColors(context).warning,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (c.retry != null)
                                            TextButton(
                                              onPressed: c.busy
                                                  ? null
                                                  : () => c.retry!(),
                                              child: const Text(
                                                'Retry failed action',
                                              ),
                                            ),
                                          if (c.corrupt)
                                            TextButton(
                                              onPressed: () async {
                                                if (await confirm(
                                                  'Reset local state?',
                                                  'This replaces unreadable local service and template data with starter templates. No physical display is connected.',
                                                  'Reset local data',
                                                ))
                                                  await c.resetCorrupt();
                                              },
                                              child: const Text(
                                                'Reset local data…',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                AbsorbPointer(
                                  absorbing:
                                      c.corrupt || !c.pairing.localControl,
                                  child: page == 0
                                      ? live()
                                      : page == 1
                                      ? templates()
                                      : page == 2
                                      ? settingsHub()
                                      : reports(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: focused
                ? SafeArea(
                    top: false,
                    child: TextButton.icon(
                      onPressed: () => setFocused(false),
                      icon: const Icon(Icons.fullscreen_exit),
                      label: const Text('Exit focused view'),
                    ),
                  )
                : NavigationBar(
                    selectedIndex: page,
                    onDestinationSelected: (v) {
                      if (!controlsLocked) setState(() => page = v);
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.radio_button_checked),
                        label: 'Live',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.view_timeline_outlined),
                        label: 'Templates',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: 'Settings',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.assessment_outlined),
                        label: 'Reports',
                      ),
                    ],
                  ),
          ),
  );
}

class TextComposer extends StatefulWidget {
  final TextLayout initial;
  final String title, button;
  final Future<bool> Function()? onDelete;
  const TextComposer({
    super.key,
    required this.initial,
    required this.title,
    required this.button,
    this.onDelete,
  });
  @override
  State<TextComposer> createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {
  late TextEditingController text;
  late bool bold, italic;
  bool deleting = false;
  late String effect, align, font;
  String? fontRequest, fontError;
  late int height, speed;
  final watch = Stopwatch()..start();
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    text = TextEditingController(text: l.text);
    bold = l.bold;
    italic = l.italic;
    effect = l.effect;
    align = l.align;
    height = l.height;
    speed = l.speed;
    font = l.font;
    ticker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    text.dispose();
    super.dispose();
  }

  TextLayout get layout => TextLayout(
    text.text,
    bold: bold,
    italic: italic,
    effect: effect,
    align: align,
    height: height,
    speed: speed,
    font: font,
  );
  @override
  Widget build(BuildContext context) {
    final request = layout;
    if (request.font == 'tinos' &&
        NativeDisplayFonts.key(request) != fontRequest) {
      fontRequest = NativeDisplayFonts.key(request);
      fontError = null;
      final requestedKey = fontRequest;
      NativeDisplayFonts.prepare(request)
          .then((_) {
            if (mounted && fontRequest == requestedKey) setState(() {});
          })
          .catchError((Object e) {
            if (mounted && fontRequest == requestedKey)
              setState(() => fontError = '$e');
          });
    }
    String? error;
    try {
      validateLayout(layout);
    } catch (e) {
      error = e.toString();
    }
    if (font == 'tinos' && fontError != null) error = fontError;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LedMatrix(
                pixels: error == null
                    ? renderPixels(layout, watch.elapsedMilliseconds)
                    : List.filled(512, false),
              ),
              const SizedBox(height: 8),
              Text(
                'NOT TESTED ON SIGN · simulator preview',
                style: TextStyle(
                  color: appColors(context).warning,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Display text',
                  helperText: '1–160 characters · basic Latin and punctuation',
                ),
                onChanged: (_) => setState(() {
                  watch.reset();
                }),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Bold'),
                    selected: bold,
                    onSelected: (v) => setState(() => bold = v),
                  ),
                  FilterChip(
                    label: const Text('Italic'),
                    selected: italic,
                    onSelected: (v) => setState(() => italic = v),
                  ),
                  FilterChip(
                    label: const Text('Tall · 14 px'),
                    selected: height == 2,
                    onSelected: (v) => setState(() => height = v ? 2 : 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: font,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Display font'),
                items: displayFontNames.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  font = v!;
                  fontRequest = null;
                  if (font == 'tinos') height = 2;
                  watch.reset();
                }),
              ),
              if (font == 'tinos')
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Bundled Tinos font · 14 px recommended. Compact text has fewer serif details.',
                    style: TextStyle(color: appColors(context).muted),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: effect,
                decoration: const InputDecoration(labelText: 'Effect'),
                items: const [
                  DropdownMenuItem(
                    value: 'static',
                    child: Text('Static · must fit'),
                  ),
                  DropdownMenuItem(
                    value: 'scroll',
                    child: Text('Scroll long text'),
                  ),
                  DropdownMenuItem(
                    value: 'flash',
                    child: Text('Flash · must fit'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  effect = v!;
                  watch.reset();
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: align,
                decoration: const InputDecoration(
                  labelText: 'Alignment (text that fits)',
                ),
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('Left')),
                  DropdownMenuItem(value: 'center', child: Text('Center')),
                  DropdownMenuItem(value: 'right', child: Text('Right')),
                ],
                onChanged: (v) => setState(() => align = v!),
              ),
              if (effect == 'scroll') ...[
                const SizedBox(height: 12),
                Text('Scroll speed: $speed pixels / second'),
                Slider(
                  value: speed.toDouble(),
                  min: 4,
                  max: 24,
                  divisions: 20,
                  onChanged: (v) => setState(() => speed = v.round()),
                ),
                if (error == null)
                  Text(
                    'One complete message pass: approximately ${(math.max(0, textWidth(layout)) / speed).toStringAsFixed(1)} seconds.',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(color: appColors(context).warning),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton.icon(
            onPressed: deleting
                ? null
                : () async {
                    setState(() => deleting = true);
                    try {
                      final removed = await widget.onDelete!();
                      if (removed && context.mounted) Navigator.pop(context);
                    } finally {
                      if (mounted) setState(() => deleting = false);
                    }
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete cue'),
            style: TextButton.styleFrom(
              foregroundColor: appColors(context).error,
            ),
          ),
        TextButton(
          onPressed: deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: error == null && !deleting
              ? () => Navigator.pop(context, layout)
              : null,
          child: Text(widget.button),
        ),
      ],
    );
  }
}

class TemplateEditor extends StatefulWidget {
  final Timeline initial;
  final Set<String> existingNames;
  final TextLayout defaultEnd;
  final bool upcomingOnly;
  const TemplateEditor({
    super.key,
    required this.initial,
    required this.existingNames,
    this.defaultEnd = defaultEndScreen,
    this.upcomingOnly = false,
  });
  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late TextEditingController name;
  late List<Segment> segments;
  late TextLayout endScreen;
  late String templateType;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial.name);
    segments = [...widget.initial.segments];
    endScreen = widget.initial.display.end;
    templateType = widget.initial.type;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> segment({int? index}) async {
    final label = TextEditingController(
          text: index == null ? '' : segments[index].name,
        ),
        duration = TextEditingController(
          text: index == null ? '5' : '${segments[index].minutes}',
        );
    final speaker = TextEditingController(
      text: index == null ? '' : segments[index].speaker,
    );
    final notes = TextEditingController(
      text: index == null ? '' : segments[index].notes,
    );
    String? issue;
    final result = await showDialog<Segment>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text(index == null ? 'Add segment' : 'Edit segment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Segment name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration · whole minutes (1–99)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: speaker,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Speaker (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Private operator notes',
                  helperText:
                      'Never shown on the sign. Included in template backups.',
                ),
              ),
              if (issue != null)
                Text(
                  issue!,
                  style: TextStyle(color: appColors(context).warning),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final s = Segment.fromJson({
                    'name': label.text,
                    'minutes': int.tryParse(duration.text),
                    'speaker': speaker.text,
                    'notes': notes.text,
                  });
                  Navigator.pop(ctx, s);
                } catch (e) {
                  update(() => issue = e.toString());
                }
              },
              child: const Text('Save segment'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      label.dispose();
      duration.dispose();
      speaker.dispose();
      notes.dispose();
    });
    if (result != null && mounted)
      setState(() {
        if (index == null) {
          segments.add(result);
        } else {
          segments[index] = result;
        }
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.upcomingOnly ? 'Upcoming segments' : 'Timeline editor',
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!widget.upcomingOnly) ...[
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Template name'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: templateType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Template group'),
              items: const [
                DropdownMenuItem(value: 'service', child: Text('Service')),
                DropdownMenuItem(value: 'rehearsal', child: Text('Rehearsal')),
              ],
              onChanged: (value) => setState(() => templateType = value!),
            ),
            const SizedBox(height: 8),
            Text(
              'Grouping organizes templates. Choose rehearsal speed when starting a service.',
              style: TextStyle(color: appColors(context).muted, fontSize: 12),
            ),
          ],
          if (widget.upcomingOnly)
            const Text(
              'Edit only the upcoming segments. Current and completed segments, saved templates and end screens stay unchanged.',
            ),
          const SizedBox(height: 16),
          Text(
            '${segments.length} segments · ${segments.fold<int>(0, (a, s) => a + s.minutes)} minutes',
            style: TextStyle(color: appColors(context).muted),
          ),
          const SizedBox(height: 8),
          Text(
            'Hold a row to drag it into a new position.',
            style: TextStyle(color: appColors(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: segments.length,
            onReorderItem: (a, b) => setState(() {
              segments.insert(b, segments.removeAt(a));
            }),
            itemBuilder: (context, i) => Card(
              key: ValueKey(segments[i]),
              child: ListTile(
                leading: const Icon(Icons.drag_handle),
                title: Text(segments[i].name),
                subtitle: Text(
                  '${segments[i].minutes} minutes${segments[i].speaker.isEmpty ? '' : ' · ${segments[i].speaker}'}${segments[i].notes.isEmpty ? '' : '\nPrivate notes saved'}',
                ),
                onTap: () => segment(index: i),
                trailing: IconButton(
                  tooltip: 'Remove segment',
                  onPressed: () => setState(() => segments.removeAt(i)),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: segments.length < 200 ? segment : null,
            icon: const Icon(Icons.add),
            label: const Text('Add segment'),
          ),
          if (!widget.upcomingOnly) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End screen · this template',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    LedMatrix(pixels: renderPixels(endScreen, 0)),
                    const SizedBox(height: 12),
                    Text(styleSummary(endScreen)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit template end screen'),
                          onPressed: () async {
                            final next = await showDialog<TextLayout>(
                              context: context,
                              builder: (_) => TextComposer(
                                initial: endScreen,
                                title: 'Template end screen',
                                button: 'Use end screen',
                              ),
                            );
                            if (next != null && mounted)
                              setState(() => endScreen = next);
                          },
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => endScreen = widget.defaultEnd),
                          child: const Text('Use current default'),
                        ),
                      ],
                    ),
                    Text(
                      'Saved with this template. At Zero is shared across all services and can be changed in Settings → Display settings.',
                      style: TextStyle(color: appColors(context).muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Warnings are shared across all services. Edit them in Settings → Warnings & alerts.',
            ),
            const SizedBox(height: 24),
          ],
          if (error != null)
            Text(error!, style: TextStyle(color: appColors(context).warning)),
          if (widget.upcomingOnly) const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              try {
                if (widget.upcomingOnly) {
                  require(segments.length <= 200, 'Keep at most 200 segments.');
                  for (final s in segments) {
                    Segment.fromJson(s.toJson());
                  }
                  Navigator.pop(
                    context,
                    Timeline(
                      widget.initial.name,
                      segments,
                      widget.initial.display,
                      type: widget.initial.type,
                    ),
                  );
                  return;
                }
                final t = Timeline.fromJson(
                  Timeline(
                    name.text,
                    segments,
                    widget.initial.display.withEnd(endScreen),
                    type: templateType,
                  ).toJson(),
                );
                require(
                  !widget.existingNames.contains(t.name.toLowerCase()),
                  'A template with this name already exists.',
                );
                validateTimelinePixels(t);
                Navigator.pop(context, t);
              } catch (e) {
                setState(() => error = e.toString());
              }
            },
            icon: const Icon(Icons.check),
            label: Text(
              widget.upcomingOnly ? 'Review rundown changes' : 'Save timeline',
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.upcomingOnly)
            Text(
              'Template edits apply the next time you load this service. Default end screens are available in Settings → Display settings. Warnings are shared through Settings → Warnings & alerts.',
              style: TextStyle(color: appColors(context).muted),
            ),
        ],
      ),
    ),
  );
}
