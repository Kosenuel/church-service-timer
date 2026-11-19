import 'dart:async';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/programs/segment_library_views.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/wide_layout.dart';

class TemplateEditor extends StatefulWidget {
  final Timeline initial;
  final Set<String> existingNames;
  final TextLayout defaultEnd;
  final bool upcomingOnly;
  final bool? creating;
  final ValueChanged<Json>? onDraftChanged;
  final AppController? draftController;
  final List<ServiceReport> reports;
  const TemplateEditor({
    super.key,
    required this.initial,
    required this.existingNames,
    this.defaultEnd = defaultEndScreen,
    this.upcomingOnly = false,
    this.creating,
    this.onDraftChanged,
    this.draftController,
    this.reports = const [],
  });
  @override
  State<TemplateEditor> createState() => TemplateEditorState();
}

class TemplateEditorState extends State<TemplateEditor> {
  late TextEditingController name;
  late List<Segment> segments;
  late TextLayout endScreen;
  late String templateType;
  String? error;

  /// Whether anything has been changed yet; "Draft saved" waits for it.
  bool touched = false;
  void saveDraft() {
    if (!touched && mounted) setState(() => touched = true);
    _saveDraft();
  }

  void _saveDraft() => widget.onDraftChanged?.call({
    'name': name.text,
    'type': templateType,
    'segments': [for (final s in segments) s.toJson()],
    'end': endScreen.toJson(),
  });
  void change(VoidCallback action) {
    setState(action);
    saveDraft();
  }

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial.name);
    segments = [...widget.initial.segments];
    endScreen = widget.initial.display.end;
    templateType = widget.initial.type;
    name.addListener(saveDraft);
  }

  @override
  void dispose() {
    name.removeListener(saveDraft);
    name.dispose();
    super.dispose();
  }

  Future<void> segment({int? index}) async {
    final label = TextEditingController(
      text: index == null ? '' : segments[index].name,
    );
    var durationSeconds = index == null ? 300 : segments[index].durationSeconds;
    final speaker = TextEditingController(
      text: index == null ? '' : segments[index].speaker,
    );
    final notes = TextEditingController(
      text: index == null ? '' : segments[index].notes,
    );
    var protected = index == null ? false : segments[index].protected;
    String? issue, saved;
    Segment build() {
      final s = Segment.fromJson({
        'name': label.text,
        'minutes': durationSeconds ~/ 60,
        'seconds': durationSeconds % 60,
        'speaker': speaker.text,
        'notes': notes.text,
        'protected': protected,
      });
      require(
        s.durationMs <= supportedCountdownMs,
        'Keep each segment within 59:59.',
      );
      return s;
    }

    final result = await showDialog<Segment>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text(index == null ? 'Add segment' : 'Edit segment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Segment name'),
              ),
              const SizedBox(height: 12),
              DurationField(
                key: const ValueKey('segment-duration-field'),
                value: formatTime(durationSeconds * 1000),
                onTap: () async {
                  final value = await showWheelTimePicker(
                    ctx,
                    title: 'Set segment duration',
                    initial: durationSeconds,
                  );
                  if (value != null && ctx.mounted)
                    update(() => durationSeconds = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: speaker,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Speaker (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Private operator notes',
                  helperMaxLines: 3,
                  helperText:
                      'Never shown on the sign. Included in program backups.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Protect duration'),
                subtitle: const Text(
                  'Time recovery will not shorten this segment.',
                ),
                value: protected,
                onChanged: (v) => update(() => protected = v),
              ),
              if (issue != null)
                Text(
                  issue!,
                  style: TextStyle(color: appColors(context).warning),
                ),
              if (saved != null)
                Text(
                  saved!,
                  style: TextStyle(color: appColors(context).accent),
                ),
            ],
          ),
          actions: [
            StackedDialogActions(
              children: [
                FilledButton(
                  onPressed: () {
                    try {
                      Navigator.pop(ctx, build());
                    } catch (e) {
                      update(() => issue = e.toString());
                    }
                  },
                  child: const Text('Save segment'),
                ),
                if (widget.draftController case final library?)
                  OutlinedButton.icon(
                    key: const ValueKey('save-segment-to-library'),
                    onPressed: () async {
                      try {
                        final s = build();
                        if (!await library.commit(
                          (draft, _) => draft.saveLibrarySegment(s),
                        ))
                          throw RuleError(
                            library.error ?? 'Could not save to the library.',
                          );
                        update(() {
                          issue = null;
                          saved = 'Saved “${s.name}” to the segment library.';
                        });
                      } catch (e) {
                        update(() {
                          saved = null;
                          issue = e.toString();
                        });
                      }
                    },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save to library'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      label.dispose();

      speaker.dispose();
      notes.dispose();
    });
    if (result != null && mounted) {
      change(() {
        if (index == null) {
          segments.add(result);
        } else {
          segments[index] = result;
        }
      });
    } else if (saved != null && mounted) {
      // Shows From library after a save to the library, even on Cancel.
      setState(() {});
    }
  }

  void save() {
    try {
      if (widget.upcomingOnly) {
        require(segments.length <= 200, 'Keep at most 200 segments.');
        for (final s in segments) {
          Segment.fromJson(s.toJson());
        }
        Navigator.pop(
          context,
          Timeline(
            widget.initial.name,
            segments,
            widget.initial.display,
            type: widget.initial.type,
          ),
        );
        return;
      }
      final t = Timeline.fromJson(
        Timeline(
          name.text,
          segments,
          widget.initial.display.withEnd(endScreen),
          type: templateType,
        ).toJson(),
      );
      require(
        !widget.existingNames.contains(t.name.toLowerCase()),
        'A program with this name already exists.',
      );
      validateTimelinePixels(t);
      Navigator.pop(context, t);
    } catch (e) {
      change(() => error = e.toString());
    }
  }

  Future<void> editDuration(int i) async {
    final value = await showWheelTimePicker(
      context,
      title: 'Set segment duration',
      initial: segments[i].durationSeconds,
    );
    if (value == null || !mounted) return;
    try {
      final next = Segment.fromJson({
        ...segments[i].toJson(),
        'minutes': value ~/ 60,
        'seconds': value % 60,
      });
      change(() {
        segments[i] = next;
        error = null;
      });
    } catch (e) {
      change(() => error = e.toString());
    }
  }

  Future<void> editEndScreen() async {
    final next = await showDialog<TextLayout>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => TextComposer(
        initial: endScreen,
        title: 'Program end screen',
        button: 'Use end screen',
      ),
    );
    if (next != null && mounted) change(() => endScreen = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final totalMs = segments.fold<int>(0, (a, s) => a + s.durationMs);
    final creating = widget.creating ?? widget.initial.name.isEmpty;
    final draft = widget.draftController;
    // In a wide window the saved-program editor keeps the running order
    // beside the form. Upcoming segments open as a dialog instead.
    final wide = isWideWindow(context) && !widget.upcomingOnly;
    // The form's column in a wide window, bar padding included.
    const formWidth = 712.0;
    final fields = <Widget>[
      if (!widget.upcomingOnly) ...[
        if (wide) ...[
          const PaneLabel('Name and group'),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Program name',
            hintText: 'Youth sunday',
          ),
        ),
        const SizedBox(height: 14),
        ChoiceField<String>(
          value: templateType,
          decoration: const InputDecoration(labelText: 'Program group'),
          options: const [
            ChoiceOption(value: 'service', label: 'Service'),
            ChoiceOption(value: 'rehearsal', label: 'Rehearsal'),
          ],
          onChanged: (value) => change(() => templateType = value!),
        ),
        const SizedBox(height: 6),
        Text(
          'Grouping organises programs. Choose rehearsal speed when starting.',
          style: muted,
        ),
      ],
      if (widget.upcomingOnly)
        Text(
          'Edit only the upcoming segments. Current and completed segments, saved programs and end screens stay unchanged.',
          style: TextStyle(color: colors.muted),
        ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'SEGMENTS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: colors.muted,
                ),
              ),
            ),
          ),
          // Only when there is something to reorder.
          if (segments.length > 1)
            Text('Drag the handle to reorder', style: muted),
        ],
      ),
      // Only when past services can actually suggest something;
      // otherwise the dialog would be a dead end.
      if (!widget.upcomingOnly &&
          widget.reports.isNotEmpty &&
          durationInsights(
            Timeline(
              name.text,
              segments,
              widget.initial.display,
              type: templateType,
            ),
            widget.reports,
          ).isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: reviewDurationSuggestions,
            icon: const Icon(Icons.insights_outlined, size: 18),
            label: const Text('Learn from previous services'),
          ),
        ),
      const SizedBox(height: 8),
      if (segments.isNotEmpty)
        Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.border),
          ),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: segments.length,
            onReorderItem: (a, b) => change(() {
              segments.insert(b, segments.removeAt(a));
            }),
            itemBuilder: (context, i) {
              final s = segments[i];
              final detail = [
                if (s.speaker.isNotEmpty) s.speaker,
                if (s.notes.isNotEmpty) 'private note',
                if (s.protected) 'protected',
              ].join(' · ');
              return Material(
                key: ValueKey(s),
                color: colors.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i > 0) const AppDivider(),
                    InkWell(
                      onTap: () => segment(index: i),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(
                                  Icons.drag_indicator,
                                  color: colors.muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (detail.isNotEmpty)
                                    Text(detail, style: muted),
                                ],
                              ),
                            ),
                            ActionChip(
                              key: ValueKey('segment-duration-$i'),
                              label: Text(
                                formatTime(s.durationMs),
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              onPressed: () => editDuration(i),
                            ),
                            IconButton(
                              tooltip: 'Remove segment',
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  change(() => segments.removeAt(i)),
                              icon: Icon(
                                Icons.close,
                                size: 18,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 10),
      () {
        final add = OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: wide ? const Size(0, 44) : const Size.fromHeight(46),
          ),
          onPressed: segments.length < 200 ? segment : null,
          icon: const Icon(Icons.add),
          label: const Text('Add segment'),
        );
        final library = widget.draftController;
        final fromLibrary =
            library == null || library.state.segmentLibrary.isEmpty
            ? null
            : OutlinedButton.icon(
                key: const ValueKey('add-from-library'),
                style: OutlinedButton.styleFrom(
                  minimumSize: wide
                      ? const Size(0, 44)
                      : const Size.fromHeight(46),
                ),
                onPressed: segments.length < 200
                    ? () async {
                        final s = await pickLibrarySegment(context, library);
                        if (s != null && mounted) change(() => segments.add(s));
                      }
                    : null,
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('From library'),
              );
        // Ordinary-size buttons in a wide window; a full-width
        // row on a phone.
        return wide
            ? Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [add, ?fromLibrary],
                ),
              )
            : Row(
                children: [
                  Expanded(child: add),
                  if (fromLibrary != null) ...[
                    const SizedBox(width: 10),
                    Expanded(child: fromLibrary),
                  ],
                ],
              );
      }(),
      if (!widget.upcomingOnly) ...[
        const SizedBox(height: 16),
        Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                key: const ValueKey('edit-end-screen'),
                leading: Icon(Icons.flag_outlined, color: colors.muted),
                title: Text(
                  'End screen · ${endScreen.text}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  sameLayout(endScreen, widget.defaultEnd)
                      ? deviceText('Uses the current default · tap to edit')
                      : deviceText(
                          'This program’s own end screen · tap to edit',
                        ),
                  style: muted,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: editEndScreen,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 168,
                    child: LedMatrix(pixels: renderPixels(endScreen, 0)),
                  ),
                ),
              ),
              if (!sameLayout(endScreen, widget.defaultEnd))
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: TextButton(
                      onPressed: () =>
                          change(() => endScreen = widget.defaultEnd),
                      child: const Text('Use current default'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('Program edits apply the next time you load it.', style: muted),
      ],
    ];
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: TextStyle(color: colors.warning)),
          ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    durationLabel(totalMs),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${plural(segments.length, 'segment')} · planned length',
                    style: muted,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              onPressed: save,
              icon: const Icon(Icons.check),
              label: Text(
                widget.upcomingOnly
                    ? 'Review rundown changes'
                    : creating
                    ? 'Create program'
                    : 'Save changes',
              ),
            ),
          ],
        ),
      ],
    );
    final bar = Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: wide
              ? const EdgeInsets.fromLTRB(24, 12, 24, 14)
              : const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          // In a wide window the bar spans the form's pane and its
          // contents line up with the form.
          child: wide
              ? Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: formWidth),
                    child: actions,
                  ),
                )
              : actions,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.upcomingOnly ? 'Upcoming segments' : 'Program editor',
        ),
        actions: [
          if (draft != null && touched)
            AnimatedBuilder(
              animation: draft,
              builder: (context, _) => draft.draftError == null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Center(
                        child: Text(
                          'Draft saved',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ),
                    )
                  : TextButton(
                      onPressed: draft.flushEditDrafts,
                      child: Text(draft.draftError!),
                    ),
            ),
        ],
        bottom: draft?.liveSession.active == true
            ? RunningServiceBar.forContext(context, controller: draft!)
            : null,
      ),
      body: wide
          ? SplitPage(
              mainMaxWidth: double.infinity,
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, space) {
                        final side = ((space.maxWidth - formWidth) / 2).clamp(
                          24.0,
                          double.infinity,
                        );
                        return ListView(
                          key: const ValueKey('program-editor-form'),
                          primary: false,
                          padding: EdgeInsets.fromLTRB(side, 20, side, 28),
                          children: fields,
                        );
                      },
                    ),
                  ),
                  bar,
                ],
              ),
              side: ProgramDraftSummary(
                segments: segments,
                insights: widget.reports.isEmpty
                    ? const []
                    : durationInsights(
                        Timeline(
                          name.text,
                          segments,
                          widget.initial.display,
                          type: templateType,
                        ),
                        widget.reports,
                      ),
              ),
            )
          : SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: fields,
              ),
            ),
      bottomNavigationBar: wide ? null : bar,
    );
  }
}

