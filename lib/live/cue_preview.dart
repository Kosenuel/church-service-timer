import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The preview in the cue editor, with a switch over it between the cue
/// as an LED sign shows it and as a stage screen shows it. The stage
/// picture is drawn by the same [StageSurface] the screens use.
class CuePreviewSwitch extends StatefulWidget {
  /// The cue as written so far; null while it cannot be shown.
  final TextLayout? cue;

  /// The LED sign's preview.
  final Widget led;

  /// Whether the switch starts on the stage screen.
  final bool stageFirst;
  const CuePreviewSwitch({
    super.key,
    required this.cue,
    required this.led,
    required this.stageFirst,
  });
  @override
  State<CuePreviewSwitch> createState() => _CuePreviewSwitchState();
}

class _CuePreviewSwitchState extends State<CuePreviewSwitch> {
  late var stage = widget.stageFirst;

  @override
  Widget build(BuildContext context) {
    final cue = widget.cue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SegmentedButton<bool>(
            key: const ValueKey('cue-preview-kind'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text(simulatorKinds['led']!)),
              ButtonSegment(value: true, label: Text(simulatorKinds['stage']!)),
            ],
            selected: {stage},
            onSelectionChanged: (kinds) => setState(() => stage = kinds.single),
          ),
        ),
        const SizedBox(height: 12),
        if (!stage)
          widget.led
        else
          Semantics(
            key: const ValueKey('cue-stage-preview'),
            label: 'Stage screen preview',
            child: CueStagePreview(cue),
          ),
      ],
    );
  }
}

/// A cue as a stage, web or second screen shows it, in a 16:9 box and
/// drawn by the same [StageSurface] the screens use. A banner sits over
/// a sample countdown. With [still], a scrolling cue holds still.
class CueStagePreview extends StatelessWidget {
  final TextLayout? cue;
  final bool still;
  const CueStagePreview(this.cue, {super.key, this.still = false});
  @override
  Widget build(BuildContext context) {
    final cue = this.cue;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: ExcludeSemantics(
            child: StageSurface(
              stale: false,
              data: {
                'stageSharing': true,
                'stageLayout': 'timer',
                'displayIsTimer': false,
                'outputMode': 'Cue',
                'displayText': cue?.text ?? '',
                'effect': still && cue?.effect == 'scroll'
                    ? 'static'
                    : cue?.effect ?? 'static',
                'speed': cue?.speed ?? 12,
                'screenSpeed': ?cue?.screenSpeed,
                if (cue != null && cue.screenColor != 'white')
                  'cueColor': stageColorHex(
                    screenCueColors[cue.screenColor] ??
                        stageAccentRgbOf(appColors(context).accent),
                  ),
                if (cue != null && cue.screenPosition != 'full') ...{
                  'cuePosition': cue.screenPosition,
                  'underText': '12:34',
                  'underMode': 'Countdown',
                },
                'bold': cue?.bold ?? false,
                'italic': cue?.italic ?? false,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// [CueStagePreview] that plays a scrolling cue only while pointed at,
/// as the sign previews beside it do.
class HoverCueStagePreview extends StatefulWidget {
  final TextLayout cue;
  const HoverCueStagePreview(this.cue, {super.key});
  @override
  State<HoverCueStagePreview> createState() => _HoverCueStagePreviewState();
}

class _HoverCueStagePreviewState extends State<HoverCueStagePreview> {
  var playing = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => playing = true),
    onExit: (_) => setState(() => playing = false),
    child: CueStagePreview(widget.cue, still: !playing),
  );
}
