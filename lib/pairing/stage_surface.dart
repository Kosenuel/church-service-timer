import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/pairing/confidence_monitor.dart';
import 'package:church_service_timer/pairing/countdown_face.dart';
import 'package:church_service_timer/pairing/flip_clock.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';

/// The face every stage screen is drawn in: Roboto, which the app carries,
/// so a screen looks the same on Windows (whose own font is Segoe UI),
/// Android and in the previews.
const stageFontFamily = 'Roboto';

class StageSurface extends StatelessWidget {
  final Json data;
  final bool stale;
  const StageSurface({super.key, required this.data, required this.stale});
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(fontFamily: stageFontFamily),
    child: Builder(builder: picture),
  );

  Widget picture(BuildContext context) {
    final sent = this.data;
    if (sent['stageSharing'] == false)
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The host is not sending to stage screens.\nOn the host, tap Show on stage screens on Live, or Change display and choose Phone, tablet or web screens.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    // Lyrics from the Lyrics page, where this screen is ticked for them.
    if (stageLyrics(sent) case final lyrics?)
      return LyricStage(data: lyrics, stale: stale);
    // Slides and timer: the slide's words beside the countdown.
    if (stageConfidence(sent) != null)
      return ConfidenceMonitor(data: sent, stale: stale);
    if (sent['blank'] == true) return const ColoredBox(color: Colors.black);
    if (sent['quickMessage'] is Map)
      return RichStageMessage(
        message: QuickMessage.fromJson(
          Map<String, dynamic>.from(sent['quickMessage']),
        ),
      );
    final layout = stageLayoutValue(sent['stageLayout']);
    // On the last segment, in a Quick timer or with no program, 'Up next
    // only' shows what the program ends on: its end screen, or the clock.
    final data = stageForLayout(sent, layout);
    // A banner cue leaves the countdown or clock in view, so the screen is
    // laid out for that and the cue is drawn in a band over it.
    final position = stageBannerPosition(data);
    final under = position == null ? data : stageUnderBanner(data);
    // The countdown is drawn whole by [StageCountdown]: its time, the
    // band for the segment or what is next, the progress line and the
    // colours of the moment.
    if (under['displayIsTimer'] == true) {
      return StageBannerFrame(
        banner: position == null ? null : stageBannerText(data),
        top: position == 'top',
        stale: stale,
        builder: (context, band, top) => StageCountdown(
          data: under,
          layout: layout,
          stale: stale,
          inset: EdgeInsets.only(top: top ? band : 0, bottom: top ? 0 : band),
        ),
      );
    }
    // A full-screen cue in a colour: its words in that colour (warm white
    // for amber) on charcoal, with a rule in its colour along the bottom
    // edge (see [stageColouredCard]).
    final card = stageColouredCard(data);
    // Whenever the screen is filled with the time of day, it is a flip
    // clock in the host's theme (see [stageShowsClock]).
    final clock = under['displayIsTimer'] == true
        ? null
        : stageClockFace(under);
    final colors = StageColors.of(data);
    final timer = clock != null
        ? FlipClock(
            face: clock,
            colors: colors,
            animate: !stale && !reduceAppMotion(context),
          )
        : StageMessage(
            data: under,
            stale: stale,
            fullscreen: true,
            ink: card
                ? Color(0xff000000 | stageCardInkFor(stageCueRgb(data)!))
                : null,
          );
    Widget surface(double rule) => StageBannerFrame(
      banner: position == null ? null : stageBannerText(data),
      top: position == 'top',
      stale: stale,
      builder: (context, band, top) => Padding(
        // Clear of the rule, above and below alike, so the cue stays
        // centred.
        padding: EdgeInsets.fromLTRB(12, 12 + rule, 12, 12 + rule),
        child: LayoutBuilder(
          builder: (context, space) {
            if (!space.maxHeight.isFinite) return timer;
            // The time keeps the box it has without a banner and gives up
            // the same space above and below, so it stays centred.
            final clear = StageBannerFrame.clearance(
              space.maxHeight,
              above: top && band > 0 ? band - 12 : 0,
              below: !top && band > 0 ? band - 12 : 0,
            );
            return Padding(
              // The flip clock fills its box, so it gives up the whole
              // band, not only the empty part of a line.
              padding: clock != null
                  ? EdgeInsets.only(top: top ? band : 0, bottom: top ? 0 : band)
                  : EdgeInsets.symmetric(vertical: clear),
              child: timer,
            );
          },
        ),
      ),
    );
    // A full-screen cue's screen flash lights the whole screen; a banner's
    // lights only its band (see [StageBanner]).
    return LayoutBuilder(
      builder: (context, screen) {
        final rule = card && screen.maxHeight.isFinite
            ? stageCardRule(screen.maxHeight)
            : 0.0;
        return StageScreenFlash(
          data: position == null ? data : null,
          base: card
              ? const Color(0xff000000 | stageCardBackground)
              : clock != null
              ? colors.background
              : Colors.transparent,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              surface(rule),
              if (rule > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: rule,
                  child: ColoredBox(
                    key: const ValueKey('stage-card-rule'),
                    color: stageCueColor(data),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A cue's whole-screen flash: when a cue with the 'screenFlash' effect
/// appears, [child]'s background glows with a deep tint of the cue's
/// colour (red for a white cue) for [duration], with the cue still drawn
/// in its own colour, and then it is [base] again. With reduced motion there is no flash: the
/// edge stays in the cue's colour while the cue shows instead.
class StageScreenFlash extends StatefulWidget {
  /// The cue's snapshot, or null where nothing here flashes.
  final Json? data;
  final Color base;
  final Widget child;

  /// The decoration's border while there is one, e.g. a banner's rule.
  final Border? border;
  const StageScreenFlash({
    super.key,
    required this.data,
    required this.base,
    required this.child,
    this.border,
  });
  static const duration = Duration(milliseconds: 600);

  /// The colour a cue in [data] flashes the screen: its own, or red when
  /// it is white, as white would only glare.
  static Color colorOf(Json data) {
    final color = stageCueColor(data);
    return color == Colors.white ? const Color(0xffff4d4d) : color;
  }

  @override
  State<StageScreenFlash> createState() => _StageScreenFlashState();
}

class _StageScreenFlashState extends State<StageScreenFlash>
    with SingleTickerProviderStateMixin {
  late final flash = AnimationController(
    vsync: this,
    duration: StageScreenFlash.duration,
  );
  bool get on =>
      widget.data != null && stageScreenEffect(widget.data!) == 'screenFlash';
  String key(Json? data) => data == null || stageScreenEffect(data) == null
      ? ''
      : '${data['displayText']}|${stageScreenEffect(data)}';

  @override
  void initState() {
    super.initState();
    if (on) flash.forward();
  }

  @override
  void didUpdateWidget(StageScreenFlash old) {
    super.didUpdateWidget(old);
    if (key(old.data) != key(widget.data)) {
      if (on) {
        flash.forward(from: 0);
      } else {
        flash.reset();
      }
    }
  }

  @override
  void dispose() {
    flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) => AnimatedBuilder(
      animation: flash,
      builder: (context, child) {
        final calm = reduceAppMotion(context);
        final lit = on && !calm && flash.isAnimating;
        final color = on ? StageScreenFlash.colorOf(widget.data!) : null;
        final edge = (space.biggest.shortestSide * .025)
            .clamp(4.0, 24.0)
            .toDouble();
        return DecoratedBox(
          key: const ValueKey('stage-screen-flash'),
          decoration: BoxDecoration(
            color: lit ? Color.lerp(Colors.black, color, .32) : widget.base,
            border: on && calm
                ? Border.all(color: color!, width: edge)
                : widget.border,
          ),
          child: StageFlashScope(lit: lit, child: child!),
        );
      },
      child: widget.child,
    ),
  );
}

/// The stage with room for a banner cue: a band across the top or bottom
/// edge in the cue's colour, with the countdown still in view.
///
/// The band is laid over the stage. [builder] is told how tall the band is
/// just now (it slides in and out) and which edge it is on, and keeps the
/// countdown centred where it was and clear of it (see [clearance]), so
/// the time never jumps aside as a banner comes or goes.
class StageBannerFrame extends StatefulWidget {
  /// The snapshot of the banner's text, or null when no banner shows.
  final Json? banner;
  final bool top, stale;
  final Widget Function(BuildContext context, double band, bool top) builder;
  const StageBannerFrame({
    super.key,
    required this.banner,
    required this.top,
    required this.stale,
    required this.builder,
  });

  /// The band's height on a screen [height] tall: a fifth of it.
  static double bandHeight(double height) =>
      (height * .2).clamp(0.0, 260.0).toDouble();

  /// The space the time gives up at both the top and the bottom of a box
  /// [box] tall, so that its digits stay clear of things reaching [above]
  /// and [below] into that box.
  ///
  /// The time's line is taller than its digits: at least 13% of it is
  /// empty above them and 19% below (Roboto has no digit below the line).
  /// That empty part may sit behind the band, so the time gives up less
  /// than the band's height and stays as large as it can.
  static double clearance(double box, {double above = 0, double below = 0}) {
    double need(double reach, double slack) =>
        reach <= 0 ? 0 : (reach * 1.18 - slack * box) / (1 - 2 * slack);
    final most = math.max(need(above, .13), need(below, .19));
    return most.clamp(0.0, math.max(0.0, box / 2 - 1)).toDouble();
  }

  @override
  State<StageBannerFrame> createState() => _StageBannerFrameState();
}

class _StageBannerFrameState extends State<StageBannerFrame> {
  // The last banner, kept so it can slide away after the cue has gone.
  Json? _shown;
  bool _top = false;
  @override
  Widget build(BuildContext context) {
    if (widget.banner != null) {
      _shown = widget.banner;
      _top = widget.top;
    }
    return LayoutBuilder(
      builder: (context, space) {
        final full = space.maxHeight.isFinite
            ? StageBannerFrame.bandHeight(space.maxHeight)
            : 0.0;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.banner == null ? 0 : 1),
          duration: reduceAppMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          builder: (context, shown, _) {
            final band = _shown;
            final height = shown == 0 || band == null ? 0.0 : full * shown;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                widget.builder(context, height, _top),
                if (height > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _top ? 0 : null,
                    bottom: _top ? null : 0,
                    height: height,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: _top
                            ? Alignment.bottomCenter
                            : Alignment.topCenter,
                        minHeight: full,
                        maxHeight: full,
                        child: StageBanner(
                          data: band!,
                          top: _top,
                          stale: widget.stale,
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

/// A banner cue's band: the cue in its colour on a dark tint of the same
/// colour, with a rule along the edge that faces the countdown.
class StageBanner extends StatelessWidget {
  final Json data;
  final bool top, stale;
  const StageBanner({
    super.key,
    required this.data,
    required this.top,
    required this.stale,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final color = stageCueColor(data);
      final rule = BorderSide(
        color: color,
        width: (space.maxHeight * .035).clamp(2.0, 8.0),
      );
      return StageScreenFlash(
        key: const ValueKey('stage-banner'),
        data: data,
        base: Color.alphaBlend(color.withValues(alpha: .16), Colors.black),
        border: top ? Border(bottom: rule) : Border(top: rule),
        child: Padding(
          padding: EdgeInsets.symmetric(
            // Scrolling text runs from edge to edge of the screen.
            horizontal: data['effect'] == 'scroll' && !stageWrapsText(data)
                ? 0
                : space.maxHeight * .3,
            vertical: space.maxHeight * .1,
          ),
          child: StageMessage(
            data: data,
            stale: stale,
            fullscreen: true,
            wrapLines: stageBannerWrapLines,
            fromTop: top,
            // The band is a fifth of the screen.
            screenHeight: space.maxHeight / .2,
          ),
        ),
      );
    },
  );
}

class RichStageMessage extends StatelessWidget {
  final QuickMessage message;
  const RichStageMessage({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    final colors = switch (message.palette) {
      'amber' => (const Color(0xffffdc8b), const Color(0xff261b09)),
      'sky' => (const Color(0xffc4e6ff), const Color(0xff071b2c)),
      'mint' => (const Color(0xffbcf4da), const Color(0xff08271c)),
      _ => (Colors.white, const Color(0xff10151c)),
    };
    final align = switch (message.align) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    // One fixed-aspect canvas is shared by the composer, operator preview and stage.
    // Fit the canvas uniformly; never distort individual text or auto-scroll it.
    TextStyle headlineStyle(double fit) => TextStyle(
      fontFamily: stageFontFamily,
      color: colors.$1,
      fontSize: 42 * message.scale * fit,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    TextStyle bodyStyle(double fit) => TextStyle(
      fontFamily: stageFontFamily,
      color: colors.$1,
      fontSize: (message.length > 100 ? 38 : 48) * message.scale * fit,
      height: 1.2,
      fontWeight: message.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: message.italic ? FontStyle.italic : FontStyle.normal,
    );
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: align,
        textDirection: Directionality.of(context),
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: 864);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var fit = 1.0;
    while (fit > .4 &&
        (measure(message.body, bodyStyle(fit)) +
                (message.headline.isEmpty
                    ? 0
                    : measure(message.headline, headlineStyle(fit)) + 24)) >
            476) {
      fit -= .025;
    }
    return ColoredBox(
      color: colors.$2,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 960,
              height: 540,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message.headline.isNotEmpty) ...[
                      Text(
                        message.headline,
                        textAlign: align,
                        textScaler: TextScaler.noScaling,
                        style: headlineStyle(fit),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Flexible(
                      child: Text(
                        message.body,
                        textAlign: align,
                        textScaler: TextScaler.noScaling,
                        style: bodyStyle(fit),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
