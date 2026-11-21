/// Styled text for the sign and screens, and a program's display settings.
library;

import 'dart:math' as math;
import 'package:church_service_timer/domain/domain.dart';

/// The fastest a cue may scroll on screens: twice the LED sign's fastest.
const maxScreenSpeed = 48;

/// The colours a cue may have on screens. 'accent' is the host's theme
/// colour; the others are fixed (see [screenCueColors]).
const screenColorNames = {'white', 'amber', 'red', 'green', 'accent'};

/// Where a cue may show on screens.
const screenPositions = {'full', 'top', 'bottom'};

/// The effects every version of the app knows, and plays on the LED sign.
const classicEffects = {'static', 'scroll', 'flash'};

/// The newer effects. Each is drawn on screens; on the LED sign only
/// 'flashHold' moves (the sign cannot dim, slide or colour) and the rest
/// show steady, except text too wide for the sign: 'pulse' shows it a few
/// words at a time (see [wordGroupEffects]) and the rest of them scroll it
/// (see [signScrollEffects]). Stage snapshots carry them beside a classic
/// effect, so an older paired screen shows the cue steady (see
/// [TextLayout.screenEffect]).
const screenEffects = {'pulse', 'flashHold', 'slideIn', 'bar', 'screenFlash'};

/// The effects only screens show, which the LED sign shows steady when the
/// text fits it and scrolls across it, at the cue's speed on the sign, when
/// it is too wide. Screens play the effect either way.
const signScrollEffects = {'slideIn', 'bar', 'screenFlash'};

/// Every effect a cue may have.
const textEffects = {...classicEffects, ...screenEffects};

/// Short names for an effect, as summaries write them.
const effectNames = {
  'static': 'static',
  'scroll': 'scroll',
  'flash': 'flash',
  'pulse': 'pulse',
  'flashHold': 'flash then hold',
  'slideIn': 'slide in',
  'bar': 'countdown bar',
  'screenFlash': 'screen flash',
};

/// How long 'flashHold' flashes before it holds steady: three flashes at
/// the rhythm of 'flash', half a second on and half a second off.
const flashHoldMs = 3000;

/// On the LED sign a 'flashHold' cue is a loop the controller plays by
/// itself, so its three flashes come again once each cycle this long.
const flashHoldCycleMs = 300000;

/// The effects that show text too wide for the LED sign a few words at a
/// time: the text is split into the largest groups of whole words that fit
/// the sign (see [groupWords]), shown one after another, over and over.
const wordGroupEffects = {'flash', 'pulse'};

/// The most characters shown a few words at a time; longer text scrolls.
const wordGroupMaxLength = 60;

/// How long each group of words takes: Flash shows it twice at its
/// half-second rhythm (a second in view in all), Pulse fades it in and out.
const wordGroupMs = 2000;

/// After the last group Flash leaves a pause this long, in place of its
/// usual half second off, so the start of the message stands out.
const wordGroupPauseMs = 800;

/// The LED sign's frames for a few words at a time, and the step screens
/// and the simulator keep to so that they match it.
const wordGroupFrameMs = 100;

/// One round of [count] groups of words for [effect], in milliseconds.
int wordGroupCycleMs(String effect, int count) =>
    count * wordGroupMs + (effect == 'flash' ? wordGroupPauseMs - 500 : 0);

/// Which of [count] groups of words [effect] shows [elapsedMs] after the
/// cue appears, and how brightly, from 0 (blank) to 1. Flash is on for
/// half a second, off for half a second, on and off again, then the next
/// group; after the last group it stays off for [wordGroupPauseMs]. Pulse
/// fades each group in and out over [wordGroupMs].
({int index, double opacity}) wordGroupAt(
  String effect,
  int count,
  int elapsedMs,
) {
  final cycle = wordGroupCycleMs(effect, count);
  final t = ((elapsedMs % cycle) + cycle) % cycle;
  final index = math.min(t ~/ wordGroupMs, count - 1);
  final within = t - index * wordGroupMs;
  if (effect == 'flash') {
    final on = within < 500 || (within >= 1000 && within < 1500);
    return (index: index, opacity: on ? 1.0 : 0.0);
  }
  final s = math.sin(math.pi * within / wordGroupMs);
  return (index: index, opacity: s * s);
}

