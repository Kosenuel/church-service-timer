import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/stage_screen_views.dart';

class QuickMessageComposer extends StatefulWidget {
  final QuickMessage initial;
  final List<QuickMessage> presets;
  final ValueChanged<QuickMessage>? onChanged;
  final Future<bool?> Function(QuickMessage)? onSend;
  final Future<bool> Function(QuickMessage)? onSavePreset;
  final String saveLabel;

  /// Widgets shown between the preview and the fields (recipients, banners).
  final List<Widget> header;
  final String? previewLabel;

  /// Fills its parent with a scrolling body and a pinned action bar.
  final bool sticky;
  final Future<bool?> Function(QuickMessage)? onTest;

  /// Why Send is unavailable, shown on the disabled button.
  final String? sendUnavailableReason;

  /// The specific reason the last action failed, when the app knows it.
  final String? Function()? failureReason;
  const QuickMessageComposer({
    super.key,
    required this.initial,
    this.presets = const [],
    this.onChanged,
    this.onSend,
    this.onSavePreset,
    this.saveLabel = 'Save as preset',
    this.header = const [],
    this.previewLabel,
    this.sticky = false,
    this.onTest,
    this.sendUnavailableReason,
    this.failureReason,
  });
  @override
  State<QuickMessageComposer> createState() => _QuickMessageComposerState();
}

class _QuickMessageComposerState extends State<QuickMessageComposer> {
  late final TextEditingController headline, body;
  late QuickMessage style;
  bool busy = false;
  int? selectedPreset;
  String? error;
  QuickMessage get value => QuickMessage(
    headline: headline.text.trim(),
    body: body.text.trim(),
    bold: style.bold,
    italic: style.italic,
    align: style.align,
    palette: style.palette,
    seconds: style.seconds,
    scale: style.scale,
    requestSeen: style.requestSeen,
  );
  @override
  void initState() {
    super.initState();
    style = widget.initial;
    headline = TextEditingController(text: style.headline);
    body = TextEditingController(text: style.body);
  }

  @override
  void dispose() {
    headline.dispose();
    body.dispose();
    super.dispose();
  }

  void changed({
    bool? bold,
    bool? italic,
    bool? requestSeen,
    String? align,
    String? palette,
    int? seconds,
    double? scale,
  }) {
    setState(() {
      selectedPreset = null;
      style = QuickMessage(
        body: body.text,
        bold: bold ?? style.bold,
        italic: italic ?? style.italic,
        requestSeen: requestSeen ?? style.requestSeen,
        align: align ?? style.align,
        palette: palette ?? style.palette,
        seconds: seconds ?? style.seconds,
        scale: scale ?? style.scale,
      );
      error = null;
    });
    widget.onChanged?.call(value);
  }

