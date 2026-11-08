import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// Equal-width controls that wrap cleanly at narrow widths and large text sizes.
class ControlGrid extends StatelessWidget {
  final List<Widget> children;
  final int maxColumns;

  /// The narrowest a column may be before the grid drops a column.
  final double minWidth;

  /// A lone item on the last row spans it, instead of leaving a gap.
  final bool fillLastRow;
  const ControlGrid({
    super.key,
    required this.children,
    this.maxColumns = 3,
    this.minWidth = 118,
    this.fillLastRow = false,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final minimum = MediaQuery.textScalerOf(
        context,
      ).scale(minWidth).clamp(minWidth, 220.0);
      final columns = ((space.maxWidth + 10) / (minimum + 10)).floor().clamp(
        1,
        maxColumns,
      );
      final gap = appLayout(context).gap;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var column = 0;
                    column <
                        (fillLastRow && start + 1 == children.length
                            ? 1
                            : columns);
                    column++
                  ) ...[
                    if (column > 0) SizedBox(width: gap),
                    Expanded(
                      child: start + column < children.length
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: appLayout(context).controlHeight,
                              ),
                              child: children[start + column],
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
