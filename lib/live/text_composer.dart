import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/live/cue_screen_controls.dart';
import 'package:church_service_timer/live/cue_preview.dart';

/// Whether two layouts look the same; layouts are compared by content, as
/// a copy of the default end screen is still the default.
bool sameLayout(TextLayout a, TextLayout b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());

/// The effects a cue may have, as the editor lists them, each with a line
/// saying what it does. "Steady on the LED sign" marks those only screens
/// can show; the sign shows the cue without moving.
const effectChoices = [
  ChoiceOption(
    value: 'static',
    label: 'Static · must fit',
    hint: 'Holds still',
  ),
  ChoiceOption(
    value: 'scroll',
    label: 'Scroll long text',
    hint: 'Moves across, for text too long to fit',
  ),
  ChoiceOption(
    value: 'flash',
    label: 'Flash · must fit',
    hint: 'Blinks on and off until cleared',
  ),
  ChoiceOption(
    value: 'flashHold',
    label: 'Flash then hold · must fit',
    hint: 'Flashes three times, then stays steady',
  ),
  ChoiceOption(
    value: 'pulse',
    label: 'Pulse · must fit',
    hint: 'Gently brightens and dims · steady on the LED sign',
  ),
  ChoiceOption(
    value: 'slideIn',
    label: 'Slide in · must fit',
    hint: 'Slides in from the edge of the screen · steady on the LED sign',
  ),
  ChoiceOption(
    value: 'bar',
    label: 'Countdown bar · must fit',
    hint:
        'A bar under the cue empties as its time runs out · steady on the LED sign',
  ),
  ChoiceOption(
    value: 'screenFlash',
    label: 'Screen flash · must fit',
    hint:
        'The screen flashes once in the cue’s colour · steady on the LED sign',
  ),
];

/// More about the chosen effect, under the Effect choice.
const effectNotes = {
  'flashHold':
      'On the LED sign the three flashes come again every 5 minutes while the cue shows.',
  'pulse': 'Screens only. Steady on the LED sign.',
  'slideIn':
      'Screens only. Steady on the LED sign. With reduced motion the cue simply appears.',
  'bar':
      'Screens only. Steady on the LED sign. The bar runs over a warning’s time or the time chosen when sending; a cue shown until cleared has no bar.',
  'screenFlash':
      'Screens only. Steady on the LED sign. Red for a white cue. With reduced motion the screen gets a coloured edge instead.',
};

class TextComposer extends StatefulWidget {
  final TextLayout initial;
  final String title, button;
  final Future<bool> Function()? onDelete;

