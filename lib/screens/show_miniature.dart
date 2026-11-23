import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/stage_layout_tiles.dart';
import 'package:flutter/material.dart';

/// A small picture of what a group shows, always in the stage's own dark
/// look: the four countdown layouts as [StageLayoutMiniature] draws them,
/// a slide (lines of words on a picture), and Slides and timer (words on
/// the left, the time and what is next on the right).
///
/// With [slide] false a group showing slides is drawn as it looks with no
/// slide up: the countdown in its [fallback] layout.
class ShowMiniature extends StatelessWidget {
  final String show;
  final bool slide, small;
  final String fallback;
  const ShowMiniature({
    super.key,
    required this.show,
    this.slide = true,
    this.small = false,
    this.fallback = 'timer',
  });

  static const _ground = Color(0xff0a1210),
      _panel = Color(0xff131d1a),
      _digits = Color(0xffe4e7de),
      _accent = Color(0xffc9f96c),
      _muted = Color(0xff9caaa5);

  @override
  Widget build(BuildContext context) {
    if (!showsSlides(show)) return StageLayoutMiniature(layout: show);
    if (!slide) return StageLayoutMiniature(layout: stageLayoutValue(fallback));
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(small ? 6 : 7),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            Widget lines(List<double> widths, {bool left = false}) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: left
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                for (final (i, f) in widths.indexed) ...[
                  if (i > 0) SizedBox(height: h * .055),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(
                      height: h * .065,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            );
            if (show == 'slides') {
              return DecoratedBox(
                key: const ValueKey('show-miniature-slides'),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xff2a2f6b),
                      Color(0xff7a5a8c),
                      Color(0xff3a2350),
                    ],
                    stops: [0, .6, 1],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * .17),
                  child: lines(const [1, .78, .9]),
                ),
              );
            }
            return ColoredBox(
              key: const ValueKey('show-miniature-monitor'),
              color: _ground,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 155,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(w * .07, 0, w * .04, 0),
                      child: lines(const [1, .78, .9, .6], left: true),
                    ),
                  ),
                  Expanded(
                    flex: 100,
                    child: ColoredBox(
                      color: _panel,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '12:34',
                              maxLines: 1,
                              softWrap: false,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                color: _digits,
                                fontSize: h * .2,
                                fontWeight: FontWeight.w500,
                                height: 1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: h * .08),
                          Container(
                            width: w * .13,
                            height: h * .035,
                            color: _accent,
                          ),
                          SizedBox(height: h * .04),
                          Container(
                            width: w * .3,
                            height: h * .045,
                            color: _muted.withValues(alpha: .8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
