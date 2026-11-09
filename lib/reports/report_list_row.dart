import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/reports/report_outcome.dart';
import 'package:church_service_timer/reports/report_views.dart';

class ReportListRow extends StatelessWidget {
  final ServiceReport report;
  final VoidCallback onTap;
  const ReportListRow({
    super.key,
    required this.report,
    required this.onTap,
    this.onMenu,
    this.menu,
    this.selected = false,
    this.checked,
    this.onChecked,
  });
  final VoidCallback? onMenu;
  final Widget? menu;
  final bool selected;
  final bool? checked;
  final ValueChanged<bool?>? onChecked;
  @override
  Widget build(BuildContext context) {
    final r = report, colors = appColors(context);
    final variance = r.comparable ? r.totalMs! - r.plannedMs : null;
    final outcome = variance == null ? 'Partial' : outcomeLabel(variance);
    // Over is warm, under is cool, on time is the accent; they also differ
    // in lightness so they read apart without colour.
    final tone = variance == null
        ? colors.muted
        : variance >= 1000
        ? colors.warning
        : variance <= -1000
        ? colors.info
        : colors.accent;
    final when = DateTime.fromMillisecondsSinceEpoch(
      r.startedWall ?? r.endedWall,
    );
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final started = r.startedWall == null
        ? null
        : '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final meta = [
      r.totalMs == null
          ? 'Not fully recorded'
          : '${durationLabel(r.totalMs!)}${r.rehearsal ? ' simulated' : ''}',
      if (started != null) 'started $started',
      if (r.rehearsal || r.quickTimer) reportMode(r),
    ].join(' · ');
    return InkWell(
      key: ValueKey('open-report-${r.id}'),
      onTap: onTap,
      onLongPress: onMenu,
      highlightColor: colors.accent.withValues(alpha: .1),
      child: Container(
        color: selected || checked == true
            ? colors.accent.withValues(alpha: .12)
            : null,
        constraints: const BoxConstraints(minHeight: 72),
        padding: appLayout(context).rowInsets,
        child: Row(
          children: [
            if (checked != null) Checkbox(value: checked, onChanged: onChecked),
            Semantics(
              label: reportDate(r.startedWall ?? r.endedWall),
              child: ExcludeSemantics(
                child: Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.track,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        days[when.weekday - 1],
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${when.day}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (r.review != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 14,
                            color: colors.muted,
                            semanticLabel: 'Has review notes',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              key: ValueKey('report-outcome-${r.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                outcome,
                style: TextStyle(
                  color: tone,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (menu != null && checked == null) menu!,
            if (checked == null && menu == null && !selected)
              Icon(Icons.chevron_right, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
