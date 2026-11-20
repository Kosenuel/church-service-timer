import 'package:flutter/services.dart';

/// One way of pressing a shortcut: a key, and whether Ctrl is held.
class KeyPress {
  final LogicalKeyboardKey key;

  /// Whether Ctrl must be held (true), must not be (false), or makes no
  /// difference (null): a clicker's keys work either way.
  final bool? control;

  /// Whether Shift must be held. False means Shift makes no difference.
  final bool shift;
  const KeyPress(this.key, {this.control = false, this.shift = false});

  bool matches(
    LogicalKeyboardKey pressed, {
    required bool control,
    required bool shift,
  }) =>
      pressed == key &&
      (this.control == null || this.control == control) &&
      (!this.shift || shift);
}

/// The headings of the shortcuts sheet, and when the keys under each
/// one work.
enum ShortcutGroup {
  service(
    'During a service',
    'On Live while a service is running, with no question or other page on top.',
  ),
  stage(
    'Stage',
    'On Live while a service is running and a display is connected.',
  ),
  moving(
    'Moving around',
    'On any tab, while nothing is being typed into a field.',
  );

  final String title, when;
  const ShortcutGroup(this.title, this.when);
}

/// A key the app answers to: what to press, what it does, when it works
/// and how it asks before changing anything. The shortcuts sheet, the
/// key shown beside each command, the clicker test page and
/// `docs/WINDOWS.md` all follow this list, and a test holds it to what
/// `HomeState.onClickerKey` really does.
class Shortcut {
  /// Stable name; the command palette uses the same one for its command.
  final String id;
  final ShortcutGroup group;

  /// The keys as drawn on the sheet. Each inner list is one way to press
  /// it, its keys held together: `[['Ctrl', 'Z']]`, `[['Space'], ['B']]`.
  final List<List<String>> caps;

  /// A word between the ways to press it: "or", or "to" for 1 to 9.
  final String joiner;

  /// The short form shown beside a button or a command.
  final String hint;

  /// What it does, as a name: "Next segment".
  final String action;

  /// How it asks before anything changes, in a few words, or how soon it
  /// happens when it does not ask.
  final String confirm;

  /// On a phone or tablet, when that differs: a clicker there has no
  /// screen in the hand to confirm on.
  final String? phoneConfirm;

  /// When it applies, where that is narrower than its group's.
  final String? condition;

  /// Whether it changes the running timer.
  final bool timerAction;

  /// Whether a clicker or pedal on a phone or tablet can do it too. The
  /// rest need a computer.
  final bool clicker;

  /// Answered by the question or window on screen, not by Live.
  final bool inDialogs;

  /// Every press that does it.
  final List<KeyPress> presses;
  const Shortcut({
    required this.id,
    required this.group,
    required this.caps,
    required this.hint,
    required this.action,
    required this.confirm,
    required this.presses,
    this.joiner = 'or',
    this.phoneConfirm,
    this.condition,
    this.timerAction = false,
    this.clicker = false,
    this.inDialogs = false,
  });

  String get when => condition ?? group.when;

  /// One line for the clicker test page: "Next segment: press twice to
  /// confirm".
  String explanation({required bool desktop}) =>
      '$action: ${desktop ? confirm : phoneConfirm ?? confirm}';
}

const _k = LogicalKeyboardKey.new;

