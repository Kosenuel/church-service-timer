/// The mini timer's window: the app window made small and kept above
/// other programs, for a laptop that also runs lyrics or slides.
///
/// This is all the rest of the app knows about it. On Windows it is
/// `WindowMemory` (window_memory.dart); tests use a fake; a phone has
/// none.
abstract class MiniWindow {
  /// Makes the window small, with room for [width] × [height] of the app
  /// (in the app's own units), and keeps it above other programs. Where it
  /// was is kept for [leave]. False, with the window as it was, when the
  /// computer would not do it.
  Future<bool> enter({required double width, required double height});

  /// Puts the window back exactly where [enter] found it, no longer above
  /// other programs. Does nothing when the window is not small.
  Future<void> leave();
}

/// The app window made truly full screen: no title bar or borders,
/// covering the monitor it is on, for showing the stage on the operator's
/// own screen. On Windows it is `WindowMemory` too; a phone hides its
/// system bars instead and has none.
abstract class FullScreenWindow {
  /// Covers the window's monitor. Where the window was is kept for
  /// [leaveFullScreen]. False, with the window as it was, when the
  /// computer would not do it.
  Future<bool> enterFullScreen();

  /// Puts the window back exactly as [enterFullScreen] found it. Does
  /// nothing when the window is not full screen.
  Future<void> leaveFullScreen();
}

/// The size of the inside of the window, in screen pixels, and how many of
/// those make one of the app's units ([scale], 1.5 on a screen set to
/// 150%).
typedef ViewMetrics = ({double scale, double width, double height});
