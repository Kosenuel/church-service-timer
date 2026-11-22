import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/whats_new_page.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The small notice on Live, while standing by, that the app has just been
/// updated. It follows the update notice's rules: never during a service,
/// with the controls locked, while joined to another device, or on a stage
/// screen, second screen or full screen. While the update-available notice
/// is showing, this one waits behind it, so the two never stack.
extension WhatsNewNoticeView on HomeState {
  Widget whatsNewNotice() {
    final version = c.whatsNew.notice;
    if (version == null ||
        !liveStandingBy ||
        controlsLocked ||
        c.practice.active ||
        c.pairing.joined ||
        !c.pairing.localControl ||
        c.autoUpdate.notice != null) {
      return const SizedBox.shrink();
    }
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const ValueKey('whats-new-notice'),
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
                  Icon(Icons.auto_awesome_outlined, color: colors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Updated to $version',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              );
              final buttons = Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    key: const ValueKey('whats-new-dismiss'),
                    onPressed: c.busy ? null : c.whatsNew.markSeen,
                    child: const Text('Dismiss'),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey('whats-new-see'),
                    onPressed: seeWhatsNew,
                    child: const Text('See what’s new'),
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

  /// Opens What’s new, after the Settings PIN when one is set, and marks
  /// this version as seen.
  Future<void> seeWhatsNew() async {
    if (!await ensureSettingsUnlocked(
      reason: 'Enter the Settings PIN to see what’s new.',
    )) {
      return;
    }
    if (!mounted) return;
    await c.whatsNew.markSeen();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WhatsNewPage()));
  }
}