/// Every keyboard shortcut, in the order the sheet lists them.
final List<Shortcut> shortcuts = List.unmodifiable([
  Shortcut(
    id: 'pause',
    group: ShortcutGroup.service,
    caps: const [
      ['Space'],
      ['B'],
    ],
    hint: 'Space',
    action: 'Pause or resume',
    confirm: 'asks first',
    phoneConfirm: 'at once, without asking',
    timerAction: true,
    clicker: true,
    presses: [
      KeyPress(LogicalKeyboardKey.space, control: null),
      KeyPress(LogicalKeyboardKey.keyB, control: null),
    ],
  ),
  Shortcut(
    id: 'next',
    group: ShortcutGroup.service,
    caps: const [
      ['Page Down'],
      ['→'],
    ],
    hint: 'PgDn',
    action: 'Next segment',
    confirm: 'press twice to confirm',
    timerAction: true,
    clicker: true,
    presses: [
      KeyPress(LogicalKeyboardKey.pageDown, control: null),
      KeyPress(LogicalKeyboardKey.arrowRight, control: null),
    ],
  ),
  Shortcut(
    id: 'adjust',
    group: ShortcutGroup.service,
    caps: const [
      ['+'],
      ['−'],
    ],
    hint: '+ −',
    action: 'Adjust time',
    confirm: 'you choose, then confirm',
    timerAction: true,
    presses: [
      KeyPress(LogicalKeyboardKey.add),
      // The + key without Shift.
      KeyPress(LogicalKeyboardKey.equal),
      KeyPress(LogicalKeyboardKey.minus),
      KeyPress(LogicalKeyboardKey.numpadAdd),
      KeyPress(LogicalKeyboardKey.numpadSubtract),
    ],
  ),
  Shortcut(
    id: 'undo',
    group: ShortcutGroup.service,
    caps: const [
      ['Ctrl', 'Z'],
    ],
    hint: 'Ctrl Z',
    action: 'Undo the last segment change',
    confirm: 'asks first',
    condition: 'On Live, after Next or a jump, until the next change.',
    timerAction: true,
    presses: [KeyPress(LogicalKeyboardKey.keyZ, control: true)],
  ),
  Shortcut(
    id: 'jump',
    group: ShortcutGroup.service,
    caps: const [
      ['J'],
    ],
    hint: 'J',
    action: 'Jump to a later segment',
    confirm: 'you choose, then confirm',
    condition: 'On Live while a later segment is still to come.',
    timerAction: true,
    presses: [KeyPress(LogicalKeyboardKey.keyJ)],
  ),
  Shortcut(
    id: 'recover',
    group: ShortcutGroup.service,
    caps: const [
      ['R'],
    ],
    hint: 'R',
    action: 'Recover time',
    confirm: 'you choose, then confirm',
    timerAction: true,
    presses: [KeyPress(LogicalKeyboardKey.keyR)],
  ),
  Shortcut(
    id: 'edit-upcoming',
    group: ShortcutGroup.service,
    caps: const [
      ['E'],
    ],
    hint: 'E',
    action: 'Edit upcoming',
    confirm: 'you edit, then save',
    timerAction: true,
    presses: [KeyPress(LogicalKeyboardKey.keyE)],
  ),
  Shortcut(
    id: 'lock',
    group: ShortcutGroup.service,
    caps: const [
      ['Ctrl', 'L'],
    ],
    hint: 'Ctrl L',
    action: 'Lock controls',
    confirm: 'at once; hold to unlock',
    presses: [KeyPress(LogicalKeyboardKey.keyL, control: true)],
  ),
  Shortcut(
    id: 'cue',
    group: ShortcutGroup.stage,
    caps: const [
      ['1'],
      ['9'],
    ],
    joiner: 'to',
    hint: '1–9',
    action: 'Show a prepared cue',
    confirm: 'at once; again to go back to the timer',
    presses: [
      for (var i = 0; i < 9; i++) ...[
        KeyPress(_k(LogicalKeyboardKey.digit1.keyId + i)),
        KeyPress(_k(LogicalKeyboardKey.numpad1.keyId + i)),
      ],
    ],
  ),
  Shortcut(
    id: 'message',
    group: ShortcutGroup.stage,
    caps: const [
      ['M'],
    ],
    hint: 'M',
    action: 'Send message',
    confirm: 'you type, then send',
    presses: [KeyPress(LogicalKeyboardKey.keyM)],
  ),
  Shortcut(
    id: 'commands',
    group: ShortcutGroup.moving,
    caps: const [
      ['Ctrl', 'K'],
    ],
    hint: 'Ctrl K',
    action: 'Commands',
    confirm: 'a list of everything you can do now',
    presses: [KeyPress(LogicalKeyboardKey.keyK, control: true)],
  ),
  Shortcut(
    id: 'mini',
    group: ShortcutGroup.moving,
    caps: const [
      ['Ctrl', 'M'],
    ],
    hint: 'Ctrl M',
    action: 'Mini timer',
    confirm: 'a small window on top; again to leave it',
    presses: [KeyPress(LogicalKeyboardKey.keyM, control: true)],
  ),
  Shortcut(
    id: 'fullscreen',
    group: ShortcutGroup.moving,
    caps: const [
      ['F11'],
    ],
    hint: 'F11',
    action: 'Full screen',
    confirm: 'the stage on this screen; again or Esc to leave it',
    condition: 'While a service is running.',
    presses: [KeyPress(LogicalKeyboardKey.f11, control: null)],
  ),
  Shortcut(
    id: 'shortcuts',
    group: ShortcutGroup.moving,
    caps: const [
      ['?'],
      ['F1'],
    ],
    hint: '?',
    action: 'Keyboard shortcuts',
    confirm: 'this list',
    presses: [
      KeyPress(LogicalKeyboardKey.question, control: null),
      KeyPress(LogicalKeyboardKey.slash, control: null, shift: true),
      KeyPress(LogicalKeyboardKey.f1, control: null),
    ],
  ),
  Shortcut(
    id: 'confirm',
    group: ShortcutGroup.moving,
    caps: const [
      ['Enter'],
      ['Space'],
    ],
    hint: 'Enter',
    action: 'Confirm the question on screen',
    confirm: 'not End service, which must be clicked',
    condition: 'While a question is on screen.',
    inDialogs: true,
    presses: [
      KeyPress(LogicalKeyboardKey.enter, control: null),
      KeyPress(LogicalKeyboardKey.numpadEnter, control: null),
    ],
  ),
  Shortcut(
    id: 'cancel',
    group: ShortcutGroup.moving,
    caps: const [
      ['Esc'],
    ],
    hint: 'Esc',
    action: 'Cancel or close',
    confirm: 'nothing is changed',
    condition: 'While a question, a list or this sheet is on screen.',
    inDialogs: true,
    presses: [KeyPress(LogicalKeyboardKey.escape, control: null)],
  ),
]);

