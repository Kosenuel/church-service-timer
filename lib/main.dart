import 'package:church_service_timer/shared/device_words.dart';
import 'dart:async';
import 'dart:io' show Platform, exit;
import 'dart:ui' show AppExitResponse, ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/list_views.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/windows/stage_output_app.dart';
import 'package:church_service_timer/windows/windows_app.dart';
import 'package:church_service_timer/windows/file_drop.dart';

import 'package:church_service_timer/settings/settings_views.dart';
import 'package:church_service_timer/pairing/pairing_views.dart';
import 'package:church_service_timer/pairing/stage_screen_views.dart';
import 'package:church_service_timer/live/live_layout_views.dart';
import 'package:church_service_timer/programs/program_library_views.dart';
import 'package:church_service_timer/programs/programs_desktop.dart';
import 'package:church_service_timer/settings/settings_pin_views.dart';
import 'package:church_service_timer/live/clicker_controls.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/live/shortcuts_sheet.dart';
import 'package:church_service_timer/settings/clicker_test_page.dart';
import 'package:church_service_timer/programs/programs_page_state.dart';
import 'package:church_service_timer/reports/reports_page_state.dart';
import 'package:church_service_timer/programs/program_edit_actions.dart';
import 'package:church_service_timer/shared/tab_swipe.dart';
import 'package:church_service_timer/live/live_page.dart';
import 'package:church_service_timer/live/stage_output_views.dart';
import 'package:church_service_timer/settings/stage_cue_settings_views.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/home_notices.dart';
import 'package:church_service_timer/live/live_actions.dart';
import 'package:church_service_timer/live/live_timer_views.dart';
import 'package:church_service_timer/live/planning_views.dart';
import 'package:church_service_timer/live/time_recovery_views.dart';
import 'package:church_service_timer/live/timing_overview_views.dart';
import 'package:church_service_timer/live/mini_timer.dart';
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/reports/report_library_views.dart';
import 'package:church_service_timer/reports/reports_desktop.dart';
import 'package:church_service_timer/lyrics/lyrics_page.dart';
import 'package:church_service_timer/shared/home_pages.dart';

export 'package:church_service_timer/settings/appearance_views.dart';
export 'package:church_service_timer/reports/report_views.dart';
export 'package:church_service_timer/live/live_timer_views.dart';
export 'package:church_service_timer/programs/program_views.dart';
export 'package:church_service_timer/settings/settings_pin_views.dart';
export 'package:church_service_timer/settings/settings_views.dart';
export 'package:church_service_timer/settings/display_settings_views.dart';
export 'package:church_service_timer/hardware/hardware_views.dart';
export 'package:church_service_timer/settings/stage_cue_settings_views.dart';
export 'package:church_service_timer/live/planning_views.dart';
export 'package:church_service_timer/pairing/pairing_views.dart';
export 'package:church_service_timer/hardware/device_management_views.dart';
export 'package:church_service_timer/pairing/stage_screen_views.dart';
export 'package:church_service_timer/hardware/wifi_reconnect_views.dart';
export 'package:church_service_timer/live/live_layout_views.dart';
export 'package:church_service_timer/live/stage_output_views.dart';
export 'package:church_service_timer/live/time_recovery_views.dart';
export 'package:church_service_timer/live/timing_overview_views.dart';
export 'package:church_service_timer/programs/program_editor_insights.dart';
export 'package:church_service_timer/programs/program_import_export_views.dart';
export 'package:church_service_timer/programs/program_library_views.dart';
export 'package:church_service_timer/programs/programs_desktop.dart';
export 'package:church_service_timer/reports/report_actions.dart';
export 'package:church_service_timer/reports/report_library_views.dart';
export 'package:church_service_timer/reports/reports_desktop.dart';
export 'package:church_service_timer/reports/timing_insights_views.dart';
export 'package:church_service_timer/settings/clock_settings_views.dart';
export 'package:church_service_timer/settings/settings_search_views.dart';
export 'package:church_service_timer/settings/warning_settings_views.dart';
export 'package:church_service_timer/shared/format_labels.dart';
export 'package:church_service_timer/shared/item_menu_views.dart';
export 'package:church_service_timer/shared/selection_views.dart';
export 'package:church_service_timer/shared/home_pages.dart';
export 'package:church_service_timer/lyrics/lyrics_page.dart';
export 'package:church_service_timer/shared/undo_actions.dart';
export 'package:church_service_timer/live/live_actions.dart';
export 'package:church_service_timer/programs/program_edit_actions.dart';
export 'package:church_service_timer/shared/home_widgets.dart';
export 'package:church_service_timer/live/live_page.dart';
export 'package:church_service_timer/live/text_composer.dart';
export 'package:church_service_timer/programs/template_editor.dart';
export 'package:church_service_timer/live/control_grid.dart';
export 'package:church_service_timer/live/mini_timer.dart';

