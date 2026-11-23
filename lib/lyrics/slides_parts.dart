import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_photos.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

// The pieces of the Slides page's output pane and Library that are laid
// out on their own: the four buttons, the rows that fold open, the Add
// row and the line of keys. See docs/LYRICS-DESIGN.md, "The Slides page".

/// A background's name as the picker and the Background row call it.
String lyricBackgroundName(String id) {
  if (id.startsWith('custom:')) return 'Your picture';
  if (id.startsWith('photo:')) {
    return lyricPhotoById(id.substring(6))?.title ?? 'Photo';
  }
  return lyricDrawnBackgrounds[id] ?? id;
}

/// The background picker's group for [id]: designs, nature, people or
/// yours.
String lyricBackgroundGroup(String id) {
  if (id.startsWith('custom:')) return 'yours';
  if (id.startsWith('photo:')) {
    return lyricPhotoById(id.substring(6))?.kind ?? 'nature';
  }
  return 'designs';
}

/// The closed Look row: "Dim 70% · Medium · Centre · Gentle", and the
/// corner countdown when it is on. Built from the look as it is, so it
/// never says something the screens do not show.
String lyricLookSummary(LyricsLook look) => [
  look.darkInk ? 'Not dimmed' : 'Dim ${look.dim}%',
  switch (look.size) {
    's' => 'Small',
    'l' => 'Large',
    _ => 'Medium',
  },
  look.align == 'left' ? 'Left' : 'Centre',
  look.moving ? 'Gentle' : 'Still',
  if (look.chip) 'Countdown',
].join(' · ');

