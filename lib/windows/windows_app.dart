import 'dart:io';

import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/desktop_files.dart';
import 'package:church_service_timer/windows/file_drop.dart';
import 'package:church_service_timer/windows/single_instance.dart';
import 'package:church_service_timer/windows/win32_api.dart' as win32;
import 'package:church_service_timer/windows/window_memory.dart';
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:church_service_timer/windows/windows_system.dart';
import 'package:flutter/widgets.dart';

/// Where the app keeps its data on Windows: the user's roaming app-data
/// folder, the same place path_provider gives the diagnostics recording.
Directory windowsDataDirectory() {
  final base =
      Platform.environment['APPDATA'] ??
      '${Platform.environment['USERPROFILE'] ?? '.'}\\AppData\\Roaming';
  return Directory('$base\\I-Proton\\Church Service Timer');
}

class _Win32Window implements PinnableWindow, FillableWindow {
  @override
  WindowPlace? read() {
    try {
      return win32.windowPlacement(win32.appWindow());
    } catch (_) {
      return null;
    }
  }

  @override
  bool restore(WindowPlace place) {
    try {
      return win32.restoreWindowPlacement(
        win32.appWindow(),
        place.frame,
        maximised: place.maximised,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  bool pin(bool onTop) {
    try {
      return win32.pinWindow(win32.appWindow(), onTop: onTop);
    } catch (_) {
      return false;
    }
  }

  @override
  bool fill() {
    try {
      return win32.enterFullScreen(win32.appWindow());
    } catch (_) {
      return false;
    }
  }

  @override
  void unfill(WindowPlace place) {
    try {
      win32.leaveFullScreen(
        win32.appWindow(),
        place.frame,
        maximised: place.maximised,
      );
    } catch (_) {}
  }
}

/// The program file named on the command line, if any: what Windows passes
/// when a `.json` or `.csv` is opened with the app.
String? fileArgument(List<String> arguments) {
  for (final argument in arguments) {
    if (argument.startsWith('-')) continue;
    final lower = argument.toLowerCase();
    if (lower.endsWith('.json') || lower.endsWith('.csv')) return argument;
  }
  return null;
}

/// Passed by the runner when it has already opened the window at its saved
/// place.
const windowPlacedArgument = '--window-placed';

/// Builds the Windows port, or returns null when another copy of the app
/// is already running (it has then been asked to come forward and this
/// copy should close).
WindowsPort? startWindowsPort(List<String> arguments) {
  final dataDir = windowsDataDirectory();
  final instance = SingleInstance(dataDir);
  final file = fileArgument(arguments);
  if (!instance.acquire()) {
    instance.handOver(file);
    return null;
  }
  const system = WindowsSystem();
  final memory = WindowMemory(
    JsonPrefs(File('${dataDir.path}\\window.json')),
    _Win32Window(),
    metrics: () {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      return (
        scale: view.devicePixelRatio,
        width: view.physicalSize.width,
        height: view.physicalSize.height,
      );
    },
  );
  final fonts =
      '${File(Platform.resolvedExecutable).parent.path}\\data\\display_fonts\\tinos';
  final port = WindowsPort(
    dataDir: dataDir,
    monotonicMs: win32.tickCount64,
    protector: const DpapiProtector(),
    dialogs: const SystemFileDialogs(),
    system: system,
    loadTinosFace: (style) => File('$fonts\\Tinos-$style.ttf').readAsBytes(),
    stageLauncher: const WindowsStageLauncher(),
    miniWindow: memory,
    fullScreenWindow: memory,
  );
  if (file != null) port.offerIncomingFile(file);
  instance.listen((path) {
    if (path == null) {
      system.raise();
    } else {
      port.offerIncomingFile(path);
    }
  });
  // A file dropped on the window (windows/runner/flutter_window.cpp).
  listenForDroppedFiles(port.filesDropped);
  // The runner opens the window where it was last time, before Flutter
  // starts, and says so (windows/runner/main.cpp). Only if it could not is
  // the window moved from here: moving a window that is already drawing,
  // onto a screen with a different scale, makes Windows resize it again.
  final placed = arguments.contains(windowPlacedArgument);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!placed) {
      try {
        await memory.restore();
      } catch (_) {}
    }
    memory.start();
  });
  return port;
}
