import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

extension ClockSettingsViews on HomeState {
  Widget clockFormatSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Clock format',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: c.state.clockFormat,
          onChanged: (v) {
            if (!c.busy && v != null)
              c.commit((draft, _) => draft.clockFormat = v);
          },
          child: Column(
            children: [
              for (final format in ['24h', '12h'])
                RadioListTile<String>(
                  value: format,
                  enabled: !c.busy,
                  title: Text(format == '24h' ? '24-hour' : '12-hour'),
                  subtitle: Text(stageClockText(c.now.wall, format)),
                ),
            ],
          ),
        ),
        const AppDivider(),
        SwitchListTile(
          key: const ValueKey('clock-blink'),
          title: const Text('Blink clock colon'),
          subtitle: Text(
            c.state.clockBlink ? 'Blinking · once per second' : 'Steady',
          ),
          value: c.state.clockBlink,
          onChanged: c.busy
              ? null
              : (v) => c.commit((draft, _) => draft.clockBlink = v),
        ),
        const Text(
          'Blinking applies to the simulator and paired screens. The LED sign and its preview keep a steady colon.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Shared across services and stage screens. Uses this phone’s current time and timezone. Countdown timers stay in minutes and seconds.',
        ),
      ],
    ),
  );
}
