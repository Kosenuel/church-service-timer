import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';

/// Paints the finish's background behind [child] (a whole screen). Flat
/// draws nothing, so [child] paints its own background as it always did.
///
/// The painting sits in its own repaint boundary, so it is drawn once and
/// kept: a ticking clock on top of it never redraws the material.
class FinishWall extends StatelessWidget {
  final Widget child;
  const FinishWall({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    if (!look.active) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: FinishWallPainter(look)),
          ),
        ),
        child,
      ],
    );
  }
}

/// A card or column in the finish's material. With Flat it is the plain
/// themed surface the app always had, so every screen can use it.
///
/// [radius] is the Flat corner; a finish brings its own. A [pane] fills its
/// area edge to edge (a side column), so it has no shadow or trim.
class FinishSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool pane;

  /// Flat only: the plain card's outline.
  final bool outlined;
  const FinishSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.pane = false,
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
    final r = pane ? 0.0 : finishRadius(look.id);
    final content = Material(type: MaterialType.transparency, child: child);
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: FinishPanelPainter(look, r, pane: pane),
            ),
          ),
        ),
        pane
            ? content
            : ClipRRect(borderRadius: BorderRadius.circular(r), child: content),
      ],
    );
  }
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
    'brick' => 6.0,
    'carbon' => 6.0,
    'denim' => 8.0,
    'glass' => 12.0,
    _ => 10.0,
  };
  final shape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
  );
  final keycap = look.id == 'console' || look.id == 'plastic';
  if (!keycap) return ButtonStyle(shape: shape);
  final dark = !look.light;
  final gloss = look.id == 'plastic' ? .12 : .08;
  return ButtonStyle(
    shape: shape,
    // Only a light top edge and a shaded foot are laid over the button's own
    // fill, so a button keeps whatever colour it was given (End service stays
    // red) and the keycap look never replaces it.
    backgroundBuilder: (context, states, child) {
      final pressed = states.contains(WidgetState.pressed);
      final enabled = !states.contains(WidgetState.disabled);
      if (!enabled && filled) return child!;
      final top = Colors.white.withValues(
        alpha: pressed ? 0 : (filled ? gloss : (dark ? .05 : 0)),
      );
      final foot = Colors.black.withValues(
        alpha: pressed ? .02 : (filled ? .15 : (dark ? .14 : .07)),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, Colors.transparent, Colors.transparent, foot],
            stops: const [0, .14, .8, 1],
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
  const FinishPane({
    super.key,
    required this.child,
    this.flatSurface = false,
    this.strip = false,
  });
  @override
  Widget build(BuildContext context) {
    if (!finishLook(context).active) {
      return flatSurface
          ? ColoredBox(color: appColors(context).surface, child: child)
          : child;
    }
    if (strip) return FinishSurface(pane: true, child: child);
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
