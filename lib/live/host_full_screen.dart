import 'dart:async';

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/screen_orientation.dart';
import 'package:church_service_timer/windows/second_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// F11 shows the stage full screen on this screen, and leaves it again.
bool isFullScreenKey(LogicalKeyboardKey key) => key == LogicalKeyboardKey.f11;

/// Whether the stage picture fills this device's own screen, for
/// [HostFullScreenMode]. Kept on [HomeState] as one object.
class HostFullScreenState {
  /// The stage is showing in place of the whole app.
  bool showing = false;

  /// The window or the system bars are changing just now.
  bool changing = false;

  /// Shows the Exit control for a few seconds; set by the view.
  VoidCallback? reveal;

  /// Puts the control tray away if it is showing, and says whether it
  /// was; set by the view. Esc and Back close the tray first.
  bool Function()? closeTray;

  /// Brings back the gestures tip; set by the view.
  VoidCallback? showTip;
}

/// The id kept in [AppState.dismissedHints], on this device only, once the
/// gestures tip has been shown on its own.
const gesturesTipHint = 'full-screen-gestures';

/// Makes the screen itself full: on a computer the window loses its frame
/// and covers its monitor, where the computer can do that; on a phone or
/// tablet the system bars are hidden and it turns landscape. Without
/// either, the stage still fills the app's window.
Future<void> applyFullScreen(DevicePort port, bool on) async {
  try {
    if (port.isDesktop) {
      final window = port.fullScreenWindow;
      if (on) {
        await window?.enterFullScreen();
      } else {
        await window?.leaveFullScreen();
      }
    } else {
      // Landscape suits the stage picture; leaving brings back what the
      // app asked for before.
      await Future.wait([
        ScreenOrientation.setFullScreen(on),
        SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      ]);
    }
  } catch (_) {
    // The stage fills the window all the same.
  }
}

/// Full screen: the stage picture a second screen or paired stage screen
/// shows, on the screen of the device running the service, for when that
/// is the screen people watch.
extension HostFullScreenMode on HomeState {
  /// During a service or quick timer this device runs. A device joined to
  /// another's service as a stage screen has its own full screen.
  bool get hostFullScreenAvailable =>
      c.ready && c.liveSession.active && !c.pairing.joined;

  /// Full screen on a PC, once open, stays after the service ends,
  /// showing its end screen; it closes when the next service is set up or
  /// Live is left. On a phone or tablet it closes when the service ends,
  /// and the screen turns back to how it was.
  bool get hostFullScreenStays =>
      c.ready &&
      !c.pairing.joined &&
      (c.liveSession.active ||
          (c.port.isDesktop && c.liveSession.phase == 'ended'));

  /// The header has room for the Full screen button from this width; a
  /// narrower screen would lose the service's name to it.
  static const _headerWidth = 600.0;

  /// The Full screen button belongs in the header just now.
  bool get fullScreenInHeader =>
      hostFullScreenAvailable &&
      MediaQuery.sizeOf(context).width >= _headerWidth;

