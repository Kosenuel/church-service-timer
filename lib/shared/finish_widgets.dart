import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_popups.dart';

export 'package:church_service_timer/shared/finish_popups.dart'
    show FinishPopups, FinishPopupFrame, finishPopupColor;
export 'package:church_service_timer/shared/finish_paint.dart'
    show finishEdgeInset, finishFade, finishClear;

/// Paints the finish's background behind [child] (a whole screen). Flat
/// draws nothing, so [child] paints its own background as it always did.
///
/// The wall is its own layer, drawn once and kept: a ticking clock, a scroll
/// or a page sliding in over it never draws it again.
class FinishWall extends StatefulWidget {
  final Widget child;
  const FinishWall({super.key, required this.child});
  @override
  State<FinishWall> createState() => _FinishWallState();
}

class _FinishWallState extends State<FinishWall> {
  final _wall = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    if (!look.active) return widget.child;
    return FinishWallScope(
      wallKey: _wall,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: FinishPaint(key: _wall, look: look, part: FinishPart.wall),
          ),
          // Every dialog, sheet and menu opened on this page takes the
          // finish too.
          FinishPopups(wallKey: _wall, child: widget.child),
        ],
      ),
    );
  }
}

/// A card or column in the finish's material. With Flat it is the plain
/// themed surface the app always had, so every screen can use it.
///
/// [radius] is the Flat corner; a finish brings its own. A [pane] fills its
/// area edge to edge (a bar or a column), so it has no shadow; for a
/// stitched finish its seam runs along [seams] only.
///
/// Every finish keeps the content inside the panel's edge (see
/// [finishEdgeInset]): it is cut off there, what scrolls toward the edge
/// fades under the panel's material, and the edge (a wood lip, a chamfer, a
/// rim, a bevel and screws, a seam) is drawn over it, so nothing is ever
/// drawn across the edge or sticks out past it. In a stitched finish
/// (Denim, Leather) the content box itself also starts a little inside.
class FinishSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool pane;

  /// A pane's corners, where it has rounded ones (the header).
  final BorderRadius? corners;
  final FinishEdges seams;

  /// Flat only: the plain card's outline.
  final bool outlined;

  /// A small card set into a panel ([FinishLook.card]), with corners no
  /// rounder than [radius].
  final bool card;
  const FinishSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.pane = false,
    this.corners,
    this.seams = noEdges,
    this.outlined = true,
    this.card = false,
  });
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final page = finishLook(context), look = card ? page.card : page;
    if (!look.active) {
      if (pane) return ColoredBox(color: colors.surface, child: child);
      return Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: outlined ? BorderSide(color: colors.border) : BorderSide.none,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
    }
    final shape =
        corners ??
        (pane
            ? BorderRadius.zero
            : BorderRadius.circular(
                card
                    ? math.min(radius, finishRadius(look.id))
                    : finishRadius(look.id),
              ));
    final content = FinishOnPanel(
      child: Material(type: MaterialType.transparency, child: child),
    );
    final material = Positioned.fill(
      child: FinishPaint(
        look: look,
        part: FinishPart.panel,
        corners: shape,
        strip: pane,
        edges: seams,
      ),
    );
    if (pane) {
      // A bar: its edge is drawn under what is on it, which does not scroll
      // and keeps clear of it.
      return Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          material,
          shape == BorderRadius.zero
              ? ClipRect(child: content)
              : ClipRRect(borderRadius: shape, child: content),
        ],
      );
    }
    final pad = finishContentPadding(look.id);
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        material,
        // The content is cut off inside the panel's edge along a plain
        // rectangle (the cheapest clip there is); the corners it lets
        // through are covered by the panel's material drawn over them.
        Padding(
          padding: EdgeInsets.all(pad),
          child: ClipRect(
            key: const ValueKey('finish-seam-clip'),
            clipper: FinishEdgeClipper(finishEdgeInset(look.id) - pad),
            child: content,
          ),
        ),
        // Over the content, so it can never cover the edge: what reaches
        // the edge fades under the material, and the edge is drawn on top.
        Positioned.fill(
          child: IgnorePointer(
            child: FinishPaint(
              look: look,
              part: FinishPart.seam,
              corners: shape,
            ),
          ),
        ),
      ],
    );
  }
}

/// Where a panel's content is cut off: [inset] inside the content box.
class FinishEdgeClipper extends CustomClipper<Rect> {
  final double inset;
  const FinishEdgeClipper(this.inset);
  @override
  Rect getClip(Size size) => (Offset.zero & size).deflate(inset);
  // What shows, for scrolling a field into view and for screen readers.
  @override
  Rect getApproximateClipRect(Size size) => getClip(size);
  @override
  bool shouldReclip(FinishEdgeClipper old) => old.inset != inset;
}

const noEdges = (top: false, bottom: false, left: false, right: false);
const finishSeamAbove = (top: true, bottom: false, left: false, right: false);
const finishSeamBelow = (top: false, bottom: true, left: false, right: false);