/// Pulse on the LED sign, which cannot dim: a group is lit while a screen
/// shows it at least this bright, about 1.3 seconds of its two.
const wordGroupSignPulseLevel = .25;

/// [text] split into the largest groups of consecutive whole words, in
/// order, that each [fits]; null when a word does not fit on its own.
/// "PLEASE WRAP UP NOW" may become "PLEASE", "WRAP UP", "NOW".
List<String>? groupWords(String text, bool Function(String text) fits) {
  final words = text.trim().split(RegExp(r'\s+'));
  final groups = <String>[];
  for (var i = 0; i < words.length;) {
    if (!fits(words[i])) return null;
    var group = words[i++];
    while (i < words.length && fits('$group ${words[i]}')) {
      group = '$group ${words[i++]}';
    }
    groups.add(group);
  }
  return groups;
}

class TextLayout {
  final String text, effect, align, font;
  final bool bold, italic;
  final int speed, height;

  /// Scrolling speed on stage, web and second screens, on the sign's scale
  /// but up to twice as fast; null follows the LED sign's [speed].
  final int? screenSpeed;
  int get speedOnScreens => screenSpeed ?? speed;

  /// The cue's colour on screens: one of [screenColorNames]. White, as
  /// every cue was, until it is chosen.
  final String screenColor;

  /// Where the cue shows on screens: 'full' in place of the countdown, as
  /// every cue did, or a band at the 'top' or 'bottom' with the countdown
  /// still in view.
  final String screenPosition;
  bool get bannerOnScreens => screenPosition != 'full';

  /// Whether stage, web and second screens wrap the text onto up to three
  /// lines (two in a banner) instead of scrolling it or shrinking it onto
  /// one. The LED sign is not changed. Off, as every cue was, until chosen.
  final bool screenWrap;

  /// The effect as every version of the app knows it: the newer effects
  /// are steady text to an older paired screen.
  String get compatibleEffect =>
      classicEffects.contains(effect) ? effect : 'static';

  /// One of [screenEffects], or null for a classic effect.
  String? get screenEffect => screenEffects.contains(effect) ? effect : null;

