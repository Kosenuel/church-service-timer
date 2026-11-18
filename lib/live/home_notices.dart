import 'package:flutter/material.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';

/// Notices above every page: who controls a shared service, stage screens
/// waiting for output, and errors.
extension HomeNotices on HomeState {
  List<Widget> homeNotices() => [
    if (c.pairing.hosting)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.pairing.localControl
                    ? deviceText(
                        'This phone controls the service · ${c.pairing.peers.where((p) => p.approved).length} paired devices${c.webStage.activeDevices.isEmpty ? '' : ' · ${c.webStage.activeDevices.length} web screens'}',
                      )
                    : deviceText(
                        'Control is with a paired operator. This phone remains the service host.',
                      ),
              ),
              TextButton(
                onPressed: () => openSettingsDetail(
                  'Screens & devices',
                  pairedDeviceSettings,
                ),
                child: const Text('Manage devices and control'),
              ),
            ],
          ),
        ),
      ),
    if (c.stageScreensWaiting > 0)
      Padding(
        key: const ValueKey('stage-screens-waiting'),
        padding: const EdgeInsets.only(bottom: 12),
        child: panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: appColors(context).warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${c.stageScreensWaiting == 1 ? 'A stage screen has joined but is' : '${c.stageScreensWaiting} stage screens have joined but are'} not being shown anything: the display is set to ${c.destinationName}.',
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('show-on-stage-screens'),
                  onPressed: controlsLocked || !c.pairing.localControl
                      ? null
                      : showOnStageScreens,
                  child: const Text('Show on stage screens'),
                ),
              ),
            ],
          ),
        ),
      ),
    if (c.backgroundError != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        // In a card with an icon, like the
        // other notices, not loose text.
        child: panel(
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: appColors(context).error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c.backgroundError!,
                  style: TextStyle(color: appColors(context).error),
                ),
              ),
            ],
          ),
        ),
      ),
    if (c.error != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.error!,
                style: TextStyle(color: appColors(context).warning),
              ),
              const SizedBox(height: 8),
              if (c.retry == null && !c.corrupt)
                TextButton(
                  key: const ValueKey('dismiss-error'),
                  onPressed: c.dismissError,
                  child: const Text('Dismiss'),
                ),
              if (c.retry != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.retry!(),
                  child: Text(
                    c.reportSavePending
                        ? 'Retry saving report'
                        : 'Retry failed action',
                  ),
                ),
              if (c.corrupt)
                TextButton(
                  onPressed: () async {
                    if (await confirm(
                      'Reset local state?',
                      'This replaces unreadable local service and program data with starter programs. No physical display is connected.',
                      'Reset local data',
                      destructive: true,
                    ))
                      await c.resetCorrupt();
                  },
                  child: const Text('Reset local data…'),
                ),
            ],
          ),
        ),
      ),
  ];
}