/// One line describing a layout. Each " · " stays with the word before
/// it, so a wrap never starts a line with "· scroll".
String styleSummary(TextLayout l) =>
    '${l.text} · ${displayFontNames[l.font]} · ${l.bold ? 'bold · ' : ''}${l.italic ? 'italic · ' : ''}${l.height * 7}\u00a0px · ${l.align == 'center' ? 'centre' : l.align} · ${effectNames[l.effect] ?? l.effect}${l.effect == 'scroll' ? ' ${l.speed}\u00a0px/s${l.screenSpeed == null ? '' : ' · screens ${l.screenSpeed}'}' : ''}${l.screenColor == 'white' ? '' : ' · ${l.screenColor == 'accent' ? 'theme colour' : l.screenColor} on screens'}${l.bannerOnScreens ? ' · banner at the ${l.screenPosition}' : ''}${l.screenWrap ? ' · wrapped on screens' : ''}'
        .replaceAll(' · ', '\u00a0· ');

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final DevicePort port;
  if (Platform.isWindows && arguments.contains('--stage-output')) {
    // This copy was started by the app itself to be the stage window on
    // a second screen; it shows the stage and nothing else.
    unawaited(runStageOutput(arguments));
    return;
  }
  if (Platform.isWindows) {
    // Null when the app is already open: that copy has been brought to
    // the front (and given any file this one was asked to open).
    final windows = startWindowsPort(arguments);
    if (windows == null) exit(0);
    port = windows;
    desktopWording = true;
  } else {
    port = AndroidPort();
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tinos',
    ], await rootBundle.loadString('assets/licenses/OFL-Tinos.txt'));
  });
  runApp(TimerApp(controller: AppController(port)));
}