  /// Whether the LED sign shows the cue without moving when it fits: the
  /// newer effects it cannot draw, as well as static text. Text too wide
  /// for the sign moves all the same: Pulse a few words at a time, and
  /// slide in, countdown bar and screen flash scroll across it.
  bool get steadyOnSign =>
      effect == 'static' || (effect != 'flashHold' && screenEffect != null);
  const TextLayout(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.effect = 'scroll',
    this.align = 'center',
    this.speed = 12,
    this.screenSpeed,
    this.screenColor = 'white',
    this.screenPosition = 'full',
    this.screenWrap = false,
    this.height = 1,
    this.font = 'i-proton_matrix',
  });
  factory TextLayout.fromJson(Json j) {
    keys(j, {
      'text',
      'bold',
      'italic',
      'effect',
      'align',
      'speed',
      'screenSpeed',
      'screenColor',
      'screenPosition',
      'screenWrap',
      'height',
      'font',
    }, 'Text layout');
    require(
      j['text'] is String &&
          j['bold'] is bool &&
          j['italic'] is bool &&
          j['speed'] is int &&
          (j['screenSpeed'] == null || j['screenSpeed'] is int) &&
          (j['screenColor'] == null || j['screenColor'] is String) &&
          (j['screenPosition'] == null || j['screenPosition'] is String) &&
          (j['screenWrap'] == null || j['screenWrap'] is bool) &&
          j['height'] is int,
      'Text layout has missing or invalid fields.',
    );
    final s = TextLayout(
      j['text'],
      bold: j['bold'],
      italic: j['italic'],
      effect: j['effect'],
      align: j['align'],
      speed: j['speed'],
      screenSpeed: j['screenSpeed'],
      screenColor: j['screenColor'] ?? 'white',
      screenPosition: j['screenPosition'] ?? 'full',
      screenWrap: j['screenWrap'] ?? false,
      height: j['height'],
      // Font ids from earlier versions still open (see legacyFontIds).
      font: legacyFontIds[j['font']] ?? j['font'] ?? 'i-proton_matrix',
    );
    s.validate();
    return s;
  }
  void validate() {
    require(displayFontNames.containsKey(font), 'Unknown display font: $font.');
    require(
      text.trim().isNotEmpty && text.runes.length <= 160,
      'Display text must contain 1–160 characters.',
    );
    require(textEffects.contains(effect), 'Unsupported text effect.');
    require(
      {'left', 'center', 'right'}.contains(align),
      'Unsupported alignment.',
    );
    require(
      speed >= 4 && speed <= 24 && (height == 1 || height == 2),
      'Invalid text size or scrolling speed.',
    );
    require(
      screenSpeed == null ||
          (screenSpeed! >= 4 && screenSpeed! <= maxScreenSpeed),
      'Invalid scrolling speed on screens.',
    );
    require(
      screenColorNames.contains(screenColor),
      'Unsupported colour on screens.',
    );
    require(
      screenPositions.contains(screenPosition),
      'Unsupported position on screens.',
    );
  }

  Json toJson() => {
    'text': text,
    'bold': bold,
    'italic': italic,
    'effect': effect,
    'align': align,
    'speed': speed,
    // Left out until it is set, so files without it stay as they were.
    'screenSpeed': ?screenSpeed,
    if (screenColor != 'white') 'screenColor': screenColor,
    if (screenPosition != 'full') 'screenPosition': screenPosition,
    if (screenWrap) 'screenWrap': true,
    'height': height,
    'font': font,
  };
}

/// How summaries describe a program with no end screen.
const noEndScreenLine = 'No end screen · shows the clock';

const defaultEndScreen = TextLayout(
  'Hallelujah',
  bold: true,
  italic: true,
  height: 2,
);

/// The stage cues a new install starts with, in the order of keys 1–7,
/// in the tall 14-pixel letters that read best from a distance.
///
/// None of them fits the LED sign's 32 columns in bold (the shortest,
/// SEE ME, is 39). So WRAP UP pulses and TIME'S UP flashes a word at a
/// time on the sign. TIME'S UP is at least 41 columns in every built-in
/// pixel font, so it cannot flash then hold, and it is in regular weight
/// so that TIME'S (29 columns) fits on its own. SEE ME slides in on
/// screens and scrolls on the sign, and the rest scroll on the sign. On
/// screens they wrap, which holds short text still and as large as it
/// fits; the colour and position say how urgent it is.
const defaultStageCues = [
  TextLayout(
    'WRAP UP',
    bold: true,
    height: 2,
    effect: 'pulse',
    screenColor: 'amber',
    screenPosition: 'bottom',
    screenWrap: true,
  ),
  // Regular weight: in bold, TIME'S alone is 35 columns, too wide.
  TextLayout(
    "TIME'S UP",
    height: 2,
    effect: 'flash',
    speed: 14,
    screenColor: 'red',
    screenWrap: true,
  ),
  TextLayout(
    'SPEAK UP',
    bold: true,
    height: 2,
    screenPosition: 'top',
    screenWrap: true,
  ),
  TextLayout(
    'SLOW DOWN',
    bold: true,
    height: 2,
    speed: 10,
    screenPosition: 'top',
    screenWrap: true,
  ),
  TextLayout(
    'MIC OFF?',
    bold: true,
    height: 2,
    screenColor: 'amber',
    screenPosition: 'top',
    screenWrap: true,
  ),
  TextLayout(
    'FINAL SONG',
    bold: true,
    height: 2,
    screenColor: 'green',
    screenPosition: 'bottom',
    screenWrap: true,
  ),
  TextLayout(
    'SEE ME',
    bold: true,
    height: 2,
    effect: 'slideIn',
    screenColor: 'accent',
    screenWrap: true,
  ),
];

