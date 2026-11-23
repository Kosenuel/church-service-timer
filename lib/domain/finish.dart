/// The finish: the material of the app's background and panels. The theme
/// chooses the colours; the finish chooses what they are made of.
///
/// Every id a backup or saved look may name is listed here, so a look saved
/// by a later version still loads; one this version does not know draws as
/// [defaultFinish]. They are listed, and shown, in this order: Flat, the
/// cloths (Leather with them, a hide that is stitched like Denim), Glass,
/// the woods, Plastic, the metals, Marble and then the rest.
const finishIds = [
  'flat',
  'cashmere',
  'denim',
  'leather',
  'glass',
  'walnut',
  'oak',
  'plastic',
  'console',
  'carbon',
  'marble',
  'brick',
];
const defaultFinish = 'flat';

/// How much of the material shows: Subtle is half, for long services.
const finishStrengths = ['subtle', 'full'];

/// The strength a finish has until one is chosen: Full, except the dark,
/// busy grains (Walnut, Oak and Carbon fibre), which read best at Subtle.
const subtleByDefault = {'walnut', 'oak', 'carbon'};
String defaultFinishStrength(String finish) =>
    subtleByDefault.contains(finish) ? 'subtle' : 'full';

/// The strength drawn for [finish] when [chosen] is the one chosen (null when
/// none has been): the choice, else the finish's own default.
String finishStrengthFor(String finish, String? chosen) =>
    chosen ?? defaultFinishStrength(finish);

/// The themes that carry their own finish, Papery, whatever finish is saved.
/// Papery is not in [finishIds]: it is never chosen, never saved and never
/// shown among the tiles; it comes with these themes and with nothing else
/// (a custom theme is not one of them, even with the same colours).
const paperyThemeIds = {'paper_ink', 'paper_ink_blue'};
const paperyFinish = 'papery';

/// The finish drawn with [themeId] when [saved] is the chosen one: Papery
/// for a Paper & Ink theme, else [saved]. The saved choice is not touched,
/// so going back to another theme restores it.
String effectiveFinish(String themeId, String saved) =>
    paperyThemeIds.contains(themeId) ? paperyFinish : saved;

String finishName(String id) => switch (id) {
  'papery' => 'Papery',
  'glass' => 'Glass',
  'console' => 'Bridge console',
  'brick' => 'Brick',
  'cashmere' => 'Cashmere',
  'denim' => 'Denim',
  'plastic' => 'Plastic',
  'walnut' => 'Walnut',
  'oak' => 'Oak',
  'leather' => 'Leather',
  'marble' => 'Marble',
  'carbon' => 'Carbon fibre',
  _ => 'Flat',
};

String finishDescription(String id) => switch (id) {
  'papery' => 'Fine paper, with panels as loose sheets',
  'glass' => 'Frosted panes over a soft glow',
  'console' => 'Brushed steel plates, bolted down',
  'brick' => 'Signboards on a brick wall',
  'cashmere' => 'Soft knit, no hard edges',
  'denim' => 'Twill weave with stitched seams',
  'plastic' => 'Glossy moulded shells',
  'walnut' => 'Panels set into a dark wooden desk',
  'oak' => 'Panels on a pale, open-grained desk',
  'leather' => 'Stitched hide, like a good notebook',
  'marble' => 'Polished stone with fine veins',
  'carbon' => 'A fine woven black weave with a sheen',
  _ => 'Plain panels, as now',
};

/// A stored id this version can draw, else Flat.
String finishValue(dynamic value) =>
    value is String && finishIds.contains(value) ? value : defaultFinish;

/// A stored strength this version knows, else null: none chosen, so the
/// finish's own default.
String? finishStrengthValue(dynamic value) =>
    value is String && finishStrengths.contains(value) ? value : null;
