import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The choice of what a stage screen shows while it counts down, as
/// picture tiles: a miniature of each layout with its name and a tick on
/// the one chosen. Every chooser of [stageLayouts] uses it: the second
/// screen, paired stage screens, web screens, full screen and the stage
/// simulator.
///
/// The tiles share a row as far as they fit (never narrower than 112) and
/// wrap onto the next, so on a phone, or with large text, two or one to a
/// row, and the tiles of a row are as tall as the tallest.
class StageLayoutTiles extends StatelessWidget {
  final String value;

  /// Chosen layout, or null where the choice is locked.
  final ValueChanged<String>? onChanged;

  /// Each tile is keyed `<keyPrefix>-<layout>`.
  final String keyPrefix;
  const StageLayoutTiles({
    super.key,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
  });

  static const minTile = 112.0, gap = 10.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final width = space.maxWidth.isFinite ? space.maxWidth : 640.0;
      final layouts = stageLayouts.entries.toList();
      var columns = ((width + gap) / (minTile + gap)).floor().clamp(
        1,
        layouts.length,
      );
      // Three and one would leave a tile alone on the last row: two and
      // two is tidier.
      if (columns == 3) columns = 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < layouts.length; i += columns) ...[
            if (i > 0) const SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) const SizedBox(width: gap),
                    Expanded(
                      child: j < layouts.length
                          ? StageLayoutTile(
                              key: ValueKey('$keyPrefix-${layouts[j].key}'),
                              layout: layouts[j].key,
                              label: layouts[j].value,
                              selected: value == layouts[j].key,
                              isNew: layouts[j].key == 'only',
                              onTap: onChanged == null
                                  ? null
                                  : () => onChanged!(layouts[j].key),
                            )
                          : const SizedBox.shrink(),
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

/// One tile of [StageLayoutTiles].
class StageLayoutTile extends StatelessWidget {
  final String layout, label;
  final bool selected, isNew;
  final VoidCallback? onTap;
  const StageLayoutTile({
    super.key,
    required this.layout,
    required this.label,
    required this.selected,
    required this.onTap,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? colors.accent : colors.muted.withValues(alpha: .4),
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: selected ? colors.accent.withValues(alpha: .12) : null,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      StageLayoutMiniature(layout: layout),
                      if (isNew)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            key: const ValueKey('layout-new-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .6,
                                color: readable(colors.accent),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: _Tick(selected: selected),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 14, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final bool selected;
  const _Tick({required this.selected});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Container(
      key: ValueKey(selected ? 'layout-tick-on' : 'layout-tick-off'),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.accent : null,
        border: Border.all(
          color: selected ? colors.accent : colors.muted,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 13, color: readable(colors.accent))
          : null,
    );
  }
}

/// A small picture of a layout, always in the stage's own dark look.
class StageLayoutMiniature extends StatelessWidget {
  final String layout;
  const StageLayoutMiniature({super.key, required this.layout});
  static const _ground = Color(0xff0a1210),
      _digits = Color(0xffe4e7de),
      _accent = Color(0xffc9f96c),
      _muted = Color(0xff9caaa5),
      _strip = Color(0xff1c2a25);

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          Widget time(double size, {double dy = 0}) => Align(
            alignment: Alignment(0, dy),
            child: Text(
              '12:34',
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: 'Roboto',
                color: _digits,
                fontSize: size,
                fontWeight: FontWeight.w500,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
          Widget strip({required bool top}) => Positioned(
            left: w * .1,
            right: w * .1,
            top: top ? h * .09 : null,
            bottom: top ? null : h * .11,
            height: h * .13,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _strip,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * .05),
                child: Row(
                  children: [
                    FractionallySizedBox(
                      heightFactor: .36,
                      child: SizedBox(
                        width: w * .13,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(color: _accent),
                        ),
                      ),
                    ),
                    SizedBox(width: w * .04),
                    Expanded(
                      child: FractionallySizedBox(
                        heightFactor: .36,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _muted.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          Widget bar(double width, double height, Color color) => Container(
            width: w * width,
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
          return ColoredBox(
            key: ValueKey('layout-miniature-$layout'),
            color: _ground,
            child: Stack(
              children: [
                switch (layout) {
                  'current' => Stack(
                    children: [strip(top: true), time(h * .36, dy: .25)],
                  ),
                  'next' => Stack(
                    children: [time(h * .36, dy: -.3), strip(top: false)],
                  ),
                  'only' => Center(
                    child: SizedBox(
                      width: w * .64,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(.19, h * .06, _accent),
                          SizedBox(height: h * .08),
                          bar(.64, h * .15, _digits),
                          SizedBox(height: h * .08),
                          bar(.4, h * .07, _muted),
                        ],
                      ),
                    ),
                  ),
                  _ => time(h * .5),
                },
                Positioned(
                  left: 0,
                  bottom: 0,
                  height: 3,
                  width: w * .58,
                  child: const ColoredBox(color: _accent),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