/// The stage cues version 15 started with, before the effects only
/// screens show could scroll on the sign: each scrolled there. Saved state
/// with them as they were is upgraded to [defaultStageCues].
const version15DefaultStageCues = [
  TextLayout(
    'WRAP UP',
    bold: true,
    height: 2,
    screenColor: 'amber',
    screenPosition: 'bottom',
    screenWrap: true,
  ),
  TextLayout(
    "TIME'S UP",
    bold: true,
    height: 2,
    speed: 14,
    screenColor: 'red',
    screenWrap: true,
  ),
  TextLayout(
    'SPEAK UP',
    bold: true,
    height: 2,
    screenPosition: 'top',
    screenWrap: true,
  ),
  TextLayout(
    'SLOW DOWN',
    bold: true,
    height: 2,
    speed: 10,
    screenPosition: 'top',
    screenWrap: true,
  ),
  TextLayout(
    'MIC OFF?',
    bold: true,
    height: 2,
    screenColor: 'amber',
    screenPosition: 'top',
    screenWrap: true,
  ),
  TextLayout(
    'FINAL SONG',
    bold: true,
    height: 2,
    screenColor: 'green',
    screenPosition: 'bottom',
    screenWrap: true,
  ),
  TextLayout(
    'SEE ME',
    bold: true,
    height: 2,
    screenColor: 'accent',
    screenWrap: true,
  ),
];

/// The stage cues installs started with before [defaultStageCues], which
/// saved state from then is upgraded from.
const legacyDefaultStageCues = [
  TextLayout('WRAP UP'),
  TextLayout("TIME'S UP"),
  TextLayout('MIC LOW'),
];

class DisplaySettings {
  final TextLayout? zero;

  /// What stage outputs show when the service ends, or null for no end
  /// screen: they show the clock instead. Saved as `"end": null`, which
  /// versions before this one refuse, as they need an end screen.
  final TextLayout? end;
  final List<TextLayout> cues;
  final List<WarningRule> warnings;
  DisplaySettings({
    this.zero,
    this.end = defaultEndScreen,
    List<TextLayout>? cues,
    List<WarningRule>? warnings,
  }) : warnings = List.unmodifiable(warnings ?? defaultWarnings),
       cues = List.unmodifiable(cues ?? defaultStageCues);
  factory DisplaySettings.fromJson(Json j) {
    keys(j, {'zero', 'end', 'cues', 'warnings'}, 'Display settings');
    require(
      j.containsKey('zero') &&
          j.containsKey('end') &&
          (j['end'] == null || j['end'] is Map) &&
          j['cues'] is List,
      'Display settings are incomplete.',
    );
    final c = (j['cues'] as List)
        .map((e) => TextLayout.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    require(c.length <= 9, 'Configure at most 9 program cues.');
    return DisplaySettings(
      zero: j['zero'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['zero'])),
      end: j['end'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['end'])),
      cues: c,
      warnings: readWarnings(j['warnings']),
    );
  }
  DisplaySettings withCues(List<TextLayout> value) =>
      DisplaySettings(zero: zero, end: end, cues: value, warnings: warnings);
  DisplaySettings withWarnings(List<WarningRule> value) =>
      DisplaySettings(zero: zero, end: end, cues: cues, warnings: value);
  DisplaySettings withZero(TextLayout? value) =>
      DisplaySettings(zero: value, end: end, cues: cues, warnings: warnings);
  DisplaySettings withEnd(TextLayout? value) =>
      DisplaySettings(zero: zero, end: value, cues: cues, warnings: warnings);
  Json toJson() => {
    'zero': zero?.toJson(),
    'end': end?.toJson(),
    'cues': cues.map((e) => e.toJson()).toList(),
    'warnings': warnings.map((e) => e.toJson()).toList(),
  };
}
