import 'dart:async';
import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';

/// "Check this service": runs a program through at high speed on the
/// Simulator, then lists what fired. See [ServiceCheckRun].
extension ServiceCheckViews on HomeState {
  /// Why a check cannot start now, or null when it can.
  String? get serviceCheckUnavailable => controlsLocked
      ? 'Unlock the controls to check a service.'
      : c.serviceCheckUnavailable;

  /// Opens the check for [t]. Nothing is asked first: it never touches
  /// the timer, the displays or the reports.
  Future<void> checkService(Timeline t) async {
    final reason = serviceCheckUnavailable;
    if (reason != null) {
      await showError(reason);
      return;
    }
    try {
      // A program the service could not start, the check cannot either.
      validateProgramDuration(t);
    } catch (e) {
      await showError('$e');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ServiceCheckPage(controller: c, program: t),
      ),
    );
  }

  /// The button that starts a check, for Live and Programs.
  Widget checkServiceButton(Timeline t) => OutlinedButton.icon(
    key: const ValueKey('check-service'),
    onPressed: serviceCheckUnavailable == null && !c.busy
        ? () => checkService(t)
        : null,
    icon: const Icon(Icons.fact_check_outlined),
    label: const Text('Check this service'),
  );
}

/// The check while it runs, then its checklist.
class ServiceCheckPage extends StatefulWidget {
  final AppController controller;
  final Timeline program;

  /// How much real time each tick moves the check on.
  static const tickMs = 50;
  const ServiceCheckPage({
    super.key,
    required this.controller,
    required this.program,
  });
  @override
  State<ServiceCheckPage> createState() => ServiceCheckPageState();
}

class ServiceCheckPageState extends State<ServiceCheckPage> {
  late ServiceCheckRun run;
  Timer? _timer;
  bool stopped = false;

  /// Planned start and finish, worked out when the check begins.
  late int startWall, finishWall;
  bool scheduled = false;

