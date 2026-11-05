import 'dart:convert';

import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/w2_program.dart';

/// The simulator is an output adapter, not a fake Huidu protocol implementation.
class Simulator {
  TextLayout? delivered;
  String owner = '', signature = '';
  int revision = -1, deliveredAt = 0;
  List<bool> pixels = List.filled(512, false);
  void clear() {
    delivered = null;
    owner = signature = '';
    revision = -1;
    deliveredAt = 0;
    pixels = List.filled(512, false);
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
    pixels = s.outputMode(now) == 'Clock'
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
