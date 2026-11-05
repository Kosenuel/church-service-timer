import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

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

extension TimingInsightsViews on HomeState {
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
