import 'dart:async';

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:flutter/foundation.dart';

/// What the second screen can show, by the name [StageSurface] knows it
/// by, with the words the operator chooses from.
const secondScreenLayouts = {
  'timer': 'Timer only',
  'current': 'Timer and segment name',
  'next': 'Timer and next segment',
};

/// `Screen 2 · 3840 × 2160`: a screen as the operator is told about it.
String stageMonitorLabel(StageMonitor screen) =>
    'Screen ${screen.index + 1} · '
    '${screen.rect[2] - screen.rect[0]} × ${screen.rect[3] - screen.rect[1]}';

/// The operator's choices for the second screen of this computer: which
/// monitor was used last, whether it opens when a service starts, and what
/// it shows. They are kept on this computer only, because another PC has
/// other screens. Opening and closing stay with [StageOutputHost].
class SecondScreen extends ChangeNotifier {
  final StageOutputHost host;
  final DevicePort port;
  SecondScreen(this.host, this.port) {
    host.addListener(_hostChanged);
  }

  /// The monitor last shown on: its place on the desktop and its number.
  List<int>? rememberedRect;
  int? rememberedIndex;

  /// Whether the stage was showing there when this was last saved.
  bool wasShowing = false;

  /// "Open the second screen when a service starts".
  bool openOnStart = false;
  String layout = 'timer';

  /// A quiet word for the status line: why it did not open with the
  /// service. It goes once that screen is connected again.
  String? get note => remembered == null ? _note : null;
  String? _note;

  /// The monitor the operator picked on Live, when there are several.
  int? chosenIndex;

  bool _disposed = false;

  Future<void> load() async {
    try {
      final saved = await port.secondScreenSettings();
      final rect = saved['rect'];
      if (rect is List && rect.length == 4 && rect.every((v) => v is int)) {
        rememberedRect = rect.cast<int>();
        rememberedIndex = saved['index'] is int ? saved['index'] as int : null;
      }
      wasShowing = saved['showing'] == true;
      openOnStart = saved['openOnStart'] == true;
      if (secondScreenLayouts.containsKey(saved['layout'])) {
        layout = saved['layout'] as String;
      }
    } catch (_) {
      // Unreadable choices are the same as none.
    }
    _changed();
  }

  Future<void> _save() async {
    try {
      await port.saveSecondScreenSettings({
        'rect': rememberedRect,
        'index': rememberedIndex,
        'showing': wasShowing,
        'openOnStart': openOnStart,
        'layout': layout,
      });
    } catch (_) {
      // The choice still holds until the app closes.
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Every screen except the operator's own.
  List<StageMonitor> get others =>
      host.monitors().where((s) => !s.primary).toList();

  /// The screen the stage is on now, if it is still connected.
  StageMonitor? get showingOn => host.open
      ? host.monitors().where((s) => s.index == host.monitor).firstOrNull
      : null;

  /// The remembered monitor, if it is connected now: the screen at the
  /// same place and size, whatever number Windows gives it today. Never
  /// the operator's own screen.
  StageMonitor? get remembered {
    final rect = rememberedRect;
    if (rect == null) return null;
    final same = others.where((s) => listEquals(s.rect, rect)).toList();
    return same.where((s) => s.index == rememberedIndex).firstOrNull ??
        same.firstOrNull;
  }

  /// The screen the one button on Live would show on: the one picked
  /// there, else the remembered one, else the first.
  StageMonitor? get target {
    final screens = others;
    return screens.where((s) => s.index == chosenIndex).firstOrNull ??
        remembered ??
        screens.firstOrNull;
  }

  void choose(StageMonitor screen) {
    chosenIndex = screen.index;
    _changed();
  }

  Future<void> show(StageMonitor screen) async {
    _note = null;
    chosenIndex = screen.index;
    await host.show(screen);
    if (host.open) {
      rememberedRect = List.of(screen.rect);
      rememberedIndex = screen.index;
      wasShowing = true;
      await _save();
    }
    _changed();
  }

  Future<void> stop() async {
    _note = null;
    wasShowing = false;
    await host.close();
    await _save();
    _changed();
  }

  /// The stage window closed by itself: Esc on that screen, or its
  /// monitor was unplugged.
  void _hostChanged() {
    if (host.open || !wasShowing || _disposed) return;
    wasShowing = false;
    unawaited(_save());
  }

  Future<void> setOpenOnStart(bool on) async {
    openOnStart = on;
    if (!on) _note = null;
    await _save();
    _changed();
  }

  Future<void> setLayout(String value) async {
    if (!secondScreenLayouts.containsKey(value)) return;
    layout = value;
    await _save();
    _changed();
  }

  /// A service has started. With the setting on, shows the stage on the
  /// remembered monitor when it is connected and nothing is showing yet.
  Future<void> serviceStarted() async {
    if (!openOnStart || host.open) return;
    final screen = remembered;
    if (screen == null) {
      _note = rememberedRect == null
          ? 'Not opened: no screen has been chosen yet.'
          : 'Not opened: the screen used last time is not connected.';
      _changed();
      return;
    }
    await show(screen);
  }

  @override
  void dispose() {
    _disposed = true;
    host.removeListener(_hostChanged);
    super.dispose();
  }
}
