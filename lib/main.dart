import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/list_views.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/app/platform.dart';

import 'package:church_service_timer/settings/settings_views.dart';
import 'package:church_service_timer/pairing/pairing_views.dart';
import 'package:church_service_timer/pairing/stage_screen_views.dart';
import 'package:church_service_timer/live/live_layout_views.dart';
import 'package:church_service_timer/programs/program_library_views.dart';
import 'package:church_service_timer/settings/settings_pin_views.dart';
import 'package:church_service_timer/live/clicker_controls.dart';
import 'package:church_service_timer/programs/programs_page_state.dart';
import 'package:church_service_timer/reports/reports_page_state.dart';
import 'package:church_service_timer/programs/program_edit_actions.dart';
import 'package:church_service_timer/shared/home_widgets.dart';
import 'package:church_service_timer/live/live_page.dart';
import 'package:church_service_timer/reports/report_library_views.dart';

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
export 'package:church_service_timer/reports/report_actions.dart';
export 'package:church_service_timer/reports/report_library_views.dart';
export 'package:church_service_timer/reports/timing_insights_views.dart';
export 'package:church_service_timer/settings/clock_settings_views.dart';
export 'package:church_service_timer/settings/settings_search_views.dart';
export 'package:church_service_timer/settings/warning_settings_views.dart';
export 'package:church_service_timer/shared/format_labels.dart';
export 'package:church_service_timer/shared/item_menu_views.dart';
export 'package:church_service_timer/shared/selection_views.dart';
export 'package:church_service_timer/shared/undo_actions.dart';
export 'package:church_service_timer/live/live_actions.dart';
export 'package:church_service_timer/programs/program_edit_actions.dart';
export 'package:church_service_timer/shared/home_widgets.dart';
export 'package:church_service_timer/live/live_page.dart';
export 'package:church_service_timer/live/text_composer.dart';
export 'package:church_service_timer/programs/template_editor.dart';
export 'package:church_service_timer/live/control_grid.dart';

