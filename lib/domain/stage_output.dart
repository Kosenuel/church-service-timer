import 'package:church_service_timer/domain/domain.dart';

String readClockFormat(dynamic value) {
  require({'12h', '24h'}.contains(value), 'Choose a 12-hour or 24-hour clock.');
  return value as String;
}

String stageClockText(int wall, String format) {
  final time = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  final minute = time.minute.toString().padLeft(2, '0');
  if (format == '12h')
    return '${time.hour % 12 == 0 ? 12 : time.hour % 12}:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  return '${time.hour.toString().padLeft(2, '0')}:$minute';
}

TextLayout clockLayout(int wall, String format) => TextLayout(
  stageClockText(wall, format),
  effect: 'static',
  height: format == '12h' ? 1 : 2,
);

int readMessageDuration(dynamic seconds) {
  require(
    seconds is int && seconds >= 0 && seconds <= 3599,
    'Choose Until cleared or 00:01–59:59.',
  );
  return seconds as int;
}

class StageOutputMessage {
  final TextLayout layout;
  final int seconds;
  const StageOutputMessage(this.layout, {this.seconds = 0});
}

/// How fast a scrolling cue moves on a screen, on the LED sign's scale: the
/// cue's speed on screens when the host sent one, otherwise the sign's.
double stageScrollSpeed(Json data) {
  final speed = data['screenSpeed'] ?? data['speed'];
  return (speed is num ? speed.toDouble() : 12.0).clamp(1.0, 60.0);
}

/// A cue's effect as a stage snapshot carries it. `effect` is always one
/// every version knows, so an older paired screen shows a newer effect as
/// steady text; `screenEffect` is the newer effect, for screens that know
/// it. [time] is the cue's whole time and the time left, in milliseconds,
/// for a countdown bar; a cue shown until cleared has none, and no bar.
Json stageEffectFields(TextLayout? cue, {({int total, int left})? time}) => {
  'effect': cue?.compatibleEffect ?? 'static',
  'screenEffect': ?cue?.screenEffect,
  if (cue?.screenEffect == 'bar' && time != null && time.total > 0) ...{
    'cueTotalMs': time.total,
    'cueLeftMs': time.left.clamp(0, time.total),
  },
};

/// The newer effect a snapshot asks screens for, or null: none, or one
/// this version does not know, which is then shown as its `effect` says.
String? stageScreenEffect(Json data) {
  final effect = data['screenEffect'];
  return screenEffects.contains(effect) ? effect as String : null;
}

/// A countdown bar's whole time and time left, in milliseconds, or null
/// when the snapshot has no sensible one (the cue then shows no bar).
({int total, int left})? stageCueTime(Json data) {
  final total = data['cueTotalMs'], left = data['cueLeftMs'];
  if (stageScreenEffect(data) != 'bar' ||
      total is! int ||
      left is! int ||
      total <= 0 ||
      left < 0 ||
      left > total) {
    return null;
  }
  return (total: total, left: left);
}

/// The fixed colours a cue can have on screens, as RGB. Each is bright
/// enough to read on the black stage background and they are far apart
/// from one another. The theme's accent is worked out by the host.
const screenCueColors = <String, int>{
  'white': 0xffffff,
  'amber': 0xffa833,
  'red': 0xff4d4d,
  'green': 0x4ade80,
};

/// A colour as the stage snapshot carries it: "#rrggbb".
String stageColorHex(int rgb) =>
    '#${(rgb & 0xffffff).toRadixString(16).padLeft(6, '0')}';

/// The cue colour in a stage snapshot as RGB, or null when the snapshot
/// has none or it is not a colour; the cue is then white, as always.
int? stageCueRgb(Json data) {
  final value = data['cueColor'];
  if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return null;
  }
  return int.parse(value.substring(1), radix: 16);
}

/// 'top' or 'bottom' when the snapshot shows its cue as a banner over the
/// countdown or clock, otherwise null: the cue fills the screen.
String? stageBannerPosition(Json data) {
  final position = data['cuePosition'];
  return (position == 'top' || position == 'bottom') &&
          data['underText'] is String &&
          data['blank'] != true
      ? position as String
      : null;
}

/// The snapshot of what stays in view under a banner: the countdown or
/// the clock, plain and white, as if no cue were showing.
Json stageUnderBanner(Json data) {
  final clock = data['underMode'] == 'Clock';
  return {
    ...data,
    'displayText': data['underText'],
    'effect': 'static',
    'bold': false,
    'italic': false,
    'outputMode': clock ? 'Clock' : 'Countdown',
    'displayIsTimer': !clock,
  }..removeWhere(
    (key, _) => const {
      'cueColor',
      'cuePosition',
      'underText',
      'underMode',
      'screenSpeed',
      // The countdown under a banner never takes the cue's effect.
      'screenEffect',
      'cueTotalMs',
      'cueLeftMs',
    }.contains(key),
  );
}

/// The snapshot of the banner's own text: the cue in its colour.
Json stageBannerText(Json data) => {
  ...data,
  'displayIsTimer': false,
  'outputMode': 'Cue',
}..removeWhere((key, _) => const {'cuePosition', 'underText'}.contains(key));
