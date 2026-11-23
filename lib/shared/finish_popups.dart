import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';

/// The background a popup is given inside [FinishPopupFrame]: no colour at
/// all, so the finish's material drawn behind it shows, and a colour no
/// other surface has, so the frame can tell the popup's own sheet from the
/// buttons and cards inside it.
const finishPopupColor = Color(0x00f1a15e);

/// Puts the finish on every dialog, bottom sheet, popup menu and picker
/// opened from below it, with no change where they are opened.
///
/// Flutter builds each of those in a route of its own, and wraps what it
/// shows in the themes captured where it was opened
/// ([InheritedTheme.capture]). This is one of them: [FinishWall] puts it
/// under every page, so each popup is wrapped in a [FinishPopupFrame], and
/// a popup opened from a popup is wrapped again. In Flat there is no
/// [FinishWall], so popups are exactly as they were.
class FinishPopups extends InheritedTheme {
  /// The page's wall, for Glass, which shows the wall behind it.
  final GlobalKey? wallKey;
  const FinishPopups({super.key, this.wallKey, required super.child});

  @override
  Widget wrap(BuildContext context, Widget child) => FinishPopups(
    wallKey: wallKey,
    child: FinishPopupFrame(wallKey: wallKey, child: child),
  );

  @override
  bool updateShouldNotify(FinishPopups oldWidget) =>
      oldWidget.wallKey != wallKey;
}

/// A popup in the finish's material: its sheet is made clear (in
/// [finishPopupColor], with no shadow), and the frame draws the panel
/// material, edge and shadow behind it at the place and size the sheet has,
/// and a stitched finish's stitches over it. The material is the same cached
/// images a panel draws (see [RenderFinishPaint]), each in a layer of its
/// own, so a popup sliding in or a caret blinking in it never draws them
/// again.
class FinishPopupFrame extends StatelessWidget {
  final Widget child;
  final GlobalKey? wallKey;
  const FinishPopupFrame({super.key, this.wallKey, required this.child});

  @override
  Widget build(BuildContext context) {
    final look = finishLook(context);
    if (!look.active) return child;
    final theme = Theme.of(context);
    final r = math.max(finishRadius(look.id), 8.0);
    final all = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
    final top = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
    );
    const clear = Colors.transparent;
    return Theme(
      data: theme.copyWith(
        dialogTheme: theme.dialogTheme.copyWith(
          backgroundColor: finishPopupColor,
          elevation: 0,
          shadowColor: clear,
          surfaceTintColor: clear,
          shape: all,
        ),
        bottomSheetTheme: theme.bottomSheetTheme.copyWith(
          backgroundColor: finishPopupColor,
          modalBackgroundColor: finishPopupColor,
          elevation: 0,
          modalElevation: 0,
          shadowColor: clear,
          surfaceTintColor: clear,
          shape: top,
        ),
        popupMenuTheme: theme.popupMenuTheme.copyWith(
          color: finishPopupColor,
          elevation: 0,
          shadowColor: clear,
          surfaceTintColor: clear,
          shape: all,
        ),
        datePickerTheme: theme.datePickerTheme.copyWith(
          backgroundColor: finishPopupColor,
          elevation: 0,
          shadowColor: clear,
          surfaceTintColor: clear,
          shape: all,
        ),
        timePickerTheme: theme.timePickerTheme.copyWith(
          backgroundColor: finishPopupColor,
          elevation: 0,
          shape: all,
        ),
      ),
      child: _PopupFrame(
        look: look,
        wall: wallKey,
        dpr: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        child: child,
      ),
    );
  }
}

class _PopupFrame extends SingleChildRenderObjectWidget {
  final FinishLook look;
  final GlobalKey? wall;
  final double dpr;
  const _PopupFrame({
    required this.look,
    required this.wall,
    required this.dpr,
    required super.child,
  });

  @override
  RenderFinishPopupFrame createRenderObject(BuildContext context) =>
      RenderFinishPopupFrame(look: look, wall: wall, dpr: dpr);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFinishPopupFrame renderObject,
  ) => renderObject.update(look, wall, dpr);
}

