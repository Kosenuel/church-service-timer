import 'package:church_service_timer/domain/core.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Monday", as the flip clock names the day.
String stageWeekday(DateTime time) => _weekdays[time.weekday - 1];

/// "23 November 2026": day first, as the rest of the app writes dates.
String stageDate(DateTime time) =>
    '${time.day} ${_months[time.month - 1]} ${time.year}';

/// The day and date a stage snapshot carries beside a clock, in the host's
/// own time, so every screen shows the day the host's clock is on.
Json stageClockDateFields(int wall) {
  final time = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return {'clockWeekday': stageWeekday(time), 'clockDate': stageDate(time)};
}

/// Whether a snapshot fills the screen with the time of day: the clock
/// (after Show clock, and an ended service with no end screen), the clock
/// shown before a scheduled service starts, and the clock under a banner.
/// The host marks the clock before a service with `clockFace`, because
/// its output is then 'Pre-service', as the countdown to the start is.
bool stageShowsClock(Json data) =>
    data['outputMode'] == 'Clock' || data['clockFace'] == true;

final _clockPattern = RegExp(r'^(\d{1,2}):(\d\d)(?: ([AP])M)?$');

/// What the flip clock draws: the hours and minutes as the host writes
/// them (no leading zero on a 12 hour clock, "8:59"; two digits on a 24
/// hour clock, "08:59"), whether it is PM (null on a 24 hour clock, which
/// has no AM or PM), and the weekday and date under the time.
class StageClockFace {
  final String hours, minutes, weekday, date;
  final bool? pm;
  const StageClockFace(
    this.hours,
    this.minutes,
    this.pm,
    this.weekday,
    this.date,
  );
  bool get twelveHour => pm != null;

  /// "8:59 AM" or "08:59", for assistive technology.
  String get time =>
      '$hours:$minutes${pm == null
          ? ''
          : pm!
          ? ' PM'
          : ' AM'}';

  @override
  bool operator ==(Object other) =>
      other is StageClockFace &&
      other.hours == hours &&
      other.minutes == minutes &&
      other.pm == pm &&
      other.weekday == weekday &&
      other.date == date;
  @override
  int get hashCode => Object.hash(hours, minutes, pm, weekday, date);
}

/// The clock a snapshot shows, or null when it shows none or its time is
/// not one. A host from before the flip clock sends no day or date, and
/// the screen then uses its own ([now], for tests).
StageClockFace? stageClockFace(Json data, {DateTime? now}) {
  if (!stageShowsClock(data)) return null;
  final match = _clockPattern.firstMatch('${data['displayText'] ?? ''}');
  if (match == null) return null;
  final own = now ?? DateTime.now();
  String text(dynamic value, String otherwise) =>
      value is String && value.isNotEmpty && value.length <= 40
      ? value
      : otherwise;
  return StageClockFace(
    match.group(1)!,
    match.group(2)!,
    match.group(3) == null ? null : match.group(3) == 'P',
    text(data['clockWeekday'], stageWeekday(own)),
    text(data['clockDate'], stageDate(own)),
  );
}

/// The five colours of a stage theme, in the order they are sent.
const stageThemeKeys = ['background', 'surface', 'accent', 'muted', 'text'];

/// The theme a snapshot carries, with every colour a checked "#rrggbb",
/// or null when it has none or any colour is not one: the screen then
/// keeps to white on black, as it was before screens followed the theme.
Map<String, String>? stageThemeOf(Json data) {
  final theme = data['stageTheme'];
  if (theme is! Map) return null;
  final colours = <String, String>{};
  for (final key in stageThemeKeys) {
    final value = theme[key];
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    colours[key] = value.toLowerCase();
  }
  return colours;
}
