import 'package:church_service_timer/shared/finish_widgets.dart';
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
      child: FinishPane(flatSurface: true, child: side),
    );
    // With a finish the content is a panel too, like the pane beside it, so
    // nothing on the page sits on the bare wall; the cards in it are set
    // into the panel (FinishCard).
    final content = Expanded(
      child: FinishPane(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: mainMaxWidth),
            child: main,
          ),
        ),
      ),
    );
    final line = finishRule(
      context,
      VerticalDivider(width: 1, thickness: 1, color: colors.border),
    );
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

/// Padding for a pushed page's scrolling list. In a wide window the
/// content sits in a centred column of at most [maxWidth] instead of
/// running from edge to edge; smaller windows keep [base] unchanged.
EdgeInsets widePagePadding(
  BuildContext context,
  EdgeInsets base, {
  double maxWidth = 640,
}) {
  if (!isWideWindow(context)) return base;
  final side = (MediaQuery.sizeOf(context).width - maxWidth) / 2;
  return base.copyWith(
    left: side > base.left ? side : base.left,
    right: side > base.right ? side : base.right,
  );
}

/// A short form or picker: a bottom sheet on a phone or tablet, and a
/// centred dialog with a Close button in a wide window, where a sheet
/// would hang off the bottom edge far from where the eye is.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool useSafeArea = false,
  bool reduceMotion = true,
  double maxWidth = 580,
}) {
  final still = reduceMotion && reduceAppMotion(context)
      ? AnimationStyle.noAnimation
      : null;
  if (!isWideWindow(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: still,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    animationStyle: still,
    builder: (ctx) => Dialog(
      key: const ValueKey('wide-sheet-dialog'),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(ctx).height * .85,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 4),
              child: builder(ctx),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens a small page (a short list or form with its own app bar): pushed
/// full screen on a phone or tablet, and shown as a centred dialog in a
/// wide window, so a few rows do not stretch across the whole screen.
Future<T?> pushAppPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 560,
  double height = 560,
  bool dismissible = true,
}) {
  if (!isWideWindow(context)) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (ctx) {
      final room = MediaQuery.sizeOf(ctx).height - 48;
      return Dialog(
        key: const ValueKey('wide-page-dialog'),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height < room ? height : room,
          child: builder(ctx),
        ),
      );
    },
  );
}