  /// The Full screen button under the stage preview on Live, where the
  /// header is too narrow for it (a phone); nothing elsewhere.
  List<Widget> fullScreenControl() {
    if (!hostFullScreenAvailable || fullScreenInHeader) return const [];
    return [
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: 'Full screen: show the stage on this screen',
          child: OutlinedButton.icon(
            key: const ValueKey('full-screen-button'),
            onPressed: controlsLocked
                ? null
                : () => unawaited(setHostFullScreen(true)),
            icon: const Icon(Icons.fullscreen, size: 20),
            label: const Text('Full screen'),
          ),
        ),
      ),
    ];
  }

  /// A question is asked in the compact card: in the mini timer window,
  /// and over the stage in full screen.
  bool get compactQuestions => miniTimer || hostFullScreen.showing;

  /// Timer only, with the segment name, or with the next segment. A PC
  /// uses its second screen's choice; a phone or tablet has its own.
  String get hostFullScreenLayout =>
      c.secondScreen?.layout ?? c.state.fullScreenLayout;

  /// What the stage shows now, as the second screen would get it.
  Json hostStageSnapshot() =>
      c.stageWindowSnapshot()..['stageLayout'] = hostFullScreenLayout;

  /// Shows the stage full screen or goes back to Live. Opening needs a
  /// running service and nothing else open on top; otherwise nothing
  /// happens. Returns whether the stage is full screen afterwards.
  Future<bool> setHostFullScreen(bool value) async {
    final state = hostFullScreen;
    if (!mounted || state.changing || value == state.showing) {
      return state.showing;
    }
    if (value &&
        (!hostFullScreenAvailable ||
            miniTimer ||
            ModalRoute.of(context)?.isCurrent != true)) {
      return false;
    }
    state.changing = true;
    try {
      if (value) {
        refreshHome(() {
          state.showing = true;
          page = 0;
        });
        await applyFullScreen(c.port, true);
      } else {
        await applyFullScreen(c.port, false);
        if (mounted) refreshHome(() => state.showing = false);
      }
    } finally {
      state.changing = false;
    }
    // The service may have gone while the window was changing.
    if (mounted && state.showing && !hostFullScreenStays) {
      return setHostFullScreen(false);
    }
    return state.showing;
  }

  /// F11 on a computer opens and leaves full screen; Esc leaves it. Null
  /// for any other key. Like every key it does nothing while typing, under
  /// a question or another page, or with the controls locked.
  bool? fullScreenKey(LogicalKeyboardKey key) {
    final showing = hostFullScreen.showing;
    final toggles = c.port.isDesktop && isFullScreenKey(key);
    if (!toggles && !(showing && key == LogicalKeyboardKey.escape)) {
      return null;
    }
    // Esc belongs to the question or list on top.
    if (ModalRoute.of(context)?.isCurrent != true || typingInField) {
      return false;
    }
    if (controlsLocked) {
      // Not left, but shown why: Hold to unlock is on the control.
      hostFullScreen.reveal?.call();
      return false;
    }
    if (!showing && (!hostFullScreenAvailable || miniTimer)) return false;
    // Esc puts the control tray away before it leaves full screen.
    if (showing &&
        key == LogicalKeyboardKey.escape &&
        (hostFullScreen.closeTray?.call() ?? false)) {
      return true;
    }
    unawaited(setHostFullScreen(!showing));
    return true;
  }

  /// What full screen shows in place of the whole app.
  Widget hostFullScreenView() => HostFullScreenView(home: this);

  /// The choice of what full screen shows, for a phone or tablet in
  /// Settings › Screens & devices. A PC chooses with its second screen.
  Widget fullScreenPanel() {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: colors.muted);
    return panel(
      child: Column(
        key: const ValueKey('full-screen-settings'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            deviceText('Full screen on this phone'),
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            deviceText(
              'During a service, Full screen on Live shows the stage on this phone’s own screen. Choose what it shows.',
            ),
            style: muted,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final layout in secondScreenLayouts.entries)
                ChoiceChip(
                  key: ValueKey('full-screen-layout-${layout.key}'),
                  label: Text(layout.value),
                  selected: c.state.fullScreenLayout == layout.key,
                  onSelected: controlsLocked
                      ? null
                      : (_) => c.commit(
                          (draft, _) => draft.fullScreenLayout = layout.key,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            deviceText(
              'Only this phone. Paired stage screens keep their own choice.',
            ),
            style: muted,
          ),
        ],
      ),
    );
  }
}

/// Which part of the stage a double tap or double click was on: the left
/// third asks to undo, the middle to pause or resume, the right third to
/// go to the next segment.
enum StageThird { left, middle, right }

/// The third of a stage [width] wide that [dx] falls in.
StageThird stageThird(double dx, double width) => dx < width / 3
    ? StageThird.left
    : dx < width * 2 / 3
    ? StageThird.middle
    : StageThird.right;

/// The stage on black, filling the window. Over it, never on any stage
/// screen:
///
/// * a double tap or double click asks, in the usual card, to undo (left
///   third), pause or resume (middle) or go to the next segment (right);
/// * a tap or click, a swipe up from the bottom edge, or the mouse at the
///   bottom edge brings up a small control tray, which goes after
///   [trayTime] untouched, on Esc or on a swipe down;
/// * a small control in the corner, shown at first, offers Exit full
///   screen, or Hold to unlock while the controls are locked. Locked, the
///   gestures and the tray do nothing else.
class HostFullScreenView extends StatefulWidget {
  final HomeState home;
  const HostFullScreenView({super.key, required this.home});

  /// How long the corner control stays.
  static const controlTime = Duration(seconds: 4);

