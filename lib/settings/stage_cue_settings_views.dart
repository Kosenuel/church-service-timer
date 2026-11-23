import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/live/cue_preview.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/main.dart';

extension OperatorSettings on HomeState {
  Widget deviceManagement() =>
      SettingsWide(maxWidth: 1100, main: DeviceManagementPanel(controller: c));

  Future<void> sendPreparedCue(TextLayout cue) async {
    final revision = c.state.session.revision;
    if (c.state.session.phase == 'ended' &&
        !await confirm(
          'Send after service ended?',
          'Show “${cue.text}” on the connected display? The report stays unchanged.',
          'Send cue',
        ))
      return;
    if (!await c.act('cue', value: cue, revision: revision) && mounted) {
      await showError(c.error ?? 'The cue could not be sent.');
    } else if (mounted &&
        c.hardware.enabled &&
        (!c.hardware.connected || c.hardware.held)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cue applied to the service and paired screens · LED sign unavailable or held',
          ),
        ),
      );
    }
  }

  Future<void> editSavedCue({int? index}) async {
    final old = index == null ? null : c.state.stageCues[index];
    final revision = c.state.stageCues.map((e) => e.toJson()).toString();
    final result = await compose(
      old ?? const TextLayout(''),
      index == null ? 'Create stage cue' : 'Edit stage cue',
      'Save cue',
      switchPreview: true,
    );
    if (result == null) return;
    final ok = await c.commit((draft, _) {
      require(
        draft.stageCues.map((e) => e.toJson()).toString() == revision,
        'The cue list changed. Please open it again.',
      );
      validateLayout(result, signFit: c.signFitRequired);
      if (index == null) {
        require(
          draft.stageCues.length < 100,
          'Keep at most 100 prepared cues.',
        );
        draft.stageCues.add(result);
      } else {
        draft.stageCues[index] = result;
      }
    });
    if (!ok && mounted) await showError(c.error ?? 'Could not save cue.');
  }

  Widget stageCueSettings() => SettingsWide(
    side: (context) => stageCuePreviewPane(),
    main: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Shared across all services. Editing here never sends to the sign.',
        ),
        const SizedBox(height: 16),
        ordinarySize(
          context,
          FilledButton.icon(
            onPressed: c.busy ? null : () => editSavedCue(),
            icon: const Icon(Icons.add),
            label: const Text('New cue'),
          ),
        ),
        const SizedBox(height: 16),
        if (c.state.stageCues.isEmpty)
          const Text('No prepared cues. Create one to show it on Live.'),
        panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final e in c.state.stageCues.asMap().entries) ...[
                if (e.key > 0) const AppDivider(),
                ListTile(
                  title: Text(e.value.text),
                  subtitle: Text(
                    styleSummary(e.value).substring(e.value.text.length + 3),
                  ),
                  onTap: c.busy ? null : () => editSavedCue(index: e.key),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Cue actions',
                    enabled: !c.busy,
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await editSavedCue(index: e.key);
                        return;
                      }
                      if (action == 'delete') {
                        if (await confirm(
                          'Delete stage cue?',
                          'Remove “${e.value.text}” from every service’s Live buttons? Output already on stage stays unchanged.',
                          'Delete cue',
                          destructive: true,
                        ))
                          await deleteCueWithUndo(e.key, e.value);
                        return;
                      }
                      await c.commit((draft, _) {
                        require(
                          e.key < draft.stageCues.length &&
                              draft.stageCues[e.key].toJson().toString() ==
                                  e.value.toJson().toString(),
                          'The cue list changed.',
                        );
                        final next = e.key + (action == 'up' ? -1 : 1);
                        require(
                          next >= 0 && next < draft.stageCues.length,
                          'Cannot move this cue further.',
                        );
                        final cue = draft.stageCues.removeAt(e.key);
                        draft.stageCues.insert(next, cue);
                      });
                    },
                    itemBuilder: (ctx) => appMenuEntries(ctx, [
                      const AppMenuAction('edit', 'Edit'),
                      if (e.key > 0) const AppMenuAction('up', 'Move up'),
                      if (e.key + 1 < c.state.stageCues.length)
                        const AppMenuAction('down', 'Move down'),
                      const AppMenuAction(
                        'delete',
                        'Delete cue',
                        destructive: true,
                      ),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  /// Beside Stage cues in a wide window: what each cue looks like on the
  /// display in use, in the order of the buttons on Live. With stage
  /// screens, or the Simulator standing in for one, that is a stage
  /// screen; otherwise the LED sign.
  Widget stageCuePreviewPane() {
    final cues = c.state.stageCues;
    final stage = c.previewsAsStageScreen;
    return SidePane(
      key: const ValueKey('stage-cue-preview-pane'),
      title: stage ? 'On the stage screen' : 'On the LED sign',
      note: cues.isEmpty
          ? stage
                ? 'No cues yet. Create one and it is shown here as a stage screen will show it.'
                : 'No cues yet. Create one and it is shown here as the sign will show it.'
          : stage
          ? 'What each cue shows on a stage, web or second screen when you send it from Live, in the order of the buttons there. Nothing here is sent to a screen. Point at a scrolling cue to play it.'
          : 'What each cue shows when you send it from Live, in the order of the buttons there. Nothing here is sent to the sign. Point at a preview to play it.',
      children: [
        if (cues.isNotEmpty)
          SignPreviewGrid(
            preview: stage ? HoverCueStagePreview.new : null,
            items: [
              for (final cue in cues)
                (
                  cue.text,
                  styleSummary(cue).substring(cue.text.length + 3),
                  cue,
                ),
            ],
          ),
      ],
    );
  }
}
