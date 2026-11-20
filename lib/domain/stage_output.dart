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