  Future<void> run(
    Future<bool?> Function(QuickMessage) action,
    String success,
  ) async {
    try {
      value.validate();
    } catch (e) {
      setState(() => error = '$e');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await action(value);
      if (mounted)
        setState(
          () => error = ok == null
              ? null
              : ok
              ? success
              : widget.failureReason?.call() ??
                    'Could not complete the action. Check the connection or storage and try again.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'Could not complete the action. Please try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get styleSummary {
    final size = switch (style.scale) {
      < .9 => 'Comfortable',
      > 1.1 => 'Extra large',
      _ => 'Large',
    };
    final align = switch (style.align) {
      'left' => 'left',
      'right' => 'right',
      _ => 'centred',
    };
    return [
      size,
      align,
      style.palette,
      if (style.bold) 'bold',
      if (style.italic) 'italic',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final content = <Widget>[
      if (widget.previewLabel != null) ...[
        Text(
          widget.previewLabel!.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1,
            color: colors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
      ],
      ClipRRect(
        key: const ValueKey('quick-message-preview'),
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RichStageMessage(message: value),
        ),
      ),
      const SizedBox(height: 14),
      ...widget.header,
      if (widget.presets.isNotEmpty) ...[
        ChoiceField<int>(
          key: ValueKey(widget.presets.length),
          value: selectedPreset,
          decoration: const InputDecoration(labelText: 'Choose a preset'),
          options: [
            for (var i = 0; i < widget.presets.length; i++)
              ChoiceOption(value: i, label: widget.presets[i].name),
          ],
          onChanged: (i) {
            if (i == null) return;
            setState(() {
              selectedPreset = i;
              style = widget.presets[i];
              headline.text = style.headline;
              body.text = style.body;
              error = null;
            });
            widget.onChanged?.call(value);
          },
        ),
        const SizedBox(height: 14),
      ],
      TextField(
        controller: headline,
        maxLength: 48,
        decoration: const InputDecoration(
          labelText: 'Headline (optional)',
          counterText: '',
        ),
        onChanged: (_) => changed(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: body,
        minLines: 2,
        maxLines: 5,
        maxLength: 160,
        decoration: const InputDecoration(
          labelText: 'Message',
          hintText: 'A discreet message for the person on stage',
          counterText: '',
        ),
        onChanged: (_) => changed(),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${value.length}/160 characters',
            style: TextStyle(
              fontSize: 12,
              color: value.length > 160 ? colors.error : colors.muted,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        child: Column(
          children: [
            ExpansionTile(
              key: const ValueKey('quick-message-style'),
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(Icons.format_paint_outlined, color: colors.muted),
              title: const Text('Style'),
              subtitle: Text(styleSummary, style: muted),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Bold'),
                      selected: style.bold,
                      onSelected: (v) => changed(bold: v),
                    ),
                    FilterChip(
                      label: const Text('Italic'),
                      selected: style.italic,
                      onSelected: (v) => changed(italic: v),
                    ),
                    for (final a in ['left', 'center', 'right'])
                      IconButton(
                        tooltip: 'Align $a',
                        isSelected: style.align == a,
                        onPressed: () => changed(align: a),
                        icon: Icon(
                          a == 'left'
                              ? Icons.format_align_left
                              : a == 'right'
                              ? Icons.format_align_right
                              : Icons.format_align_center,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in ['white', 'amber', 'sky', 'mint'])
                      ChoiceChip(
                        label: Text(p[0].toUpperCase() + p.substring(1)),
                        selected: style.palette == p,
                        onSelected: (_) => changed(palette: p),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ChoiceField<double>(
                  key: ValueKey('size-${style.scale}'),
                  value: style.scale,
                  decoration: const InputDecoration(labelText: 'Text size'),
                  options: const [
                    ChoiceOption(value: .85, label: 'Comfortable'),
                    ChoiceOption(value: 1.0, label: 'Large'),
                    ChoiceOption(value: 1.15, label: 'Extra large'),
                  ],
                  onChanged: (v) => changed(scale: v),
                ),
              ],
            ),
            const AppDivider(),
            ListTile(
              leading: Icon(Icons.timer_outlined, color: colors.muted),
              title: const Text('Show for'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    style.seconds == 0
                        ? 'Until cleared'
                        : formatTime(style.seconds * 1000),
                    style: TextStyle(color: colors.muted),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              onTap: busy
                  ? null
                  : () async {
                      final value = await showWheelTimePicker(
                        context,
                        title: 'Message duration · 00:00 means Until cleared',
                        initial: style.seconds,
                        allowZero: true,
                      );
                      if (value != null && mounted) changed(seconds: value);
                    },
            ),
            const AppDivider(),
            CheckboxListTile(
              value: style.requestSeen,
              onChanged: busy ? null : (v) => changed(requestSeen: v),
              secondary: Icon(Icons.done_all, color: colors.muted),
              title: const Text('Request Seen acknowledgement'),
              subtitle: Text(
                'The recipient taps Seen on a paired stage screen. Web screens show the message without asking.',
                style: muted,
              ),
            ),
          ],
        ),
      ),
      if (value.length > 100 && style.seconds > 0 && style.seconds < 15)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'For a longer message, consider 15 or 30 seconds.',
            style: TextStyle(color: colors.warning, fontSize: 12),
          ),
        ),
      if (error != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!)),
    ];
    final sendable = widget.saveLabel == 'Save as preset';
    final send = UnavailableAction(
      reason: busy
          ? 'Wait for the current message to finish.'
          : widget.onSend == null
          ? widget.sendUnavailableReason ??
                'Connect a stage screen and enable operator controls first.'
          : null,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: busy || widget.onSend == null
            ? null
            : () => run(widget.onSend!, 'Message sent.'),
        icon: const Icon(Icons.send),
        label: const Text('Send message'),
      ),
    );
    final savePreset = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
      onPressed: busy || widget.onSavePreset == null
          ? null
          : () => run(widget.onSavePreset!, 'Preset saved.'),
      icon: const Icon(Icons.bookmark_add_outlined),
      label: Text(sendable ? 'Save preset' : widget.saveLabel),
    );
    final actions = sendable
        ? Row(
            children: [
              if (widget.onTest != null) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: busy
                      ? null
                      : () => run(widget.onTest!, 'Test sent for 5 seconds.'),
                  child: const Text('Test 5 s'),
                ),
                const SizedBox(width: 8),
              ],
              IconButton.outlined(
                tooltip: 'Save as preset',
                onPressed: busy || widget.onSavePreset == null
                    ? null
                    : () => run(widget.onSavePreset!, 'Preset saved.'),
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(child: send),
            ],
          )
        : savePreset;
    if (!widget.sticky)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...content, const SizedBox(height: 16), actions],
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: content,
          ),
        ),
        Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: actions,
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Send to" choices: only screens that can receive a message now, with
/// counts. A choice that has gone away stays visible, disabled, so it never
/// changes silently under the operator.
List<ChoiceOption<String>> quickAudienceChoices({
  required List<({String id, String name})> screens,
  required String current,
  required String Function(String id) groupOf,
  required String? Function(String id) savedName,
}) {
  final groups = <String, int>{};
  for (final s in screens.where((s) => !s.id.startsWith('web:'))) {
    groups.update(groupOf(s.id), (n) => n + 1, ifAbsent: () => 1);
  }
  final options = <ChoiceOption<String>>[
    ChoiceOption(
      value: 'all',
      label: screens.isEmpty
          ? 'No stage screens connected'
          : 'All connected stage screens · ${screens.length}',
      enabled: screens.isNotEmpty,
    ),
    for (final g in screenGroups.entries)
      if (groups[g.key] != null)
        ChoiceOption(
          value: 'group:${g.key}',
          label: '${g.value} screens · ${groups[g.key]}',
        ),
    for (final s in screens)
      ChoiceOption(value: 'device:${s.id}', label: s.name),
  ];
  if (!options.any((o) => o.value == current)) {
    final group = current.startsWith('group:')
        ? screenGroups[current.substring(6)]
        : null;
    final id = current.startsWith('device:') ? current.substring(7) : '';
    final name =
        savedName(id) ?? (id.startsWith('web:') ? 'Web screen' : 'Screen');
    options.add(
      ChoiceOption(
        value: current,
        label: group != null
            ? '$group screens · none connected'
            : '$name · offline',
        enabled: false,
      ),
    );
  }
  return options;
}