/// The two rules that hold for every key.
const shortcutsConfirmRule =
    'Every timer action asks you to confirm before anything changes.';
const shortcutsLockRule =
    'Lock controls blocks every key until you hold to unlock.';

/// The shortcut with this [id]. Throws for a name that is not listed.
Shortcut shortcut(String id) => shortcuts.firstWhere((s) => s.id == id);

/// The key shown beside the button or command that [id] presses.
String shortcutHint(String id) => shortcut(id).hint;

/// The shortcut this press belongs to, or null when the app does not use
/// the key.
Shortcut? shortcutFor(
  LogicalKeyboardKey key, {
  required bool control,
  bool shift = false,
}) {
  for (final s in shortcuts) {
    if (s.presses.any((p) => p.matches(key, control: control, shift: shift))) {
      return s;
    }
  }
  return null;
}

/// Keys that only change what another key means.
bool isModifierKey(LogicalKeyboardKey key) => _modifiers.contains(key);

final _modifiers = {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.altGraph,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
};

final _names = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.pageDown: 'Page Down',
  LogicalKeyboardKey.pageUp: 'Page Up',
  LogicalKeyboardKey.arrowRight: 'Right arrow',
  LogicalKeyboardKey.arrowLeft: 'Left arrow',
  LogicalKeyboardKey.arrowUp: 'Up arrow',
  LogicalKeyboardKey.arrowDown: 'Down arrow',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.numpadEnter: 'Enter',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.insert: 'Insert',
  LogicalKeyboardKey.period: 'Full stop',
  LogicalKeyboardKey.comma: 'Comma',
  LogicalKeyboardKey.slash: 'Slash',
  LogicalKeyboardKey.question: 'Question mark',
  LogicalKeyboardKey.add: 'Plus',
  LogicalKeyboardKey.numpadAdd: 'Plus',
  LogicalKeyboardKey.equal: 'Equals',
  LogicalKeyboardKey.minus: 'Minus',
  LogicalKeyboardKey.numpadSubtract: 'Minus',
  LogicalKeyboardKey.mediaPlayPause: 'Play or pause',
  LogicalKeyboardKey.mediaPlay: 'Play',
  LogicalKeyboardKey.mediaPause: 'Pause',
  LogicalKeyboardKey.mediaStop: 'Stop',
  LogicalKeyboardKey.mediaTrackNext: 'Next track',
  LogicalKeyboardKey.mediaTrackPrevious: 'Previous track',
  LogicalKeyboardKey.audioVolumeUp: 'Volume up',
  LogicalKeyboardKey.audioVolumeDown: 'Volume down',
  LogicalKeyboardKey.audioVolumeMute: 'Mute',
  LogicalKeyboardKey.goBack: 'Back',
  LogicalKeyboardKey.browserBack: 'Back',
  LogicalKeyboardKey.browserForward: 'Forward',
};

/// A key's name in words, as a volunteer would say it: "Page Down",
/// "Right arrow", "B", "F5". Held with Ctrl or Shift it reads
/// "Ctrl + Z".
String keyName(
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) {
  var name = _names[key];
  if (name == null) {
    final digit = key.keyId - LogicalKeyboardKey.numpad0.keyId;
    final label = key.keyLabel.trim();
    name = digit >= 0 && digit <= 9
        ? '$digit'
        : label.isNotEmpty
        ? label
        : 'An unnamed key';
  }
  // Shift and / is how a question mark is typed.
  if (shift && key == LogicalKeyboardKey.slash) {
    name = 'Question mark';
    shift = false;
  }
  return [if (control) 'Ctrl', if (shift) 'Shift', name].join(' + ');
}

/// What the clicker test page says for a key the app has no use for.
const unusedKeyExplanation = 'Nothing: the app does not use this key';

/// What a press does on Live, in one line. On a phone or tablet only the
/// clicker's keys do anything, and only while the clicker setting is on.
String keyExplanation(
  LogicalKeyboardKey key, {
  required bool control,
  required bool shift,
  required bool desktop,
  required bool clickerOn,
}) {
  final s = shortcutFor(key, control: control, shift: shift);
  if (s == null || (!desktop && !s.clicker)) return unusedKeyExplanation;
  if (!desktop && !clickerOn) {
    return 'Nothing while Clicker and foot pedal is switched off';
  }
  return s.explanation(desktop: desktop);
}
