import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:flutter/material.dart';

/// What a settings page returns when it has more to offer a wide window
/// than one column. In a phone or tablet window it is simply [main], so
/// the page looks as it always has; `openSettingsDetail` reads the rest
/// when the window is wide.
class SettingsWide extends StatelessWidget {
  /// The page as a phone shows it.
  final Widget main;

  /// The main content rearranged for a wide window, when one column is not
  /// the best use of it. Defaults to [main].
  final Widget? wideMain;

  /// The pane beside the content: a preview or a summary.
  final WidgetBuilder? side;

  /// The whole body in a wide window, for a page with its own panes.
  final WidgetBuilder? body;

  /// The most the main content grows to in a wide window.
  final double maxWidth;
  const SettingsWide({
    super.key,
    required this.main,
    this.wideMain,
    this.side,
    this.body,
    this.maxWidth = 640,
  });

  @override
  Widget build(BuildContext context) => main;

  /// The page body for a wide window.
  Widget wideBody(BuildContext context) {
    if (body != null) return body!(context);
    final content = SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: wideMain ?? main,
    );
    if (side != null) {
      return SplitPage(
        mainMaxWidth: maxWidth + 64,
        main: content,
        side: side!(context),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 64),
        child: content,
      ),
    );
  }
}

/// A button at its ordinary size in a wide window, at the left of its
/// column; in a narrower window the button as it was, the width of the
/// page.
Widget ordinarySize(BuildContext context, Widget button) =>
    isWideWindow(context)
    ? Align(alignment: Alignment.centerLeft, child: button)
    : button;

/// The pane beside a settings page: a heading that says what it is for,
/// one line of explanation, then its blocks. It scrolls on its own.
class SidePane extends StatelessWidget {
  final String title;
  final String? note;
  final List<Widget> children;
  const SidePane({
    super.key,
    required this.title,
    this.note,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(24),
      children: [
        PaneLabel(title),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(
            note!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.muted, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

/// One captioned block in a [SidePane].
class PaneBlock extends StatelessWidget {
  final String heading;
  final String? detail;
  final Widget child;
  const PaneBlock({
    super.key,
    required this.heading,
    this.detail,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            heading,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: text.bodySmall?.copyWith(
                color: appColors(context).muted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A line of a summary: what it is on the left, its value on the right.
class PaneFact extends StatelessWidget {
  final String name, value;
  const PaneFact(this.name, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              style: text.bodyMedium?.copyWith(color: appColors(context).muted),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain list of short points under a heading, each with a small mark.
class PanePoints extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final List<String> points;
  const PanePoints({
    super.key,
    required this.icon,
    this.color,
    required this.points,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final point in points)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 10),
                child: Icon(
                  icon,
                  size: 17,
                  color: color ?? appColors(context).muted,
                ),
              ),
              Expanded(
                child: Text(
                  point,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Whether [layout] is too wide for the sign and moves across it, so a
/// still preview shows only its beginning.
bool scrollsOnSign(TextLayout layout) {
  try {
    return layout.effect == 'scroll' && textWidth(layout) > 32;
  } catch (_) {
    return false;
  }
}

/// The sign showing [layout], or a line of text while its font is still
/// being prepared.
class SignPreview extends StatelessWidget {
  final TextLayout layout;
  const SignPreview(this.layout, {super.key});
  @override
  Widget build(BuildContext context) {
    List<bool>? pixels;
    try {
      pixels = renderPixels(layout, 0);
    } catch (_) {
      pixels = null;
    }
    if (pixels != null) return LedMatrix(pixels: pixels);
    return AspectRatio(
      aspectRatio: 2,
      child: Center(
        child: Text(
          'Preview is being prepared',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: appColors(context).muted),
        ),
      ),
    );
  }
}

/// Small sign previews, two to a row, each with a caption under it.
class SignPreviewGrid extends StatelessWidget {
  /// The caption's first line, its quieter second line, and what the sign
  /// shows (nothing when this item never reaches the sign).
  final List<(String, String, TextLayout?)> items;
  const SignPreviewGrid({super.key, required this.items});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, space) {
        const gap = 14.0;
        final width = (space.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [
            for (final (title, detail, layout) in items)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (layout != null)
                      SignPreview(layout)
                    else
                      AspectRatio(
                        aspectRatio: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'Not shown on the sign',
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
