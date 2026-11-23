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

/// The fixed colours a cue can have on screens, as RGB. Each reads at
/// 7:1 or better on a coloured cue's charcoal (and so on the black stage
/// background), red lightened only as far as that needs, and they are far
/// apart from one another. The theme's accent is worked out by the host.
const screenCueColors = <String, int>{
  'white': 0xffffff,
  'amber': 0xffa833,
  'red': 0xff7979,
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

/// The groups of words a snapshot's Flash or Pulse cue steps through on
/// screens, as the LED sign does with text too wide for it (see
/// [groupWords]); null when it sent none, or they are not words. An older
/// version leaves them out, and a screen then shows the whole text.
List<String>? stageWordGroups(Json data) {
  final words = data['screenWords'];
  if (words is! List ||
      words.isEmpty ||
      words.length > wordGroupMaxLength ||
      words.any((w) => w is! String || w.trim().isEmpty)) {
    return null;
  }
  return List<String>.from(words);
}

/// The effect a snapshot steps its groups of words with, 'flash' or
/// 'pulse', or null when it shows its text whole: no groups, another
/// effect, or wrapped onto lines (wrapped text flashes or pulses whole).
String? stageWordEffect(Json data) {
  if (stageWordGroups(data) == null || stageWrapsText(data)) return null;
  if (data['effect'] == 'flash') return 'flash';
  if (stageScreenEffect(data) == 'pulse') return 'pulse';
  return null;
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
      'screenWrap',
      'screenWords',
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

/// The most lines a cue wraps onto on screens: three filling the screen,
/// two in a banner.
const stageWrapLines = 3, stageBannerWrapLines = 2;

/// The smallest wrapped text may be, as a share of the height of its box
/// for each line it may use: on a 1080-line screen, 130 px for three lines
/// and, in a banner, 31 px for two. Text that would need to be smaller
/// scrolls instead, so it is never cut off or too small to read.
const stageWrapMinimum = .36;

/// Whether a snapshot's cue is wrapped onto lines on screens: a cue (not
/// the countdown or clock) with "Wrap long text" chosen. Wrapped text does
/// not scroll on screens (the LED sign still does); a newer effect such as
/// pulse or slide in plays on the wrapped block as a whole. The effects
/// arrive as a classic `effect` (see [stageEffectFields]), so one this
/// version does not know is not wrapped.
bool stageWrapsText(Json data) =>
    data['screenWrap'] == true &&
    data['displayIsTimer'] != true &&
    data['outputMode'] != 'Clock' &&
    const {'static', 'scroll', 'flash', null}.contains(data['effect']);

/// A time as screens show it: "48:03", "+01:10", "123:00", "09:30" or
/// "9:30 AM".
final stageTimePattern = RegExp(r'^[+-]?\d{1,3}(:\d\d){1,2}( [AP]M)?$');

/// Whether a snapshot shows a time that screens hold still as it changes,
/// each digit in its own place: the countdown, the clock, and the clock
/// or countdown shown before a scheduled service starts.
bool stageShowsTime(Json data) =>
    data['outputMode'] == 'Clock' ||
    (data['displayIsTimer'] == true && data['effect'] == 'static') ||
    (data['outputMode'] == 'Pre-service' &&
        data['effect'] == 'static' &&
        stageScreenEffect(data) == null &&
        stageTimePattern.hasMatch('${data['displayText'] ?? ''}'));

/// Whether a snapshot's time blinks its colons: the clock, and the
/// countdown while it runs.
bool stageTimeBlinks(Json data) =>
    data['clockBlink'] != false &&
    (data['outputMode'] == 'Clock' ||
        (data['displayIsTimer'] == true && data['paused'] != true));

/// A full-screen cue in a colour other than white is shown on a warm
/// charcoal screen, with a rule in its colour along the bottom edge. Its
/// words are in the cue's colour too, except amber, whose words are warm
/// white (see [stageCardInkFor]). White cues, banners, the countdown and
/// the clock are as they were.
const stageCardBackground = 0x1a1712, stageCardInk = 0xfff4dc;

/// The colour of a coloured full-screen cue's words, as RGB, for a cue in
/// [rgb]: warm white for amber, otherwise the cue's own colour. Each reads
/// on the charcoal: amber's words would be no clearer than warm white, so
/// they stay warm white; the theme's colour is lightened until it reads at
/// 7:1 or better before it is sent (see `stageAccentRgbOf`).
int stageCardInkFor(int rgb) =>
    rgb == screenCueColors['amber'] ? stageCardInk : rgb;

/// Whether [data] shows its cue full screen in a colour (see
/// [stageCardBackground]).
bool stageColouredCard(Json data) {
  final rgb = stageCueRgb(data);
  final text = data['displayText'];
  return rgb != null &&
      rgb != 0xffffff &&
      data['blank'] != true &&
      data['quickMessage'] == null &&
      data['displayIsTimer'] != true &&
      data['outputMode'] != 'Clock' &&
      stageBannerPosition(data) == null &&
      text is String &&
      text.trim().isNotEmpty;
}

/// The coloured rule along the bottom of a screen [height] tall: 18 px on
/// a 1080-line screen, and never thinner than 4 px.
double stageCardRule(double height) =>
    (height * 18 / 1080).clamp(4.0, double.infinity).toDouble();

/// What a stage screen shows while it counts down, by the name the stage
/// snapshot carries, with the words every chooser uses: paired stage
/// screens, web stage displays, the second screen, full screen and the
/// stage simulator.
const stageLayouts = {
  'timer': 'Timer only',
  'current': 'Timer and segment name',
  'next': 'Timer and up next',
  'only': 'Up next only',
};

/// A stage layout from saved settings; anything unknown is 'timer'.
String stageLayoutValue(dynamic value) =>
    stageLayouts.containsKey(value) ? value as String : 'timer';

/// The "up next" line for the segment after [index] in [timeline]:
/// `Next: Response · Worship team · 5 min`. Empty on the last segment,
/// during a Quick timer and with no program, so nothing shows then.
String stageUpNextLine(Timeline? timeline, int index, {bool quick = false}) {
  if (timeline == null || quick || index + 1 >= timeline.segments.length) {
    return '';
  }
  final next = timeline.segments[index + 1];
  return [
    'Next: ${next.name}',
    if (next.speaker.trim().isNotEmpty) next.speaker.trim(),
    next.durationText,
  ].join(' · ');
}

/// The line under the countdown in a stage snapshot for its layout: the
/// segment name, the up next line, or empty for nothing. A snapshot from
/// a host from before the up next line has only the next segment's name.
String stageLayoutLine(Json data, String layout) => switch (layout) {
  'timer' || 'only' => '',
  'next' => switch (data['upNext']) {
    final String line => line,
    _ => switch (data['nextSegment']) {
      final String name when name.isNotEmpty => 'Next: $name',
      _ => '',
    },
  },
  _ => '${data['segment'] ?? ''}',
};

/// The next item as 'Up next only' shows it: its name, and below it who
/// has it and how long it runs ("Worship team · 6 min 30 s", empty when
/// it has neither). Null when nothing is next: the last segment, a Quick
/// timer, or no program. A host from before 'Up next only' sends the
/// whole line, `Next: Response · Worship team · 6 min 30 s`, and no more
/// than the name otherwise; the words after the name are taken from it.
({String name, String detail})? stageUpNext(Json data) {
  final name = data['nextSegment'];
  if (name is! String || name.trim().isEmpty) return null;
  final line = data['upNext'];
  final lead = 'Next: $name';
  var detail = '';
  if (line is String && line.startsWith('$lead · ')) {
    detail = line.substring(lead.length + 3);
  }
  return (name: name, detail: detail);
}

/// How the countdown looks at this moment, by the host's own warning
/// settings: 'overtime' (past zero), 'paused', 'warning' (inside a
/// warning's time, as the operator's timer shows it) or 'normal'. An
/// older host sends no warning and so never shows 'warning'.
String stageMoment(Json data) => data['overtime'] == true
    ? 'overtime'
    : data['paused'] == true
    ? 'paused'
    : data['warning'] == true
    ? 'warning'
    : 'normal';

/// How much of the current segment has gone, from 0 to 1, for the line
/// along the bottom edge; 0 from a host that sends none, and full in
/// overtime.
double stageProgress(Json data) {
  if (data['overtime'] == true) return 1;
  final value = data['progress'];
  return value is num ? value.toDouble().clamp(0.0, 1.0) : 0.0;
}

/// How strongly overtime is shown on stage screens: Gentle keeps the
/// theme's background with red digits and a thick red frame, Strong makes
/// the whole screen red, and Strongest also pulses it slowly.
const overtimeAlerts = {
  'gentle': 'Gentle',
  'strong': 'Strong',
  'strongest': 'Strongest',
};

/// An overtime alert from saved settings or a snapshot; anything unknown
/// (or missing, as in data saved before the setting) is 'strong'.
String overtimeAlertValue(dynamic value) =>
    overtimeAlerts.containsKey(value) ? value as String : 'strong';

/// What a snapshot shows in place of the next item on the last segment, a
/// Quick timer or with no program, when the screen is set to 'Up next
/// only': the end screen set for the program or service, or the clock
/// where it has none. The host sends it as `afterEnd`, in the fields of a
/// snapshot, with nothing for a screen that is not counting down.
Json stageForLayout(Json data, String layout) {
  final after = data['afterEnd'];
  if (layout != 'only' ||
      data['displayIsTimer'] != true ||
      stageBannerPosition(data) != null ||
      after is! Map ||
      stageUpNext(data) != null) {
    return data;
  }
  return {
    ...data,
    ...Map<String, dynamic>.from(after),
    'displayIsTimer': false,
    'overtime': false,
    'paused': false,
  }..remove('afterEnd');
}
