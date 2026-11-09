import 'dart:async';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';

Future<bool?> reviewSavedDraft(BuildContext context) => showDialog<bool>(
  context: context,
  animationStyle: reduceAppMotion(context) ? AnimationStyle.noAnimation : null,
  builder: (ctx) => AlertDialog(
    title: const Text('Restore program draft?'),
    content: const Text(
      'An unfinished edit is saved on this phone. Restore it for review; the saved program changes only when you save.',
    ),
    actions: [
      StackedDialogActions(
        children: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore draft'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ],
  ),
);

extension EditorInsights on TemplateEditorState {
  Future<void> reviewDurationSuggestions() async {
    final program = Timeline(
      name.text,
      segments,
      widget.initial.display,
      type: templateType,
    );
    final insights = durationInsights(program, widget.reports);
    final chosen = <int>{};
    final yes = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Suggested durations'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Median active time from up to five comparable services, rounded up to a minute. Select changes to apply to this draft.',
                  ),
                  if (insights.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'At least three comparable services with matching, unique segment names are needed.',
                      ),
                    ),
                  AppMenuList(
                    children: [
                      for (final i in insights)
                        CheckboxListTile(
                          title: Text(i.name),
                          subtitle: Text(
                            '${i.exceeded}/${i.samples} over allocation · ${i.currentMinutes} to ${i.suggestedMinutes} min',
                          ),
                          value: chosen.contains(i.index),
                          onChanged: i.currentMinutes == i.suggestedMinutes
                              ? null
                              : (v) => update(() {
                                  if (v!) {
                                    chosen.add(i.index);
                                  } else {
                                    chosen.remove(i.index);
                                  }
                                }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Apply to draft'),
            ),
          ],
        ),
      ),
    );
    if (yes != true || !mounted) return;
    change(() {
      for (final i in insights.where((v) => chosen.contains(v.index))) {
        final s = segments[i.index];
        segments[i.index] = Segment(
          s.name,
          i.suggestedMinutes,
          speaker: s.speaker,
          notes: s.notes,
          protected: s.protected,
        );
      }
    });
  }
}
