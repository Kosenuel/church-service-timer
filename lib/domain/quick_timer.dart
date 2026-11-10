import 'package:church_service_timer/domain/domain.dart';

/// The ready-made Quick timer lengths, in minutes. The sign counts down
/// up to 59:59, so the longest is 45 min; Custom goes up to 59 min 59 s.
const quickTimerMinutes = [5, 10, 15, 30, 45];

/// The longest Quick timer, in seconds (59:59, the sign's limit).
const quickTimerMaxSeconds = 3599;

/// How many recent Quick timers Live offers as one-tap choices.
const quickTimerRecentLimit = 3;

/// The name a Quick timer has when none is given.
const quickTimerDefaultName = 'Quick timer';

/// A Quick timer the operator started: its name (may be empty) and length.
class QuickTimerChoice {
  final String name;
  final int seconds;
  const QuickTimerChoice(this.name, this.seconds);

  String get title => name.trim().isEmpty ? quickTimerDefaultName : name.trim();

  /// A one-segment program for the service engine.
  Timeline timeline(DisplaySettings display) => Timeline(title, [
    Segment(title, seconds ~/ 60, seconds: seconds % 60),
  ], display);

  @override
  bool operator ==(Object other) =>
      other is QuickTimerChoice &&
      other.name.trim().toLowerCase() == name.trim().toLowerCase() &&
      other.seconds == seconds;
  @override
  int get hashCode => Object.hash(name.trim().toLowerCase(), seconds);

  Json toJson() => {'name': name, 'seconds': seconds};

  static QuickTimerChoice? tryRead(dynamic j) {
    if (j is! Map) return null;
    final name = j['name'], seconds = j['seconds'];
    if (name is! String || name.length > 60) return null;
    if (seconds is! int || seconds < 1 || seconds > quickTimerMaxSeconds) {
      return null;
    }
    return QuickTimerChoice(name, seconds);
  }
}

/// [recent] with [choice] first, without repeats, at most
/// [quickTimerRecentLimit] long.
List<QuickTimerChoice> rememberQuickTimer(
  List<QuickTimerChoice> recent,
  QuickTimerChoice choice,
) => [
  choice,
  ...recent.where((r) => r != choice),
].take(quickTimerRecentLimit).toList();
