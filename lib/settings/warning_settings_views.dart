import 'package:church_service_timer/live/cue_preview.dart';
export 'package:church_service_timer/settings/warning_editor.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/settings/clicker_test_page.dart';
import 'dart:async';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';

class WarningSettingsPanel extends StatelessWidget {
  final DisplaySettings settings;
  final Future<void> Function(DisplaySettings) onSave;
  final bool busy;
  final String title;
  final String? scope;

  /// Whether the warning text's preview starts as a stage screen shows
  /// it; null leaves the LED sign's preview alone, with no switch.
  final bool? stagePreviewFirst;
  const WarningSettingsPanel({
    super.key,
    required this.settings,
    required this.onSave,
    this.busy = false,
    this.title = 'Automatic warning cues',
    this.scope,
    this.stagePreviewFirst,
  });
  @override
  Widget build(BuildContext context) {
    final d = settings;
    final colors = appColors(context);
    Future<void> save(List<WarningRule> rules) => onSave(d.withWarnings(rules));
    Future<void> toggle(int index, bool on) {
      final rules = [...d.warnings];
      rules[index] = WarningRule.fromJson({
        ...rules[index].toJson(),
        'enabled': on,
      });
      return save(rules);
    }

    /// Asks first; true when the warning was deleted.
    Future<bool> delete(int index) async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete warning for all services?'),
          content: Text(
            'Remove “${d.warnings[index].cue.text}”? A warning already on stage will finish normally.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: destructiveFilled(),
              child: const Text('Delete warning'),
            ),
          ],
        ),
      );
      if (yes != true) return false;
      await save([...d.warnings]..removeAt(index));
      return true;
    }

    Future<void> edit({int? index}) async {
      final initial = index == null
          ? const WarningRule(
              60,
              TextLayout('1 MIN LEFT'),
              destination: 'stage',
            )
          : d.warnings[index];
      final next = await showDialog<WarningRule>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) => WarningEditor(
          initial: initial,
          isNew: index == null,
          onDelete: index == null ? null : () => delete(index),
          stagePreviewFirst: stagePreviewFirst,
          usedThresholds: d.warnings
              .asMap()
              .entries
              .where((e) => e.key != index)
              .map((e) => e.value.seconds)
              .toSet(),
        ),
      );
      if (next != null && context.mounted) {
        final rules = [...d.warnings];
        if (index == null) {
          rules.add(next);
        } else {
          rules[index] = next;
        }
        await onSave(d.withWarnings(rules));
      }
    }

    Widget card(int index) {
      final w = d.warnings[index];
      final timeColor = warningTimeColor(context, w.seconds, w.enabled);
      final where = [
        w.destination == 'stage' ? 'Operator and stage' : 'Operator only',
        if (w.destination == 'stage')
          w.scrollOnce
              ? 'scrolls once'
              : durationLabel(w.durationSeconds * 1000),
        displayFontNames[w.cue.font] ?? w.cue.font,
      ].join(' · ');
      return Material(
        key: ValueKey('warning-rule-$index'),
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: busy ? null : () => edit(index: index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    formatTime(w.seconds * 1000),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      color: timeColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.cue.text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: w.enabled ? null : colors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        where,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: w.enabled,
                  onChanged: busy ? null : (on) => toggle(index, on),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Warning actions',
                  enabled: !busy,
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await edit(index: index);
                    } else if (action == 'delete') {
                      await delete(index);
                    } else {
                      await toggle(index, !w.enabled);
                    }
                  },
                  itemBuilder: (ctx) => appMenuEntries(ctx, [
                    const AppMenuAction('edit', 'Edit warning'),
                    AppMenuAction(
                      'toggle',
                      w.enabled ? 'Disable warning' : 'Enable warning',
                    ),
                    const AppMenuAction(
                      'delete',
                      'Delete warning',
                      destructive: true,
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: sectionLabelStyle(context),
              ),
            ),
            if (d.warnings.length < 6)
              TextButton.icon(
                onPressed: busy ? null : () => edit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
          ],
        ),
        if (scope != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              scope!,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
        for (var i = 0; i < d.warnings.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          card(i),
        ],
        if (d.warnings.isEmpty)
          OutlinedButton.icon(
            onPressed: busy ? null : () => save(defaultWarnings),
            icon: const Icon(Icons.auto_awesome_outlined, size: 20),
            label: const Text('Use suggested warnings'),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.zero,
          child: Text(
            'Each warning fires once per segment at the time remaining. Stage cues return to the timer afterwards; Blank screen hides them.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

extension WarningSettingsViews on HomeState {
  Future<void> editZero() async {
    final next = await compose(
      c.state.defaults.zero ?? const TextLayout("TIME'S UP"),
      'Zero-time screen · all services',
      'Save zero screen',
    );
    if (next != null) await c.setSharedZero(next);
  }

  Widget sharedZeroSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('At zero · all services'),
        const SizedBox(height: 8),
        Text(
          c.state.defaults.zero?.text ?? '00:00',
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose what the stage display shows when a segment reaches 00:00. The operator’s timer continues into overtime, and the next segment starts only when you select Next segment. This setting applies to every service. Blank output and active cues take priority; an end screen applies when you end the whole service.',
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          key: const ValueKey('zero-choice'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Show 00:00'),
              icon: Icon(Icons.timer_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('Custom text'),
              icon: Icon(Icons.edit_outlined),
            ),
          ],
          selected: {c.state.defaults.zero != null},
          onSelectionChanged: c.busy
              ? null
              : (values) async {
                  if (!values.single) {
                    await c.setSharedZero(null);
                    return;
                  }
                  await editZero();
                },
        ),
        if (c.state.defaults.zero != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: c.busy ? null : editZero,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit custom text'),
          ),
        ],
      ],
    ),
  );

  Widget ledShapeSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Simulator LED shape'),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'square',
              label: Text('Square LEDs'),
              icon: Icon(Icons.square),
            ),
            ButtonSegment(
              value: 'circular',
              label: Text('Circular LEDs'),
              icon: Icon(Icons.circle),
            ),
          ],
          selected: {c.state.pixelShape},
          onSelectionChanged: c.busy || c.corrupt
              ? null
              : (values) async {
                  await c.commit((draft, _) {
                    draft.pixelShape = values.single;
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(
          'Saved for this device. Applies to Live and all cue previews; fonts and the 32 × 16 pixel data stay the same.',
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 12),
        LedMatrix(
          pixels: renderPixels(
            const TextLayout('Aa 12', font: 'i-proton_sq_matrix'),
            0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'I-Proton Sq-Matrix · compact preview',
          style: TextStyle(color: appColors(context).muted),
        ),
      ],
    ),
  );

  Widget warningsSettings() => SettingsWide(
    maxWidth: 720,
    side: (context) => warningPreviewPane(),
    main: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WarningSettingsPanel(
          stagePreviewFirst: c.previewsAsStageScreen,
          settings: c.state.defaults,
          title: 'Automatic warnings',
          scope:
              'All services and rehearsals. Changes apply to future warnings; earlier thresholds are not replayed.',
          busy: c.busy,
          onSave: saveWarningsWithUndo,
        ),
        const SizedBox(height: 24),
        phoneWarningSettings(),
        settingsGroup('During a service', [
          SwitchListTile(
            key: const ValueKey('lock-screen-controls'),
            contentPadding: appLayout(context).tileInsets,
            secondary: Icon(
              Icons.screen_lock_portrait_outlined,
              color: appColors(context).accent,
            ),
            title: const Text(
              'Lock-screen controls',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              deviceText(
                'Countdown, Pause and Next in a notification. Next needs a second tap.',
              ),
              style: TextStyle(fontSize: 13, color: appColors(context).muted),
            ),
            value: c.state.lockScreenControls,
            onChanged: c.busy
                ? null
                : (v) async {
                    await c.commit((draft, _) => draft.lockScreenControls = v);
                    await c.syncActiveService();
                  },
          ),
          SwitchListTile(
            key: const ValueKey('clicker-controls'),
            contentPadding: appLayout(context).tileInsets,
            secondary: Icon(
              Icons.keyboard_alt_outlined,
              color: appColors(context).accent,
            ),
            title: const Text(
              'Clicker and foot pedal',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              c.port.isDesktop
                  // A PC cannot tell a clicker from its keyboard; the
                  // shortcuts list and Test a clicker or pedal say more.
                  ? 'Page Down or Right arrow twice for Next, B or Space to pause or resume. Off, these keys do nothing from the keyboard either.'
                  : 'Page Down or Right arrow for Next (press twice to confirm). B or Space to pause or resume.',
              style: TextStyle(fontSize: 13, color: appColors(context).muted),
            ),
            value: c.state.clickerControls,
            onChanged: c.busy
                ? null
                : (v) => c.commit((draft, _) => draft.clickerControls = v),
          ),
          settingsRow(
            Icons.ads_click,
            'Test a clicker or pedal',
            'Press its buttons to see the key each one sends and what it does on Live. Nothing reaches the service.',
            openClickerTest,
          ),
          settingsRow(
            c.backgroundActive ? Icons.sync : Icons.info_outline,
            c.backgroundActive
                ? 'Background operation active'
                : 'Background operation',
            'Starts with the LED sign or sharing and keeps warnings running while locked. If unavailable, keep the app open; after an interruption, reconnect and review the output.',
            null,
          ),
        ]),
      ],
    ),
  );

  /// Beside Warnings & alerts in a wide window: what each automatic
  /// warning puts on the stage display.
  Widget warningPreviewPane() {
    final rules = c.state.defaults.warnings;
    final stage = c.previewsAsStageScreen;
    return SidePane(
      key: const ValueKey('warning-preview-pane'),
      title: stage ? 'On the stage screen' : 'On the LED sign',
      note: rules.isEmpty
          ? stage
                ? 'No automatic warnings yet. Add one and it is shown here as a stage screen will show it.'
                : 'No automatic warnings yet. Add one and it is shown here as the sign will show it.'
          : stage
          ? 'What each automatic warning shows on a stage, web or second screen when its time is reached. A warning that is switched off shows nothing. Point at a scrolling warning to play it.'
          : 'What each automatic warning shows when its time is reached. A warning that is switched off shows nothing. Point at a preview to play it.',
      children: [
        if (rules.isNotEmpty)
          SignPreviewGrid(
            preview: stage ? HoverCueStagePreview.new : null,
            absent: stage ? 'Not shown on the stage screen' : null,
            items: [
              for (final w in rules)
                (
                  '${formatTime(w.seconds * 1000)} left',
                  !w.enabled
                      ? 'Switched off'
                      : w.destination == 'stage'
                      ? (scrollsOnSign(w.cue)
                            ? 'Operator and stage · scrolls across'
                            : 'Operator and stage')
                      : 'Operator only',
                  w.enabled && w.destination == 'stage' ? w.cue : null,
                ),
            ],
          ),
      ],
    );
  }

  Widget phoneWarningSettings() {
    final colors = appColors(context);
    final on = c.notificationState['enabled'] == true;
    final exact = c.notificationState['exact'] == true;
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (mounted) await showError('$e');
      }
    }

    // A PC has no notification channel to manage: the app flashes its
    // taskbar button and shows a notification. Its sound is a setting,
    // off unless turned on, because a PC is often plugged into the sound
    // system.
    if (c.port.isDesktop) {
      return settingsGroup('Alerts on this computer', [
        ListTile(
          key: const ValueKey('desktop-alerts-status'),
          contentPadding: appLayout(context).tileInsets,
          leading: Icon(
            Icons.notifications_active_outlined,
            color: colors.accent,
          ),
          title: const Text(
            'Windows notification at each warning',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            c.notificationError ??
                'A notification appears and the taskbar button flashes. Windows may hold notifications back while Do not disturb is on, which it turns on by itself when a screen is duplicated; the flash still shows.',
            style: TextStyle(
              fontSize: 13,
              color: c.notificationError == null
                  ? colors.muted
                  : colors.warning,
            ),
          ),
          trailing: TextButton(
            onPressed: () => run(c.port.testNotification),
            child: const Text('Test'),
          ),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('desktop-warning-sound'),
          contentPadding: appLayout(context).tileInsets,
          secondary: Icon(
            c.notificationState['sound'] == true
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
            color: colors.accent,
          ),
          title: const Text(
            'Play the Windows notification sound',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            c.notificationState['sound'] == true
                ? 'On. Each warning plays the sound, through whatever this computer’s sound goes to.'
                : 'Off. Warnings make no sound, so nothing goes out through the sound system.',
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          value: c.notificationState['sound'] == true,
          onChanged: (on) => run(() async {
            await c.port.setWarningSound(on);
            await c.phoneWarnings.sync();
            settingsRefresh.value++;
          }),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('desktop-tray-countdown'),
          contentPadding: appLayout(context).tileInsets,
          secondary: Icon(Icons.timer_outlined, color: colors.accent),
          title: const Text(
            'Show the countdown in the notification area',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            c.notificationState['tray'] != false
                ? 'On. While a service runs, an icon beside the Windows clock shows the time left when you point at it. Click the icon to bring this window forward.'
                : 'Off. No icon is added beside the Windows clock.',
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          value: c.notificationState['tray'] != false,
          onChanged: (on) => run(() async {
            await c.port.setTrayCountdown(on);
            await c.phoneWarnings.sync();
            settingsRefresh.value++;
          }),
        ),
      ]);
    }
    return settingsGroup('Phone alerts', [
      ListTile(
        key: const ValueKey('phone-alerts-status'),
        contentPadding: appLayout(context).tileInsets,
        leading: Icon(
          on
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          color: on ? colors.accent : colors.warning,
        ),
        title: Text(
          on
              ? (c.notificationState['sound'] == true
                    ? 'Notifications and sound on'
                    : 'Notifications on · channel sound off')
              : 'Notifications are off',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          c.notificationError ??
              (on
                  ? 'Warnings also reach this phone'
                  : 'Warnings show on the stage only'),
          style: TextStyle(
            fontSize: 13,
            color: c.notificationError == null ? colors.muted : colors.warning,
          ),
        ),
        trailing: on
            ? null
            : fixButton(
                context,
                'Turn on',
                c.busy ? null : c.enablePhoneWarnings,
              ),
      ),
      Padding(
        padding: EdgeInsets.zero,
        child: ChoiceField<int>(
          value: c.state.notificationClearSeconds,
          row: true,
          icon: Icons.timer_outlined,
          rowPadding: appLayout(context).tileInsets,
          decoration: const InputDecoration(
            labelText: 'Clear phone warnings after',
          ),
          options: const [
            ChoiceOption(value: 15, label: '15 s'),
            ChoiceOption(value: 30, label: '30 s'),
            ChoiceOption(value: 60, label: '1 min'),
            ChoiceOption(value: 0, label: 'Until dismissed'),
          ],
          onChanged: c.busy
              ? null
              : (value) async {
                  if (!await c.commit(
                        (draft, _) => draft.notificationClearSeconds = value!,
                      ) &&
                      mounted) {
                    await showError(
                      c.error ?? 'Could not save notification preference.',
                    );
                  }
                },
        ),
      ),
      ListTile(
        contentPadding: appLayout(context).tileInsets,
        leading: Icon(Icons.volume_up_outlined, color: colors.muted),
        title: const Text('Sound and vibration'),
        subtitle: Text(
          'Follows phone volume and Do Not Disturb · watches mirror the vibration',
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
        trailing: TextButton(
          onPressed: () => run(c.port.testNotification),
          child: const Text('Test'),
        ),
      ),
      if (!exact)
        ListTile(
          contentPadding: appLayout(context).tileInsets,
          leading: Icon(Icons.alarm, color: colors.warning),
          title: const Text('Precise timing'),
          subtitle: Text(
            'Without precise alarm access, Android may delay warnings while the phone sleeps.',
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          trailing: fixButton(
            context,
            'Allow',
            () => run(c.port.requestExactWarnings),
          ),
        ),
      settingsRow(
        Icons.settings_outlined,
        'Notification settings',
        'Android channel, sound and lock-screen visibility',
        () => run(c.port.openNotificationSettings),
      ),
    ]);
  }
}
