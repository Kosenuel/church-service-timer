/// PROTOTYPE: how the desktop Live layouts use a very large window.
///
/// Every switch defaults to 'off', which is the layout as it ships today.
/// Turn one on for a build with, for example,
/// `--dart-define=LIVE_PANES_LARGE=grow`, or set the static in a test.
/// Each variant only changes a window with room to spare, measured by a
/// `LayoutBuilder`; smaller windows keep the current arrangement.
class LargeScreenLive {
  /// Three panes and The dial. 'grow': the ring takes the height the title
  /// and controls leave, and the controls sit at the bottom of the pane.
  /// 'beside': the ring at the left of a wide pane, the controls in a
  /// column at its right.
  static String panes = const String.fromEnvironment(
    'LIVE_PANES_LARGE',
    defaultValue: 'off',
  );

  /// Mission control. 'fill': the three sections grow into the height
  /// above the timeline. 'rundown': the timeline becomes a taller rundown
  /// with speaker and planned/actual in each block.
  static String mission = const String.fromEnvironment(
    'LIVE_MISSION_LARGE',
    defaultValue: 'off',
  );

  /// Classic. 'wide': the two columns use a wider cap. 'three': timer,
  /// display and cues, and rundown side by side from about 1700 px.
  static String classic = const String.fromEnvironment(
    'LIVE_CLASSIC_LARGE',
    defaultValue: 'off',
  );

  /// The middle pane height from which [panes] applies. The default
  /// leaves a 1920 × 1080 window exactly as it is today; 800 also changes
  /// that window and a tall laptop one (1366 × 900).
  static double panesFromHeight =
      double.tryParse(const String.fromEnvironment('LIVE_PANES_FROM_HEIGHT')) ??
      1040;

  /// The height above the timeline from which [mission] applies.
  static const missionFromHeight = 900.0;

  /// The widest Classic's Live page is laid out.
  static double get classicCap => switch (classic) {
    'wide' => 1640,
    'three' => 2280,
    _ => 1200,
  };

  static void reset() {
    panes = mission = classic = 'off';
    panesFromHeight = 1040;
  }
}
