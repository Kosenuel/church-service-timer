import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_popups.dart';

export 'package:church_service_timer/shared/finish_popups.dart'
    show FinishPopups, FinishPopupFrame, finishPopupColor;

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
/// In a stitched finish (Denim, Leather) the seam is a frame inside the
/// panel's edge, and the content is kept inside it: it is inset clear of
/// the thread and clipped there, with a soft hem, so text or buttons
/// scrolled toward the edge pass under the hem and nothing is ever drawn
/// across the stitches or cut in half by them.
class FinishSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool pane;

  /// A pane's corners, where it has rounded ones (the header).
  final BorderRadius? corners;
  final FinishEdges seams;

  /// Flat only: the plain card's outline.
  final bool outlined;
  const FinishSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.pane = false,
    this.corners,
    this.seams = noEdges,
    this.outlined = true,
  });
  @override
  Widget build(BuildContext context) {
    final look = finishLook(context), colors = appColors(context);
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
            : BorderRadius.circular(finishRadius(look.id)));
    final stitched = stitchedFinishes.contains(look.id);
    final content = Material(type: MaterialType.transparency, child: child);
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
      // A bar: its seam runs along the edges that face the page, clear of
      // what is on the bar, which does not scroll.
      return Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          material,
          ClipRRect(borderRadius: shape, child: content),
        ],
      );
    }
    if (!stitched) {
      return Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          material,
          ClipRRect(borderRadius: shape, child: content),
        ],
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        material,
        // The content starts just inside the edge, so it keeps nearly all
        // its room, and is cut off inside the seam: what reaches the seam
        // is only the content's own margin, and what scrolls there goes
        // under the hem.
        Padding(
          padding: const EdgeInsets.all(finishContentInset),
          child: ClipRRect(
            key: const ValueKey('finish-seam-clip'),
            clipper: _InsideSeam(finishInnerCorners(shape)),
            child: content,
          ),
        ),
        // Over the content, so it can never cover a stitch.
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

class _InsideSeam extends CustomClipper<RRect> {
  final BorderRadius corners;
  const _InsideSeam(this.corners);
  @override
  RRect getClip(Size size) => corners.toRRect(
    (Offset.zero & size).deflate(finishSeamInset - finishContentInset),
  );
  @override
  bool shouldReclip(_InsideSeam old) => old.corners != corners;
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
