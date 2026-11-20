import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
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

/// The cue editor's settings that only the LED sign uses, under their
/// own heading in the same style as [ScreenCueControls].
class LedSignControls extends StatelessWidget {
  final List<Widget> children;
  const LedSignControls({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = appColors(context);
    return Container(
      key: const ValueKey('on-led-sign'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PaneLabel('On the LED sign'),
          const SizedBox(height: 4),
          Text(
            'For the LED sign. Stage, web and second screens stay as they are.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// The cue editor's choices for stage, web and second screens: a colour
/// from a short list, full screen or a banner over the countdown, wrapping
/// long text onto lines, and the scrolling speed. None of them changes the
/// LED sign.
class ScreenCueControls extends StatelessWidget {
  final String color, position;

  /// Whether the cue scrolls, which is when it has a speed.
  final bool scrolls;

  /// Whether long text wraps onto lines, and whether the text is long
  /// enough to be hard to read when it does.
  final bool wrap, longText;
  final int ledSpeed;
  final int? screenSpeed;
  final ValueChanged<String> onColor, onPosition;
  final ValueChanged<int?> onSpeed;
  final ValueChanged<bool> onWrap;
  const ScreenCueControls({
    super.key,
    required this.color,
    required this.position,
    required this.scrolls,
    required this.ledSpeed,
    required this.screenSpeed,
    required this.onColor,
    required this.onPosition,
    required this.onSpeed,
    this.wrap = false,
    this.longText = false,
    required this.onWrap,
  });

  /// Wrapped text longer than this many characters gets a gentle warning.
  static const longWrapLength = 60;

  static const colorLabels = {
    'white': 'White',
    'amber': 'Amber',
    'red': 'Red',
    'green': 'Green',
    'accent': 'Theme colour',
  };
  static const positionLabels = {
    'full': 'Full screen',
    'top': 'Banner at the top',
    'bottom': 'Banner at the bottom',
  };

  @override
  Widget build(BuildContext context) {
    final p = appColors(context);
    final muted = TextStyle(color: p.muted, fontSize: 12);
    final lines = position == 'full' ? '3 lines' : '2 lines in the banner';
    Color swatch(String name) =>
        Color(0xff000000 | (screenCueColors[name] ?? stageAccentRgb(p.id)));
    return Container(
      key: const ValueKey('on-screens'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PaneLabel('On screens'),
          const SizedBox(height: 4),
          Text(
            'For stage, web and second screens. The LED sign stays as it is.',
            style: muted,
          ),
          const SizedBox(height: 12),
          const Text('Colour'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in colorLabels.entries)
                ChoiceChip(
                  key: ValueKey('screen-color-${e.key}'),
                  showCheckmark: false,
                  // The colour as it is on the black stage background.
                  avatar: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: swatch(e.key),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  label: Text(e.value),
                  selected: color == e.key,
                  onSelected: (_) => onColor(e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Position'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in positionLabels.entries)
                ChoiceChip(
                  key: ValueKey('screen-position-${e.key}'),
                  // No tick, so the chips keep their places when chosen.
                  showCheckmark: false,
                  label: Text(e.value),
                  selected: position == e.key,
                  onSelected: (_) => onPosition(e.key),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            position == 'full'
                ? 'The cue takes the place of the countdown.'
                : 'The cue shows in a band at the ${position == 'top' ? 'top' : 'bottom'} and the countdown stays in view. Once the service has ended, it fills the screen.',
            key: const ValueKey('screen-position-note'),
            style: muted,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            key: const ValueKey('screen-wrap'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Wrap long text'),
            subtitle: Text(
              !wrap
                  ? 'Show the text on up to $lines, as large as fits, instead of scrolling or shrinking it onto one line.'
                  : 'Up to $lines, as large as fits, without scrolling. Text too long for that still scrolls. The LED sign is not changed.',
              style: muted,
            ),
            value: wrap,
            onChanged: onWrap,
          ),
          if (wrap && longText)
            Row(
              key: const ValueKey('screen-wrap-warning'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: p.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Long text is hard to read from a distance. Keep it shorter, or let it scroll instead.',
                    style: TextStyle(color: p.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          if (scrolls) ...[
            const SizedBox(height: 12),
            ScreenSpeedControl(
              ledSpeed: ledSpeed,
              screenSpeed: screenSpeed,
              onChanged: onSpeed,
            ),
          ],
        ],
      ),
    );
  }
}