/// Lays out the popup, finds its sheet (the first [RenderPhysicalShape] in
/// [finishPopupColor]) and draws the material behind it and the stitches
/// over it. The sheet may move or grow inside the popup without this
/// laying out again (a bottom sheet slides up, a menu opens out), so where
/// it is is read again each time this paints; a sheet that has changed
/// size has a plain plate of the panel colour for that one frame, and the
/// material is fitted to it on the next.
class RenderFinishPopupFrame extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  RenderFinishPopupFrame({
    required FinishLook look,
    required GlobalKey? wall,
    required double dpr,
  }) : _look = look,
       panel = RenderFinishPaint(
         look: look,
         part: FinishPart.panel,
         corners: BorderRadius.zero,
         strip: false,
         edges: allEdges,
         dpr: dpr,
         wall: wall,
       ),
       stitches = RenderFinishPaint(
         look: look,
         part: FinishPart.stitches,
         corners: BorderRadius.zero,
         strip: false,
         edges: allEdges,
         dpr: dpr,
         wall: wall,
       ) {
    adoptChild(panel);
    adoptChild(stitches);
  }

  FinishLook _look;

  /// The material behind the sheet, and a stitched finish's stitches over
  /// it.
  final RenderFinishPaint panel, stitches;

  RenderPhysicalShape? _sheet;
  bool _refit = false;
  Offset? _paintedAt;

  /// The sheet this frame drew behind when it last laid out, for tests.
  RenderBox? get sheet => _sheet;

  bool get _stitched => stitchedFinishes.contains(_look.id);

  void update(FinishLook look, GlobalKey? wall, double dpr) {
    _look = look;
    for (final p in [panel, stitches]) {
      p
        ..look = look
        ..wall = wall
        ..dpr = dpr;
    }
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    panel.attach(owner);
    stitches.attach(owner);
  }

  @override
  void detach() {
    super.detach();
    panel.detach();
    stitches.detach();
  }

  @override
  void redepthChildren() {
    redepthChild(panel);
    super.redepthChildren();
    redepthChild(stitches);
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    visitor(panel);
    super.visitChildren(visitor);
    visitor(stitches);
  }

  // The material says nothing to a screen reader.
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final popup = child;
    if (popup != null) visitor(popup);
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  @override
  void performLayout() {
    final popup = child;
    if (popup == null) {
      size = constraints.smallest;
      return;
    }
    popup.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(popup.size);
    final sheet = _sheet = _findSheet(popup);
    if (sheet == null) return;
    // The sheet is not this box's child, so its size is read the way a
    // layout callback reads what it has just built.
    late final Size sheetSize;
    invokeLayoutCallback<BoxConstraints>((_) => sheetSize = sheet.size);
    final corners = _cornersOf(sheet);
    for (final p in [panel, stitches]) {
      p
        ..corners = corners
        ..layout(BoxConstraints.tight(sheetSize));
    }
  }

  static RenderPhysicalShape? _findSheet(RenderObject root) {
    RenderPhysicalShape? found;
    void visit(RenderObject r) {
      if (found != null) return;
      if (r is RenderPhysicalShape && r.color == finishPopupColor) {
        found = r;
        return;
      }
      r.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  BorderRadius _cornersOf(RenderPhysicalShape sheet) {
    final clipper = sheet.clipper;
    final shape = clipper is ShapeBorderClipper ? clipper.shape : null;
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius.resolve(TextDirection.ltr);
    }
    return BorderRadius.circular(math.max(finishRadius(_look.id), 8));
  }

  /// How much of the sheet shows, for a popup that fades in inside the
  /// frame (a menu).
  double _opacityOf(RenderObject sheet) {
    var alpha = 1.0;
    for (RenderObject? r = sheet.parent; r != null && r != this; r = r.parent) {
      if (r is RenderOpacity) alpha *= r.opacity;
      if (r is RenderAnimatedOpacity) alpha *= r.opacity.value;
    }
    return alpha;
  }

  void _later(void Function() action) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (attached) action();
      })
      ..ensureVisualUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final popup = child;
    if (popup == null) return;
    final sheet = _sheet;
    if (sheet == null || !sheet.attached || !sheet.hasSize) {
      context.paintChild(popup, offset);
      if (sheet != null && !_refit) {
        _refit = true;
        _later(() {
          _refit = false;
          markNeedsLayout();
        });
      }
      return;
    }
    final at = MatrixUtils.transformPoint(
      sheet.getTransformTo(this),
      Offset.zero,
    );
    final alpha = _opacityOf(sheet);
    final fits = panel.hasSize && panel.size == sheet.size;
    if (!fits) {
      // Grown or shrunk since the material was laid out: a plain plate now,
      // the material next frame.
      context.canvas.drawRRect(
        panel.corners.toRRect((offset + at) & sheet.size),
        Paint()..color = _look.panel.withValues(alpha: alpha),
      );
      if (!_refit) {
        _refit = true;
        _later(() {
          _refit = false;
          markNeedsLayout();
        });
      }
    }
    void layer(RenderFinishPaint part) {
      (part.parentData! as BoxParentData).offset = at;
      if (alpha >= 1) {
        context.paintChild(part, offset + at);
      } else if (alpha > 0) {
        context.pushOpacity(
          offset + at,
          (alpha * 255).round(),
          (c, o) => c.paintChild(part, o),
        );
      }
    }

    if (fits) layer(panel);
    context.paintChild(popup, offset);
    if (fits && _stitched) layer(stitches);
    // Glass shows the part of the wall behind it: moved, it draws once more
    // when it comes to rest.
    if (_look.id == 'glass' && _paintedAt != at) {
      _paintedAt = at;
      _later(panel.markNeedsPaint);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final data = child.parentData! as BoxParentData;
    transform.translateByDouble(data.offset.dx, data.offset.dy, 0, 1);
  }
}
