import 'package:flutter/material.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/windows/second_screen.dart';

/// The second screen on Live: what it is doing, in words, beside the one
/// button that changes it. A phone has no second screen and shows nothing.
extension SecondScreenControl on HomeState {
  /// The lines to add under the stage preview; none on a phone.
  List<Widget> secondScreenControl() {
    final second = c.secondScreen;
    if (second == null) return const [];
    final colors = appColors(context);
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.muted);
    final host = second.host;
    final others = second.others;
    if (others.isEmpty && !host.open) {
      return [
        const SizedBox(height: 12),
        Text(
          'No second screen connected',
          key: const ValueKey('live-second-screen'),
          style: muted,
        ),
      ];
    }
    final showing = second.showingOn;
    final target = second.target;
    final status = !host.open
        ? 'Second screen: not showing'
        : showing == null
        ? 'Showing on the second screen'
        : host.connected
        ? 'Showing on ${stageMonitorLabel(showing)}'
        : 'Opening on ${stageMonitorLabel(showing)}…';
    return [
      const SizedBox(height: 12),
      SizedBox(
        key: const ValueKey('live-second-screen'),
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              status,
              key: const ValueKey('live-second-screen-status'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!host.open && others.length > 1)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: DropdownButton<int>(
                  key: const ValueKey('live-second-screen-choice'),
                  value: target?.index,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: controlsLocked
                      ? null
                      : (index) => second.choose(
                          others.firstWhere((s) => s.index == index),
                        ),
                  items: [
                    for (final screen in others)
                      DropdownMenuItem(
                        value: screen.index,
                        child: Text(
                          stageMonitorLabel(screen),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            if (host.open)
              OutlinedButton(
                key: const ValueKey('live-second-screen-stop'),
                onPressed: controlsLocked ? null : second.stop,
                child: const Text('Stop'),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('live-second-screen-show'),
                onPressed: controlsLocked || target == null
                    ? null
                    : () => second.show(target),
                icon: const Icon(Icons.connected_tv, size: 20),
                label: const Text('Show on second screen'),
              ),
          ],
        ),
      ),
      if (second.note case final note? when !host.open)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            note,
            key: const ValueKey('live-second-screen-note'),
            style: muted,
          ),
        ),
      if (host.error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            error,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ),
    ];
  }
}