/// The background of a bar (the header, a page's app bar, the bottom
/// navigation) in the finish's material, with its seam along [seams]; null
/// in Flat, so the bar is exactly as it was.
Widget? finishBar(
  BuildContext context, {
  FinishEdges seams = finishSeamBelow,
  BorderRadius? corners,
}) {
  final look = finishLook(context);
  if (!look.active) return null;
  return FinishSurface(
    pane: true,
    corners: corners,
    seams: seams,
    child: const SizedBox.expand(),
  );
}

/// The bottom navigation on a plate of the finish, seamed along its top;
/// [bar] itself in Flat.
Widget finishNavigationBar(BuildContext context, Widget bar) {
  if (!finishLook(context).active) return bar;
  return FinishSurface(pane: true, seams: finishSeamAbove, child: bar);
}

/// Page transitions with the finish's wall behind each page, so a page that
/// slides in brings its own background instead of showing the one beneath.
class FinishPageTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;
  const FinishPageTransitions(this.inner);
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    FinishWall(child: child),
  );
}

/// Buttons in the finish's shape: round or square, and for Console and
/// Plastic a keycap (a light top edge and a shaded foot) instead of a flat
/// fill. The shading stays inside the budgets [FinishLook] checks text on.
ButtonStyle? finishButtonStyle(FinishLook look, {required bool filled}) {
  if (!look.active) return null;
  final r = switch (look.id) {
    'cashmere' || 'plastic' => 40.0,
    'console' => 4.0,
    'brick' => 4.0,
    'carbon' => 6.0,
    'denim' => 8.0,
    'glass' => 12.0,
    // Printed labels: square, like a letterpress plate.
    'papery' => 3.0,
    _ => 10.0,
  };
  final shape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
  );
  final keycap = look.id == 'console' || look.id == 'plastic';
  if (!keycap) return ButtonStyle(shape: shape);
  final dark = !look.light;
  final console = look.id == 'console';
  final gloss = console ? .10 : .12;
  return ButtonStyle(
    shape: shape,
    // Only a light top edge and a shaded foot are laid over the button's own
    // fill, so a button keeps whatever colour it was given (End service stays
    // red) and the keycap look never replaces it. On the console a filled
    // key is backlit: a bright line of light leaks along its lower edge.
    backgroundBuilder: (context, states, child) {
      final pressed = states.contains(WidgetState.pressed);
      final enabled = !states.contains(WidgetState.disabled);
      if (!enabled && filled) return child!;
      final top = Colors.white.withValues(
        alpha: pressed ? 0 : (filled ? gloss : (dark ? .06 : 0)),
      );
      final foot = Colors.black.withValues(
        alpha: pressed ? .02 : (filled ? .16 : (dark ? .16 : .07)),
      );
      final glow = console && filled && !pressed
          ? Colors.white.withValues(alpha: .22)
          : Colors.transparent;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, Colors.transparent, Colors.transparent, foot, glow],
            stops: const [0, .14, .8, .93, 1],
          ),
        ),
        child: child,
      );
    },
  );
}

/// A column or strip of a desktop layout. With Flat it is the column as it
/// was: bare on the background, or on the surface colour when [flatSurface].
/// With a finish it floats as a panel with a gap round it, so the wall shows
/// between the panels and words always sit on a panel.
class FinishPane extends StatelessWidget {
  final Widget child;
  final bool flatSurface;

  /// A strip across the window: with a finish it is a plate of the material
  /// from edge to edge, with no gap round it, so it takes no height.
  final bool strip;

  /// A strip's edges that face the page, where a stitched finish runs its
  /// seam.
  final FinishEdges seams;
  const FinishPane({
    super.key,
    required this.child,
    this.flatSurface = false,
    this.strip = false,
    this.seams = noEdges,
  });
  @override
  Widget build(BuildContext context) {
    if (!finishLook(context).active) {
      return flatSurface
          ? ColoredBox(color: appColors(context).surface, child: child)
          : child;
    }
    if (strip) return FinishSurface(pane: true, seams: seams, child: child);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: finishGapX,
        vertical: finishGapY,
      ),
      child: FinishSurface(child: child),
    );
  }
}

/// The wall that shows between floating panels: wider across than down, as
/// a window has less height to give than width.
const finishGapX = 10.0, finishGapY = 5.0;

/// The rule between columns: none where a finish floats the panels apart.
Widget finishRule(BuildContext context, Widget rule) =>
    finishLook(context).active ? const SizedBox.shrink() : rule;

