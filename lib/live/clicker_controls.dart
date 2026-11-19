import 'package:flutter/services.dart';

/// What a presentation clicker or foot pedal key does on Live.
enum ClickerAction { next, pause }

/// Default mapping: Page Down or → for Next, B or Space for Pause.
/// Most clickers send Page Down/Up; "blank" buttons send B or a full stop.
ClickerAction? clickerActionFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.arrowRight)
    return ClickerAction.next;
  if (key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.space)
    return ClickerAction.pause;
  return null;
}

/// Ctrl+K opens the command palette on a PC.
bool isCommandPaletteKey(LogicalKeyboardKey key, {required bool control}) =>
    control && key == LogicalKeyboardKey.keyK;

/// Ctrl+M switches between the mini timer and the full window.
bool isMiniTimerKey(LogicalKeyboardKey key, {required bool control}) =>
    control && key == LogicalKeyboardKey.keyM;

/// Next needs a second press within this window, like the lock-screen card.
const clickerConfirmWindow = Duration(seconds: 4);

/// What a PC keyboard adds on Live, beside the clicker keys. Each does
/// what its button on screen does, confirmation included.
enum DesktopLiveAction {
  adjustTime,
  undo,
  lock,
  message,
  editUpcoming,
  recoverTime,
  jump,
}

/// + or − (on the main keys or the number pad) opens Adjust time; Ctrl+Z
/// offers to undo the last segment change; Ctrl+L locks the controls (it
/// never unlocks them). M opens Send message, E Edit upcoming, R Recover
/// time and J Jump to segment.
DesktopLiveAction? desktopLiveActionFor(
  LogicalKeyboardKey key, {
  required bool control,
}) {
  if (control) {
    if (key == LogicalKeyboardKey.keyZ) return DesktopLiveAction.undo;
    if (key == LogicalKeyboardKey.keyL) return DesktopLiveAction.lock;
    return null;
  }
  if (key == LogicalKeyboardKey.keyM) return DesktopLiveAction.message;
  if (key == LogicalKeyboardKey.keyE) return DesktopLiveAction.editUpcoming;
  if (key == LogicalKeyboardKey.keyR) return DesktopLiveAction.recoverTime;
  if (key == LogicalKeyboardKey.keyJ) return DesktopLiveAction.jump;
  if (key == LogicalKeyboardKey.add ||
      key == LogicalKeyboardKey.equal ||
      key == LogicalKeyboardKey.minus ||
      key == LogicalKeyboardKey.numpadAdd ||
      key == LogicalKeyboardKey.numpadSubtract)
    return DesktopLiveAction.adjustTime;
  return null;
}

/// The number keys send the prepared cues on a PC: 1 is the first cue.
/// Returns its position in the list, or null for any other key.
int? desktopCueIndexFor(LogicalKeyboardKey key, {required bool control}) {
  if (control) return null;
  const digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  const pad = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final index = digits.indexOf(key);
  if (index >= 0) return index;
  final onPad = pad.indexOf(key);
  return onPad >= 0 ? onPad : null;
}
