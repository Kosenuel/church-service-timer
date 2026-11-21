import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The small notice on Live, while standing by, that the automatic update
/// check found a newer version. Never during a service, never with the
/// controls locked, and never on a stage screen, second screen or full
/// screen, which do not show Live's notices.
extension UpdateAvailableNotice on HomeState {
  Widget updateAvailableNotice() {
    final version = c.autoUpdate.notice;
    if (version == null ||
        !liveStandingBy ||
        controlsLocked ||
        c.practice.active ||
        c.pairing.joined ||
        !c.pairing.localControl) {
      return const SizedBox.shrink();
    }
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const ValueKey('update-available-notice'),
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: LayoutBuilder(
            builder: (context, space) {
              final line = Row(
                children: [
                  Icon(Icons.system_update_alt_outlined, color: colors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Version $version is available',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              );
              final buttons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: const ValueKey('update-notice-later'),
                    onPressed: c.busy
                        ? null
                        : () => c.autoUpdate.dismiss(version),
                    child: const Text('Not now'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    key: const ValueKey('update-notice-see'),
                    onPressed: seeUpdate,
                    child: const Text('See update'),
                  ),
                ],
              );
              // A narrow screen puts the buttons under the line, at the
              // right.
              if (space.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: line,
                    ),
                    Align(alignment: Alignment.centerRight, child: buttons),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: line),
                  const SizedBox(width: 8),
                  buttons,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Opens Settings › About › Check for updates, after the Settings PIN
  /// when one is set.
  Future<void> seeUpdate() async {
    if (!await ensureSettingsUnlocked(
      reason: 'Enter the Settings PIN to check for updates.',
    )) {
      return;
    }
    if (mounted) await openCheckForUpdates();
  }
}