  /// For a stage cue: the preview has a switch between the LED sign and a
  /// stage screen, starting on the stage screen when this is true. Null
  /// shows the LED sign only.
  final bool? stagePreviewFirst;
  const TextComposer({
    super.key,
    required this.initial,
    required this.title,
    required this.button,
    this.onDelete,
    this.stagePreviewFirst,
  });
  @override
  State<TextComposer> createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {
  late TextEditingController text;
  late bool bold, italic;
  bool deleting = false;
  late String effect, align, font;
  String? fontRequest, fontError;
  late int height, speed;
  int? screenSpeed;
  late String screenColor, screenPosition;
  final watch = Stopwatch()..start();
  final previewTick = ValueNotifier<int>(0);
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    text = TextEditingController(text: l.text);
    bold = l.bold;
    italic = l.italic;
    effect = l.effect;
    align = l.align;
    height = l.height;
    speed = l.speed;
    screenSpeed = l.screenSpeed;
    screenColor = l.screenColor;
    screenPosition = l.screenPosition;
    font = l.font;
    ticker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) previewTick.value++;
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    previewTick.dispose();
    text.dispose();
    super.dispose();
  }

  TextLayout get layout => TextLayout(
    text.text,
    bold: bold,
    italic: italic,
    effect: effect,
    align: align,
    height: height,
    speed: speed,
    // Only scrolling text has a speed; nothing is kept for other effects.
    screenSpeed: effect == 'scroll' ? screenSpeed : null,
    screenColor: screenColor,
    screenPosition: screenPosition,
    font: font,
  );
  @override
  Widget build(BuildContext context) {
    final request = layout;
    if (request.font == 'tinos' &&
        NativeDisplayFonts.key(request) != fontRequest) {
      fontRequest = NativeDisplayFonts.key(request);
      fontError = null;
      final requestedKey = fontRequest;
      NativeDisplayFonts.prepare(request)
          .then((_) {
            if (mounted && fontRequest == requestedKey) setState(() {});
          })
          .catchError((Object e) {
            if (mounted && fontRequest == requestedKey)
              setState(() => fontError = '$e');
          });
    }
    String? error;
    try {
      validateLayout(layout);
    } catch (e) {
      error = e.toString();
    }
    if (font == 'tinos' && fontError != null) error = fontError;
    final ledPreview = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          child: ValueListenableBuilder<int>(
            valueListenable: previewTick,
            builder: (context, _, child) => LedMatrix(
              pixels: error == null
                  ? renderPixels(layout, watch.elapsedMilliseconds)
                  : List.filled(512, false),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'NOT TESTED ON SIGN · simulator preview',
          style: TextStyle(color: appColors(context).warning, fontSize: 11),
        ),
      ],
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.stagePreviewFirst case final stageFirst?)
                CuePreviewSwitch(
                  cue: error == null ? layout : null,
                  stageFirst: stageFirst,
                  led: ledPreview,
                )
              else
                ledPreview,
              const SizedBox(height: 16),
              TextField(
                controller: text,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Display text',
                  helperText: '1–160 characters · basic Latin and punctuation',
                ),
                onChanged: (_) => setState(() {
                  watch.reset();
                }),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Bold'),
                    selected: bold,
                    onSelected: (v) => setState(() => bold = v),
                  ),
                  FilterChip(
                    label: const Text('Italic'),
                    selected: italic,
                    onSelected: (v) => setState(() => italic = v),
                  ),
                  FilterChip(
                    label: const Text('Tall · 14 px'),
                    selected: height == 2,
                    onSelected: (v) => setState(() => height = v ? 2 : 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ChoiceField<String>(
                value: font,
                decoration: const InputDecoration(labelText: 'Display font'),
                options: displayFontNames.entries
                    .map((e) => ChoiceOption(value: e.key, label: e.value))
                    .toList(),
                onChanged: (v) => setState(() {
                  font = v!;
                  fontRequest = null;
                  if (font == 'tinos') height = 2;
                  watch.reset();
                }),
              ),
              if (font == 'tinos')
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Bundled Tinos font · 14 px recommended. Compact text has fewer serif details.',
                    style: TextStyle(color: appColors(context).muted),
                  ),
                ),
              const SizedBox(height: 12),
              ChoiceField<String>(
                key: const ValueKey('effect-choice'),
                value: effect,
                decoration: InputDecoration(
                  labelText: 'Effect',
                  helperText: effectNotes[effect],
                  helperMaxLines: 3,
                ),
                options: effectChoices,
                onChanged: (v) => setState(() {
                  effect = v!;
                  watch.reset();
                }),
              ),
              const SizedBox(height: 12),
              ChoiceField<String>(
                value: align,
                decoration: const InputDecoration(
                  labelText: 'Alignment (text that fits)',
                ),
                options: const [
                  ChoiceOption(value: 'left', label: 'Left'),
                  ChoiceOption(value: 'center', label: 'Centre'),
                  ChoiceOption(value: 'right', label: 'Right'),
                ],
                onChanged: (v) => setState(() => align = v!),
              ),
              if (effect == 'scroll') ...[
                const SizedBox(height: 12),
                Text('Speed on the LED sign: $speed pixels / second'),
                Slider(
                  key: const ValueKey('led-speed'),
                  value: speed.toDouble(),
                  min: 4,
                  max: 24,
                  divisions: 20,
                  onChanged: (v) => setState(() => speed = v.round()),
                ),
                if (error == null)
                  Text(
                    'One complete message pass: approximately ${(math.max(0, textWidth(layout)) / speed).toStringAsFixed(1)} seconds.',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              ScreenCueControls(
                color: screenColor,
                position: screenPosition,
                scrolls: effect == 'scroll',
                ledSpeed: speed,
                screenSpeed: screenSpeed,
                onColor: (v) => setState(() => screenColor = v),
                onPosition: (v) => setState(() => screenPosition = v),
                onSpeed: (v) => setState(() => screenSpeed = v),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(color: appColors(context).warning),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        StackedDialogActions(
          children: [
            FilledButton(
              onPressed: error == null && !deleting
                  ? () => Navigator.pop(context, layout)
                  : null,
              child: Text(widget.button),
            ),
            if (widget.onDelete != null)
              TextButton.icon(
                onPressed: deleting
                    ? null
                    : () async {
                        setState(() => deleting = true);
                        try {
                          final removed = await widget.onDelete!();
                          if (removed && context.mounted)
                            Navigator.pop(context);
                        } finally {
                          if (mounted) setState(() => deleting = false);
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete cue'),
                style: TextButton.styleFrom(
                  foregroundColor: appColors(context).error,
                ),
              ),
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
