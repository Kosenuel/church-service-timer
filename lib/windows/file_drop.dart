import 'package:flutter/services.dart';

/// The channel the Windows runner uses to tell the app about its window
/// (windows/runner/flutter_window.cpp).
const windowChannel = MethodChannel('church_service_timer/window');

/// What the app says when a drop is not one program file.
const dropOneProgramFile = 'Drop one program file (.json or .csv).';

/// The one program file among [paths] dropped on the window, or null when
/// the drop is anything else: several files, a folder, or another kind of
/// file.
String? droppedProgramFile(List<String> paths) {
  if (paths.length != 1) return null;
  final lower = paths.single.toLowerCase();
  return lower.endsWith('.json') || lower.endsWith('.csv')
      ? paths.single
      : null;
}

/// Passes files dropped on the window to [onDrop]: the runner sends
/// `filesDropped` with the list of paths.
void listenForDroppedFiles(
  void Function(List<String> paths) onDrop, {
  MethodChannel channel = windowChannel,
}) {
  channel.setMethodCallHandler((call) async {
    if (call.method != 'filesDropped') return;
    final paths = call.arguments;
    if (paths is List) onDrop(paths.whereType<String>().toList());
  });
}