  /// How long the control tray stays untouched.
  static const trayTime = Duration(seconds: 6);

  /// How long the gestures tip shows if nothing dismisses it.
  static const tipTime = Duration(seconds: 8);

  /// How long after the tip is tapped away a tap is ignored, so the second
  /// tap of a double tap does not open the tray.
  static const tipGuard = Duration(milliseconds: 400);

  /// How long a hint such as "Nothing to undo" shows.
  static const hintTime = Duration(milliseconds: 1600);

  /// How close to the bottom the mouse opens the tray.
  static const mouseEdge = 24.0;
  @override
  State<HostFullScreenView> createState() => _HostFullScreenViewState();
}

class _HostFullScreenViewState extends State<HostFullScreenView> {
  HomeState get home => widget.home;
  bool _control = false;
  Timer? _hide;

  bool _tray = false;
  Timer? _trayHide;

  /// A question or list opened from the tray is on top, or the mouse is
  /// over the tray: the tray waits.
  int _trayBusy = 0;
  bool _mouseInTray = false;

  String? _hint;
  Timer? _hintHide;

  /// The gestures tip is showing; [_tipGuarded] while a tap just
  /// dismissed it.
  bool _tip = false, _tipGuarded = false;
  Timer? _tipHide, _tipGuardEnd;

  Offset? _doubleAt;
  double _dragFrom = 0, _dragBy = 0;

