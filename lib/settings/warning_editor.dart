import 'dart:async';

import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/cue_preview.dart';
import 'package:church_service_timer/live/text_composer.dart';
import 'package:church_service_timer/settings/settings_wide.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

/// The colour of a warning's time, the same in the list and the editor:
/// amber under a minute, red at 00:00, muted while switched off.
Color warningTimeColor(BuildContext context, int seconds, bool enabled) {
  final colors = appColors(context);
  return !enabled
      ? colors.muted
      : seconds == 0
      ? colors.error
      : seconds < 60
      ? colors.warning
      : colors.text;
}

/// How a warning's text looks, in a few words: "Bold · Scrolling ·
/// I-Proton Matrix".
String warningLookSummary(TextLayout cue) => [
  if (cue.bold) 'Bold',
  if (cue.italic) 'Italic',
  switch (cue.effect) {
    'static' => 'Still',
    'scroll' => 'Scrolling',
    'flash' => 'Flashing',
    'flashHold' => 'Flash then hold',
    'pulse' => 'Pulsing',
    'slideIn' => 'Slides in',
    'bar' => 'Countdown bar',
    'screenFlash' => 'Screen flash',
    final other => other,
  },
  displayFontNames[cue.font] ?? cue.font,
].join(' · ');

/// The editor for one automatic warning, opened from Warnings & alerts:
/// when it fires, what it shows, where, for how long, and whether it is
/// on. Two columns in a wide window, one in a narrower one, and the
/// whole screen on a phone. It returns the edited warning; nothing is
/// saved until Save.
class WarningEditor extends StatefulWidget {
  final WarningRule initial;

  /// The times other warnings already fire at; this one cannot share one.
  final Set<int> usedThresholds;

  /// Whether the preview starts on the stage screen.
  final bool? stagePreviewFirst;

  /// A warning not yet in the list: "New warning", and nothing to delete.
  final bool isNew;

  /// Deletes this warning, after asking; true when it was deleted. Null
  /// for a new warning.
  final Future<bool> Function()? onDelete;
  const WarningEditor({
    super.key,
    required this.initial,
    required this.usedThresholds,
    this.stagePreviewFirst,
    this.isNew = false,
    this.onDelete,
  });
  @override
  State<WarningEditor> createState() => _WarningEditorState();
}

class _WarningEditorState extends State<WarningEditor> {
  late int threshold;
  late bool enabled;
  late String destination;
  late bool scrollOnce;
  late int duration;
  late TextLayout cue;
  late bool previewStage = widget.stagePreviewFirst ?? false;
  bool deleting = false;
  String? error;
  @override
  void initState() {
    super.initState();
    threshold = widget.initial.seconds;
    enabled = widget.initial.enabled;
    destination = widget.initial.destination;
    cue = widget.initial.cue;
    scrollOnce = widget.initial.scrollOnce;
    duration = widget.initial.durationSeconds;
  }

  bool get clash => widget.usedThresholds.contains(threshold);
  bool get canSave => !clash && !deleting;
  String get title => widget.isNew ? 'New warning' : 'Edit warning';

  WarningRule get rule => WarningRule(
    threshold,
    cue,
    enabled: enabled,
    destination: destination,
    durationSeconds: duration,
    scrollOnce: scrollOnce,
  );

  void save() {
    if (!canSave) return;
    try {
      require(
        threshold >= 0 && threshold <= 3599,
        'Choose a time up to 59:59.',
      );
      validateLayout(cue);
      require(
        duration >= 1 && duration <= 120,
        'Choose from 1 to 120 seconds.',
      );
      Navigator.pop(context, rule);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null || deleting) return;
    setState(() => deleting = true);
    try {
      final removed = await onDelete();
      if (removed && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  Future<void> pickTime() async {
    final value = await showWheelTimePicker(
      context,
      title: 'Time left when it fires',
      initial: threshold,
      allowZero: true,
    );
    if (value != null && mounted) {
      setState(() {
        threshold = value;
        error = null;
      });
    }
  }

  Future<void> pickDuration() async {
    final value = await showWheelTimePicker(
      context,
      title: 'Stays up for',
      initial: duration,
      maximum: 120,
    );
    if (value != null && mounted) setState(() => duration = value);
  }

  Future<void> editText() async {
    final next = await showDialog<TextLayout>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => TextComposer(
        initial: cue,
        title: 'Warning text and formatting',
        button: 'Use warning text',
        stagePreviewFirst: previewStage,
      ),
    );
    if (next != null && mounted) {
      setState(() {
        cue = next;
        error = null;
      });
    }
  }

  // Sections ---------------------------------------------------------

  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: sectionLabelStyle(context)),
  );

