import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/feedback/feedback_page.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

extension SettingsSearchViews on HomeState {
  Widget settingsSearchResults() {
    final entries = <(String, String, IconData, VoidCallback)>[
      (
        'Clock format',
        'clock time 12 hour 24 hour blinking colon',
        Icons.schedule,
        () => openSettingsDetail('Clock format', clockFormatSettings),
      ),
      (
        'LED device management',
        'password wifi network reconnect credentials router',
        Icons.router_outlined,
        () => openSettingsDetail('LED device management', deviceManagement),
      ),
      (
        'Display fonts',
        'font tinos matrix typography',
        Icons.text_fields,
        () => openSettingsDetail('Display fonts', displayFonts),
      ),
      (
        'Warnings & alerts',
        'warning notifications sound threshold alerts',
        Icons.notifications_outlined,
        () => openSettingsDetail('Warnings & alerts', warningsSettings),
      ),
      (
        'Appearance',
        'theme density compact comfortable spacious dividers contrast motion picker feedback sound haptics',
        Icons.palette_outlined,
        openAppearance,
      ),
      (
        'Desktop layout',
        'layout wide window computer three panes mission control dial keys classic saved looks reset keyboard keys buttons',
        Icons.dashboard_customize_outlined,
        () => openAppearance(tab: 1),
      ),
      (
        'Church profile',
        'church name image banner',
        Icons.church_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChurchProfilePage(controller: c)),
        ),
      ),
      (
        'Display settings',
        'display screen led connection simulator',
        Icons.display_settings_outlined,
        () => openSettingsDetail('Display settings', displaySettings),
      ),
      (
        'LED preview shape',
        'square circular pixels',
        Icons.apps,
        () => openSettingsDetail('LED preview shape', ledShapeSettings),
      ),
      (
        'At zero',
        'zero overtime elapsed end countdown',
        Icons.timer_off_outlined,
        () => openSettingsDetail('At zero', sharedZeroSettings),
      ),
      (
        'Default end screen',
        'end screen hallelujah',
        Icons.flag_outlined,
        () => openSettingsDetail('Default end screen', defaultEndSettings),
      ),
      (
        'Stage cues',
        'cue message format text',
        Icons.chat_bubble_outline,
        () => openSettingsDetail('Stage cues', stageCueSettings),
      ),
      (
        'Quick message presets',
        'quick announcement message presets',
        Icons.message_outlined,
        () => openSettingsDetail('Quick message presets', quickPresetSettings),
      ),
      (
        'Screens & devices',
        'pair qr pin host share tablet mobile stage screen control',
        Icons.devices,
        () => openSettingsDetail(
          'Screens & devices',
          pairedDeviceSettings,
          showLiveShortcut: true,
        ),
      ),
      (
        'Backup & restore',
        'backup restore export import data',
        Icons.backup_outlined,
        () => openSettingsDetail('Backup & restore', backupSettings),
      ),
      (
        'Keep screen awake',
        'sleep awake screen lock',
        Icons.wb_sunny_outlined,
        () => openSettingsDetail(
          'Keep screen awake',
          () => SwitchListTile(
            title: const Text('Keep screen awake'),
            value: c.state.keepScreenAwake,
            onChanged: c.busy
                ? null
                : (v) => c.commit((d, _) => d.keepScreenAwake = v),
          ),
        ),
      ),
      (
        'Feedback centre',
        'feedback complaint contact email',
        Icons.feedback_outlined,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FeedbackCenterPage(controller: c)),
        ),
      ),
      (
        'About',
        'version author i proton software licence license',
        Icons.info_outline,
        () => openSettingsDetail('About', aboutSettings),
      ),
    ];
    // A one-line summary under each result, like the rows on Settings.
    const summaries = {
      'Clock format': '12 or 24 hour, and the blinking colon',
      'LED device management':
          'Saved passwords, the sign’s Wi-Fi and connection',
      'Display fonts': 'Fonts for the stage display',
      'Warnings & alerts': 'Shared thresholds, phone notifications and sound',
      'Appearance': 'Theme, spacing and motion',
      'Desktop layout': 'How Live is arranged in a wide window',
      'Church profile': 'Logo, church name and banner',
      'Display settings': 'Connection, profile, end screens, fonts and LEDs',
      'LED preview shape': 'Square or round LEDs in the simulator',
      'At zero': 'What the stage shows at 00:00',
      'Default end screen': 'What the stage shows when the service ends',
      'Stage cues': 'Saved cues and how they look',
      'Quick message presets': 'Saved quick messages',
      'Screens & devices': 'Pair phones and share to stage screens',
      'Backup & restore': 'Export or restore all your data',
      'Keep screen awake': 'Prevent sleep while the app is visible',
      'Feedback centre': 'Report a problem or send an idea',
      'About': 'Version, what’s new and licences',
    };
    final words = settingsQuery.toLowerCase().trim().split(RegExp(r'\s+'));
    final found = entries
        .where((e) => words.every('${e.$1} ${e.$2}'.toLowerCase().contains))
        .toList();
    return panel(
      padding: EdgeInsets.zero,
      child: AppMenuList(
        children: [
          if (found.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No matching settings. Try clock, password, font or warning.',
              ),
            ),
          for (final e in found)
            ListTile(
              leading: Icon(e.$3),
              title: Text(e.$1),
              subtitle: summaries[e.$1] == null
                  ? null
                  : Text(
                      summaries[e.$1]!,
                      style: TextStyle(
                        fontSize: 13,
                        color: appColors(context).muted,
                      ),
                    ),
              trailing: const Icon(Icons.chevron_right),
              onTap: e.$4,
            ),
        ],
      ),
    );
  }
}