class TimerApp extends StatelessWidget {
  final AppController controller;
  const TimerApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      controller.themeSelection,
      controller.appearanceSelection,
    ]),
    builder: (context, _) => MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: controller.appearanceSelection.value.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      theme: appTheme(
        controller.themeSelection.value,
        appearance: controller.appearanceSelection.value,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final chosen = controller.appearanceSelection.value;
        final effective = chosen.copyWith(
          highContrast: chosen.highContrast || media.highContrast,
          reducedMotion: chosen.reducedMotion || media.disableAnimations,
        );
        return Theme(
          data: appTheme(
            controller.themeSelection.value,
            appearance: effective,
            size: media.size,
          ),
          child: MediaQuery(
            data: media.copyWith(disableAnimations: effective.reducedMotion),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => LedAppearance(
                shape: controller.ready
                    ? controller.state.pixelShape
                    : 'square',
                child: SignFit(
                  required: !controller.ready || controller.signFitRequired,
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
      home: Home(controller: controller),
    ),
  );
}

class Home extends StatefulWidget {
  final AppController controller;
  const Home({super.key, required this.controller});
  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> with WidgetsBindingObserver {
  AppController get c => widget.controller;
  int page = 0;
  QuickMessage quickDraft = const QuickMessage(body: '');
  bool quickDraftReviewed = false;
  int quickDraftGeneration = 0;
  String quickAudience = 'all';
  String? previewScreenId;
  void refreshHome(VoidCallback change) {
    final locked = c.uiLocked;
    setState(change);
    settingsRefresh.value++;
    // Unlocking the controls is coming back to standing by, for the
    // automatic update check.
    if (locked != c.uiLocked) c.autoUpdate.lockChanged();
  }

  bool focused = false, controlsLocked = false;

  /// The battery hint's × hides it until the app is next opened.
  bool batteryHintDismissed = false;

  /// Not now on the practice invitation hides it until the app is next
  /// opened; Don't show again hides it for good.
  bool practicePromptSnoozed = false;

  /// The program picked on the wide Live page before a service.
  String? standingByProgramId;
  final homeScroll = ScrollController();
  bool? _completedService;

  void _followServiceCompletion() {
    if (!c.ready) return;
    final completed = c.state.session.phase == 'ended' && !c.reportSavePending;
    final showWelcome = _completedService == false && completed && page == 0;
    _completedService = completed;
    if (!showWelcome || !mounted) return;
    setState(() => focused = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && homeScroll.hasClients) {
        if (reduceAppMotion(context)) {
          homeScroll.jumpTo(0);
          return;
        }
        homeScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void setFocused(bool value) => setState(() {
    focused = value;
    page = 0;
  });

  /// The window is the mini timer: small, above other programs, showing
  /// only the running segment (a computer only; see mini_timer.dart).
  bool miniTimer = false;
  bool _miniTimerChanging = false;

  /// Opens the mini timer or expands back to the full window. Opening
  /// needs a computer and nothing else open on top;
  /// otherwise nothing happens. Returns whether the mini timer is showing
  /// afterwards.
  Future<bool> setMiniTimer(bool value) async {
    final window = c.port.miniWindow;
    if (window == null || !mounted || _miniTimerChanging) return miniTimer;
    if (value == miniTimer) return miniTimer;
    if (value &&
        (!miniTimerAvailable || ModalRoute.of(context)?.isCurrent != true)) {
      return false;
    }
    _miniTimerChanging = true;
    try {
      if (value) {
        // The small layout first: it fits any window, the full one does
        // not fit a small window.
        setState(() {
          miniTimer = true;
          page = 0;
        });
        var entered = false;
        try {
          entered = await window.enter(
            width: miniTimerSize.width,
            height: miniTimerSize.height,
          );
        } catch (_) {}
        if (!entered && mounted) {
          setState(() => miniTimer = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The window could not be made small.'),
            ),
          );
        }
      } else {
        try {
          await window.leave();
        } catch (_) {}
        if (mounted) setState(() => miniTimer = false);
      }
    } finally {
      _miniTimerChanging = false;
      // The window changed under the keyboard: Ctrl may have been let go
      // in the other one.
      syncKeyboard();
    }
    // The service may have ended while the window was changing.
    if (mounted && miniTimer && !miniTimerAvailable) {
      return setMiniTimer(false);
    }
    return miniTimer;
  }

  /// Whether the service was running when [_followMiniTimer] last looked.
  bool _serviceWasActive = false;

  /// When the service the mini timer was showing ends (or this device
  /// joins another's), the full window comes back. Opened before a
  /// service, it stays.
  void _followMiniTimer() {
    final active = c.ready && c.liveSession.active;
    final ended = _serviceWasActive && !active;
    _serviceWasActive = active;
    if (miniTimer && (!miniTimerAvailable || ended)) {
      unawaited(setMiniTimer(false));
    }
  }

  /// The stage picture fills this screen (see host_full_screen.dart).
  final hostFullScreen = HostFullScreenState();

  final settingsRefresh = ValueNotifier<int>(0);

  final programsPage = ProgramsPageState();

  /// Keeps New program over the list column of the desktop Programs page.
  final programsButtonLocation = ListColumnButtonLocation();
  final reportsPage = ReportsPageState();
  bool practiceSummaryQueued = false;
  String settingsQuery = '';

  /// Bumped by the search field's clear button to rebuild it empty.
  int settingsSearchResets = 0;
  Offset? menuAnchor;
  void returnToLive() {
    navigatePage(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void selectReportFilter(String value) =>
      setState(() => reportsPage.filter = value);
  void selectReportView(String value) =>
      setState(() => reportsPage.view = value);

  /// Each tab's scroll position, restored when the tab is shown again.
  final tabScrollOffsets = <int, double>{};

  /// The side the current tab slid in from after a swipe; 0 when it was
  /// opened another way.
  int tabSlide = 0;

  void navigatePage(int value, {int slide = 0}) {
    if (value != page && homeScroll.hasClients) {
      tabScrollOffsets[page] = homeScroll.offset;
    }
    final changed = value != page;
    setState(() {
      page = value;
      tabSlide = slide;
    });
    if (!changed) return;
    // A page that fills the window always sits right under the header.
    final offset =
        liveFillsWindow ||
            programsFillWindow ||
            reportsFillWindow ||
            lyricsFillsWindow
        ? 0.0
        : tabScrollOffsets[value] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !homeScroll.hasClients || page != value) return;
      final position = homeScroll.position;
      homeScroll.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  /// Whether a swipe can move from this tab to the next (+1) or previous
  /// (-1) one. Live keeps a loaded or running service in view, so swiping
  /// away from it waits until the service is over; the bar still works.
  bool canSwipeTab(int direction) {
    final target = homePageAt(homePageSlot(page) + direction);
    return target != null &&
        c.ready &&
        !c.corrupt &&
        c.pairing.localControl &&
        !focused &&
        !controlsLocked &&
        !programsPage.selecting &&
        !reportsPage.selecting &&
        !(page == 0 && !liveStandingBy);
  }

  void swipeTab(int direction) => unawaited(
    goToPage(
      homePageAt(homePageSlot(page) + direction) ?? page,
      slide: direction,
    ),
  );
  DateTime? _clickerNextArmed;

  /// How long a key can be held before its repeats count as one press.
  /// Windows repeats a held key every 30 ms or so after about half a
  /// second; a repeat that comes after a longer silence is a new press
  /// whose key-down was lost.
  static const keyRepeatSilence = Duration(milliseconds: 900);

  /// The clock the silence is measured on; a test replaces it.
  @visibleForTesting
  Duration Function() keyClock = () => _wallClock.elapsed;
  static final _wallClock = Stopwatch()..start();
  final _lastKeyEvent = <LogicalKeyboardKey, Duration>{};

  /// Whether [event] is a new press of its key. A key-down is. A repeat is
  /// only when nothing was heard from that key for a while: on Windows a
  /// key-up can go missing (a window or the on-screen keyboard took it),
  /// and the engine then reports the next press as a repeat for good, so
  /// the shortcut would work only every other time.
  bool _isFreshPress(KeyEvent event) {
    final now = keyClock();
    final before = _lastKeyEvent[event.logicalKey];
    if (event is KeyUpEvent) {
      _lastKeyEvent.remove(event.logicalKey);
      return false;
    }
    _lastKeyEvent[event.logicalKey] = now;
    if (event is KeyDownEvent) return true;
    return before == null || now - before > keyRepeatSilence;
  }

  /// Puts the keyboard's record of which keys are down right again. A key
  /// released while another window had the keyboard (Alt+Tab, the mini
  /// timer, the second screen) never reaches this one, and Ctrl would stay
  /// held in the record.
  void syncKeyboard() {
    try {
      unawaited(
        HardwareKeyboard.instance.syncKeyboardState().catchError((_) {}),
      );
    } catch (_) {}
  }

  /// Whether the keyboard is typing into a text field just now.
  bool get typingInField {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Lock controls: every button and key is ignored until Hold to unlock.
  void lockControls() => refreshHome(() => c.uiLocked = controlsLocked = true);

  /// Presentation clickers and foot pedals: Next (pressed twice) and Pause.
  /// Ignored while typing, while a dialog or another page is on top, and
  /// whenever touch controls would be unavailable.
  bool onClickerKey(KeyEvent event) {
    if (!mounted || !c.ready) return false;
    if (!_isFreshPress(event)) return false;
    // The clicker test page only shows what a key would do: nothing
    // pressed there reaches the service.
    if (clickerTestOpen) return false;
    // F11 shows the stage full screen on this screen; F11 or Esc leaves.
    final fullScreen = fullScreenKey(event.logicalKey);
    if (fullScreen != null) return fullScreen;
    // Ctrl+K opens the command palette from any tab of the home screen.
    if (c.port.isDesktop &&
        isCommandPaletteKey(
          event.logicalKey,
          control: HardwareKeyboard.instance.isControlPressed,
        )) {
      // Ctrl+K means nothing to a text field, so a field that kept the
      // keyboard does not block it.
      if (!commandPaletteAvailable) return false;
      unawaited(openCommandPalette());
      return true;
    }
    // Ctrl+M shrinks the app to the mini timer and brings it back.
    if (c.port.isDesktop &&
        isMiniTimerKey(
          event.logicalKey,
          control: HardwareKeyboard.instance.isControlPressed,
        )) {
      if (controlsLocked) return false;
      if (!miniTimer && !miniTimerAvailable) return false;
      unawaited(setMiniTimer(!miniTimer));
      return true;
    }
    // ? or F1 lists the keys, from any tab of the home screen.
    if (c.port.isDesktop &&
        isShortcutsSheetKey(
          event.logicalKey,
          shift: HardwareKeyboard.instance.isShiftPressed,
          character: event.character,
        )) {
      if (!shortcutsSheetAvailable || typingInField) return false;
      unawaited(openShortcutsSheet());
      return true;
    }
    // The Lyrics page has keys of its own (→ Space next slide, ← back,
    // Esc clear, B black). Live's keys work only on Live, so the two never
    // clash.
    if (page == lyricsPage) return lyricsKey(event);
    // A PC keyboard adds its own keys on top of the clicker's; they open
    // the same confirmations as the buttons on screen. The clicker's keys
    // follow Clicker and foot pedal on every device: a computer cannot
    // tell a clicker from its keyboard, so switched off they do nothing
    // from either, and the other keys still work.
    final desktopAction = c.port.isDesktop
        ? desktopLiveActionFor(
            event.logicalKey,
            control: HardwareKeyboard.instance.isControlPressed,
          )
        : null;
    final action = c.state.clickerControls
        ? clickerActionFor(event.logicalKey)
        : null;
    final cueIndex = c.port.isDesktop
        ? desktopCueIndexFor(
            event.logicalKey,
            control: HardwareKeyboard.instance.isControlPressed,
          )
        : null;
    if (action == null && desktopAction == null && cueIndex == null)
      return false;
    if (typingInField) return false;
    if (page != 0 || ModalRoute.of(context)?.isCurrent != true) return false;
    final s = c.state.session;
    if (!s.active ||
        c.busy ||
        c.corrupt ||
        controlsLocked ||
        c.reportSavePending ||
        !c.pairing.localControl)
      return false;
    final messenger = ScaffoldMessenger.of(context);
    if (cueIndex != null) {
      // The same as tapping the cue's button: send it, or, if it is the
      // one showing, go back to the timer.
      if (cueIndex >= c.state.stageCues.length ||
          !outputControlsEnabled ||
          c.hardware.sending)
        return false;
      final cue = c.state.stageCues[cueIndex];
      final showing =
          !s.outputBlank &&
          s.hasManualCue(c.now) &&
          !s.alertIsMessage &&
          s.alert!.text == cue.text;
      unawaited(showing ? c.act('clearCue') : sendPreparedCue(cue));
      return true;
    }
    if (desktopAction == DesktopLiveAction.adjustTime) {
      unawaited(adjustTime());
      return true;
    }
    if (desktopAction == DesktopLiveAction.undo) {
      if (s.undo == null) return false;
      unawaited(undo());
      return true;
    }
    if (desktopAction == DesktopLiveAction.lock) {
      // Locks only: unlocking stays Hold to unlock, and a locked window
      // never reaches this line.
      lockControls();
      return true;
    }
    if (desktopAction == DesktopLiveAction.message) {
      if (!outputControlsEnabled) return false;
      unawaited(sendStageMessage());
      return true;
    }
    if (desktopAction == DesktopLiveAction.editUpcoming) {
      unawaited(editUpcoming());
      return true;
    }
    if (desktopAction == DesktopLiveAction.recoverTime) {
      unawaited(recoverTime());
      return true;
    }
    if (desktopAction == DesktopLiveAction.jump) {
      if (s.index + 1 >= s.timeline!.segments.length) return false;
      unawaited(jumpToSegment());
      return true;
    }
    if (action == ClickerAction.pause) {
      _clickerNextArmed = null;
      // On a computer Space asks first, like the Pause button; a second
      // Space or Enter confirms. A clicker or pedal on a phone has no
      // screen in the hand to confirm on, so it pauses at once.
      unawaited(
        c.port.isDesktop
            ? confirmPause()
            : c.act('pause', revision: s.revision),
      );
      return true;
    }
    final t = s.timeline!;
    if (s.index + 1 >= t.segments.length) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Final segment · end the service on screen'),
        ),
      );
      return true;
    }
    final now = DateTime.now();
    final armed = _clickerNextArmed;
    if (armed != null && now.difference(armed) <= clickerConfirmWindow) {
      _clickerNextArmed = null;
      messenger.hideCurrentSnackBar();
      unawaited(c.act('advance', revision: s.revision));
      return true;
    }
    _clickerNextArmed = now;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('clicker-confirm'),
        duration: clickerConfirmWindow,
        content: Text('Press again to start ${t.segments[s.index + 1].name}'),
      ),
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _followServiceCompletion();
    c.addListener(_followServiceCompletion);
    c.addListener(_followMiniTimer);
    _serviceWasActive = c.ready && c.liveSession.active;
    c.liveNavigation.addListener(returnToLive);
    HardwareKeyboard.instance.addHandler(onClickerKey);
    c.port.setIncomingFileHandler(receiveIncomingFile);
    c.port.setFileDropHandler(receiveDroppedFiles);
    if (c.port.isDesktop) {
      _windowClose = AppLifecycleListener(onExitRequested: confirmWindowClose);
    }
    // A stage request: a short vibration and a note that opens Live,
    // where the request waits with its buttons.
    c.stageRequests.onRequest = (request) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('stage-request-note'),
          content: Text('${request.label} · ${request.screenName}'),
          action: page == 0
              ? null
              : SnackBarAction(label: 'View', onPressed: () => goToPage(0)),
          duration: const Duration(seconds: 6),
        ),
      );
    };
    c.onWebJoined = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('web-joined'),
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
    };
    if (!c.ready) {
      c.initialize().then((_) => receiveIncomingFile()).catchError((Object e) {
        if (mounted)
          showError(
            c.port.isDesktop
                ? 'Could not start the app: $e'
                : 'Could not start Android services: $e',
          );
      });
    } else {
      unawaited(receiveIncomingFile());
    }
  }

  /// Opens a program file received through "Open with" or Share in the
  /// same import review as Import from file.
  Future<void> receiveIncomingFile() async {
    if (!c.ready || !mounted) return;
    final Map<String, dynamic>? file;
    try {
      file = await c.port.takeIncomingFile();
    } catch (e) {
      if (mounted) await showError('Could not open the received file: $e');
      return;
    }
    if (file == null || !mounted) return;
    // The import review needs the full window.
    if (miniTimer && await setMiniTimer(false)) return;
    if (hostFullScreen.showing && await setHostFullScreen(false)) return;
    if (mounted) await importFile(received: file);
  }

  /// A file dropped on the window is opened exactly as "Open with" opens
  /// it, in the same import review. Nothing else is accepted, and nothing
  /// at all while a service runs or the controls are locked.
  void receiveDroppedFiles(List<String> paths) {
    if (!c.ready || !mounted || paths.isEmpty) return;
    final path = droppedProgramFile(paths);
    final refusal = path == null
        ? dropOneProgramFile
        : c.liveSession.active
        ? 'A service is running. End it before you import a program.'
        : controlsLocked
        ? 'Controls are locked. Unlock them before you import a program.'
        : null;
    if (path != null && refusal == null) return c.port.offerIncomingFile(path);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('drop-refused'),
          content: Text(refusal ?? dropOneProgramFile),
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(onClickerKey);
    c.port.setIncomingFileHandler(null);
    c.port.setFileDropHandler(null);
    _windowClose?.dispose();
    c.removeListener(_followServiceCompletion);
    c.removeListener(_followMiniTimer);
    c.liveNavigation.removeListener(returnToLive);
    homeScroll.dispose();
    settingsRefresh.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Whatever happened to the keys while another window had the
    // keyboard, the record is right again before the next press.
    if (c.port.isDesktop) syncKeyboard();
    if (c.port.isDesktop) {
      // A desktop app keeps running when its window is minimised or
      // behind another, so the service is never suspended; only Settings
      // locks again when the window is put away.
      if (state == AppLifecycleState.hidden) c.lockSettings();
      return;
    }
    if (state == AppLifecycleState.paused) {
      c.lockSettings();
      c.suspend();
    }
    if (state == AppLifecycleState.resumed) {
      c.resume();
      if (page == 3 && c.settingsLocked && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        navigatePage(0);
      }
    }
  }

  Future<void> showError(String message) => compactQuestions
      ? miniError(message)
      : showDialog<void>(
          context: context,
          animationStyle: reduceAppMotion(context)
              ? AnimationStyle.noAnimation
              : null,
          builder: (context) => AlertDialog(
            title: const Text('Please review'),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
  Future<bool> confirm(
    String title,
    String body,
    String button, {
    bool destructive = false,
  }) async =>
      // A dialog does not fit the mini timer window; the same question is
      // asked in a compact form there, and over the stage in full screen.
      compactQuestions
      ? miniConfirm(
          title: title,
          action: button,
          destructive: destructive,
          content: () => Text(body),
        )
      : await showDialog<bool>(
              context: context,
              animationStyle: reduceAppMotion(context)
                  ? AnimationStyle.noAnimation
                  : null,
              builder: (context) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(child: Text(body)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('confirm-action'),
                    onPressed: () => Navigator.pop(context, true),
                    style: destructive ? destructiveFilled() : null,
                    child: Text(button),
                  ),
                ],
              ),
            ) ??
            false;

  void handleBack() {
    if (programsPage.selecting || reportsPage.selecting) {
      refreshHome(() {
        programsPage.selecting = false;
        reportsPage.selecting = false;
        programsPage.selected.clear();
        reportsPage.selected.clear();
      });
      return;
    }
    if (page == 0 &&
        c.ready &&
        c.state.session.phase == 'ready' &&
        c.pairing.localControl &&
        !controlsLocked) {
      if (!c.busy) unawaited(c.act('cancelReady'));
      return;
    }
    if (page != 0) {
      navigatePage(0);
      return;
    }
    unawaited(confirmExit());
  }

  /// Closing the window ends the app on a PC, so a running service asks
  /// first. Called by the system when the window's close button is used.
  Future<AppExitResponse> confirmWindowClose() async {
    final response = await _confirmWindowClose();
    // The icon in the notification area goes with the window.
    if (response == AppExitResponse.exit) {
      try {
        await c.port.windowClosing();
      } catch (_) {}
    }
    return response;
  }

  Future<AppExitResponse> _confirmWindowClose() async {
    if (!c.ready || !c.liveSession.active || !mounted) {
      return AppExitResponse.exit;
    }
    if (_closeDialogOpen) return AppExitResponse.cancel;
    _closeDialogOpen = true;
    try {
      return await confirm(
            'Close during the service?',
            'A service is running. Closing the app stops the timer on stage screens and the LED sign, and stops warnings. The service is saved, and opening the app again carries on from the clock.',
            'Close the app',
            destructive: true,
          )
          ? AppExitResponse.exit
          : AppExitResponse.cancel;
    } finally {
      _closeDialogOpen = false;
    }
  }

  bool _closeDialogOpen = false;
  AppLifecycleListener? _windowClose;

  bool _exitArmed = false;
  static const exitConfirmWindow = Duration(seconds: 2);

  /// Back on the Live tab asks for a second press while the hint is shown,
  /// or during a service for confirmation, so a stray gesture does not
  /// close the app.
  Future<void> confirmExit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (c.ready && c.liveSession.active) {
      messenger.hideCurrentSnackBar();
      if (await confirm(
        'Leave the app?',
        'A service is running. The timer, the display and warnings keep running in the background; open the app again to control it.',
        'Leave',
      ))
        await SystemNavigator.pop();
      return;
    }
    if (_exitArmed) {
      _exitArmed = false;
      messenger.hideCurrentSnackBar();
      await SystemNavigator.pop();
      return;
    }
    messenger.hideCurrentSnackBar();
    _exitArmed = true;
    messenger
        .showSnackBar(
          const SnackBar(
            key: ValueKey('exit-confirm'),
            duration: exitConfirmWindow,
            persist: false,
            content: Text('Press Back again to exit'),
          ),
        )
        .closed
        .then((_) => _exitArmed = false);
  }

  double headerHeight(BuildContext context) => math.max(
    76,
    MediaQuery.textScalerOf(context).scale(18) * 2.4 +
        ((c.ready ? c.state.churchName : c.loadingChurchName).isNotEmpty
            ? MediaQuery.textScalerOf(context).scale(12) * 1.3
            : 0) +
        8,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => c.pairing.joined
        ? PairedScreen(controller: c)
        : miniTimer
        ? miniTimerView()
        : hostFullScreen.showing
        ? hostFullScreenView()
        : PopScope(
            // Android Back leaves selection mode, cancels a service that is
            // loaded but not started, returns to Live, and only then asks
            // for a second press before leaving the app.
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) handleBack();
            },
            child: Scaffold(
              body: navigationShell(
                TabSwipeDetector(
                  canSwipe: canSwipeTab,
                  onSwipe: swipeTab,
                  touchOnly: c.port.isDesktop,
                  child: Listener(
                    onPointerDown: (e) => menuAnchor = e.position,
                    child: CustomScrollView(
                      controller: homeScroll,
                      // A page that fills the window scrolls in its own
                      // panes, never under the header.
                      physics:
                          liveFillsWindow ||
                              programsFillWindow ||
                              reportsFillWindow ||
                              lyricsFillsWindow
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      slivers: [
                        SliverAppBar(
                          bottom: c.ready && page != 0 && c.liveSession.active
                              ? RunningServiceBar.forContext(
                                  context,
                                  controller: c,
                                )
                              : null,
                          pinned: true,
                          clipBehavior: Clip.antiAlias,
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          // Square in a desktop layout, where panes meet
                          // the header edge to edge.
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(squareHeader ? 0 : 26),
                            ),
                            side: squareHeader
                                ? BorderSide(color: appColors(context).border)
                                : BorderSide.none,
                          ),
                          // A finish makes the header a plate of its
                          // material (with no backdrop blur, which would
                          // cost a pass every frame); Flat keeps the
                          // frosted bar it always had.
                          flexibleSpace:
                              finishBar(
                                context,
                                corners: BorderRadius.vertical(
                                  bottom: Radius.circular(
                                    squareHeader ? 0 : 26,
                                  ),
                                ),
                              ) ??
                              ClipRRect(
                                borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(
                                    squareHeader ? 0 : 26,
                                  ),
                                ),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 8,
                                    sigmaY: 8,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.alphaBlend(
                                            appColors(
                                              context,
                                            ).accent.withValues(alpha: .04),
                                            appColors(context).surface,
                                          ).withValues(
                                            alpha:
                                                appColors(context).highContrast
                                                ? 1
                                                : .84,
                                          ),
                                          appColors(context).surface.withValues(
                                            alpha:
                                                appColors(context).highContrast
                                                ? 1
                                                : .92,
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                          actions: [
                            if (c.ready)
                              UnavailableAction(
                                reason: controlsLocked
                                    ? 'Unlock the controls to change the display.'
                                    : !c.pairing.localControl
                                    ? 'Take back control to change the display.'
                                    : null,
                                child: HeaderDisplayChip(
                                  key: const ValueKey('header-connection'),
                                  connection: c.displayConnection,
                                  label: headerDisplayLabel(),
                                  reconnecting: displayReconnecting,
                                  onPressed:
                                      (controlsLocked ||
                                          !c.pairing.localControl)
                                      ? null
                                      : chooseDisplay,
                                ),
                              ),
                            // The mini timer was only in the menu and by
                            // Ctrl+M, where it was easy never to find. On a
                            // computer it is on every page, service or not.
                            if (miniTimerAvailable && !miniTimer)
                              IconButton(
                                key: const ValueKey('mini-timer-button'),
                                tooltip: showKeyHints
                                    ? 'Mini timer: a small window that stays on top (Ctrl+M)'
                                    : 'Mini timer: a small window that stays on top',
                                onPressed: controlsLocked
                                    ? null
                                    : () => unawaited(setMiniTimer(true)),
                                icon: const Icon(
                                  Icons.picture_in_picture_alt_outlined,
                                ),
                              ),
                            // The stage on this screen, for when it is the
                            // one people watch. A narrow screen has the
                            // button under the stage preview instead.
                            if (page == 0 && fullScreenInHeader)
                              IconButton(
                                key: const ValueKey('full-screen-button'),
                                tooltip: showKeyHints
                                    ? 'Full screen: show the stage on this screen (F11)'
                                    : 'Full screen: show the stage on this screen',
                                onPressed: controlsLocked
                                    ? null
                                    : () => unawaited(setHostFullScreen(true)),
                                icon: const Icon(Icons.fullscreen),
                              ),
                            if (c.ready && page == 0 && liveFillsWindow)
                              lyricsHeaderButton(),
                            if (c.ready && page == 0 && c.liveSession.active)
                              IconButton(
                                key: const ValueKey('control-lock'),
                                tooltip: controlsLocked
                                    ? 'Controls locked'
                                    : 'Lock controls',
                                onPressed: controlsLocked ? null : lockControls,
                                icon: Icon(
                                  controlsLocked ? Icons.lock : Icons.lock_open,
                                ),
                              ),
                            if (c.ready && page == 0) liveMenu(),
                            // Without the Live menu, the chip needs its own
                            // margin so it does not touch the screen edge.
                            SizedBox(width: c.ready && page == 0 ? 4 : 16),
                          ],
                          toolbarHeight: headerHeight(context),
                          title: Row(
                            children: [
                              // Tap the mark to open Church profile, where the
                              // logo, name and banner are set.
                              Tooltip(
                                message: 'Church profile',
                                child: InkWell(
                                  key: const ValueKey('header-logo'),
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: !c.ready || controlsLocked
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ChurchProfilePage(
                                              controller: c,
                                            ),
                                          ),
                                        ),
                                  child: ChurchTimerMark(
                                    logo: c.ready ? c.state.churchLogo : '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                flex: useTopTabs ? 0 : 1,
                                fit: useTopTabs ? FlexFit.loose : FlexFit.tight,
                                child: headerName(),
                              ),
                              // A desktop layout keeps the tabs in the
                              // header, where a rail would cost a pane.
                              if (useTopTabs) ...[
                                const SizedBox(width: 28),
                                desktopTabs(),
                                const Spacer(),
                              ],
                            ],
                          ),
                        ),
                        if (!c.ready)
                          SliverFillRemaining(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const ChurchTimerMark(size: 84),
                                    const SizedBox(height: 20),
                                    const Text(
                                      appName,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (c.loadingChurchName.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          c.loadingChurchName,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    const SizedBox(height: 24),
                                    const CircularProgressIndicator(),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else if (liveFillsWindow ||
                            programsFillWindow ||
                            reportsFillWindow ||
                            lyricsFillsWindow)
                          SliverFillRemaining(
                            child: SafeArea(
                              top: false,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (homeNotices().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: homeNotices(),
                                      ),
                                    ),
                                  Expanded(
                                    child: AbsorbPointer(
                                      absorbing:
                                          c.corrupt || !c.pairing.localControl,
                                      child: page == 1
                                          ? programsDesktop()
                                          : page == 2
                                          ? reportsDesktop()
                                          : page == lyricsPage
                                          ? lyricsPanel()
                                          : live(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverToBoxAdapter(
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                // During a service, room below End service for
                                // the short notes at the bottom of the screen.
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  page == 0 && c.liveSession.active ? 96 : 32,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: page == 0
                                          ? classicLiveWidth
                                          : 1200,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ...homeNotices(),
                                        AbsorbPointer(
                                          absorbing:
                                              c.corrupt ||
                                              !c.pairing.localControl,
                                          child: TabSlideIn(
                                            key: ValueKey('tab-$page'),
                                            direction: tabSlide,
                                            reduceMotion: reduceAppMotion(
                                              context,
                                            ),
                                            child: page == 0
                                                ? live()
                                                : page == 1
                                                ? programsResponsive()
                                                : page == 2
                                                ? reportsResponsive()
                                                : settingsHub(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              floatingActionButton:
                  c.ready &&
                      page == 1 &&
                      !focused &&
                      !programsPage.selecting &&
                      !controlsLocked
                  ? FloatingActionButton.extended(
                      key: const ValueKey('new-template'),
                      // A soft shadow, not a dark halo around the button.
                      elevation: 2,
                      highlightElevation: 4,
                      backgroundColor: appColors(context).accent,
                      foregroundColor: appColors(context).background,
                      onPressed: c.busy || c.corrupt
                          ? null
                          : () async {
                              await editTemplate();
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('New program'),
                    )
                  : null,
              // The desktop Programs page keeps it over the list column,
              // clear of the table and the summary.
              floatingActionButtonLocation: programsFillWindow
                  ? programsButtonLocation
                  : null,
              // Opening Programs changes the location as the button
              // appears; animating that move showed it first at the right
              // edge, over the summary, before it jumped to the list.
              floatingActionButtonAnimator:
                  FloatingActionButtonAnimator.noAnimation,
              bottomNavigationBar:
                  !focused &&
                      ((page == 1 && programsPage.selecting) ||
                          (page == 2 && reportsPage.selecting))
                  ? selectionActionBar(programs: page == 1)
                  : focused
                  ? SafeArea(
                      top: false,
                      child: TextButton.icon(
                        onPressed: () => setFocused(false),
                        icon: const Icon(Icons.fullscreen_exit),
                        label: const Text('Exit focused view'),
                      ),
                    )
                  : useNavigationRail || useTopTabs
                  ? null
                  : finishNavigationBar(
                      context,
                      NavigationBar(
                        selectedIndex: homePageSlot(page),
                        onDestinationSelected: (v) {
                          if (!controlsLocked) goToPage(homePageOrder[v].page);
                        },
                        destinations: [
                          for (final p in homePageOrder)
                            NavigationDestination(
                              icon: Icon(p.icon),
                              label: p.name,
                            ),
                        ],
                      ),
                    ),
            ),
          ),
  );
}
