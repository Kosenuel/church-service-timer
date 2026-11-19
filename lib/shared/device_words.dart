/// Whether the app is running on a computer rather than a phone or tablet.
/// Set once at start-up; screens use [deviceText] so their wording fits.
bool desktopWording = false;

const _replacements = [
  ('Android Wi-Fi settings', 'Windows Wi-Fi settings'),
  ('in Android settings', 'in Windows settings'),
  ('in Android', 'in Windows'),
  ('Android', 'Windows'),
  ('this phone', 'this computer'),
  ('This phone', 'This computer'),
  ('the phone clock', 'the computer’s clock'),
  ('The phone and', 'This computer and'),
  ('on the phone', 'on the computer'),
  ('your phone’s', 'your computer’s'),
  ('Timing and phone warnings', 'Timing and warnings'),
  // A computer is clicked, not tapped.
  ('press and hold', 'click and hold'),
  ('Press and hold', 'Click and hold'),
  ('a second tap', 'a second click'),
  ('Tap', 'Click'),
  (', then tap ', ', then click '),
  (' tap ', ' click '),
  (' tap.', ' click.'),
  ('tap to ', 'click to '),
];

/// [text] as written for a phone, reworded for a computer when the app is
/// running on one. Text about other people's phones is not passed through
/// here.
String deviceText(String text) {
  if (!desktopWording) return text;
  for (final (from, to) in _replacements) {
    text = text.replaceAll(from, to);
  }
  return text;
}
