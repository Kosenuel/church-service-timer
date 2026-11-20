import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';

/// The scrolling speed of a cue on stage, web and second screens. Until it
/// is set the screens follow the LED sign's speed, as they always have.
class ScreenSpeedControl extends StatelessWidget {
  /// The LED sign's speed, which the screens follow while [screenSpeed] is
  /// null.
  final int ledSpeed;
  final int? screenSpeed;
  final ValueChanged<int?> onChanged;
  const ScreenSpeedControl({
    super.key,
    required this.ledSpeed,
    required this.screenSpeed,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final own = screenSpeed != null;
    final value = screenSpeed ?? ledSpeed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          own
              ? 'Speed on screens: $value'
              : 'Speed on screens: same as the LED sign',
          key: const ValueKey('screen-speed-label'),
        ),
        Slider(
          key: const ValueKey('screen-speed'),
          value: value.toDouble(),
          min: 4,
          max: maxScreenSpeed.toDouble(),
          divisions: maxScreenSpeed - 4,
          label: '$value',
          semanticFormatterCallback: (v) => '${v.round()}',
          onChanged: (v) => onChanged(v.round()),
        ),
        Text(
          own
              ? 'Stage, web and second screens scroll this cue at $value. The LED sign keeps its own speed.'
              : 'Stage, web and second screens scroll this cue at the LED sign’s speed. Move the slider to make it faster or slower on screens only, up to twice the sign’s fastest.',
          style: TextStyle(color: appColors(context).muted, fontSize: 12),
        ),
        if (own)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('screen-speed-same'),
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.link),
              label: const Text('Same as the LED sign'),
            ),
          ),
      ],
    );
  }
}