/// Marks the header of a [SlidesFold], so the page's keys can leave Space
/// to it: Space opens and closes a focused row instead of moving on a
/// slide.
class SlidesFoldHeader extends StatelessWidget {
  final Widget child;
  const SlidesFoldHeader({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

/// Whether the keyboard is on the header of a row that folds open.
bool slidesFoldHasFocus() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<SlidesFoldHeader>() !=
    null;

/// A row of the output pane that opens in place: a quiet name, what is
/// chosen now, and a chevron (or [action], such as Change). Tab reaches
/// it, Enter or Space opens and closes it, and a screen reader hears
/// whether it is open.
class SlidesFold extends StatelessWidget {
  final String name, value;
  final bool open;
  final VoidCallback onToggle;
  final Widget body;

  /// Beside the value: the Background row's swatch.
  final Widget? swatch;

  /// In place of the chevron, words such as Change.
  final String? action;
  final Color? valueColor;
  const SlidesFold({
    super.key,
    required this.name,
    required this.value,
    required this.open,
    required this.onToggle,
    required this.body,
    this.swatch,
    this.action,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final header = SlidesFoldHeader(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            key: key is ValueKey<String>
                ? ValueKey('${(key as ValueKey<String>).value}-header')
                : null,
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(
                children: [
                  Text(name.toUpperCase(), style: sectionLabelStyle(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        color: valueColor ?? colors.muted,
                      ),
                    ),
                  ),
                  if (swatch != null) ...[
                    const SizedBox(width: 8),
                    ExcludeSemantics(child: swatch!),
                  ],
                  const SizedBox(width: 8),
                  if (action != null)
                    Text(
                      open ? 'Done' : action!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    )
                  else
                    ExcludeSemantics(
                      child: AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: reduceAppMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.expand_more,
                          size: 20,
                          color: colors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (open)
          Padding(
            key: key is ValueKey<String>
                ? ValueKey('${(key as ValueKey<String>).value}-body')
                : null,
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: body,
          ),
      ],
    );
  }
}

/// A hairline between the rows of the output pane.
class SlidesHairline extends StatelessWidget {
  const SlidesHairline({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: appColors(context).border);
}

/// One of the four buttons: its words and, under them, its key.
class _Transport {
  final String key, label, tooltip;
  final String? hint;
  final IconData? arrow;
  final int flex;
  final VoidCallback? onPressed;
  final bool primary, on;
  const _Transport(
    this.key,
    this.label,
    this.tooltip, {
    this.hint,
    this.arrow,
    this.flex = 10,
    this.onPressed,
    this.primary = false,
    this.on = false,
  });
}

/// Previous, Next, Clear and Black in one row at one height, Next the
/// widest and filled. They never wrap: when the row is narrow (a phone,
/// large text) the keys under the words go first, then the words get
/// smaller together, so the four still read as one set.
class SlidesTransport extends StatelessWidget {
  final bool enabled, showing, black, keyHints;
  final VoidCallback onPrevious, onNext, onClear, onBlack;
  const SlidesTransport({
    super.key,
    required this.enabled,
    required this.showing,
    required this.black,
    required this.keyHints,
    required this.onPrevious,
    required this.onNext,
    required this.onClear,
    required this.onBlack,
  });

  static const gap = 6.0;
  static const _inset = 6.0;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _Transport(
        'lyrics-previous',
        'Previous',
        'Previous slide',
        arrow: Icons.arrow_back,
        onPressed: enabled ? onPrevious : null,
      ),
      _Transport(
        'lyrics-next',
        'Next',
        'Next slide',
        arrow: Icons.arrow_forward,
        hint: 'or Space',
        flex: 16,
        primary: true,
        onPressed: enabled ? onNext : null,
      ),
      _Transport(
        'lyrics-clear',
        'Clear',
        'Clear the slide',
        hint: 'Esc',
        onPressed: enabled && showing ? onClear : null,
      ),
      _Transport(
        'lyrics-black',
        'Black',
        black ? 'Bring the slide back' : 'Black screens',
        hint: 'B',
        on: black,
        onPressed: enabled ? onBlack : null,
      ),
    ];
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    double measure(String text, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    const label = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      fontFamily: appFontFamily,
    );
    const hintStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      fontFamily: appFontFamily,
    );
    return LayoutBuilder(
      builder: (context, space) {
        final flexes = buttons.fold<int>(0, (a, b) => a + b.flex);
        final room = space.maxWidth - gap * (buttons.length - 1);
        double inner(_Transport b) => room * b.flex / flexes - _inset * 2 - 2;
        // The keys show only when every one fits under its words.
        final hints =
            keyHints &&
            buttons.every((b) {
              final arrow = b.arrow == null ? 0 : scaler.scale(12) + 3;
              final words = b.hint == null ? 0 : measure(b.hint!, hintStyle);
              return arrow + words <= inner(b);
            });
        // One size for all four words, as large as fits.
        var factor = 1.0;
        for (final b in buttons) {
          factor = math.min(factor, inner(b) / measure(b.label, label));
        }
        final size = 14 * factor.clamp(.6, 1.0);
        return IntrinsicHeight(
          child: Row(
            key: const ValueKey('lyrics-transport'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  flex: buttons[i].flex,
                  child: _button(context, buttons[i], size, hints),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _button(BuildContext context, _Transport b, double size, bool hints) {
    final colors = appColors(context);
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            b.label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w500),
          ),
          if (hints && (b.hint != null || b.arrow != null)) ...[
            const SizedBox(height: 2),
            _KeyUnder(arrow: b.arrow, words: b.hint),
          ],
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    const padding = EdgeInsets.symmetric(horizontal: _inset, vertical: 10);
    const minimum = Size(0, 48);
    final Widget button;
    if (b.primary) {
      button = FilledButton(
        key: ValueKey(b.key),
        style: FilledButton.styleFrom(
          padding: padding,
          minimumSize: minimum,
          shape: shape,
        ),
        onPressed: b.onPressed,
        child: content,
      );
    } else if (b.on) {
      // Black is on: the button is black, as the screens are.
      button = FilledButton(
        key: ValueKey(b.key),
        style: FilledButton.styleFrom(
          padding: padding,
          minimumSize: minimum,
          shape: shape.copyWith(side: BorderSide(color: colors.text)),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        onPressed: b.onPressed,
        child: content,
      );
    } else {
      button = OutlinedButton(
        key: ValueKey(b.key),
        style: OutlinedButton.styleFrom(
          padding: padding,
          minimumSize: minimum,
          shape: shape,
        ),
        onPressed: b.onPressed,
        child: content,
      );
    }
    return MergeSemantics(
      child: Semantics(
        toggled: b.key == 'lyrics-black' ? b.on : null,
        child: Tooltip(message: b.tooltip, child: button),
      ),
    );
  }
}

/// A key under a button's words: an arrow (Roboto has none, so it is
/// drawn) and words such as "or Space".
class _KeyUnder extends StatelessWidget {
  final IconData? arrow;
  final String? words;
  const _KeyUnder({this.arrow, this.words});
  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(
      context,
    ).style.color?.withValues(alpha: .66);
    // One height whether it is an arrow or words, so the four buttons'
    // words line up.
    return ExcludeSemantics(
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(14),
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (arrow != null)
            Icon(
              arrow,
              size: MediaQuery.textScalerOf(context).scale(12),
              color: color,
            ),
          if (arrow != null && words != null) const SizedBox(width: 3),
          if (words != null)
            Text(
              words!,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
        ],
      ),
      ),
    );
  }
}

/// The keys of the Slides page as one quiet line under the slides.
class SlidesKeysLine extends StatelessWidget {
  const SlidesKeysLine({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final style = TextStyle(fontSize: 12, color: colors.muted);
    InlineSpan key(String text, {IconData? icon}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: MediaQuery.textScalerOf(context).scale(12),
                color: colors.muted,
                semanticLabel: text,
              )
            : Text(text, style: style),
      ),
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          key('Right arrow', icon: Icons.arrow_forward),
          const TextSpan(text: ' next · '),
          key('Left arrow', icon: Icons.arrow_back),
          const TextSpan(text: ' previous · '),
          key('Esc'),
          const TextSpan(text: ' clear · '),
          key('B'),
          const TextSpan(text: ' black'),
        ],
      ),
      key: const ValueKey('lyrics-tip'),
    );
  }
}

/// What one Add button says, in full and shortened.
class SlidesAdd {
  final String key, full, short, tooltip;
  final VoidCallback? onPressed;
  const SlidesAdd(
    this.key,
    this.full,
    this.short,
    this.tooltip,
    this.onPressed,
  );
}

/// The three Add buttons as one quiet row. They keep their full words
/// when those fit on one row, take the short words when they do not, and
/// wrap onto a second row rather than cut a word.
class SlidesAddRow extends StatelessWidget {
  final List<SlidesAdd> buttons;
  const SlidesAddRow({super.key, required this.buttons});

  static const gap = 6.0, _inset = 6.0;
  static const _style = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFamily: appFontFamily,
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    double measure(String text) {
      final p = TextPainter(
        text: TextSpan(text: text, style: _style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      // A little over, so a word never ends at the very edge.
      return w + _inset * 2 + 2;
    }

    return LayoutBuilder(
      builder: (context, space) {
        final room = space.maxWidth - gap * (buttons.length - 1);
        List<double> widths(bool short) => [
          for (final b in buttons) measure(short ? b.short : b.full),
        ];
        final full = widths(false), short = widths(true);
        double sum(List<double> w) => w.fold(0, (a, b) => a + b);
        final useShort = sum(full) > room;
        final w = useShort ? short : full;
        Widget button(int i, {bool expand = true}) {
          final b = buttons[i];
          final child = Tooltip(
            message: b.tooltip,
            child: OutlinedButton(
              key: ValueKey(b.key),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: _inset,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: _style,
              ),
              onPressed: b.onPressed,
              child: Text(
                useShort ? b.short : b.full,
                maxLines: 1,
                softWrap: false,
                semanticsLabel: b.tooltip,
              ),
            ),
          );
          return expand
              ? Expanded(flex: (w[i] * 10).round(), child: child)
              : child;
        }

        if (sum(w) <= room) {
          return Row(
            key: const ValueKey('lyrics-add-row'),
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                button(i),
              ],
            ],
          );
        }
        return Wrap(
          key: const ValueKey('lyrics-add-row'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < buttons.length; i++) button(i, expand: false),
          ],
        );
      },
    );
  }
}

/// A small copy of the background for the Background row.
class LyricBackgroundSwatch extends StatelessWidget {
  final Widget thumb;
  const LyricBackgroundSwatch({super.key, required this.thumb});
  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 20,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: appColors(context).border),
    ),
    child: thumb,
  );
}
