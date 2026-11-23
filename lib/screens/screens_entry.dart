import 'dart:async';

import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:flutter/material.dart';

/// The ways to the Screens panel from Live: a button beside Change display
/// and Slides, or, in a desktop layout that keeps its panes to the window,
/// an icon in the header beside the Slides one.
extension ScreensEntry on HomeState {
  void openScreens() => unawaited(openScreensPanel(context, c));

  Widget screensButton() => OutlinedButton.icon(
    key: const ValueKey('live-screens-button'),
    onPressed: controlsLocked ? null : openScreens,
    icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
    label: const Text('Screens'),
  );

  Widget screensHeaderButton() {
    final scene = c.screens.showingScene;
    return IconButton(
      key: const ValueKey('live-screens-button'),
      tooltip: scene == null ? 'Screens' : 'Screens · scene: ${scene.name}',
      onPressed: controlsLocked ? null : openScreens,
      icon: const Icon(Icons.dashboard_customize_outlined),
    );
  }
}
