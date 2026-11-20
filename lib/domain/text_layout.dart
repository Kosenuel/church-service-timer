/// Styled text for the sign and screens, and a program's display settings.
library;

import 'package:church_service_timer/domain/domain.dart';

/// The fastest a cue may scroll on screens: twice the LED sign's fastest.
const maxScreenSpeed = 48;

/// The colours a cue may have on screens. 'accent' is the host's theme
/// colour; the others are fixed (see [screenCueColors]).
const screenColorNames = {'white', 'amber', 'red', 'green', 'accent'};

/// Where a cue may show on screens.
const screenPositions = {'full', 'top', 'bottom'};

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
    require(
      {'static', 'scroll', 'flash'}.contains(effect),
      'Unsupported text effect.',
    );
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

const defaultEndScreen = TextLayout(
  'Hallelujah',
  bold: true,
  italic: true,
  height: 2,
);

class DisplaySettings {
  final TextLayout? zero;
  final TextLayout end;
  final List<TextLayout> cues;
  final List<WarningRule> warnings;
  DisplaySettings({
    this.zero,
    this.end = defaultEndScreen,
    List<TextLayout>? cues,
    List<WarningRule>? warnings,
  }) : warnings = List.unmodifiable(warnings ?? defaultWarnings),
       cues = List.unmodifiable(
         cues ??
             const [
               TextLayout('WRAP UP'),
               TextLayout("TIME'S UP"),
               TextLayout('MIC LOW'),
             ],
       );
  factory DisplaySettings.fromJson(Json j) {
    keys(j, {'zero', 'end', 'cues', 'warnings'}, 'Display settings');
    require(
      j.containsKey('zero') && j['end'] is Map && j['cues'] is List,
      'Display settings are incomplete.',
    );
    final c = (j['cues'] as List)
        .map((e) => TextLayout.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    require(c.length <= 6, 'Configure at most 6 program cues.');
    return DisplaySettings(
      zero: j['zero'] == null
          ? null
          : TextLayout.fromJson(Map<String, dynamic>.from(j['zero'])),
      end: TextLayout.fromJson(Map<String, dynamic>.from(j['end'])),
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
  DisplaySettings withEnd(TextLayout value) =>
      DisplaySettings(zero: zero, end: value, cues: cues, warnings: warnings);
  Json toJson() => {
    'zero': zero?.toJson(),
    'end': end.toJson(),
    'cues': cues.map((e) => e.toJson()).toList(),
    'warnings': warnings.map((e) => e.toJson()).toList(),
  };
}