String styleSummary(TextLayout l) =>
    '${l.text} · ${displayFontNames[l.font]} · ${l.bold ? 'bold · ' : ''}${l.italic ? 'italic · ' : ''}${l.height * 7}\u00a0px · ${l.align} · ${l.effect}${l.effect == 'scroll' ? ' ${l.speed}\u00a0px/s' : ''}';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tinos',
    ], await rootBundle.loadString('assets/licenses/OFL-Tinos.txt'));
  });
  runApp(TimerApp(controller: AppController(AndroidPort())));
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
                child: child!,
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
    setState(change);
    settingsRefresh.value++;
  }

  bool focused = false, controlsLocked = false;

  /// The battery hint's × hides it until the app is next opened.
  bool batteryHintDismissed = false;

  /// Not now on the practice invitation hides it until the app is next
  /// opened; Don't show again hides it for good.
  bool practicePromptSnoozed = false;
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
  final settingsRefresh = ValueNotifier<int>(0);

  final programsPage = ProgramsPageState();
  final reportsPage = ReportsPageState();
  bool practiceSummaryQueued = false;
  String settingsQuery = '';
  Offset? menuAnchor;
  void returnToLive() {
    navigatePage(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void selectReportFilter(String value) =>
      setState(() => reportsPage.filter = value);
  void selectReportView(String value) =>
      setState(() => reportsPage.view = value);
  void navigatePage(int value) => setState(() => page = value);
  DateTime? _clickerNextArmed;

  /// Presentation clickers and foot pedals: Next (pressed twice) and Pause.
  /// Ignored while typing, while a dialog or another page is on top, and
  /// whenever touch controls would be unavailable.
  bool onClickerKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || !c.ready) return false;
    final action = clickerActionFor(event.logicalKey);
    if (action == null || !c.state.clickerControls) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null))
      return false;
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
    if (action == ClickerAction.pause) {
      _clickerNextArmed = null;
      unawaited(c.act('pause', revision: s.revision));
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
    c.liveNavigation.addListener(returnToLive);
    HardwareKeyboard.instance.addHandler(onClickerKey);
    c.port.setIncomingFileHandler(receiveIncomingFile);
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
        if (mounted) showError('Could not initialize Android services: $e');
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
    if (file != null && mounted) await importFile(received: file);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(onClickerKey);
    c.port.setIncomingFileHandler(null);
    c.removeListener(_followServiceCompletion);
    c.liveNavigation.removeListener(returnToLive);
    homeScroll.dispose();
    settingsRefresh.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

  Future<void> showError(String message) => showDialog<void>(
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
      await showDialog<bool>(
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
                Listener(
                  onPointerDown: (e) => menuAnchor = e.position,
                  child: CustomScrollView(
                    controller: homeScroll,
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
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(26),
                          ),
                        ),
                        flexibleSpace: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(26),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
                                      alpha: appColors(context).highContrast
                                          ? 1
                                          : .84,
                                    ),
                                    appColors(context).surface.withValues(
                                      alpha: appColors(context).highContrast
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
                                    (controlsLocked || !c.pairing.localControl)
                                    ? null
                                    : chooseDisplay,
                              ),
                            ),
                          if (c.ready && page == 0 && c.liveSession.active)
                            IconButton(
                              key: const ValueKey('control-lock'),
                              tooltip: controlsLocked
                                  ? 'Controls locked'
                                  : 'Lock controls',
                              onPressed: controlsLocked
                                  ? null
                                  : () => setState(
                                      () => c.uiLocked = controlsLocked = true,
                                    ),
                              icon: Icon(
                                controlsLocked ? Icons.lock : Icons.lock_open,
                              ),
                            ),
                          if (c.ready && page == 0) liveMenu(),
                          const SizedBox(width: 4),
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
                                          builder: (_) =>
                                              ChurchProfilePage(controller: c),
                                        ),
                                      ),
                                child: ChurchTimerMark(
                                  logo: c.ready ? c.state.churchLogo : '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // One line beside the display chip; a
                                  // long name ends in "…" and shows in
                                  // full on long-press.
                                  Tooltip(
                                    message: headerTitle(),
                                    child: Text(
                                      headerTitle(),
                                      key: const ValueKey('header-title'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (headerSubtitle().isNotEmpty)
                                    Tooltip(
                                      message: headerSubtitle(),
                                      child: Text(
                                        headerSubtitle(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: appColors(context).muted,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
                                  constraints: const BoxConstraints(
                                    maxWidth: 1200,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (c.pairing.hosting)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: panel(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  c.pairing.localControl
                                                      ? 'This phone controls the service · ${c.pairing.peers.where((p) => p.approved).length} paired devices${c.webStage.activeDevices.isEmpty ? '' : ' · ${c.webStage.activeDevices.length} web screens'}'
                                                      : 'Control is with a paired operator. This phone remains the service host.',
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      openSettingsDetail(
                                                        'Screens & devices',
                                                        pairedDeviceSettings,
                                                      ),
                                                  child: const Text(
                                                    'Manage devices and control',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (c.backgroundError != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          // In a card with an icon, like the
                                          // other notices, not loose text.
                                          child: panel(
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: appColors(
                                                    context,
                                                  ).error,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    c.backgroundError!,
                                                    style: TextStyle(
                                                      color: appColors(
                                                        context,
                                                      ).error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (c.error != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          child: panel(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  c.error!,
                                                  style: TextStyle(
                                                    color: appColors(
                                                      context,
                                                    ).warning,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                if (c.retry == null &&
                                                    !c.corrupt)
                                                  TextButton(
                                                    key: const ValueKey(
                                                      'dismiss-error',
                                                    ),
                                                    onPressed: c.dismissError,
                                                    child: const Text(
                                                      'Dismiss',
                                                    ),
                                                  ),
                                                if (c.retry != null)
                                                  TextButton(
                                                    onPressed: c.busy
                                                        ? null
                                                        : () => c.retry!(),
                                                    child: Text(
                                                      c.reportSavePending
                                                          ? 'Retry saving report'
                                                          : 'Retry failed action',
                                                    ),
                                                  ),
                                                if (c.corrupt)
                                                  TextButton(
                                                    onPressed: () async {
                                                      if (await confirm(
                                                        'Reset local state?',
                                                        'This replaces unreadable local service and program data with starter programs. No physical display is connected.',
                                                        'Reset local data',
                                                        destructive: true,
                                                      ))
                                                        await c.resetCorrupt();
                                                    },
                                                    child: const Text(
                                                      'Reset local data…',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      AbsorbPointer(
                                        absorbing:
                                            c.corrupt ||
                                            !c.pairing.localControl,
                                        child: page == 0
                                            ? live()
                                            : page == 1
                                            ? programsResponsive()
                                            : page == 2
                                            ? reportsResponsive()
                                            : settingsHub(),
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
              floatingActionButton:
                  c.ready &&
                      page == 1 &&
                      !focused &&
                      !programsPage.selecting &&
                      !controlsLocked
                  ? FloatingActionButton.extended(
                      key: const ValueKey('new-template'),
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
                  : useNavigationRail
                  ? null
                  : NavigationBar(
                      selectedIndex: page,
                      onDestinationSelected: (v) {
                        if (!controlsLocked) goToPage(v);
                      },
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.radio_button_checked),
                          label: 'Live',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.view_timeline_outlined),
                          label: 'Programs',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.assessment_outlined),
                          label: 'Reports',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          label: 'Settings',
                        ),
                      ],
                    ),
            ),
          ),
  );
}
