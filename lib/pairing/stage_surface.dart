import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

class StageSurface extends StatelessWidget {
  final Json data;
  final bool stale;
  const StageSurface({super.key, required this.data, required this.stale});
  @override
  Widget build(BuildContext context) {
    if (data['stageSharing'] == false)
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
    if (data['blank'] == true) return const ColoredBox(color: Colors.black);
    if (data['quickMessage'] is Map)
      return RichStageMessage(
        message: QuickMessage.fromJson(
          Map<String, dynamic>.from(data['quickMessage']),
        ),
      );
    final layout = data['stageLayout'] ?? 'timer';
    final timer = StageMessage(data: data, stale: stale, fullscreen: true);
    final showSegment = data['displayIsTimer'] == true && layout != 'timer';
    final text = layout == 'next'
        ? (data['nextSegment'] == ''
              ? 'Final segment'
              : 'Next: ${data['nextSegment'] ?? ''}')
        : '${data['segment'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: !showSegment
          ? timer
          : Column(
              children: [
                Expanded(child: timer),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
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
      fontFamily: 'Roboto',
      color: colors.$1,
      fontSize: 42 * message.scale * fit,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    TextStyle bodyStyle(double fit) => TextStyle(
      fontFamily: 'Roboto',
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
