import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'domain.dart';
import 'pixels.dart';
import 'platform.dart';
import 'native_fonts.dart';

part 'feature_views.dart';

const accent = Color(0xffc9f96c);
const muted = Color(0xff9caaa5);

String styleSummary(TextLayout l) =>
    '${l.text} · ${displayFontNames[l.font]} · ${l.bold ? 'bold · ' : ''}${l.italic ? 'italic · ' : ''}${l.height * 7}px · ${l.align} · ${l.effect}${l.effect == 'scroll' ? ' ${l.speed}px/s' : ''}';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TimerApp(controller: AppController(AndroidPort())));
}

class TimerApp extends StatelessWidget {
  final AppController controller;
  const TimerApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cuekeeper',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => LedAppearance(
        shape: controller.ready ? controller.state.pixelShape : 'square',
        child: child!,
      ),
    ),
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        primary: accent,
        surface: const Color(0xff131d1a),
      ),
      scaffoldBackgroundColor: const Color(0xff0a1210),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff0a1210),
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff0c1512),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 15, height: 1.45),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    ),
    home: Home(controller: controller),
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
  String settingsOwner = 'defaults';
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
      '${s.rehearsal ? 'REHEARSAL: time will run ${s.rate}× faster. Reports will be marked as rehearsal.\n\n' : ''}The countdown, zero-time screen, end screen and configured automatic stage warnings have not been tested on a physical sign. This session uses the simulator only.$warningSummary\n\n${s.disconnected ? 'The simulator is disconnected. Timing will start, but its output will stay unchanged.\n\n' : ''}Accept these layouts for this service? This does not grant physical approval.',
      'Start first segment',
    ))
      await c.act('start', revision: revision);
  }

  Future<void> advance() async {
    final s = c.state.session, revision = c.state.session.revision;
    final next = s.timeline!.segments[s.index + 1];
    if (await confirm(
      'Advance to ${next.name}?',
      'Start ${next.minutes} minutes. The current timer continues until you confirm.${s.alert != null ? '\n\nThe alert “${s.alert!.text}” will remain visible.' : ''}',
      'Start ${next.name}',
    ))
      await c.act('advance', revision: revision);
  }

  Future<void> undo() async {
    final s = c.state.session, revision = c.state.session.revision;
    if (s.undo == null) return;
    if (!s.fastUndo(c.now) &&
        !await confirm(
          'Undo advance?',
          'Restore ${s.timeline!.segments[s.undo!.index].name} at approximately ${formatTime(s.undoRemaining(c.now))}${s.undo!.paused ? ' (paused)' : ' (running)'}. The value is recalculated when you confirm.\n\nDiscard changes made to the current segment. The active alert remains.${s.uncertain ? '\nTiming is uncertain after recovery.' : ''}',
          'Restore previous segment',
        ))
      return;
    await c.act('undo', revision: revision);
  }

  Future<void> addTime() async {
    final revision = c.state.session.revision;
    final mins = TextEditingController(text: '0'),
        secs = TextEditingController(text: '30');
    String? error;
    final route = DialogRoute<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Add time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: mins,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: secs,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Seconds (0–59)',
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: Colors.orangeAccent),
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
                final m = int.tryParse(mins.text), s = int.tryParse(secs.text);
                if (m == null ||
                    s == null ||
                    m < 0 ||
                    s < 0 ||
                    s > 59 ||
                    m * 60 + s <= 0 ||
                    m * 60 + s > 5999) {
                  update(
                    () => error =
                        'Enter a positive duration; seconds must be 0–59 and total at most 99:59.',
                  );
                  return;
                }
                Navigator.pop(ctx, m * 60 + s);
              },
              child: const Text('Confirm add time'),
            ),
          ],
        ),
      ),
    );
    final delta = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    mins.dispose();
    secs.dispose();
    if (delta != null) await c.act('adjust', value: delta, revision: revision);
  }

  Future<TextLayout?> compose(
    TextLayout initial,
    String title,
    String button,
  ) => showDialog<TextLayout>(
    context: context,
    builder: (_) =>
        TextComposer(initial: initial, title: title, button: button),
  );
  Future<void> sendCue(TextLayout layout, {int? cueIndex}) async {
    final revision = c.state.session.revision;
    final result = await compose(
      layout,
      cueIndex == null ? 'New stage cue' : 'Edit stage cue',
      'Send',
    );
    if (result != null) {
      await c.sendAndSaveCue(result, index: cueIndex, revision: revision);
    }
  }

  Future<void> editTemplate({int? index}) async {
    final initial = index == null
        ? Timeline('', [], c.state.defaults)
        : c.state.templates[index];
    final result = await Navigator.of(context).push<Timeline>(
      MaterialPageRoute(
        builder: (_) => TemplateEditor(
          initial: initial,
          existingNames: c.state.templates
              .asMap()
              .entries
              .where((e) => e.key != index)
              .map((e) => e.value.name.toLowerCase())
              .toSet(),
        ),
      ),
    );
    if (result != null)
      await c.commit(
        (draft, _) => draft.saveTemplate(result, replacing: index),
      );
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
                        style: const TextStyle(color: Colors.orangeAccent),
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
    color: const Color(0xff131d1a),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Color(0xff27362f)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(padding: padding, child: child),
  );
  Widget label(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: muted,
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
          onPressed: action,
          icon: Icon(icon, size: 20),
          label: Text(text),
        )
      : OutlinedButton.icon(
          onPressed: action,
          icon: Icon(icon, size: 20),
          label: Text(text),
        );

  Widget live() {
    final s = c.state.session, t = s.timeline;
    final enabled = s.active && !c.busy && !c.corrupt;
    final ms = s.remaining(c.now);
    final phase = s.phase == 'active'
        ? (s.paused
              ? 'Paused'
              : ms == 0
              ? 'Time complete'
              : 'Live')
        : s.phase == 'ready'
        ? 'Ready'
        : s.phase == 'ended'
        ? 'Service ended'
        : 'Standing by';
    final timerPanel = panel(
      child: Column(
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
                  color: accent,
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
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 6),
            Center(
              child: FittedBox(
                child: Text(
                  s.formatted(c.now),
                  style: TextStyle(
                    fontSize: 86,
                    fontWeight: FontWeight.w300,
                    height: 1.3,
                    letterSpacing: -3,
                    color: ms == 0 && s.active
                        ? Colors.orangeAccent
                        : Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (ms / (t.segments[s.index].minutes * 60000)).clamp(
                  0.0,
                  1.0,
                ),
                minHeight: 4,
                color: accent,
                backgroundColor: const Color(0xff2c3a31),
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            const SizedBox(height: 18),
            const Text(
              'Load a timeline, keep the room on time, and send discreet cues to the stage.',
              style: TextStyle(color: muted),
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
            const Text(
              'Timing has not started. The simulator retains its previous output.',
              style: TextStyle(color: muted),
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                button(
                  s.paused ? 'Resume' : 'Pause',
                  s.paused ? Icons.play_arrow : Icons.pause,
                  enabled ? confirmPause : null,
                  primary: true,
                ),
                button('Add time', Icons.add, enabled ? addTime : null),
                button(
                  '−2 min',
                  Icons.remove,
                  enabled ? () => confirmAdjustment(-120) : null,
                ),
                button(
                  '+2 min',
                  Icons.add,
                  enabled ? () => confirmAdjustment(120) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                button(
                  'Advance…',
                  Icons.skip_next,
                  enabled && s.index + 1 < t!.segments.length ? advance : null,
                ),
                button(
                  'Undo advance',
                  Icons.undo,
                  enabled && s.undo != null ? undo : null,
                ),
              ],
            ),
            if (s.undo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Undo restores ${t!.segments[s.undo!.index].name}${s.fastUndo(c.now) ? ' · one tap available' : ' · confirmation required'}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('end-service'),
              onPressed: enabled
                  ? () async {
                      final rev = s.revision;
                      if (await confirm(
                        'End this service?',
                        'Stop timing, clear the active cue, and show “${t!.display.end.text}”.',
                        'End service',
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
                textStyle: const TextStyle(
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
          Row(
            children: [
              Expanded(child: label('Stage display')),
              const Text(
                '32 × 16',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LedMatrix(
            pixels: c.simulator.pixels,
            stale: s.held || s.disconnected,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                s.held || s.disconnected ? Icons.link_off : Icons.monitor,
                color: s.held || s.disconnected ? Colors.orangeAccent : accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.disconnected
                      ? 'Simulator disconnected'
                      : s.held
                      ? 'Simulator output held'
                      : 'Simulator connected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Intended: ${s.intended(c.now)?.text ?? 'No new output'}',
            style: const TextStyle(color: muted),
          ),
          Text(
            'Simulated: ${c.simulator.delivered?.text ?? 'Blank'}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Preview only · no physical sign connected\nPhysical delivery and readability are unverified.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          button(
            s.disconnected ? 'Reconnect simulator' : 'Disconnect simulator',
            s.disconnected ? Icons.link : Icons.link_off,
            c.busy || c.corrupt
                ? null
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
                const Icon(Icons.chat_bubble_outline, color: accent, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.hasAutomaticCue(c.now)
                ? 'Warning on display: ${s.automaticCue!.text}'
                : s.alert == null
                ? 'The right words, at the right moment.'
                : 'On display: ${s.alert!.text}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            s.alert == null
                ? 'Tap a cue to edit it. Send saves its text and formatting for every service.'
                : s.paused
                ? 'The underlying timer is paused.'
                : 'The countdown continues underneath this cue.',
            style: const TextStyle(color: muted, fontSize: 13),
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
                    enabled ? () => sendCue(e.value, cueIndex: e.key) : null,
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
                'New cue',
                Icons.edit_outlined,
                enabled ? () => sendCue(const TextLayout('')) : null,
              ),
              button(
                'Show timer',
                Icons.timer_outlined,
                enabled && (s.alert != null || s.hasAutomaticCue(c.now))
                    ? () => c.act('timer')
                    : null,
                primary: s.alert != null,
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
          if (s.held && (s.active || s.phase == 'ended'))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Review before restoring output',
                      style: TextStyle(
                        color: Colors.orangeAccent,
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
          if (constraints.maxWidth >= 850)
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
          if (s.active || s.phase == 'ended') ...[
            timingOverview(),
            const SizedBox(height: 16),
          ],
          if (s.timeline != null && (s.active || s.phase == 'ready')) ...[
            const SizedBox(height: 16),
            liveWarnings(),
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
                    style: const TextStyle(color: Colors.orangeAccent),
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
                  const SizedBox(height: 12),
                  ...t.segments.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${e.key + 1}'.padLeft(2, '0'),
                              style: TextStyle(
                                color: e.key == s.index ? accent : muted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value.name,
                              style: TextStyle(
                                color: e.key == s.index ? accent : Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            '${e.value.minutes} min',
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget templates() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Plan the service.',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'Templates are independent of a loaded or running service.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          button(
            'New timeline',
            Icons.add,
            c.busy || c.corrupt ? null : editTemplate,
            primary: true,
          ),
          button(
            'Import CSV / JSON',
            Icons.file_open_outlined,
            c.busy || c.corrupt ? null : importFile,
          ),
        ],
      ),
      const SizedBox(height: 24),
      ...c.state.templates.asMap().entries.map(
        (e) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.value.name,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${e.value.segments.length} segments · ${e.value.segments.fold<int>(0, (a, s) => a + s.minutes)} minutes',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 8),
                Text(
                  e.value.segments.map((s) => s.name).join(' → '),
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    button(
                      'Edit',
                      Icons.edit_outlined,
                      c.busy ? null : () => editTemplate(index: e.key),
                    ),
                    button(
                      'JSON',
                      Icons.ios_share,
                      () => export(e.value, 'json'),
                    ),
                    button(
                      'CSV',
                      Icons.ios_share,
                      () => export(e.value, 'csv'),
                    ),
                    TextButton.icon(
                      onPressed: c.busy
                          ? null
                          : () async {
                              if (await confirm(
                                'Delete ${e.value.name}?',
                                'Delete this saved template? Any loaded service snapshot remains unchanged.',
                                'Delete template',
                              )) {
                                if (settingsOwner == 'template:${e.value.name}')
                                  setState(() => settingsOwner = 'defaults');
                                await c.commit(
                                  (draft, _) => draft.templates.removeAt(e.key),
                                );
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget settings() {
    final index = c.state.templates.indexWhere(
      (t) => 'template:${t.name}' == settingsOwner,
    );
    final d = index < 0 ? c.state.defaults : c.state.templates[index].display;
    Future<void> save(DisplaySettings next) => c
        .commit((draft, _) {
          if (index < 0) {
            draft.defaults = next;
          } else {
            final t = draft.templates[index];
            draft.templates[index] = Timeline(t.name, t.segments, next);
          }
        })
        .then((_) {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Make every pixel count.',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Display settings affect future services. The current snapshot stays unchanged.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: index < 0 ? 'defaults' : settingsOwner,
          decoration: const InputDecoration(labelText: 'Editing'),
          items: [
            const DropdownMenuItem(
              value: 'defaults',
              child: Text('Defaults for new templates'),
            ),
            ...c.state.templates.map(
              (t) => DropdownMenuItem(
                value: 'template:${t.name}',
                child: Text(
                  'Template: ${t.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: c.busy ? null : (v) => setState(() => settingsOwner = v!),
        ),
        const SizedBox(height: 20),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('At zero'),
              const SizedBox(height: 8),
              Text(
                d.zero?.text ?? '00:00',
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  button(
                    'Use 00:00',
                    Icons.timer_outlined,
                    c.busy
                        ? null
                        : () => save(
                            DisplaySettings(
                              end: d.end,
                              cues: d.cues,
                              warnings: d.warnings,
                            ),
                          ),
                  ),
                  button(
                    'Custom text',
                    Icons.edit_outlined,
                    c.busy
                        ? null
                        : () async {
                            final l = await compose(
                              d.zero ?? const TextLayout("TIME'S UP"),
                              'Zero-time screen',
                              'Save zero screen',
                            );
                            if (l != null)
                              await save(
                                DisplaySettings(
                                  zero: l,
                                  end: d.end,
                                  cues: d.cues,
                                  warnings: d.warnings,
                                ),
                              );
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('When the service ends'),
              const SizedBox(height: 8),
              Text(d.end.text, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 12),
              button(
                'Edit end screen',
                Icons.edit_outlined,
                c.busy
                    ? null
                    : () async {
                        final l = await compose(
                          d.end,
                          'End screen',
                          'Save end screen',
                        );
                        if (l != null)
                          await save(
                            DisplaySettings(
                              zero: d.zero,
                              end: l,
                              cues: d.cues,
                              warnings: d.warnings,
                            ),
                          );
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: const Text(
            'Stage cues are shared across all services. Edit a cue or add a new one on Live; Send saves every formatting choice.',
          ),
        ),
        const SizedBox(height: 16),
        warningSettings(d, save),
        const SizedBox(height: 16),
        timesFontSettings(),
        const SizedBox(height: 16),
        ledShapeSettings(),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Prototype display profile'),
              const SizedBox(height: 10),
              const Text(
                '32 × 16 · monochrome\nFonts: Cuekeeper Matrix, Cuekeeper Sq-Matrix, imported Times New Roman\nCountdown: Cuekeeper Matrix · 14-pixel height\nPhysical controller: not configured',
              ),
              const SizedBox(height: 12),
              const Text(
                'The simulator is a visual testing tool. It cannot grant physical-layout approval or measure Wi-Fi/sign latency. Physical Test on Sign is unavailable until a verified adapter is added.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 12),
              button('Test on sign — unavailable', Icons.developer_board, null),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Cuekeeper',
                ),
                child: const Text('Font and software licenses'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: accent),
            SizedBox(width: 10),
            Text(
              'cuekeeper',
              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -.5),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xff39533c)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'PROTOTYPE',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
      body: !c.ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: panel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.error!,
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (c.retry != null)
                                    TextButton(
                                      onPressed: c.busy
                                          ? null
                                          : () => c.retry!(),
                                      child: const Text('Retry failed action'),
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
                                      child: const Text('Reset local data…'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        AbsorbPointer(
                          absorbing: c.corrupt,
                          child: page == 0
                              ? live()
                              : page == 1
                              ? templates()
                              : page == 2
                              ? settings()
                              : reports(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (v) => setState(() => page = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radio_button_checked),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_timeline_outlined),
            label: 'Templates',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Display'),
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
  const TextComposer({
    super.key,
    required this.initial,
    required this.title,
    required this.button,
  });
  @override
  State<TextComposer> createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {
  late TextEditingController text;
  late bool bold, italic;
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
    if (request.font == 'times_new_roman' &&
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
    if (font == 'times_new_roman' && fontError != null) error = fontError;
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
              const Text(
                'NOT TESTED ON SIGN · simulator preview',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
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
                  if (font == 'times_new_roman') height = 2;
                  watch.reset();
                }),
              ),
              if (font == 'times_new_roman')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Genuine imported font · 14 px recommended. Compact text has fewer serif details.',
                    style: TextStyle(color: muted),
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
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: error == null
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
  const TemplateEditor({
    super.key,
    required this.initial,
    required this.existingNames,
  });
  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late TextEditingController name;
  late List<Segment> segments;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial.name);
    segments = [...widget.initial.segments];
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
    String? issue;
    final result = await showDialog<Segment>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
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
              if (issue != null)
                Text(
                  issue!,
                  style: const TextStyle(color: Colors.orangeAccent),
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
    appBar: AppBar(title: const Text('Timeline editor')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Template name'),
          ),
          const SizedBox(height: 16),
          Text(
            '${segments.length} segments · ${segments.fold<int>(0, (a, s) => a + s.minutes)} minutes',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hold a row to drag it into a new position.',
            style: TextStyle(color: muted, fontSize: 12),
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
                subtitle: Text('${segments[i].minutes} minutes'),
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
          const SizedBox(height: 24),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          FilledButton.icon(
            onPressed: () {
              try {
                final t = Timeline.fromJson(
                  Timeline(
                    name.text,
                    segments,
                    widget.initial.display,
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
            label: const Text('Save timeline'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cue and screen styles can be changed in Display after saving. Changes never alter a loaded service.',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );
}
