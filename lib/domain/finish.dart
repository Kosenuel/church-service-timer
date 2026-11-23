/// The finish: the material of the app's background and panels. The theme
/// chooses the colours; the finish chooses what they are made of.
///
/// Every id a backup or saved look may name is listed here, so a look saved
/// by a later version still loads; one this version does not know draws as
/// [defaultFinish].
const finishIds = [
  'flat',
  'glass',
  'console',
  'brick',
  'cashmere',
  'denim',
  'plastic',
  'walnut',
  'oak',
  'leather',
  'marble',
  'carbon',
];
const defaultFinish = 'flat';

/// How much of the material shows: Subtle is half, for long services.
const finishStrengths = ['subtle', 'full'];
const defaultFinishStrength = 'subtle';

String finishName(String id) => switch (id) {
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

/// A stored strength this version knows, else Subtle.
String finishStrengthValue(dynamic value) =>
    value is String && finishStrengths.contains(value)
    ? value
    : defaultFinishStrength;
