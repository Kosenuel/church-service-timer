import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/reports/report_views.dart';

/// Bars above the line are minutes over plan, below are minutes under, on
/// one scale. Each bar is a button; the chosen one is highlighted.
class OverUnderChart extends StatelessWidget {
  final List<ServiceReport> reports;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const OverUnderChart({
    super.key,
    required this.reports,
    required this.selectedId,
    required this.onSelect,
  });
  static const height = 200.0;
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final variances = [for (final r in reports) r.totalMs! - r.plannedMs];
    final most = variances.fold<int>(60000, (m, v) => math.max(m, v.abs()));
    const half = height / 2 - 8;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(child: Container(height: 1, color: colors.border)),
          ),
          Row(
            children: [
              for (var i = 0; i < reports.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 64),
                        child: Semantics(
                          button: true,
                          selected: reports[i].id == selectedId,
                          label:
                              '${reports[i].name}, ${reportDate(reports[i].startedWall ?? reports[i].endedWall)}, ${variances[i].abs() < 1000 ? 'on time' : '${durationLabel(variances[i].abs())} ${variances[i] > 0 ? 'over' : 'under'}'}',
                          child: Material(
                            color: reports[i].id == selectedId
                                ? colors.accent.withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              key: ValueKey('graph-bar-${reports[i].id}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => onSelect(reports[i].id),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FractionallySizedBox(
                                        widthFactor: .7,
                                        child: Container(
                                          height: variances[i] >= 1000
                                              ? math.max(
                                                  3,
                                                  half * variances[i] / most,
                                                )
                                              : variances[i] > -1000
                                              ? 4
                                              : 0,
                                          decoration: BoxDecoration(
                                            color: variances[i] >= 1000
                                                ? colors.warning
                                                : colors.accent,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(6),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: FractionallySizedBox(
                                        widthFactor: .7,
                                        child: Container(
                                          height: variances[i] <= -1000
                                              ? math.max(
                                                  3,
                                                  half * -variances[i] / most,
                                                )
                                              : 0,
                                          decoration: BoxDecoration(
                                            color: colors.info,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  bottom: Radius.circular(6),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DurationEntry {
  final String title, subtitle;
  final int planned;
  final int? actual;
  final bool uncertain;
  final VoidCallback? onTap;
  const DurationEntry({
    required this.title,
    required this.subtitle,
    required this.planned,
    required this.actual,
    this.uncertain = false,
    this.onTap,
  });
}

/// Paired bars share a zero baseline and scale; missing timing is never a zero.
class DurationChart extends StatelessWidget {
  final List<DurationEntry> entries;
  const DurationChart({super.key, required this.entries});
  @override
  Widget build(BuildContext context) {
    final maxMs = entries.fold<int>(
      0,
      (m, e) => math.max(m, math.max(e.planned, e.actual ?? 0)),
    );
    final scale = math.max(60000, (maxMs / 60000).ceil() * 60000);
    Widget bar(String label, int? value, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(color: appColors(context).muted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Semantics(
              label:
                  '$label: ${value == null ? 'not recorded' : durationLabel(value)}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (value ?? 0) / scale,
                  minHeight: 11,
                  color: color,
                  backgroundColor: appColors(context).track,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Text(
              value == null ? 'Not recorded' : durationLabel(value),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: value == null ? appColors(context).muted : color,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Bar scale  0 — ${durationLabel(scale)}',
          style: TextStyle(color: appColors(context).muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < entries.length; i++)
          InkWell(
            onTap: entries[i].onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${entries[i].title}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (entries[i].onTap != null)
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: appColors(context).muted,
                        ),
                    ],
                  ),
                  Text(
                    entries[i].subtitle,
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  bar('Plan', entries[i].planned, appColors(context).muted),
                  bar(
                    'Actual',
                    entries[i].actual,
                    entries[i].uncertain
                        ? appColors(context).warning
                        : appColors(context).accent,
                  ),
                  if (entries[i].uncertain)
                    Text(
                      'Partial or uncertain timing',
                      style: TextStyle(
                        color: appColors(context).warning,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
