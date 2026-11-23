import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/live/simulator_matrix.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// Whether this device has an LED sign to show: one set up (connected or
/// not), or the LED simulator chosen as the display.
bool hasLedSign(AppController c) =>
    c.hardware.enabled ||
    (c.destination == 'simulator' && c.state.simulatorKind == 'led');

/// The sign's state in plain words: the simulator, connected, reconnecting
/// or not found, from the sign's own connection.
String ledSignState(AppController c) {
  final h = c.hardware;
  if (!h.enabled) return 'LED simulator';
  if (h.connected && !h.interrupted && !h.held) return 'Connected';
  if (h.connected && h.held) return 'Connected · output held';
  if (h.reconnecting) return 'Reconnecting…';
  return 'Not found';
}

/// Whether the sign's preview is the live picture now: the simulator, or
/// a sign that is connected and showing what it was sent.
bool ledSignLive(AppController c) =>
    !c.hardware.enabled ||
    (c.hardware.connected && !c.hardware.interrupted && !c.hardware.held);

/// The LED sign's 32 × 16 dots: the app's copy of what it last sent to
/// the sign (not read back from it), or the simulator. Dimmed whenever
/// the sign is not connected, so a stale picture never looks live.
class LedSignMatrix extends StatelessWidget {
  final AppController controller;
  const LedSignMatrix({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.hardware.enabled) return SimulatorMatrix(controller: c);
    return AnimatedBuilder(
      animation: c.previewClock,
      builder: (context, _) => Opacity(
        opacity: ledSignLive(c) ? 1 : .45,
        child: LedMatrix(
          pixels: c.hardware.preview(c.now),
          hardware: true,
          stale: !ledSignLive(c),
        ),
      ),
    );
  }
}

/// The small strip on Live for the sign, above the stage preview: its dots
/// and, beside them, what it is and its state.
class LedSignStrip extends StatelessWidget {
  final AppController controller;
  const LedSignStrip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final c = controller;
    return ListenableBuilder(
      listenable: c.hardware,
      builder: (context, _) => Row(
        key: const ValueKey('led-sign-strip'),
        children: [
          SizedBox(width: 112, child: LedSignMatrix(controller: c)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.hardware.rememberedName.isEmpty
                      ? 'LED sign'
                      : c.hardware.rememberedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${ledSignState(c)} · what was sent to it',
                  key: const ValueKey('led-sign-state'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: ledSignLive(c) ? colors.muted : colors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
