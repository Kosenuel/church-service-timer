import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_menu.dart';
import 'time_picker.dart';
import 'domain.dart';
import 'main.dart';

Future<bool?> reviewSavedDraft(BuildContext context) => showDialog<bool>(
  context: context,
  animationStyle: reduceAppMotion(context) ? AnimationStyle.noAnimation : null,
  builder: (ctx) => AlertDialog(
    title: const Text('Restore program draft?'),
    content: const Text(
      'An unfinished edit is saved on this phone. Restore it for review; the saved program changes only when you save.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: const Text('Discard draft'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: const Text('Restore draft'),
      ),
    ],
  ),
);

extension ImprovementViews on HomeState {
  void offerUndo(String label, Future<bool> Function() restore) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (!await restore() && mounted)
              await showError(c.error ?? 'Could not restore the item.');
          },
        ),
      ),
    );
  }

  Future<void> deleteCueWithUndo(int index, TextLayout cue) async {
    if (!await c.deleteStageCue(index, cue) || !mounted) return;
    offerUndo(
      'Cue deleted',
      () => c.commit((draft, _) {
        require(draft.stageCues.length < 100, 'The cue list is full.');
        require(
          !draft.stageCues.any(
            (v) => v.toJson().toString() == cue.toJson().toString(),
          ),
          'This cue has already been restored.',
        );
        draft.stageCues.insert(math.min(index, draft.stageCues.length), cue);
      }),
    );
  }

  Future<void> saveWarningsWithUndo(DisplaySettings next) async {
    final before = c.state.defaults.warnings;
    final deleted = before
        .where((v) => !next.warnings.any((n) => n.seconds == v.seconds))
        .toList();
    if (!await c.setSharedWarnings(next.warnings)) {
      if (mounted) await showError(c.error ?? 'Could not save warnings.');
      return;
    }
    if (deleted.length == 1 &&
        next.warnings.length == before.length - 1 &&
        mounted) {
      final rule = deleted.single, position = before.indexOf(deleted.single);
      offerUndo(
        'Warning deleted',
        () => c.commit((draft, at) {
          final rules = [...draft.defaults.warnings];
          require(rules.length < 6, 'There are already six warnings.');
          require(
            !rules.any((r) => r.seconds == rule.seconds),
            'A warning at this time already exists.',
          );
          rules.insert(math.min(position, rules.length), rule);
          draft.defaults = draft.defaults.withWarnings(rules);
          draft.applySharedWarnings(at);
          draft.session.revision++;
        }),
      );
    }
  }

  Future<void> recoverTime() async {
    final s = c.state.session;
    if (!s.active || !c.pairing.localControl || controlsLocked) return;
    final revision = s.revision, id = s.id;
    final proposed = await Navigator.of(context).push<List<Segment>>(
      MaterialPageRoute(builder: (_) => TimeRecoveryPage(session: s)),
    );
    if (proposed == null || !mounted) return;
    if (!await c.commit((draft, at) {
          require(
            c.pairing.localControl && draft.session.id == id,
            'Service or operator control changed.',
          );
          replaceUpcoming(draft.session, proposed, at);
        }, revision: revision) &&
        mounted)
      await showError(c.error ?? 'Review the recovery plan again.');
  }

  Widget timingInsightsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Based on the last five completed, normal-speed services per program. Pauses, rehearsals and uncertain timing are excluded. At least three observations are needed.',
      ),
      const SizedBox(height: 16),
      for (final t in c.state.templates.where(
        (t) => t.type != 'rehearsal',
      )) ...[
        Text(t.name, style: Theme.of(context).textTheme.titleLarge),
        DurationInsightList(insights: durationInsights(t, c.state.reports)),
        TextButton.icon(
          onPressed: () => editTemplate(index: c.state.templates.indexOf(t)),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Review in program editor'),
        ),
        const Divider(),
      ],
    ],
  );
}

class DurationInsightList extends StatelessWidget {
  final List<DurationInsight> insights;
  const DurationInsightList({super.key, required this.insights});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (insights.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Not enough comparable services yet.'),
        ),
      for (final i in insights)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            i.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Exceeded its allocation in ${i.exceeded} of ${i.samples} services.\nCurrent ${i.currentMinutes} min · suggested ${i.suggestedMinutes} min',
          ),
        ),
    ],
  );
}

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
                      padding: EdgeInsets.all(16),
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

class TimeRecoveryPage extends StatefulWidget {
  final Session session;
  const TimeRecoveryPage({super.key, required this.session});
  @override
  State<TimeRecoveryPage> createState() => _TimeRecoveryPageState();
}

class _TimeRecoveryPageState extends State<TimeRecoveryPage> {
  int recoverSeconds = 60;
  late Session snapshot;
  String? error;
  List<Segment>? proposal;
  @override
  void initState() {
    super.initState();
    snapshot = Session.fromJson(widget.session.toJson());
  }

  List<Segment> get upcoming =>
      snapshot.timeline!.segments.skip(snapshot.index + 1).toList();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recover time')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Shorten upcoming segments while keeping at least one minute in each; shorter segments stay unchanged. The current timer and saved program stay unchanged.',
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Time to recover'),
          subtitle: Text(formatTime(recoverSeconds * 1000)),
          trailing: const Icon(Icons.expand_more),
          onTap: () async {
            final value = await showWheelTimePicker(
              context,
              title: 'Time to recover',
              initial: recoverSeconds,
            );
            if (value != null && mounted)
              setState(() {
                recoverSeconds = value;
                proposal = null;
                error = null;
              });
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Protect important segments',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (var i = 0; i < upcoming.length; i++) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(upcoming[i].name),
            subtitle: Text(
              '${upcoming[i].durationText}${proposal == null ? '' : ' to ${proposal![i].durationText}'}',
            ),
            value: upcoming[i].protected,
            onChanged: (v) => setState(() {
              final t = snapshot.timeline!, entries = [...t.segments];
              final s = upcoming[i];
              entries[snapshot.index + 1 + i] = Segment(
                s.name,
                s.minutes,
                seconds: s.seconds,
                speaker: s.speaker,
                notes: s.notes,
                protected: v,
              );
              snapshot.timeline = Timeline(
                t.name,
                entries,
                t.display,
                type: t.type,
              );
              proposal = null;
            }),
          ),
          const Divider(height: 1),
        ],
        if (upcoming.isEmpty) const Text('No upcoming segments to shorten.'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: appColors(context).error),
            ),
          ),
        const SizedBox(height: 20),
        if (proposal == null)
          FilledButton(
            onPressed: upcoming.isEmpty
                ? null
                : () => setState(() {
                    try {
                      proposal = timeRecoveryPlanSeconds(
                        snapshot,
                        recoverSeconds,
                      );
                      error = null;
                    } catch (e) {
                      error = '$e';
                    }
                  }),
            child: const Text('Review adjustments'),
          )
        else ...[
          const Text(
            'These changes apply to this running service only. Actual finish still depends on pauses and manual advances.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, proposal),
            icon: const Icon(Icons.check),
            label: const Text('Apply reviewed adjustments'),
          ),
        ],
      ],
    ),
  );
}