/// The program being edited, as it would run: when each segment starts,
/// counted from the start of the service, and the total. Shown beside the
/// editor in a wide window and updated as segments change.
class ProgramDraftSummary extends StatelessWidget {
  final List<Segment> segments;
  final List<DurationInsight> insights;
  const ProgramDraftSummary({
    super.key,
    required this.segments,
    this.insights = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    const figures = [FontFeature.tabularFigures()];
    final total = segments.fold<int>(0, (a, s) => a + s.durationMs);
    final rule = Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Divider(height: 1, thickness: 1, color: colors.border),
    );
    var at = 0;
    // Minutes and seconds, with the hour once the service passes one.
    String offset(int ms) {
      final seconds = ms ~/ 1000;
      String two(int n) => n.toString().padLeft(2, '0');
      return seconds < 3600
          ? '${two(seconds ~/ 60)}:${two(seconds % 60)}'
          : '${seconds ~/ 3600}:${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}';
    }

    return SingleChildScrollView(
      key: const ValueKey('program-editor-summary'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PaneLabel('Running order'),
          const SizedBox(height: 6),
          Text(
            segments.isEmpty
                ? 'Add a segment to see when each part starts and how long the service runs.'
                : 'When each segment starts, counted from the start of the service.',
            style: muted,
          ),
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 14),
            SegmentBar(
              program: Timeline('', segments, DisplaySettings()),
              height: 12,
            ),
            const SizedBox(height: 10),
            for (final (i, s) in segments.indexed) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        offset((at += s.durationMs) - s.durationMs),
                        style: muted.copyWith(fontFeatures: figures),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      s.durationText,
                      style: const TextStyle(fontFeatures: figures),
                    ),
                  ],
                ),
              ),
            ],
            Divider(height: 1, thickness: 1, color: colors.muted),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(
                      offset(total),
                      style: muted.copyWith(fontFeatures: figures),
                    ),
                  ),
                  Expanded(child: Text('Service ends', style: muted)),
                  const SizedBox(width: 12),
                  Text(
                    durationLabel(total),
                    key: const ValueKey('program-editor-total'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: figures,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (insights.isNotEmpty) ...[
            rule,
            const PaneLabel('Past services'),
            for (final i in insights)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ran over in ${i.exceeded} of ${i.samples} services · planned ${i.currentMinutes} min · suggested ${i.suggestedMinutes} min',
                      style: muted,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
