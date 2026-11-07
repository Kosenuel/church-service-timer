import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

/// The built-in practice program: never saved to Programs, and its name
/// matches no saved program, so "last used" dates are left alone.
const practiceProgramName = 'Practice service';
Timeline practiceProgram() => Timeline(practiceProgramName, const [
  Segment('Welcome', 3),
  Segment('Worship', 5),
  Segment('Sermon', 8),
  Segment('Closing', 1),
], DisplaySettings());

/// Practice runs five times faster than real time, so overtime and
/// warnings appear in seconds.
const practiceRate = 5;

class PracticeStep {
  final String id, title, how;
  const PracticeStep(this.id, this.title, this.how);
}

const practiceSteps = [
  PracticeStep(
    'start',
    'Start the service',
    'Tap Start first segment. The countdown begins.',
  ),
  PracticeStep(
    'pause',
    'Pause, then resume',
    'Tap Pause, then Resume. Paused time is kept, not lost.',
  ),
  PracticeStep(
    'adjust',
    'Add 2 minutes, then take them away',
    'Tap +2 min and confirm, then −2 min. Only this segment changes.',
  ),
  PracticeStep(
    'next',
    'Go to the next segment, then Undo',
    'Tap Next, then Undo. Undo returns to the segment with its time.',
  ),
  PracticeStep(
    'cue',
    'Show a cue, then the timer again',
    'Tap a cue in Stage cues, then Show timer.',
  ),
  PracticeStep(
    'blank',
    'Blank the screen, then bring it back',
    'Tap Blank screen, then tap it again.',
  ),
  PracticeStep(
    'overtime',
    'See overtime',
    'Let a segment run out. The time turns red and counts up; nothing stops.',
  ),
  PracticeStep(
    'end',
    'End the service',
    'Tap End service and confirm. In practice, no report is saved.',
  ),
];

/// Guided practice: a short built-in service on the simulator, with steps
/// ticked off as the operator does them, in any order. It saves no report
/// and changes no programs, reports or settings except the "practised" note.
class PracticeController {
  final AppController app;
  PracticeController(this.app);

  final done = <String>{};
  final skipped = <String>{};
  int? startedMono;
  bool _paused = false,
      _added = false,
      _advanced = false,
      _cued = false,
      _blanked = false;

  /// Shown when practice ends, then cleared by the page.
  ({int done, int total, int ms})? finished;

  /// Whether the current session is a practice run.
  bool get active {
    final s = app.state.session;
    return app.ready &&
        s.noReport &&
        s.timeline?.name == practiceProgramName &&
        (s.phase == 'ready' || s.active);
  }

  PracticeStep? get current => practiceSteps
      .where((s) => !done.contains(s.id) && !skipped.contains(s.id))
      .firstOrNull;
  int get completed => done.length;

  /// Why practice can't start now, or null.
  String? get blocker {
    final s = app.state.session;
    if (!app.ready) return 'Starting up…';
    if (app.pairing.joined)
      return 'Practice runs on the device that controls the service.';
    if (s.active || s.phase == 'ready')
      return 'End or cancel the current service first.';
    if (app.busy || app.reportSavePending) return 'Wait a moment.';
    return null;
  }

  /// Loads the practice program at 5× with no report. The page makes sure
  /// the Simulator is the display first.
  Future<bool> start() async {
    if (blocker != null || app.destination != 'simulator') return false;
    done.clear();
    skipped.clear();
    _paused = _added = _advanced = _cued = _blanked = false;
    finished = null;
    if (!await app.act('load', value: practiceProgram())) return false;
    if (!await app.commit((draft, _) {
      draft.session.noReport = true;
      draft.session.rate = practiceRate;
    }))
      return false;
    startedMono = app.now.mono;
    app.notifyChanged();
    return true;
  }

  void skip() {
    final step = current;
    if (step == null) return;
    skipped.add(step.id);
    app.notifyChanged();
  }

  /// Leaves practice at once, discarding the run.
  Future<void> leave() async {
    if (!active) return;
    final ready = app.state.session.phase == 'ready';
    startedMono = null;
    done.clear();
    skipped.clear();
    await app.act(ready ? 'cancelReady' : 'end');
    finished = null;
    app.notifyChanged();
  }

  /// Called after each successful action, and on each tick for overtime.
  Future<void> observe(String action, dynamic value) async {
    if (startedMono == null) return;
    final s = app.state.session;
    // Change in Ready swapped in a real program: that is no longer
    // practice, so its report is saved and it runs in real time.
    if (action == 'load' && s.timeline?.name != practiceProgramName) {
      startedMono = null;
      done.clear();
      skipped.clear();
      await app.commit((draft, _) {
        draft.session.noReport = false;
        draft.session.rate = 1;
      });
      return;
    }
    void tick(String id) => done.add(id);
    switch (action) {
      case 'start':
        tick('start');
      case 'pause':
        if (s.paused) _paused = true;
        if (!s.paused && _paused) tick('pause');
      case 'adjust':
        final delta = value as int? ?? 0;
        if (delta > 0) _added = true;
        if (delta < 0 && _added) tick('adjust');
      case 'advance':
      case 'jump':
        _advanced = true;
      case 'undo':
        if (_advanced) tick('next');
      case 'cue':
        _cued = true;
      case 'timer':
      case 'clearCue':
        if (_cued) tick('cue');
      case 'blank':
        if (s.outputBlank) _blanked = true;
        if (!s.outputBlank && _blanked) tick('blank');
      case 'end':
        tick('end');
        finished = (
          done: done.length,
          total: practiceSteps.length,
          ms: app.now.mono - (startedMono ?? app.now.mono),
        );
        startedMono = null;
        await app.commit((draft, at) => draft.practisedWall = at.wall);
    }
    checkOvertime();
  }

  void checkOvertime() {
    // After a restart mid-practice, pick the run up again.
    if (startedMono == null && active) startedMono = app.now.mono;
    if (startedMono == null || done.contains('overtime')) return;
    final s = app.state.session;
    if (s.active && s.overtime(app.now) > 0) {
      done.add('overtime');
      app.notifyChanged();
    }
  }
}
