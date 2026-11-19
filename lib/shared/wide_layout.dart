import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// A window wide enough for side-by-side panes: the same width at which
/// the desktop layouts take over Live.
const wideWindowMinWidth = 1200.0;

bool isWideWindow(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideWindowMinWidth;

/// A page in a wide window: the working content on the left, and a pane
/// beside it for what supports it (a preview, a summary, help). Both
/// scroll on their own. In a narrower window, build the phone page
/// instead; this widget is only for [isWideWindow].
class SplitPage extends StatelessWidget {
  final Widget main;
  final Widget side;

  /// The most the main content grows to; it sits at the top, centred in
  /// its share of the window.
  final double mainMaxWidth;

  /// The side pane's share of the window, between [sideMin] and [sideMax].
  final double sideShare, sideMin, sideMax;

  /// Whether the side pane is on the left (a list to pick from) rather
  /// than the right (a preview or summary).
  final bool sideFirst;
  const SplitPage({
    super.key,
    required this.main,
    required this.side,
    this.mainMaxWidth = 860,
    this.sideShare = .32,
    this.sideMin = 380,
    this.sideMax = 620,
    this.sideFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final pane = SizedBox(
      width: (MediaQuery.sizeOf(context).width * sideShare).clamp(
        sideMin,
        sideMax,
      ),
      child: ColoredBox(color: colors.surface, child: side),
    );
    final content = Expanded(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mainMaxWidth),
          child: main,
        ),
      ),
    );
    final line = VerticalDivider(width: 1, thickness: 1, color: colors.border);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sideFirst ? [pane, line, content] : [content, line, pane],
    );
  }
}

/// A small upper-case heading for a pane or a group, as on Live.
class PaneLabel extends StatelessWidget {
  final String text;
  const PaneLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: appColors(context).muted,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w700,
    ),
  );
}
