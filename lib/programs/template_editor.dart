import 'dart:async';
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
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!widget.upcomingOnly) ...[
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: segments.length < 200 ? segment : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add segment'),
                  ),
                ),
                if (widget.draftController case final library?
                    when library.state.segmentLibrary.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('add-from-library'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: segments.length < 200
                          ? () async {
                              final s = await pickLibrarySegment(
                                context,
                                library,
                              );
                              if (s != null && mounted)
                                change(() => segments.add(s));
                            }
                          : null,
                      icon: const Icon(Icons.bookmark_outline),
                      label: const Text('From library'),
                    ),
                  ),
                ],
              ],
            ),
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
                            ? 'Uses the current default · tap to edit'
                            : 'This program’s own end screen · tap to edit',
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
              Text(
                'Program edits apply the next time you load it.',
                style: muted,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Material(
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: colors.warning),
                    ),
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
            ),
          ),
        ),
      ),
    );
  }
}
