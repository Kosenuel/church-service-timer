import 'dart:async';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:flutter/material.dart';

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

extension TimeRecoveryViews on HomeState {
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
}
