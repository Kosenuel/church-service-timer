import 'dart:convert';
import 'dart:math' as math;

import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/w2_program.dart';

/// The simulator is an output adapter, not a fake Huidu protocol implementation.
class Simulator {
  TextLayout? delivered;
  String owner = '', signature = '';
  int revision = -1, deliveredAt = 0;
  List<bool> pixels = List.filled(512, false);

  /// The monotonic time [pixels] were drawn for.
  int drawnAt = 0;

  /// Whether the picture changes between updates by itself: text wider
  /// than the sign scrolling, flashing, or shown a few words at a time. The view then draws it again
  /// on every frame with [pixelsAt], so it moves at the sign's own steady
  /// pace rather than only when the app's clock ticks.
  bool moving = false;

  /// What the sign shows at the monotonic time [mono]: the delivered text
  /// as far through its scroll or flash as it is by then.
  List<bool> pixelsAt(int mono) =>
      moving ? renderPixels(delivered, mono - deliveredAt) : pixels;

  /// The first monotonic time after [mono] at which the moving picture
  /// changes: the next column of the scroll, or the next half second of a
  /// flash. Null when it does not move.
  int? nextChangeAfter(int mono) {
    final shown = delivered;
    if (!moving || shown == null) return null;
    final elapsed = math.max(0, mono - deliveredAt);
    // A few words at a time changes, at most, every frame of the sign's.
    if (signWordGroups(shown) != null) {
      return deliveredAt + (elapsed ~/ wordGroupFrameMs + 1) * wordGroupFrameMs;
    }
    if (shown.effect == 'flash')
      return deliveredAt + (elapsed ~/ 500 + 1) * 500;
    final speed = shown.speed;
    if (speed <= 0) return null;
    final column = elapsed * speed ~/ 1000;
    return deliveredAt + ((column + 1) * 1000 + speed - 1) ~/ speed;
  }

  void clear() {
    delivered = null;
    owner = signature = '';
    revision = -1;
    deliveredAt = 0;
    pixels = List.filled(512, false);
    moving = false;
  }

  void update(Session s, Stamp now) {
    if (s.disconnected || s.held) return;
    if (s.outputBlank) {
      if (owner != s.id || signature != 'blank') deliveredAt = now.mono;
      owner = s.id;
      signature = 'blank';
      revision = s.revision;
      delivered = null;
      pixels = List.filled(512, false);
      moving = false;
      drawnAt = now.mono;
      return;
    }
    final desired = s.intended(now);
    if (desired == null) return; // Ready/idle retain previous output.
    final next = jsonEncode(desired.toJson());
    if (owner != s.id || signature != next) {
      owner = s.id;
      signature = next;
      delivered = desired;
      deliveredAt = now.mono;
    }
    revision = s.revision;
    final clock = s.outputMode(now) == 'Clock';
    final shown = delivered;
    moving =
        !clock &&
        shown != null &&
        (shown.effect == 'flash' ||
            scrollsOnSign(shown) ||
            stageWordGroupsOf(shown) != null);
    drawnAt = now.mono;
    pixels = clock
        ? W2Program.clockPixels(
            DateTime.fromMillisecondsSinceEpoch(now.wall),
            format12Hour: s.clockFormat == '12h',
          )
        : renderPixels(delivered, now.mono - deliveredAt);
    // Simulator-only blink. Physical preview stays faithful to native output.
    if (s.outputMode(now) == 'Clock' &&
        s.clockBlink &&
        now.wall % 1000 >= 500) {
      final left = s.clockFormat == '12h' ? 8 : 13;
      final width = s.clockFormat == '12h' ? 4 : 6;
      for (var y = 0; y < 16; y++) {
        for (var x = left; x < left + width; x++) {
          pixels[y * 32 + x] = false;
        }
      }
    }
  }
}
