import 'dart:async';

import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:flutter/material.dart';

/// Screens as a page of the home screen, and the ways to it from Live: a
/// button beside Change display and Slides, or, in a desktop layout that
/// keeps its panes to the window, an icon in the header beside the Slides
/// one. Every way in (these, Commands, the Screens buttons on Slides and in
/// Settings) ends in [openScreensPanel], which selects the page where the
/// navigation has it and pushes the panel where it does not.
extension ScreensEntry on HomeState {
  /// Whether the navigation (a rail or top tabs) has a Screens destination.
  /// A phone's bottom bar keeps five, so it does not.
  bool get screensInNavigation => useNavigationRail || useTopTabs;

  /// The destinations the navigation shows now.
  List<HomePage> get navigationPages =>
      homePagesFor(withScreens: screensInNavigation);

  /// Screens fills the window below the header, scrolling on its own.
  bool get screensFillsWindow => c.ready && page == screensPage;

  /// Selects the Screens destination, closing any page pushed over the
  /// home screen. False, doing nothing, where there is no such destination.
  bool showScreensPage() {
    if (!mounted || !screensInNavigation) return false;
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(goToPage(screensPage));
    return true;
  }

  /// If the window has become one with no Screens destination (a phone
  /// turned, a window narrowed) while Screens is the page, Live is shown.
  void leaveScreensIfNoDestination() {
    if (page != screensPage || screensInNavigation) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && page == screensPage && !screensInNavigation) {
        navigatePage(0);
      }
    });
  }

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
