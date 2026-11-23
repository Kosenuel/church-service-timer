import 'dart:async';
import 'dart:io';

import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/windows/stage_output.dart';
import 'package:church_service_timer/windows/win32_api.dart' as win32;
import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:flutter/services.dart';

/// The stage window: black, full screen, with the same picture a paired
/// stage screen shows. Esc closes it; so does closing the main app.
class StageOutputScreen extends StatelessWidget {
  final StageFeed feed;
  final VoidCallback onClose;
  const StageOutputScreen({
    super.key,
    required this.feed,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        onClose();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: MouseRegion(
      // No pointer over the picture the congregation's speakers see.
      cursor: SystemMouseCursors.none,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: feed,
          builder: (context, _) {
            final data = feed.data;
            // The theme's background while the clock shows, black otherwise.
            return ColoredBox(
              color: stageBackdropOf(data),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: data == null
                      ? const Text(
                          'Waiting for Church Service Timer…',
                          style: TextStyle(
                            fontFamily: stageFontFamily,
                            color: Colors.white70,
                            fontSize: 20,
                          ),
                        )
                      : StageSurface(data: data, stale: feed.stale),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// The stage window's theme: the app's, with all its text in the face the
/// stage screens use, so nothing in the window falls back to the system's
/// own font.
ThemeData stageWindowTheme() {
  final theme = appTheme('midnight_lime');
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: stageFontFamily),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: stageFontFamily),
  );
}

class StageOutputApp extends StatelessWidget {
  final StageFeed feed;
  final VoidCallback onClose;
  const StageOutputApp({super.key, required this.feed, required this.onClose});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stage output',
    debugShowCheckedModeBanner: false,
    theme: stageWindowTheme(),
    home: LedAppearance(
      shape: 'square',
      child: StageOutputScreen(feed: feed, onClose: onClose),
    ),
  );
}

/// Runs this copy of the app as the stage window. Called from `main` when
/// the app is started with `--stage-output`.
Future<void> runStageOutput(List<String> arguments) async {
  final port = int.tryParse(stageArgument(arguments, 'port') ?? '');
  final token = stageArgument(arguments, 'token');
  final rect = stageRect(arguments);
  if (port == null || token == null || token.isEmpty) exit(64);
  try {
    final window = win32.appWindow();
    win32.setWindowTitle(window, 'Stage output · Church Service Timer');
    if (rect != null) {
      win32.fillScreen(window, rect, topmost: arguments.contains('--topmost'));
    }
    // A projector must not blank or sleep while it shows the stage.
    win32.setExecutionState(system: true, display: true);
  } catch (_) {
    // Without these the stage still shows, in an ordinary window.
  }
  // Moving to a screen with a different scale makes Windows resize the
  // window once more, so the fit is applied again after it has settled.
  void refit() {
    if (rect == null) return;
    try {
      win32.fillScreen(
        win32.appWindow(),
        rect,
        topmost: arguments.contains('--topmost'),
      );
    } catch (_) {}
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => refit());
  Timer(const Duration(milliseconds: 600), refit);
  final feed = StageFeed();
  feed.addListener(() {
    // The main app closed, or closed this window: nothing left to show.
    if (feed.closed) exit(0);
  });
  runApp(StageOutputApp(feed: feed, onClose: () => exit(0)));
  await feed.connect(port, token);
}
