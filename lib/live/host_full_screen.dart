import 'dart:async';

import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/screen_orientation.dart';
import 'package:church_service_timer/windows/second_screen.dart';
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
}

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
    // The service may have ended while the window was changing.
    if (mounted && state.showing && !hostFullScreenAvailable) {
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

/// The stage on black, filling the window, with a small control that a
/// tap or click reveals for a few seconds: Exit full screen, or Hold to
/// unlock while the controls are locked.
class HostFullScreenView extends StatefulWidget {
  final HomeState home;
  const HostFullScreenView({super.key, required this.home});

  /// How long the control stays after a tap or click.
  static const controlTime = Duration(seconds: 4);
  @override
  State<HostFullScreenView> createState() => _HostFullScreenViewState();
}

class _HostFullScreenViewState extends State<HostFullScreenView> {
  HomeState get home => widget.home;
  bool _control = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    home.hostFullScreen.reveal = reveal;
    home.c.addListener(_follow);
    // Shown at first, so the way out is seen once.
    _control = true;
    _hide = Timer(HostFullScreenView.controlTime, _hideControl);
  }

  @override
  void dispose() {
    _hide?.cancel();
    home.c.removeListener(_follow);
    final state = home.hostFullScreen;
    if (state.reveal == reveal) state.reveal = null;
    // Closed some other way than Exit: the screen still goes back.
    if (state.showing && !state.changing) {
      state.showing = false;
      unawaited(applyFullScreen(home.c.port, false));
    }
    super.dispose();
  }

  /// Full screen is for a running service: when it ends, Live comes back.
  void _follow() {
    if (home.mounted && !home.hostFullScreenAvailable) leave();
  }

  void leave() => unawaited(home.setHostFullScreen(false));

  void _hideControl() {
    if (mounted) setState(() => _control = false);
  }

  void reveal() {
    _hide?.cancel();
    _hide = Timer(HostFullScreenView.controlTime, _hideControl);
    if (mounted && !_control) setState(() => _control = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = home.c;
    return PopScope(
      // Android Back leaves full screen, never the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !home.controlsLocked) leave();
        if (home.controlsLocked) reveal();
      },
      child: Scaffold(
        key: const ValueKey('host-full-screen'),
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('full-screen-stage'),
              behavior: HitTestBehavior.opaque,
              onTap: reveal,
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
            if (_control)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: home.controlsLocked ? _unlock(context) : _exit(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