  Widget help(String text, {Color? color, Key? key}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      key: key,
      style: TextStyle(fontSize: 12, color: color ?? appColors(context).muted),
    ),
  );

  Widget when() {
    final colors = appColors(context);
    final time = formatTime(threshold * 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionLabel('WHEN'),
        LayoutBuilder(
          builder: (context, space) {
            // With large text on a narrow phone the pencil stands alone.
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final roomy = space.maxWidth >= 220 * scale;
            return Semantics(
              button: true,
              label: '$time left. Change when it fires',
              excludeSemantics: true,
              child: Material(
                key: const ValueKey('warning-time'),
                color: colors.input,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: clash ? colors.warning : colors.border,
                    width: clash ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: InkWell(
                  onTap: pickTime,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 14, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w300,
                                    color: warningTimeColor(
                                      context,
                                      threshold,
                                      true,
                                    ),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'left',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit, size: 20, color: colors.accent),
                        if (roomy) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Change',
                            style: TextStyle(
                              color: colors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (clash)
          help(
            'Another warning already fires at $time. Choose a different time.',
            color: colors.warning,
            key: const ValueKey('warning-time-clash'),
          )
        else
          help(
            'Fires once in each segment when the countdown reaches this time.',
          ),
      ],
    );
  }

  Widget whatItShows({required double previewWidth}) {
    final colors = appColors(context);
    final button = OutlinedButton.icon(
      key: const ValueKey('warning-edit-text'),
      onPressed: editText,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)),
      icon: const Icon(Icons.edit, size: 18),
      label: const Text('Edit text and style'),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cue.text,
          key: const ValueKey('warning-text'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          warningLookSummary(cue),
          key: const ValueKey('warning-look'),
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionLabel('WHAT IT SHOWS'),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: previewWidth),
            child: CuePreviewSwitch(
              cue: cue,
              stageFirst: previewStage,
              led: _PlayingSignPreview(cue),
              onChanged: (stage) => setState(() => previewStage = stage),
            ),
          ),
        ),
        if (destination == 'operator')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Operator only: the stage keeps showing the timer.',
              key: const ValueKey('warning-operator-note'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, space) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            if (space.maxWidth < 400 * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [words, const SizedBox(height: 12), button],
              );
            }
            return Row(
              children: [
                Expanded(child: words),
                const SizedBox(width: 16),
                button,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget whereCard(String value, String label, String detail) {
    final colors = appColors(context);
    final selected = destination == value;
    return Material(
      key: ValueKey('warning-where-$value'),
      color: selected ? colors.accent.withValues(alpha: .12) : colors.input,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? colors.accent : colors.border,
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: () => setState(() => destination = value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<String>(value: value),
              const SizedBox(width: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(fontSize: 12.5, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget where() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionLabel('WHERE'),
      RadioGroup<String>(
        groupValue: destination,
        onChanged: (v) {
          if (v != null) setState(() => destination = v);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            whereCard(
              'operator',
              'Operator only',
              'In this app and as a notification. The stage keeps showing the timer.',
            ),
            const SizedBox(height: 10),
            whereCard(
              'stage',
              'Operator and stage',
              'Also on the LED sign and stage screens, then they go back to the timer.',
            ),
          ],
        ),
      ),
    ],
  );

  Widget howLong() {
    final colors = appColors(context);
    final scrolls = scrollsOnSign(cue);
    final byScroll = scrolls && scrollOnce;
    int? shownMs;
    try {
      shownMs = warningDurationMs(rule);
    } catch (_) {
      shownMs = null;
    }
    final value = byScroll
        ? shownMs == null
              ? 'one scroll'
              : 'about ${durationLabel(shownMs)}'
        : durationLabel(duration * 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionLabel('HOW LONG'),
        Semantics(
          button: !byScroll,
          child: InkWell(
            key: const ValueKey('warning-stays-up'),
            onTap: byScroll ? null : pickDuration,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Stays up for',
                          style: TextStyle(fontSize: 16),
                        ),
                        if (byScroll) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Set by one scroll. Turn off Scroll once to choose a time.',
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    value,
                    key: const ValueKey('warning-stays-up-value'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: byScroll ? colors.muted : colors.text,
                    ),
                  ),
                  if (!byScroll) Icon(Icons.chevron_right, color: colors.muted),
                ],
              ),
            ),
          ),
        ),
        if (scrolls)
          SwitchListTile(
            key: const ValueKey('warning-scroll-once'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Scroll once, then back to the timer'),
            subtitle: Text(
              'For text too long for the display.',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            value: scrollOnce,
            onChanged: (v) => setState(() => scrollOnce = v),
          ),
        help('The timer keeps running underneath.'),
      ],
    );
  }

  Widget onOrOff() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      sectionLabel('ON OR OFF'),
      SwitchListTile(
        key: const ValueKey('warning-enabled'),
        contentPadding: EdgeInsets.zero,
        title: Text(enabled ? 'Warning on' : 'Warning off'),
        subtitle: Text(
          enabled
              ? 'Fires in every service and rehearsal.'
              : 'Kept in the list but never fires.',
          style: TextStyle(fontSize: 12, color: appColors(context).muted),
        ),
        value: enabled,
        onChanged: (v) => setState(() => enabled = v),
      ),
    ],
  );

  Widget? errorLine() => error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            error!,
            key: const ValueKey('warning-error'),
            style: TextStyle(color: appColors(context).warning),
          ),
        );

  Widget deleteButton() => TextButton.icon(
    key: const ValueKey('warning-delete'),
    onPressed: deleting ? null : delete,
    icon: const Icon(Icons.delete_outline, size: 20),
    label: const Text('Delete warning'),
    style: TextButton.styleFrom(foregroundColor: appColors(context).error),
  );

  // Layouts ------------------------------------------------------------

  static const _gap = SizedBox(height: 24);

  List<Widget> oneColumn({required double previewWidth}) => [
    when(),
    _gap,
    whatItShows(previewWidth: previewWidth),
    _gap,
    where(),
    _gap,
    howLong(),
    _gap,
    onOrOff(),
    ?errorLine(),
  ];

  Widget twoColumns() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [when(), _gap, whatItShows(previewWidth: 380)],
        ),
      ),
      const SizedBox(width: 32),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [where(), _gap, howLong(), _gap, onOrOff(), ?errorLine()],
        ),
      ),
    ],
  );

  Widget phone() {
    final colors = appColors(context);
    return Dialog.fullscreen(
      key: const ValueKey('warning-editor-full-screen'),
      backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Cancel',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          actions: [
            Center(
              child: FilledButton(
                key: const ValueKey('warning-save'),
                onPressed: canSave ? save : null,
                child: const Text('Save'),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...oneColumn(previewWidth: double.infinity),
                if (widget.onDelete != null) ...[
                  const SizedBox(height: 16),
                  Divider(color: colors.border, height: 1),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: deleteButton(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget dialog({required bool wide}) => Dialog(
    key: ValueKey(wide ? 'warning-editor-two-columns' : 'warning-editor'),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 908 : 568),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: wide
                    ? twoColumns()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: oneColumn(previewWidth: 340),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.onDelete != null) deleteButton(),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const ValueKey('warning-save'),
                  onPressed: canSave ? save : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 54),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: const Text('Save warning'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return phone();
    // The room a dialog has, inside its margins at either side.
    return dialog(wide: width - 80 >= 900);
  }
}

/// The warning's text on the LED sign, playing by itself as the sign
/// would show it: scrolling text scrolls, a flash flashes. Its clock
/// counts frames of the preview, so it starts again with new text.
class _PlayingSignPreview extends StatefulWidget {
  final TextLayout layout;
  const _PlayingSignPreview(this.layout);
  @override
  State<_PlayingSignPreview> createState() => _PlayingSignPreviewState();
}

class _PlayingSignPreviewState extends State<_PlayingSignPreview> {
  static const _step = Duration(milliseconds: 80);
  Timer? timer;
  int elapsedMs = 0;
  String? preparing;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(_step, (_) {
      if (!mounted) return;
      // With reduced motion the sign holds still.
      if (reduceAppMotion(context)) return;
      setState(() => elapsedMs += _step.inMilliseconds);
    });
  }

  @override
  void didUpdateWidget(_PlayingSignPreview old) {
    super.didUpdateWidget(old);
    if (old.layout != widget.layout) elapsedMs = 0;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    List<bool>? pixels;
    try {
      pixels = renderPixels(layout, elapsedMs);
    } catch (_) {
      pixels = null;
      // Tinos is drawn by the device; ask once for this text.
      final key = layout.font == 'tinos'
          ? NativeDisplayFonts.key(layout)
          : null;
      if (key != null && key != preparing) {
        preparing = key;
        NativeDisplayFonts.prepare(layout).then((_) {
          if (mounted) setState(() {});
        }, onError: (_) {});
      }
    }
    if (pixels != null) {
      return RepaintBoundary(child: LedMatrix(pixels: pixels));
    }
    return AspectRatio(
      aspectRatio: 2,
      child: Center(
        child: Text(
          'Preview is being prepared',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: appColors(context).muted),
        ),
      ),
    );
  }
}
