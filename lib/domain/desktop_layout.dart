import 'package:church_service_timer/domain/domain.dart';

/// How Live is arranged in a wide window (a PC, or a large tablet held
/// sideways). Narrow windows always use the phone layout.
///
/// Every id a backup or saved look may name is listed here, so a look
/// saved by a later version still loads; [builtDesktopLayouts] are the ones
/// this version can draw.
const desktopLayoutIds = {
  'three_panes',
  'mission_control',
  'dial',
  'keys',
  'classic',
};
const builtDesktopLayouts = [
  'mission_control',
  'three_panes',
  'dial',
  'keys',
  'classic',
];
const defaultDesktopLayout = 'mission_control';

/// The narrowest window a desktop layout is used in.
const desktopLayoutMinWidth = 1200.0;
const desktopLayoutMinHeight = 600.0;

/// The layout to draw for a stored choice: itself when this version has
/// it, otherwise the default.
String effectiveDesktopLayout(String id) =>
    builtDesktopLayouts.contains(id) ? id : defaultDesktopLayout;

String desktopLayoutName(String id) => switch (id) {
  'three_panes' => 'Three panes',
  'mission_control' => 'Mission control',
  'dial' => 'The dial',
  'keys' => 'Keys',
  _ => 'Classic',
};

String desktopLayoutDescription(String id) => switch (id) {
  'three_panes' =>
    'Rundown on the left, timer in the middle, stage and cues on the right.',
  'mission_control' =>
    'Everything on one screen, with the rundown as a timeline.',
  'dial' => 'The whole service as a ring, with the countdown inside.',
  'keys' =>
    'Dense and keyboard-first: the timer in a strip, the rundown as a table.',
  _ => 'One column of cards, as on a tablet.',
};

/// The theme a layout arrives with when it is chosen; null keeps the
/// current theme.
String? desktopLayoutTheme(String id) => switch (id) {
  'three_panes' => 'midnight_lime',
  'mission_control' => 'midnight_lime',
  'dial' => 'royal_navy',
  'keys' => 'graphite',
  _ => null,
};

const keyHintChoices = {'automatic', 'on', 'off'};
const savedLookLimit = 8;

/// A layout and theme saved under a name, to return to later.
class SavedLook {
  final String name, layout, themeId, density, keyHints;
  final bool highContrast;
  const SavedLook({
    required this.name,
    required this.layout,
    required this.themeId,
    this.density = 'automatic',
    this.keyHints = 'automatic',
    this.highContrast = false,
  });
  factory SavedLook.fromJson(Json j) {
    keys(j, {
      'name',
      'layout',
      'themeId',
      'density',
      'keyHints',
      'highContrast',
    }, 'Saved look');
    final look = SavedLook(
      name: savedLookName(j['name']),
      layout: j['layout'] is String ? j['layout'] as String : '',
      themeId: themeIdValue(j['themeId']),
      density: j['density'] is String ? j['density'] as String : '',
      keyHints: j['keyHints'] is String ? j['keyHints'] as String : '',
      highContrast: j['highContrast'] == true,
    );
    require(
      desktopLayoutIds.contains(look.layout) &&
          const {
            'compact',
            'comfortable',
            'spacious',
            'automatic',
          }.contains(look.density) &&
          keyHintChoices.contains(look.keyHints) &&
          j['highContrast'] is bool,
      'Invalid saved look.',
    );
    return look;
  }
  Json toJson() => {
    'name': name,
    'layout': layout,
    'themeId': themeId,
    'density': density,
    'keyHints': keyHints,
    'highContrast': highContrast,
  };

  /// The look that [appearance] and [themeId] make now.
  factory SavedLook.of(
    String name,
    AppearancePreferences appearance,
    String themeId,
  ) => SavedLook(
    name: name,
    layout: appearance.desktopLayout,
    themeId: themeId,
    density: appearance.density,
    keyHints: appearance.keyHints,
    highContrast: appearance.highContrast,
  );

  /// [appearance] with this look applied; the settings a look does not
  /// cover (dividers, motion, picker feedback) are kept.
  AppearancePreferences applyTo(AppearancePreferences appearance) =>
      appearance.copyWith(
        desktopLayout: layout,
        density: density,
        keyHints: keyHints,
        highContrast: highContrast,
      );
}

/// The look a reset returns to.
const defaultLook = SavedLook(
  name: 'Default',
  layout: defaultDesktopLayout,
  themeId: 'midnight_lime',
);

String savedLookName(dynamic value) {
  require(value is String, 'A saved look needs a name.');
  final name = (value as String).trim();
  require(
    name.isNotEmpty &&
        name.runes.length <= 40 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name),
    'Name the look in one line, up to 40 characters.',
  );
  return name;
}

List<SavedLook> readSavedLooks(dynamic value) {
  if (value == null) return [];
  require(
    value is List && value.length <= savedLookLimit,
    'Invalid saved looks.',
  );
  final looks = [
    for (final e in value as List)
      SavedLook.fromJson(Map<String, dynamic>.from(e as Map)),
  ];
  require(
    looks.map((l) => l.name.toLowerCase()).toSet().length == looks.length,
    'Two saved looks have the same name.',
  );
  return looks;
}
