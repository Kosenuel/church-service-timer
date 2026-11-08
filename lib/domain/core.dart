/// Shared building blocks: JSON maps, validation rules and the boot-aware clock stamp.
library;

import 'dart:math' as math;

typedef Json = Map<String, dynamic>;
const maxRemainingMs = 5999000;
// Retain the old deserialization ceiling above so existing records remain readable.
const supportedCountdownMs = 3599000;
const recoveryLimitMs = 30 * 60 * 1000;

class RuleError implements Exception {
  final String message;
  RuleError(this.message);
  @override
  String toString() => message;
}

void require(bool condition, String message) {
  if (!condition) throw RuleError(message);
}

String nameValue(dynamic value, String label) {
  require(value is String, '$label must be text.');
  final s = (value as String).trim();
  require(
    s.isNotEmpty && s.runes.length <= 80,
    '$label must contain 1–80 characters.',
  );
  return s;
}

void keys(Json j, Set<String> allowed, String context) {
  final extra = j.keys.where((k) => !allowed.contains(k));
  require(
    extra.isEmpty,
    '$context contains unsupported fields: ${extra.join(', ')}. Hardware settings and approvals cannot be imported.',
  );
}

class Stamp {
  final int mono, wall;
  final String boot;
  const Stamp(this.mono, this.wall, this.boot);
  factory Stamp.fromJson(Json j) =>
      Stamp(j['mono'] as int, j['wall'] as int, j['boot'] as String);
  Json toJson() => {'mono': mono, 'wall': wall, 'boot': boot};
  bool sameBoot(Stamp other) =>
      boot != 'unknown' &&
      boot != '-1' &&
      boot == other.boot &&
      mono >= other.mono;
  int since(Stamp other) =>
      math.max(0, sameBoot(other) ? mono - other.mono : wall - other.wall);
}