  @override
  void initState() {
    super.initState();
    home.hostFullScreen
      ..reveal = reveal
      ..closeTray = _closeOverlays
      ..showTip = _showTip;
    home.c.addListener(_follow);
    HardwareKeyboard.instance.addHandler(_tipKey);
    // The first time on this device, and only unlocked.
    if (!home.controlsLocked &&
        !home.c.state.dismissedHints.contains(gesturesTipHint)) {
      _tip = true;
      _tipHide = Timer(HostFullScreenView.tipTime, _dismissTip);
      // Kept on this device only, once it has shown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          home.c.commit((d, _) => d.dismissedHints.add(gesturesTipHint)),
        );
      });
    }
    // Shown at first, so the way out is seen once.
    _control = true;
    _hide = Timer(HostFullScreenView.controlTime, _hideControl);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _trayHide?.cancel();
    _hintHide?.cancel();
    _tipHide?.cancel();
    _tipGuardEnd?.cancel();
    HardwareKeyboard.instance.removeHandler(_tipKey);
    home.c.removeListener(_follow);
    final state = home.hostFullScreen;
    if (state.reveal == reveal) state.reveal = null;
    if (state.closeTray == _closeOverlays) state.closeTray = null;
    if (state.showTip == _showTip) state.showTip = null;
    // Closed some other way than Exit: the screen still goes back.
    if (state.showing && !state.changing) {
      state.showing = false;
      unawaited(applyFullScreen(home.c.port, false));
    }
    super.dispose();
  }

  /// Full screen is for a service: on a PC it stays on the end screen once
  /// the service ends, and Live comes back when another is set up; a phone
  /// or tablet goes back to Live as the service ends.
  void _follow() {
    if (home.mounted && !home.hostFullScreenStays) leave();
  }

  /// End service from the tray: on a PC full screen stays, showing the end
  /// screen, or the clock for a program with no end screen; a phone or
  /// tablet leaves full screen.
  Future<void> _endService() => home.confirmEndService();

  void leave() => unawaited(home.setHostFullScreen(false));

  void _hideControl() {
    if (mounted) setState(() => _control = false);
  }

  void reveal() {
    _hide?.cancel();
    _hide = Timer(HostFullScreenView.controlTime, _hideControl);
    if (mounted && !_control) setState(() => _control = true);
  }

  /// The same conditions as the timer buttons on Live.
  bool get _enabled {
    final c = home.c, s = c.liveSession;
    return s.active &&
        !c.reportSavePending &&
        !c.busy &&
        !c.corrupt &&
        !home.controlsLocked &&
        c.pairing.localControl;
  }

  bool get _canAdvance {
    final s = home.c.liveSession;
    return _enabled &&
        s.timeline != null &&
        s.index + 1 < s.timeline!.segments.length;
  }

  /// Brings up the control tray; locked, shows Hold to unlock instead.
  void openTray() {
    if (!mounted) return;
    if (home.controlsLocked) return reveal();
    _hide?.cancel();
    setState(() {
      _tray = true;
      // The tray has its own Exit.
      _control = false;
    });
    _waitThenHideTray();
  }

  /// Shows the gestures tip: the first time, and from Show gestures.
  void _showTip() {
    if (!mounted || home.controlsLocked) return;
    _tipHide?.cancel();
    _tipGuardEnd?.cancel();
    setState(() {
      _tip = true;
      _tipGuarded = false;
    });
    _tipHide = Timer(HostFullScreenView.tipTime, _dismissTip);
  }

  /// Takes the tip away. After a tap, taps are ignored a moment longer.
  void _dismissTip({bool afterTap = false}) {
    _tipHide?.cancel();
    if (!mounted || !_tip) return;
    setState(() {
      _tip = false;
      _tipGuarded = afterTap;
    });
    if (afterTap) {
      _tipGuardEnd = Timer(HostFullScreenView.tipGuard, () {
        if (mounted) setState(() => _tipGuarded = false);
      });
    }
  }

  /// Any key takes the tip away, and the key still does its own work. Esc
  /// is left to [_closeOverlays].
  bool _tipKey(KeyEvent event) {
    if (_tip &&
        event is KeyDownEvent &&
        event.logicalKey != LogicalKeyboardKey.escape) {
      _dismissTip();
    }
    return false;
  }

  /// Esc and Back put the tip away first, then the tray; false if neither
  /// was showing.
  bool _closeOverlays() {
    if (_tip) {
      _dismissTip();
      return true;
    }
    return closeTray();
  }

  /// Puts the tray away; false if it was not showing.
  bool closeTray() {
    _trayHide?.cancel();
    if (!mounted || !_tray) return false;
    setState(() => _tray = false);
    return true;
  }

  /// Starts the tray's time again, unless something keeps it.
  void _waitThenHideTray() {
    _trayHide?.cancel();
    if (!_tray || _trayBusy > 0 || _mouseInTray) return;
    _trayHide = Timer(HostFullScreenView.trayTime, closeTray);
  }

  /// Runs what a gesture or the tray asked for. The tray stays while its
  /// question is open, then has its full time again.
  Future<void> _run(Future<void> Function() action) async {
    _trayBusy++;
    _trayHide?.cancel();
    try {
      await action();
    } finally {
      _trayBusy--;
      if (mounted) _waitThenHideTray();
    }
  }

  void _showHint(String text) {
    _hintHide?.cancel();
    setState(() => _hint = text);
    _hintHide = Timer(HostFullScreenView.hintTime, () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _doubleTap(Size size) {
    final at = _doubleAt;
    _doubleAt = null;
    if (at == null) return;
    if (home.controlsLocked) return reveal();
    if (!_enabled) return;
    final s = home.c.liveSession;
    switch (stageThird(at.dx, size.width)) {
      case StageThird.left:
        if (s.undo == null) return _showHint('Nothing to undo');
        unawaited(_run(home.undo));
      case StageThird.middle:
        unawaited(_run(home.confirmPause));
      case StageThird.right:
        if (!_canAdvance) return _showHint('This is the last segment');
        unawaited(_run(home.advance));
    }
  }

  void _dragEnd(DragEndDetails details, Size size) {
    if (home.controlsLocked) return;
    final velocity = details.primaryVelocity ?? 0;
    final up = _dragBy < -40 || velocity < -300;
    final down = _dragBy > 40 || velocity > 300;
    // From the bottom fifth, and at least the last 96 points.
    final edge = size.height - (size.height * .2).clamp(96.0, size.height);
    if (up && _dragFrom >= edge) {
      openTray();
    } else if (down) {
      closeTray();
    }
  }

  void _hover(PointerHoverEvent event, Size size) {
    if (event.kind != PointerDeviceKind.mouse || home.controlsLocked) return;
    if (event.localPosition.dy >= size.height - HostFullScreenView.mouseEdge) {
      if (_tray) {
        _waitThenHideTray();
      } else {
        openTray();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = home.c;
    final locked = home.controlsLocked;
    if (locked && _tray) {
      // Lock controls puts the tray away with everything else.
      _tray = false;
      _trayHide?.cancel();
    }
    if (locked && (_tip || _tipGuarded)) {
      // Nor does it leave a tip in the way of Hold to unlock.
      _tip = _tipGuarded = false;
      _tipHide?.cancel();
      _tipGuardEnd?.cancel();
    }
    final motion = reduceAppMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return PopScope(
      // Android Back puts the tray away, then leaves full screen, never
      // the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (home.controlsLocked) return reveal();
        if (!_closeOverlays()) leave();
      },
      child: Scaffold(
        key: const ValueKey('host-full-screen'),
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, space) {
            final size = space.biggest;
            return Stack(
              fit: StackFit.expand,
              children: [
                MouseRegion(
                  onHover: (event) => _hover(event, size),
                  child: GestureDetector(
                    key: const ValueKey('full-screen-stage'),
                    behavior: HitTestBehavior.opaque,
                    // A single tap waits just long enough to tell it from
                    // a double tap.
                    onTap: openTray,
                    onDoubleTapDown: (details) =>
                        _doubleAt = details.localPosition,
                    onDoubleTap: () => _doubleTap(size),
                    onVerticalDragStart: (details) {
                      _dragFrom = details.localPosition.dy;
                      _dragBy = 0;
                    },
                    onVerticalDragUpdate: (details) =>
                        _dragBy += details.primaryDelta ?? 0,
                    onVerticalDragEnd: (details) => _dragEnd(details, size),
                    child: SafeArea(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([c, c.liveClock]),
                        builder: (context, _) => StageSurface(
                          data: home.hostStageSnapshot(),
                          stale: false,
                        ),
                      ),
                    ),
                  ),
                ),
                // Never part of the stage picture: drawn here only.
                IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: motion,
                    child: _tip
                        ? _tipView(context, size)
                        : const SizedBox.shrink(),
                  ),
                ),
                // A tap anywhere on it closes it; the one after it, for a
                // moment, is not a tap on the stage.
                if (_tip || _tipGuarded)
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('full-screen-tip-tap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _dismissTip(afterTap: true),
                    ),
                  ),
                if (_control)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: locked ? _unlock(context) : _exit(),
                      ),
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: const Alignment(0, .55),
                    child: IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: motion,
                        child: _hint == null
                            ? const SizedBox.shrink()
                            : _hintView(context, _hint!),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSwitcher(
                      duration: motion,
                      transitionBuilder: (child, animation) => SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 1.2),
                          end: Offset.zero,
                        ).animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: _tray && !locked
                          ? _trayView(context, size)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The three zones with what a double tap does in each, and how to bring
  /// up the tray, over a darkened stage. Sized from the screen, so it reads
  /// from a phone in landscape and on a large monitor.
  Widget _tipView(BuildContext context, Size size) {
    final colors = appColors(context);
    final unit = (size.shortestSide / 390).clamp(1.0, 2.4);
    final click = desktopWording ? 'click' : 'tap';
    final double = desktopWording ? 'Double-click' : 'Double-tap';
    final big = TextStyle(
      color: Colors.white,
      fontSize: 19 * unit,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    final small = TextStyle(
      color: Colors.white.withValues(alpha: .82),
      fontSize: 14 * unit,
      height: 1.2,
    );
    Widget zone(IconData icon, String name) => Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8 * unit),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 36 * unit),
            SizedBox(height: 6 * unit),
            Text(name, textAlign: TextAlign.center, style: big),
            SizedBox(height: 2 * unit),
            Text('$double here', textAlign: TextAlign.center, style: small),
          ],
        ),
      ),
    );
    final line = Colors.white.withValues(alpha: .45);
    return Semantics(
      container: true,
      label:
          'Gestures. $double the left third to undo, the middle to pause or resume, the right third for the next segment. Each asks first.',
      child: ColoredBox(
        key: const ValueKey('full-screen-tip'),
        color: Colors.black.withValues(alpha: .82),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    zone(Icons.undo, 'Undo'),
                    VerticalDivider(width: 1, thickness: 1, color: line),
                    zone(Icons.pause_circle_outline, 'Pause or resume'),
                    VerticalDivider(width: 1, thickness: 1, color: line),
                    zone(Icons.skip_next_rounded, 'Next segment'),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16 * unit,
                  0,
                  16 * unit,
                  14 * unit,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14 * unit),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14 * unit,
                          vertical: 8 * unit,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.keyboard_double_arrow_up,
                              color: Colors.white,
                              size: 30 * unit,
                            ),
                            SizedBox(width: 10 * unit),
                            Flexible(
                              child: Text(
                                desktopWording
                                    ? 'Click once, or move the mouse to the bottom edge, for the controls'
                                    : 'Swipe up from the bottom, or tap once, for the controls',
                                style: big.copyWith(
                                  fontSize: 17 * unit,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8 * unit),
                    Text(
                      'Each one asks you to confirm. ${click[0].toUpperCase()}${click.substring(1)} anywhere, or press a key, to close.',
                      textAlign: TextAlign.center,
                      style: small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hintView(BuildContext context, String text) {
    final colors = appColors(context);
    return DecoratedBox(
      key: const ValueKey('full-screen-hint'),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.text),
        ),
      ),
    );
  }

  /// Every control Live has for the timer and the stage, small, along the
  /// bottom. Each timer action asks first, as on Live.
  Widget _trayView(BuildContext context, Size size) {
    final colors = appColors(context);
    final c = home.c;
    return Padding(
      key: const ValueKey('full-screen-tray'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: MouseRegion(
        onEnter: (event) {
          if (event.kind != PointerDeviceKind.mouse) return;
          _mouseInTray = true;
          _trayHide?.cancel();
        },
        onExit: (event) {
          if (!_mouseInTray) return;
          _mouseInTray = false;
          _waitThenHideTray();
        },
        child: Listener(
          // Any touch or wheel in it starts its time again.
          onPointerDown: (_) => _waitThenHideTray(),
          onPointerSignal: (_) => _waitThenHideTray(),
          child: Focus(
            skipTraversal: true,
            onKeyEvent: (_, _) {
              _waitThenHideTray();
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              // A swipe down puts it away.
              onVerticalDragStart: (_) => _dragBy = 0,
              onVerticalDragUpdate: (details) =>
                  _dragBy += details.primaryDelta ?? 0,
              onVerticalDragEnd: (details) {
                if (_dragBy > 40 || (details.primaryVelocity ?? 0) > 300) {
                  closeTray();
                }
              },
              child: Material(
                color: colors.surface,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: size.width - 24),
                  // On one line where it fits; on a narrow screen in two,
                  // so every control stays in view.
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([c, c.liveClock]),
                      builder: (context, _) => Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: _trayItems(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _trayItems(BuildContext context) {
    final c = home.c, s = c.liveSession;
    final enabled = _enabled;
    final output = home.outputControlsEnabled && !c.hardware.sending;
    // With no end screen an ended service already shows the clock.
    final clockShowing =
        !s.outputBlank && s.outputMode(c.now) == 'Clock' && !s.endsOnClock;
    final blank =
        (s.active || s.phase == 'ended') &&
        !c.busy &&
        !c.corrupt &&
        !home.controlsLocked &&
        c.pairing.localControl;
    final desktop = c.port.isDesktop;
    final colors = appColors(context);
    return [
      _item(
        'full-screen-tray-pause',
        s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        s.paused ? 'Resume' : 'Pause',
        enabled ? home.confirmPause : null,
      ),
      _item(
        'full-screen-tray-next',
        Icons.skip_next_rounded,
        'Next',
        _canAdvance ? home.advance : null,
        tooltip: 'Next segment',
      ),
      _item(
        'full-screen-tray-minus',
        Icons.remove,
        '−2 min',
        enabled && s.remaining(c.now) > 0
            ? () => home.adjustTime(fixedSeconds: -120)
            : null,
      ),
      _item(
        'full-screen-tray-plus',
        Icons.add,
        '+2 min',
        enabled && s.balance(c.now) + 120000 <= supportedCountdownMs
            ? () => home.adjustTime(fixedSeconds: 120)
            : null,
      ),
      _item(
        'full-screen-tray-undo',
        Icons.undo,
        'Undo',
        enabled && s.undo != null ? home.undo : null,
        tooltip: desktop ? 'Undo (Ctrl+Z)' : 'Undo',
      ),
      _divider(colors),
      if (c.state.stageCues.isNotEmpty)
        Builder(
          builder: (context) => _item(
            'full-screen-tray-cues',
            Icons.chat_bubble_outline,
            'Cues',
            output ? () => _cues(context) : null,
            tooltip: 'Show a cue',
          ),
        ),
      _item(
        'full-screen-tray-clock',
        clockShowing ? Icons.timer_outlined : Icons.schedule,
        clockShowing ? 'Timer' : 'Clock',
        output && !s.endsOnClock
            ? () => c.act(
                clockShowing
                    ? (s.phase == 'ended' ? 'endScreen' : 'timer')
                    : 'clock',
              )
            : null,
        tooltip: clockShowing ? 'Show timer' : 'Show clock',
      ),
      _item(
        'full-screen-tray-blank',
        s.outputBlank ? Icons.tv_outlined : Icons.tv_off_outlined,
        s.outputBlank ? 'Unblank' : 'Blank',
        blank ? home.confirmBlank : null,
        tooltip: s.outputBlank ? 'Unblank screen' : 'Blank screen',
      ),
      _item(
        'full-screen-tray-gestures',
        Icons.touch_app_outlined,
        'Show gestures',
        () async {
          closeTray();
          _showTip();
        },
        tooltip: 'Show what a double ${desktop ? 'click' : 'tap'} does',
      ),
      _divider(colors),
      // Ends the service, after the same question as End service on Live;
      // full screen stays, on the end screen or the clock.
      _item(
        'full-screen-tray-end',
        Icons.stop_circle_outlined,
        s.quickTimer ? 'End timer' : 'End service',
        enabled ? _endService : null,
        foreground: _endColor,
      ),
      _item(
        'full-screen-exit',
        Icons.fullscreen_exit,
        'Exit',
        () async => leave(),
        tooltip: desktop ? 'Exit full screen (Esc)' : 'Exit full screen',
      ),
    ];
  }

  /// End service in the tray: a light red that reads on the dark tray,
  /// so it stands apart from the other controls.
  static const _endColor = Color(0xffff7979);

  Widget _divider(AppPalette colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    child: SizedBox(
      height: 40,
      child: VerticalDivider(width: 1, color: colors.border),
    ),
  );

  Widget _item(
    String key,
    IconData icon,
    String label,
    Future<void> Function()? action, {
    String? tooltip,
    Color? foreground,
  }) => Tooltip(
    message: tooltip ?? label,
    child: TextButton(
      key: ValueKey(key),
      onPressed: action == null ? null : () => unawaited(_run(action)),
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        foregroundColor: foreground ?? appColors(context).text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  /// The saved cues, as Live has them: one sends it, and the one showing
  /// goes back to the timer.
  Future<void> _cues(BuildContext button) async {
    final c = home.c, s = c.liveSession;
    final box = button.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(button).context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    bool showing(TextLayout cue) =>
        !s.outputBlank &&
        s.hasManualCue(c.now) &&
        !s.alertIsMessage &&
        s.alert!.text == cue.text;
    final cues = c.state.stageCues;
    final choice = await showMenu<int>(
      context: button,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      popUpAnimationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      items: [
        for (final (i, cue) in cues.indexed)
          PopupMenuItem(
            key: ValueKey('full-screen-tray-cue-$i'),
            value: i,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: showing(cue)
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Flexible(
                  child: Text(
                    cue.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (choice == null || !mounted || choice >= c.state.stageCues.length) {
      return;
    }
    final cue = c.state.stageCues[choice];
    if (!home.outputControlsEnabled || c.hardware.sending) return;
    if (showing(cue)) {
      await c.act('clearCue');
    } else {
      await home.sendPreparedCue(cue);
    }
  }

  Widget _exit() => Tooltip(
    message: home.c.port.isDesktop
        ? 'Exit full screen (Esc)'
        : 'Exit full screen',
    child: FilledButton.tonalIcon(
      key: const ValueKey('full-screen-exit'),
      onPressed: leave,
      icon: const Icon(Icons.fullscreen_exit),
      label: const Text(
        'Exit full screen',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Widget _unlock(BuildContext context) {
    final colors = appColors(context);
    return Material(
      key: const ValueKey('full-screen-locked'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, size: 18, color: colors.warning),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Controls locked',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Semantics(
                label: 'Hold to unlock controls',
                child: OutlinedButton(
                  key: const ValueKey('full-screen-unlock'),
                  onPressed: () {
                    reveal();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            deviceText('Press and hold to unlock controls.'),
                          ),
                        ),
                      );
                  },
                  onLongPress: () {
                    home.refreshHome(
                      () => home.c.uiLocked = home.controlsLocked = false,
                    );
                    reveal();
                  },
                  child: const Text(
                    'Hold to unlock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