/// Marks what is drawn on a finish panel, so a card inside it is set into
/// the panel (inset) instead of standing on it as another panel.
class FinishOnPanel extends InheritedWidget {
  const FinishOnPanel({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FinishOnPanel>() != null;
  @override
  bool updateShouldNotify(FinishOnPanel oldWidget) => false;
}

/// A small card: a hint, a notice, a banner or a status strip. In Flat it is
/// exactly the card it always was ([flat], built round [child]). With a
/// finish it takes the material: on the bare wall it is a panel of its own,
/// raised like the others; inside a panel it is a material card set into
/// it ([FinishLook.card]): the panel's own material a step darker and
/// calmer, with the finish's own edge (a seam, an inlaid lip, a chamfer, a
/// moulded rim, a bevel and screws), so the two never read as one sheet.
class FinishCard extends StatelessWidget {
  final Widget child;

  /// The card in Flat.
  final Widget Function(Widget child) flat;

  /// The Flat card's corner, kept for a well.
  final double radius;
  const FinishCard({
    super.key,
    required this.flat,
    required this.child,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    if (!look.active) return flat(child);
    if (!FinishOnPanel.of(context)) {
      // A card keeps at least 10 of its own room inside its edge; a finish
      // with a deeper edge (Plastic's rim) adds what that needs.
      final more = math.max(0.0, finishClear(look.id) - 10);
      return FinishSurface(
        radius: radius,
        child: more == 0
            ? child
            : Padding(padding: EdgeInsets.all(more), child: child),
      );
    }
    return FinishSurface(card: true, radius: radius, child: child);
  }
}

/// A page's bar along the foot of the window (Save, Cancel): in Flat the
/// plain surface it always had, with a finish a strip of its material
/// seamed along its top, like the bottom navigation.
class FinishBarPlate extends StatelessWidget {
  final Widget child;
  const FinishBarPlate({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (!finishLook(context).active) {
      return Material(color: appColors(context).surface, child: child);
    }
    // At the foot of a panel it is part of the panel, under its rule.
    if (FinishOnPanel.of(context)) {
      return Material(type: MaterialType.transparency, child: child);
    }
    return FinishSurface(pane: true, seams: finishSeamAbove, child: child);
  }
}

/// The room round a list page on its panel: little at the sides, as a
/// phone has little width to give.
const listPanelPadding = EdgeInsets.fromLTRB(8, 14, 8, 14);

/// [child] on a panel of the finish, inset by [padding]; in Flat, [child]
/// as it was, with no card or padding. For content that would otherwise
/// sit straight on the finish's wall.
class FinishPanelled extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const FinishPanelled({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
  });
  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    if (!look.active) return child;
    // Never nearer the edge than its edge detail allows.
    final clear = finishClear(look.id);
    return FinishSurface(
      radius: radius,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          math.max(padding.left, clear),
          math.max(padding.top, clear),
          math.max(padding.right, clear),
          math.max(padding.bottom, clear),
        ),
        child: child,
      ),
    );
  }
}

/// A column painted in the theme's background in Flat (to set it apart
/// from the surface beside it); with a finish, a floating panel of the
/// material like the other columns.
class FinishBackdrop extends StatelessWidget {
  final Widget child;
  const FinishBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => finishLook(context).active
      ? FinishPane(child: child)
      : ColoredBox(color: appColors(context).background, child: child);
}

/// What a column inside a pane is laid on, as a [Material] so its rows can
/// show ink: the plain surface in Flat; with a finish clear, so the pane's
/// material shows.
class FinishSurfaceColumn extends StatelessWidget {
  final Widget child;
  const FinishSurfaceColumn({super.key, required this.child});
  @override
  Widget build(BuildContext context) => finishLook(context).active
      ? Material(type: MaterialType.transparency, child: child)
      : Material(color: appColors(context).surface, child: child);
}

/// A column of a wide page on the plain surface in Flat (a [Material], so
/// its rows show ink); with a finish a floating panel of the material.
class FinishColumn extends StatelessWidget {
  final Widget child;
  const FinishColumn({super.key, required this.child});
  @override
  Widget build(BuildContext context) => finishLook(context).active
      ? FinishPane(child: child)
      : Material(color: appColors(context).surface, child: child);
}

/// A divider in a finish: a groove cut into the material, a dark line with
/// its lower lip catching the light, instead of a drawn grey line. Two
/// plain lines, drawn with the row they are in.
class FinishGroove extends StatelessWidget {
  final double indent, endIndent;
  const FinishGroove({super.key, this.indent = 16, this.endIndent = 16});
  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 1,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: look.light ? .16 : .42),
            ),
          ),
          SizedBox(
            height: 1,
            child: ColoredBox(
              color: Colors.white.withValues(alpha: look.light ? .55 : .09),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row that looks pressed into the material while it is hovered,
/// focused or [selected]: a soft shade inside its top and a lit lower lip,
/// under the row's own ink and words. In Flat it is [child] as it was.
class FinishPressable extends StatefulWidget {
  final Widget child;
  final bool selected;
  const FinishPressable({
    super.key,
    required this.child,
    this.selected = false,
  });
  @override
  State<FinishPressable> createState() => _FinishPressableState();
}

class _FinishPressableState extends State<FinishPressable> {
  bool _hover = false, _focus = false;
  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    if (!look.active) return widget.child;
    final on = _hover || _focus || widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focus = f),
        child: Stack(
          children: [
            if (on)
              Positioned.fill(
                child: IgnorePointer(
                  child: FinishPaint(
                    key: const ValueKey('finish-pressed'),
                    look: look,
                    part: FinishPart.press,
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}
