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

/// Next needs a second press within this window, like the lock-screen card.
const clickerConfirmWindow = Duration(seconds: 4);
