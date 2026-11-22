import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Classic's two columns of cards, balanced by their measured heights.
///
/// The first child, the timer card, takes the top of the left column. Each
/// of the others follows in order: the first ones go down the right column
/// and the rest, from some card on, down the left under the timer, where
/// that makes the longer of the two columns as short as it can be. The
/// rundown, last in order, lands under the timer when the display and cues
/// already run lower. The columns share the width
/// by [leftFlex] and [rightFlex], or the right one has [rightWidth].
class BalancedColumns extends MultiChildRenderObjectWidget {
  const BalancedColumns({
    super.key,
    required super.children,
    this.leftFlex = 1,
    this.rightFlex = 1,
    this.rightWidth,
    this.gap = 20,
    this.spacing = 16,
    this.tolerance = 0,
    this.viewHeight = double.infinity,
  });

  final int leftFlex;
  final int rightFlex;
  final double? rightWidth;

  /// The space between the columns, and between the cards of one.
  final double gap;
  final double spacing;

  /// How far apart the columns may end while the cards keep their order
  /// down the page; beyond it, any card may change column.
  final double tolerance;

  /// The height of page in view below the top of the columns; an empty
  /// band under the shorter one only counts as far as this.
  final double viewHeight;

  @override
  RenderBalancedColumns createRenderObject(BuildContext context) =>
      RenderBalancedColumns(
        leftFlex: leftFlex,
        rightFlex: rightFlex,
        rightWidth: rightWidth,
        gap: gap,
        spacing: spacing,
        tolerance: tolerance,
        viewHeight: viewHeight,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBalancedColumns renderObject,
  ) {
    renderObject
      ..leftFlex = leftFlex
      ..rightFlex = rightFlex
      ..rightWidth = rightWidth
      ..gap = gap
      ..spacing = spacing
      ..tolerance = tolerance
      ..viewHeight = viewHeight;
  }
}

class _ColumnsParentData extends ContainerBoxParentData<RenderBox> {}

class RenderBalancedColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ColumnsParentData> {
  RenderBalancedColumns({
    required int leftFlex,
    required int rightFlex,
    required double? rightWidth,
    required double gap,
    required double spacing,
    required double tolerance,
    required double viewHeight,
  }) : _leftFlex = leftFlex,
       _rightFlex = rightFlex,
       _rightWidth = rightWidth,
       _gap = gap,
       _spacing = spacing,
       _tolerance = tolerance,
       _viewHeight = viewHeight;

  int _leftFlex;
  int _rightFlex;
  double? _rightWidth;
  double _gap;
  double _spacing;
  double _tolerance;
  double _viewHeight;

  set viewHeight(double v) {
    if (v == _viewHeight) return;
    _viewHeight = v;
    markNeedsLayout();
  }

  set tolerance(double v) {
    if (v == _tolerance) return;
    _tolerance = v;
    markNeedsLayout();
  }

  set leftFlex(int v) {
    if (v == _leftFlex) return;
    _leftFlex = v;
    markNeedsLayout();
  }

  set rightFlex(int v) {
    if (v == _rightFlex) return;
    _rightFlex = v;
    markNeedsLayout();
  }

  set rightWidth(double? v) {
    if (v == _rightWidth) return;
    _rightWidth = v;
    markNeedsLayout();
  }

  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ColumnsParentData) {
      child.parentData = _ColumnsParentData();
    }
  }

  (double, double) _widths(double total) {
    final room = total - _gap;
    final right = _rightWidth != null
        ? _rightWidth!.clamp(0.0, room).toDouble()
        : room * _rightFlex / (_leftFlex + _rightFlex);
    return (room - right, right);
  }

  /// Which cards go in the left column: bit `i` set means the card after
  /// the first, number `i`, goes left. The cards from one on go left and
  /// the ones before it right, so the cards keep their order down the page,
  /// as long as the empty band under the shorter column, as far as the page
  /// in view shows it, is within [_tolerance]; of those splits, the nearest
  /// even. When none is, any card may change column, to make the longer
  /// column as short as it can be. [inLeft] and [inRight] are each card's height in
  /// either column.
  int _choose(List<double> inLeft, List<double> inRight) {
    final n = inLeft.length - 1;
    (double, double) ends(int mask) {
      var left = inLeft[0], right = 0.0;
      var rightCount = 0;
      for (var i = 0; i < n; i++) {
        if (mask & (1 << i) != 0) {
          left += _spacing + inLeft[i + 1];
        } else {
          right += (rightCount++ > 0 ? _spacing : 0) + inRight[i + 1];
        }
      }
      return (left, right);
    }

    var best = -1;
    var bestGap = double.infinity;
    for (var split = n; split >= 0; split--) {
      final mask = ((1 << n) - 1) & ~((1 << split) - 1);
      final (l, r) = ends(mask);
      final gap = (l - r).abs();
      final shown = (l > r ? l : r) < _viewHeight
          ? (l > r ? l : r)
          : _viewHeight;
      final band = shown - (l > r ? r : l);
      if (band <= _tolerance && gap < bestGap - 0.5) {
        best = mask;
        bestGap = gap;
      }
    }
    if (best >= 0) return best;
    best = 0;
    var bestCost = double.infinity;
    for (var mask = 0; mask < (1 << n); mask++) {
      final (l, r) = ends(mask);
      final cost = l > r ? l : r;
      if (cost < bestCost - 0.5) {
        bestCost = cost;
        best = mask;
      }
    }
    return best;
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final (leftWidth, rightWidth) = _widths(width);
    final children = <RenderBox>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      children.add(c);
    }
    if (children.isEmpty) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    double heightAt(RenderBox child, double w) {
      child.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
      return child.size.height;
    }

    final inLeft = [for (final child in children) heightAt(child, leftWidth)];
    final inRight = [
      for (var i = 0; i < children.length; i++)
        i == 0 || leftWidth == rightWidth
            ? inLeft[i]
            : heightAt(children[i], rightWidth),
    ];
    final mask = children.length > 1 ? _choose(inLeft, inRight) : 0;
    var leftY = 0.0, rightY = 0.0;
    var leftCount = 0, rightCount = 0;
    for (var i = 0; i < children.length; i++) {
      final left = i == 0 || mask & (1 << (i - 1)) != 0;
      final child = children[i];
      // The card at the width of its column.
      final h = heightAt(child, left ? leftWidth : rightWidth);
      final data = child.parentData! as _ColumnsParentData;
      if (left) {
        if (leftCount++ > 0) leftY += _spacing;
        data.offset = Offset(0, leftY);
        leftY += h;
      } else {
        if (rightCount++ > 0) rightY += _spacing;
        data.offset = Offset(leftWidth + _gap, rightY);
        rightY += h;
      }
    }
    size = constraints.constrain(Size(width, leftY > rightY ? leftY : rightY));
  }

  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth, 0));

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