  // The LED preview's own animation: real time since the text changed.
  String _signature = '';
  int _shownAt = 0;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_appChanged);
    _begin();
  }

  void _begin() {
    final now = c.now;
    run = ServiceCheckRun(widget.program, now);
    // A service set up on Live for this program with a start time uses
    // it; otherwise the finish is worked out from now.
    final s = c.state.session;
    final at = s.phase == 'ready' && s.timeline?.id == widget.program.id
        ? s.startsAtWall
        : null;
    scheduled = at != null;
    startWall = at ?? now.wall;
    finishWall = startWall + run.session.plannedMs;
    stopped = false;
    _signature = '';
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: ServiceCheckPage.tickMs),
      (_) => _tick(),
    );
  }

  void _tick() {
    if (!mounted) return;
    setState(() => run.step(ServiceCheckPage.tickMs));
    if (run.done) _timer?.cancel();
  }

  /// A real service has started (from a paired phone, say): the check
  /// gives way at once.
  void _appChanged() {
    if (!mounted || run.done || stopped) return;
    if (c.serviceCheckUnavailable != null && c.state.session.active) {
      stop();
    }
  }

  void stop() {
    _timer?.cancel();
    setState(() => stopped = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_appChanged);
    super.dispose();
  }

  bool get locked => c.uiLocked;

  /// Whether a warning shows just now. A scrolling one is shown still,
  /// because the check holds it for less than a second, too short for it
  /// to scroll across.
  bool get _warning => run.session.hasAutomaticCue(run.now);

  /// What the stage simulator shows of the check, as a stage screen gets it.
  Json stageSnapshot() => {
    ...c.pairedSnapshot(false, session: run.session, at: run.now)
      ..remove('rundown')
      ..remove('connection'),
    'stageSharing': true,
    'stageLayout': c.state.simulatorLayout,
    if (_warning) 'effect': 'static',
  };

  List<bool> ledPixels() {
    final shown = run.session.intended(run.now);
    final layout = shown != null && _warning && shown.effect == 'scroll'
        ? TextLayout.fromJson({...shown.toJson(), 'effect': 'static'})
        : shown;
    final signature = jsonEncode(layout?.toJson());
    if (signature != _signature) {
      _signature = signature;
      _shownAt = run.elapsedMs;
    }
    return renderPixels(layout, run.elapsedMs - _shownAt);
  }

  Widget preview() {
    final stage = c.state.simulatorKind == 'stage';
    return Semantics(
      key: const ValueKey('service-check-preview'),
      label: stage ? 'Stage simulator preview' : 'LED simulator preview',
      child: ExcludeSemantics(
        child: stage
            ? AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: StageSurface(data: stageSnapshot(), stale: false),
                  ),
                ),
              )
            : LedMatrix(pixels: ledPixels(), hardware: false, stale: false),
      ),
    );
  }

  Widget running(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final share = run.expectedMs == 0
        ? 1.0
        : (run.elapsedMs / run.expectedMs).clamp(0.0, 1.0);
    final cue = run.holding ? run.fired.lastOrNull : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The whole service at ${run.rate}× speed, on the ${c.state.simulatorKind == 'stage' ? 'stage' : 'LED'} simulator only. It stops for a moment on each warning, shown still so it can be read. Nothing is sent to the LED sign or to screens, and no report is saved.',
          style: text.bodyMedium?.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 16),
        preview(),
        const SizedBox(height: 16),
        Text(
          run.progress,
          key: const ValueKey('service-check-progress'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          cue != null
              ? 'Warning: ${cue.rule.cue.text} · ${formatTime(cue.remainingMs!)} left · ${cue.where}'
              : '${formatTime(run.session.remaining(run.now))} left in this segment',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cue != null ? colors.warning : colors.muted),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: share),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('service-check-stop'),
            onPressed: locked ? null : stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop check'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          deviceText('Tap Stop check to end it at any time.'),
          style: text.bodySmall?.copyWith(color: colors.muted),
        ),
      ],
    );
  }

  Widget checklist(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final t = widget.program;
    final muted = text.bodySmall?.copyWith(color: colors.muted);
    Widget row(IconData icon, Color color, String line, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(line)),
        ],
      ),
    );
    final fired = run.fired.length, missed = run.unreachable.length;
    final zero = t.display.zero;
    return Column(
      key: const ValueKey('service-check-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          stopped ? 'Check stopped' : 'Check complete',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          [
            '${plural(fired, 'warning')} fired',
            if (missed > 0) '$missed could not fire',
          ].join(' · '),
          key: const ValueKey('service-check-summary'),
          style: TextStyle(color: missed > 0 ? colors.warning : colors.muted),
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < t.segments.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                Text(
                  [
                    '${i + 1}. ${t.segments[i].name}',
                    if (t.segments[i].speaker.isNotEmpty) t.segments[i].speaker,
                    t.segments[i].durationText,
                  ].join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final w in run.firedIn(i))
                  row(
                    Icons.check_circle_outline,
                    colors.success,
                    '${w.rule.cue.text} · at ${formatTime(w.remainingMs!)} left · ${w.where}',
                  ),
                for (final w in run.unreachableIn(i))
                  row(
                    Icons.warning_amber_rounded,
                    colors.warning,
                    '${w.rule.cue.text} cannot fire: it is set for ${formatTime(w.rule.seconds * 1000)} left and this segment is only ${t.segments[i].durationText}',
                  ),
                if (run.firedIn(i).isEmpty && run.unreachableIn(i).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      stopped && i >= run.session.index
                          ? 'Not reached'
                          : 'No automatic warnings',
                      style: muted,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Overtime',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                zero == null
                    ? 'If a segment runs over, the display stays at 00:00 until you move on, and Live counts the time over.'
                    : 'If a segment runs over, the display shows ${zero.text} until you move on, and Live counts the time over.',
              ),
              const Divider(height: 24),
              Text(
                'Planned finish',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                scheduled
                    ? '${clockLabel(finishWall)}: ${durationLabel(run.session.plannedMs)} from the start at ${clockLabel(startWall)}.'
                    : '${clockLabel(finishWall)} if it started now: ${durationLabel(run.session.plannedMs)} in all.',
                key: const ValueKey('service-check-finish'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This was a check only. Nothing was sent to the LED sign or to screens, and no report was saved.',
          style: muted,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              key: const ValueKey('service-check-done'),
              onPressed: locked ? null : () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('service-check-again'),
              onPressed: locked || c.serviceCheckUnavailable != null
                  ? null
                  : () => setState(_begin),
              icon: const Icon(Icons.replay),
              label: const Text('Check again'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Locked controls block every input, going back included.
    canPop: !locked,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Check ${widget.program.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: run.done || stopped
                  ? checklist(context)
                  : running(context),
            ),
          ),
        ),
      ),
    ),
  );
}
