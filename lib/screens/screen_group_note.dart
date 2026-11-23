import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// Where a screen's own settings used to choose its layout: which group it
/// is in and what that group shows, with **Screens** to change it. What a
/// screen shows is set in one place only, the Screens panel.
class ScreenGroupNote extends StatelessWidget {
  final AppController controller;

  /// The screen's key ([thisScreenKey], `pair:<id>`, `web:<token>`), or
  /// null for web screens that have not joined: the default group.
  final String? screen;
  final bool locked;

  /// Words before the group, e.g. "Web screens that join go to".
  final String? lead;
  const ScreenGroupNote({
    super.key,
    required this.controller,
    required this.screen,
    this.locked = false,
    this.lead,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final screens = controller.screens;
    final group = screen == null
        ? screens.webDefault
        : screens.groupOf(screen!);
    return Wrap(
      key: ValueKey('screen-group-note-${screen ?? 'new'}'),
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(color: colors.text),
            children: [
              TextSpan(text: '${lead ?? 'In the group'} '),
              TextSpan(
                text: group.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: ' · shows ${screenShows[group.show]}',
                style: TextStyle(color: colors.muted),
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: ValueKey('open-screens-${screen ?? 'new'}'),
          onPressed: locked
              ? null
              : () => openScreensPanel(context, controller),
          icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
          label: const Text('Screens'),
        ),
      ],
    );
  }
}
