import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/paired_screen.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The countdown as a stage screen draws it: the time as large as the
/// space allows, in the theme's colours, with a band across the top (the
/// segment now) or the bottom (what is next) as the layout says, or the
/// next item alone, and a line along the bottom edge for how much of the
/// segment has gone.
///
/// It follows the moment: amber digits and line in the host's warning
/// period, dimmed digits and a PAUSED tag when paused, and in overtime a
/// red the operator chose the strength of (see [overtimeAlerts]).
class StageCountdown extends StatefulWidget {
  final Json data;

  /// 'timer', 'current', 'next' or 'only'.
  final String layout;
  final bool stale;

  /// Room a banner cue takes at the top or bottom: the picture keeps clear
  /// of it, and the colour still fills the whole screen.
  final EdgeInsets inset;
  const StageCountdown({
    super.key,
    required this.data,
    required this.layout,
    required this.stale,
    this.inset = EdgeInsets.zero,
  });
  @override
  State<StageCountdown> createState() => _StageCountdownState();
}

class _StageCountdownState extends State<StageCountdown>
    with SingleTickerProviderStateMixin {
  // The Strongest pulse: one second up and one down, about every two.
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  bool pulsing = false;

  void syncPulse(bool want) {
    if (want == pulsing) return;
    pulsing = want;
    if (want) {
      pulse.repeat(reverse: true);
    } else {
      pulse.stop();
      pulse.value = 0;
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final colors = StageColors.of(data);
    final only = widget.layout == 'only';
    final moment = only && stageMoment(data) == 'overtime'
        ? (data['paused'] == true ? 'paused' : 'normal')
        : stageMoment(data);
    final over = moment == 'overtime';
    final alert = overtimeAlertValue(data['overtimeAlert']);
    final solid = over && alert != 'gentle';
    final calm = reduceAppMotion(context);
    final wantsPulse = solid && alert == 'strongest' && !calm && !widget.stale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) syncPulse(wantsPulse);
    });
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 1280.0;
        final h = box.maxHeight.isFinite ? box.maxHeight : w * 9 / 16;
        final upright = h > w;
        // What the screen is made of in this moment.
        final ink = over
            ? (solid ? StageColors.overtimeInk : colors.over)
            : moment == 'warning'
            ? colors.warn
            : colors.text;
        final line = over
            ? (solid ? StageColors.overtimeInk : colors.over)
            : moment == 'warning'
            ? colors.warn
            : colors.accent;
        final track = solid
            ? Colors.black.withValues(alpha: .22)
            : colors.track;
        final bandFill = solid
            ? Colors.black.withValues(alpha: .12)
            : colors.band;
        final bandLine = solid
            ? Colors.black.withValues(alpha: .3)
            : colors.bandLine;
        final eyebrow = solid ? StageColors.overtimeInk : colors.accent;
        final name = solid ? StageColors.overtimeInk : colors.text;
        final sub = solid
            ? StageColors.overtimeInk.withValues(alpha: .8)
            : colors.muted;
        final frame = over && alert == 'gentle'
            ? (math.min(w, h) * .035).clamp(6.0, 48.0).toDouble()
            : 0.0;
        final track0 = (upright ? w * .024 : w * .013).clamp(4.0, 40.0);
        final pad = upright
            ? EdgeInsets.fromLTRB(w * .06, w * .08, w * .06, w * .10)
            : EdgeInsets.fromLTRB(w * .03, w * .03, w * .03, w * .044);
        final gap = upright ? w * .05 : w * .02;

        Widget band(String label, String title, String detail) {
          final eyebrowText = Text(
            label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: stageFontFamily,
              color: eyebrow,
              fontSize: upright ? w * .042 : w * .019,
              fontWeight: FontWeight.w700,
              letterSpacing: (upright ? w * .042 : w * .019) * .16,
              height: 1.1,
            ),
          );
          TextStyle nameStyle() => TextStyle(
            fontFamily: stageFontFamily,
            color: name,
            fontSize: upright ? w * .09 : w * .044,
            fontWeight: FontWeight.w500,
            height: 1.1,
          );
          TextStyle subStyle() => TextStyle(
            fontFamily: stageFontFamily,
            color: sub,
            fontSize: upright ? w * .054 : w * .03,
            height: 1.15,
          );
          final inner = upright
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    eyebrowText,
                    SizedBox(height: w * .015),
                    Text(
                      title,
                      key: const ValueKey('stage-band-name'),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: nameStyle(),
                    ),
                    if (detail.isNotEmpty) ...[
                      SizedBox(height: w * .015),
                      Text(
                        detail,
                        key: const ValueKey('stage-band-detail'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: subStyle(),
                      ),
                    ],
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    eyebrowText,
                    SizedBox(width: w * .02),
                    Flexible(
                      child: Text(
                        title,
                        key: const ValueKey('stage-band-name'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: nameStyle(),
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      SizedBox(width: w * .02),
                      // Who and how long keep their own words unless they
                      // are very long; the name gives way first.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: w * .36),
                        child: Text(
                          detail,
                          key: const ValueKey('stage-band-detail'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: subStyle(),
                        ),
                      ),
                    ],
                  ],
                );
          return LayoutBuilder(
            builder: (context, room) => ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h * (upright ? .34 : .3)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  key: ValueKey('stage-band-${label.toLowerCase()}'),
                  width: room.maxWidth,
                  padding: upright
                      ? EdgeInsets.symmetric(
                          horizontal: w * .04,
                          vertical: w * .05,
                        )
                      : EdgeInsets.symmetric(
                          horizontal: w * .03,
                          vertical: w * .015,
                        ),
                  decoration: BoxDecoration(
                    color: bandFill,
                    border: Border.all(color: bandLine),
                    borderRadius: BorderRadius.circular(
                      upright ? w * .04 : w * .016,
                    ),
                  ),
                  child: inner,
                ),
              ),
            ),
          );
        }

        // The tag under the digits: always the same room, so the digits do
        // not change size as it comes and goes.
        final tagHeight = upright ? w * .085 : h * .075;
        Widget tag() {
          final paused = data['paused'] == true && !only;
          final text = paused
              ? (over ? 'PAUSED · OVER TIME' : 'PAUSED')
              : over
              ? 'OVER TIME'
              : '';
          if (text.isEmpty) return SizedBox(height: tagHeight);
          final pill = over && !paused;
          return SizedBox(
            height: tagHeight,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  key: const ValueKey('stage-tag'),
                  padding: EdgeInsets.symmetric(
                    horizontal: tagHeight * .5,
                    vertical: tagHeight * .12,
                  ),
                  decoration: BoxDecoration(
                    color: pill
                        ? (solid ? StageColors.overtimeInk : colors.over)
                        : bandFill,
                    border: pill ? null : Border.all(color: bandLine),
                    borderRadius: BorderRadius.circular(tagHeight),
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: stageFontFamily,
                      fontWeight: FontWeight.w700,
                      letterSpacing: tagHeight * .5 * .18,
                      fontSize: tagHeight * .5,
                      height: 1.1,
                      color: pill
                          ? (solid
                                ? StageColors.overtimeRed
                                : colors.background)
                          : colors.text,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        Widget digits() => Column(
          children: [
            Expanded(
              child: Opacity(
                opacity: moment == 'paused' ? .45 : 1,
                child: StageMessage(
                  data: data,
                  stale: widget.stale,
                  fullscreen: true,
                  ink: ink,
                ),
              ),
            ),
            tag(),
          ],
        );

        Widget only0() {
          final next = stageUpNext(data);
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: (w - pad.horizontal - widget.inset.horizontal) * .94,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'UP NEXT',
                      key: const ValueKey('stage-next-eyebrow'),
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily: stageFontFamily,
                        color: eyebrow,
                        fontSize: upright ? w * .054 : w * .03,
                        fontWeight: FontWeight.w700,
                        letterSpacing: (upright ? w * .054 : w * .03) * .16,
                      ),
                    ),
                    SizedBox(height: upright ? w * .05 : w * .022),
                    Text(
                      next?.name ?? '',
                      key: const ValueKey('stage-next-name'),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily: stageFontFamily,
                        color: name,
                        fontSize: upright ? w * .17 : w * .12,
                        fontWeight: FontWeight.w500,
                        height: 1.02,
                      ),
                    ),
                    if (next != null && next.detail.isNotEmpty) ...[
                      SizedBox(height: upright ? w * .05 : w * .022),
                      Text(
                        next.detail,
                        key: const ValueKey('stage-next-detail'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: stageFontFamily,
                          color: sub,
                          fontSize: upright ? w * .07 : w * .046,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final nowName = '${data['segment'] ?? ''}'.trim();
        final nowBy = '${data['speaker'] ?? ''}'.trim();
        final next = stageUpNext(data);
        final children = <Widget>[
          if (widget.layout == 'current' && nowName.isNotEmpty) ...[
            band('Now', nowName, nowBy),
            SizedBox(height: gap),
          ],
          Expanded(child: digits()),
          if (widget.layout == 'next' && next != null) ...[
            SizedBox(height: gap),
            band('Up next', next.name, next.detail),
          ],
        ];
        return AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            final base = solid
                ? (pulsing
                      ? Color.lerp(
                          StageColors.overtimeRed,
                          StageColors.overtimeBright,
                          Curves.easeInOut.transform(pulse.value),
                        )!
                      : StageColors.overtimeRed)
                : colors.background;
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  key: const ValueKey('stage-countdown-ground'),
                  color: base,
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: widget.inset.top,
                    bottom: widget.inset.bottom,
                  ),
                  child: Padding(
                    padding: pad + EdgeInsets.all(frame),
                    child: only ? only0() : Column(children: children),
                  ),
                ),
                if (frame > 0)
                  IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('stage-overtime-frame'),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.over, width: frame),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: track0,
                  child: ColoredBox(
                    color: track,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: stageProgress(data)),
                        duration: calm || widget.stale
                            ? Duration.zero
                            : const Duration(seconds: 1),
                        builder: (context, value, _) => FractionallySizedBox(
                          widthFactor: value,
                          child: ColoredBox(
                            key: const ValueKey('stage-progress'),
                            color: line,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
