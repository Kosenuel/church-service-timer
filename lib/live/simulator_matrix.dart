import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The LED simulator on Live.
///
/// The app's clock ticks about ten times a second, and later when it is
/// busy saving, so text scrolling across the simulator by those ticks
/// alone moves one column and then two, and stops now and then. While text
/// scrolls or flashes, this view moves it on by itself, at the moment each
/// column is due, from the app's last clock reading and the time since, so
/// it steps at the sign's own steady pace whatever the frame rate. It is
/// drawn again only when a column has changed. Everything else is drawn as
/// before, at each tick.
class SimulatorMatrix extends StatefulWidget {
  final AppController controller;
  const SimulatorMatrix({super.key, required this.controller});

  /// How far past the app's last clock reading the picture may run on.
  static const reach = 1500;

  @override
  State<SimulatorMatrix> createState() => _SimulatorMatrixState();
}

class _SimulatorMatrixState extends State<SimulatorMatrix> {
  AppController get c => widget.controller;
  List<bool> _pixels = const [];
  Timer? _next;

  /// The simulator holds its last picture while the service is held.
  bool _stale = false;

  /// The app's last clock reading, and how long it is since then.
  int _anchor = 0, _since = 0;

  /// The time last drawn: never earlier than the one before, so a clock
  /// reading that arrives late never steps the text backwards.
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    c.previewClock.addListener(_reading);
    _reading();
  }

  @override
  void didUpdateWidget(SimulatorMatrix oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.previewClock.removeListener(_reading);
      c.previewClock.addListener(_reading);
    }
    _reading();
  }

  /// A new reading of the app's clock, at a tick.
  void _reading() {
    final sim = c.simulator;
    final s = c.state.session;
    final stale = s.held || s.disconnected, held = stale != _stale;
    _stale = stale;
    _anchor = sim.drawnAt;
    _since = 0;
    // A late reading holds the text still until it catches up; a very
    // different one (a new cue, a new service) is taken as it is.
    if (_anchor > _shown || _shown - _anchor > SimulatorMatrix.reach) {
      _shown = _anchor;
    }
    _next?.cancel();
    _next = null;
    if (sim.moving && !_stale) {
      _show(sim.pixelsAt(_shown), always: held);
      _schedule();
    } else {
      _show(sim.pixels, always: held);
    }
  }

  /// Waits for the next column, or the next half second of a flash.
  void _schedule() {
    final due = c.simulator.nextChangeAfter(_shown);
    if (due == null) return;
    final wait = due - _anchor - _since;
    if (_since + wait > SimulatorMatrix.reach) return;
    _next = Timer(Duration(milliseconds: wait < 0 ? 0 : wait), () {
      _since += wait < 0 ? 0 : wait;
      _shown = _anchor + _since;
      _show(c.simulator.pixelsAt(_shown));
      _schedule();
    });
  }

  void _show(List<bool> pixels, {bool always = false}) {
    if (!mounted) return;
    if (_pixels.isEmpty) {
      // Before the first build.
      _pixels = pixels;
    } else if (always || !listEquals(pixels, _pixels)) {
      setState(() => _pixels = pixels);
    }
  }

  @override
  void dispose() {
    c.previewClock.removeListener(_reading);
    _next?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LedMatrix(pixels: _pixels, stale: _stale);
}
