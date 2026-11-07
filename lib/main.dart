import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/list_views.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/undo_actions.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/hardware/display_connection.dart';

import 'package:church_service_timer/reports/report_views.dart';
import 'package:church_service_timer/live/live_timer_views.dart';
import 'package:church_service_timer/settings/settings_views.dart';
import 'package:church_service_timer/settings/diagnostics_views.dart';
import 'package:church_service_timer/settings/display_settings_views.dart';
import 'package:church_service_timer/hardware/hardware_views.dart';
import 'package:church_service_timer/settings/stage_cue_settings_views.dart';
import 'package:church_service_timer/live/planning_views.dart';
import 'package:church_service_timer/pairing/pairing_views.dart';
import 'package:church_service_timer/pairing/stage_screen_views.dart';
import 'package:church_service_timer/live/live_layout_views.dart';
import 'package:church_service_timer/live/stage_output_views.dart';
import 'package:church_service_timer/live/time_recovery_views.dart';
import 'package:church_service_timer/live/timing_overview_views.dart';
import 'package:church_service_timer/programs/program_editor_insights.dart';
import 'package:church_service_timer/programs/program_import_export_views.dart';
import 'package:church_service_timer/programs/segment_library_views.dart';
import 'package:church_service_timer/programs/import_mapping_views.dart';
import 'package:church_service_timer/programs/program_library_views.dart';
import 'package:church_service_timer/settings/settings_pin_views.dart';
import 'package:church_service_timer/live/clicker_controls.dart';
import 'package:church_service_timer/programs/program_views.dart'
    show templateSummary;
import 'package:church_service_timer/reports/report_library_views.dart';
import 'package:church_service_timer/shared/format_labels.dart';

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

String styleSummary(TextLayout l) =>
    '${l.text} · ${displayFontNames[l.font]} · ${l.bold ? 'bold · ' : ''}${l.italic ? 'italic · ' : ''}${l.height * 7}px · ${l.align} · ${l.effect}${l.effect == 'scroll' ? ' ${l.speed}px/s' : ''}';

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

  String reportFilter = 'all', reportView = 'list';
  bool selectingPrograms = false, selectingReports = false;

  /// The report tapped in the Reports graph, shown in a card below it.
  String? graphReport;
  final selectedProgramExports = <String>{}, selectedReportExports = <String>{};
  String reportQuery = '',
      programQuery = '',
      programFilter = 'all',
      settingsQuery = '';
  DateTimeRange? reportDates;
  String? selectedProgram, selectedReport;
  Offset? menuAnchor;
  void returnToLive() {
    navigatePage(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void selectReportFilter(String value) => setState(() => reportFilter = value);
  void selectReportView(String value) => setState(() => reportView = value);
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
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xffa73238),
                      foregroundColor: Colors.white,
                    )
                  : null,
              child: Text(button),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> chooseService() async {
    final picked = await showAppSelection<Timeline>(
      context,
      title: 'Start a service',
      builder: (ctx) => ProgramChooser(
        controller: c,
        onCreate: () async {
          Navigator.pop(ctx);
          await editTemplate();
          if (mounted) await chooseService();
        },
      ),
    );
    if (!mounted || picked == null) return;
    try {
      c.state.templateIndex(picked);
      await c.act('load', value: picked);
    } catch (e) {
      if (mounted) await showError('$e');
    }
  }

  /// Swaps the program in Ready for another, keeping the start time and
  /// service mode, with a short Undo for a wrong tap.
  Future<void> changeProgram() async {
    final previous = c.state.session.timeline;
    if (previous == null || c.state.session.phase != 'ready') return;
    final picked = await showAppSelection<Timeline>(
      context,
      title: 'Change program',
      builder: (ctx) => ProgramChooser(
        controller: c,
        current: previous.name,
        onCreate: () async {
          Navigator.pop(ctx);
          await editTemplate();
          if (mounted) await changeProgram();
        },
      ),
    );
    if (!mounted || picked == null || picked.name == previous.name) return;
    try {
      c.state.templateIndex(picked);
      if (!await c.act('load', value: picked)) {
        if (mounted) await showError(c.error ?? 'Could not change program.');
        return;
      }
    } catch (e) {
      if (mounted) await showError('$e');
      return;
    }
    if (mounted)
      offerUndo('Switched to ${picked.name}', () async {
        // Nothing to undo once the service started or the setup was cancelled.
        if (c.state.session.phase != 'ready') return true;
        return c.act('load', value: previous);
      });
  }

  /// The loaded program's name with a one-tap way to switch it.
  Widget readyProgramRow(Timeline t) => Row(
    key: const ValueKey('ready-program'),
    children: [
      Icon(Icons.event_note_outlined, color: appColors(context).muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          t.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      TextButton.icon(
        key: const ValueKey('change-program'),
        onPressed:
            c.busy || controlsLocked || !c.pairing.localControl || c.corrupt
            ? null
            : changeProgram,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Change'),
      ),
    ],
  );

  /// Starting while the pre-service countdown is still running asks first.
  Future<bool> confirmEarlyStart() async {
    final at = c.state.session.startsAtWall;
    if (at == null) return true;
    final left = at - c.now.wall;
    if (left <= 0) return true;
    final wait = left >= 3600000
        ? '${left ~/ 3600000} h ${(left % 3600000) ~/ 60000} min'
        : formatTime(left);
    final start = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('early-start'),
        title: Text('The service is scheduled for ${wallTime(at)}'),
        content: Text(
          'That is $wait from now. Start now? The countdown on the display stops and the first segment begins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start now'),
          ),
        ],
      ),
    );
    return start == true;
  }

  Future<void> startFirst() async {
    if (!await confirmEarlyStart() || !mounted) return;
    final s = c.state.session, revision = c.state.session.revision;
    final problems = readinessChecks()
        .where((x) => !x.ok && x.key != 'program')
        .toList();
    if (c.destinationConnected && problems.isEmpty) {
      await startWithUndo(revision);
      return;
    }
    final start = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AnimatedBuilder(
        animation: c,
        builder: (ctx, _) {
          final colors = appColors(ctx);
          return AlertDialog(
            title: Text(
              !c.destinationConnected
                  ? 'No display connected'
                  : problems.length == 1
                  ? problems.single.detail
                  : '${plural(problems.length, 'thing')} to check',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You can still start ${s.timeline!.segments.first.name}.',
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(connectionIcon(c.displayConnection)),
                  title: Text('Display: ${c.destinationName}'),
                  subtitle: Text(c.displayConnection.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(ctx, false);
                    await chooseDisplay();
                  },
                ),
                for (final p in problems)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.priority_high, color: colors.warning),
                    title: Text(p.title),
                    subtitle: Text(p.detail),
                    trailing: p.fix == null
                        ? null
                        : TextButton(
                            onPressed: () async {
                              Navigator.pop(ctx, false);
                              await p.onFix?.call();
                            },
                            child: Text(p.fix!),
                          ),
                  ),
                if (s.rehearsal) Text('Rehearsal · ${s.rate}× speed'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              if (!c.destinationConnected)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx, false);
                    await chooseDisplay();
                  },
                  child: const Text('Connect display'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  c.destinationConnected
                      ? 'Start first segment'
                      : 'Start without a display',
                ),
              ),
            ],
          );
        },
      ),
    );
    if (start == true) await startWithUndo(revision);
  }

  /// Starts the loaded service and offers a short Undo for accidental taps.
  Future<void> startWithUndo(int revision) async {
    if (!await c.act('start', revision: revision) || !mounted) return;
    final id = c.state.session.id;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('undo-start'),
        duration: const Duration(seconds: 8),
        // An action normally keeps a snackbar up until tapped.
        persist: false,
        content: Text(
          '${c.state.session.timeline!.segments.first.name} started',
        ),
        action: SnackBarAction(
          label: 'Undo start',
          onPressed: () async {
            if (c.state.session.id != id || !c.state.session.active) return;
            if (await c.act('unstart')) return;
            final message = c.error ?? 'Could not undo the start.';
            c.dismissError();
            if (mounted) await showError(message);
          },
        ),
      ),
    );
  }

  Future<void> advance() async {
    final s = c.state.session, revision = c.state.session.revision;
    final next = s.timeline!.segments[s.index + 1];
    var keepBlank = false;
    if (await confirmTimer(
      revision: revision,
      title: 'Start ${next.name}?',
      action: 'Start ${next.name}',
      content: () => StatefulBuilder(
        builder: (context, update) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Finish ${s.timeline!.segments[s.index].name} and start ${next.name} · ${next.durationText}. Previous cues are cleared and the new countdown is sent.${c.hardware.held ? ' This also restores the reviewed output on the connected display.' : ''}',
            ),
            if (s.outputBlank)
              CheckboxListTile(
                title: const Text('Keep the display blank'),
                value: keepBlank,
                onChanged: (v) => update(() => keepBlank = v!),
              ),
          ],
        ),
      ),
    ))
      await c.act('advance', value: keepBlank, revision: revision);
  }

  Future<void> undo() async {
    final s = c.state.session, revision = c.state.session.revision;
    if (s.undo == null) return;
    if (await confirmTimer(
      revision: revision,
      title: 'Undo segment change?',
      action: 'Restore previous segment',
      content: () => Text(
        'Return to ${s.timeline!.segments[s.undo!.index].name} with ${operatorTimeDescription(s.undoBalance(c.now))} of ${formatTime(s.undoAllocatedMs)} allocated. ${s.undo!.paused ? 'Its timer will remain paused.' : 'Its timer will resume, accounting for time since the segment change.'}\n\nChanges made to ${s.timeline!.segments[s.index].name} will be discarded. The active stage cue stays visible.${s.uncertain ? '\nTiming is uncertain after recovery.' : ''}',
      ),
    ))
      await c.act('undo', revision: revision);
  }

  Future<TextLayout?> compose(
    TextLayout initial,
    String title,
    String button, {
    Future<bool> Function()? onDelete,
  }) => showDialog<TextLayout>(
    context: context,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => TextComposer(
      initial: initial,
      title: title,
      button: button,
      onDelete: onDelete,
    ),
  );
  Future<void> sendCue(TextLayout layout, {int? cueIndex}) async {
    final revision = c.state.session.revision;
    final result = await compose(
      layout,
      cueIndex == null ? 'New stage cue' : 'Edit stage cue',
      'Send',
      onDelete: cueIndex == null
          ? null
          : () async {
              if (!await confirm(
                'Delete this saved cue?',
                'Remove “${layout.text}” from the cues shared across all services? A cue already showing on stage stays visible until replaced or dismissed.',
                'Delete cue',
              ))
                return false;
              final ok = await c.deleteStageCue(cueIndex, layout);
              if (!ok && mounted)
                await showError(c.error ?? 'The cue could not be deleted.');
              return ok;
            },
    );
    if (result != null) {
      await c.sendAndSaveCue(result, index: cueIndex, revision: revision);
    }
  }

  Future<Timeline?> editTemplate({int? index}) async {
    final initial = index == null
        ? Timeline('', [], c.state.defaults)
        : c.state.templates[index];
    final draftKey = index == null ? 'program:new' : 'program:${initial.id}';
    await c.flushEditDrafts();
    var editorInitial = initial;
    final savedDraft = c.state.editDrafts[draftKey];
    if (savedDraft != null) {
      if (!mounted) return null;
      final restore = await reviewSavedDraft(context);
      if (restore == null) return null;
      if (restore) {
        try {
          editorInitial = programFromDraft(savedDraft, initial.display);
        } catch (_) {
          if (mounted)
            await showError(
              'This draft could not be opened. The saved program is unchanged.',
            );
          return null;
        }
      } else {
        c.queueEditDraft(draftKey, null);
        await c.flushEditDrafts();
      }
    }
    if (!mounted) return null;
    final result = await Navigator.of(context).push<Timeline>(
      MaterialPageRoute(
        builder: (_) => TemplateEditor(
          initial: editorInitial,
          creating: index == null,
          reports: c.state.reports,
          onDraftChanged: (value) => c.queueEditDraft(draftKey, value),
          draftController: c,
          defaultEnd: c.state.defaults.end,
          existingNames: c.state.templates
              .asMap()
              .entries
              .where((e) => e.key != index)
              .map((e) => e.value.name.toLowerCase())
              .toSet(),
        ),
      ),
    );
    await c.flushEditDrafts();
    if (result == null) return null;
    final ok = await c.commit((draft, at) {
      draft.saveTemplate(
        result,
        replacing: index == null ? null : draft.templateIndex(initial),
        replacedAt: at.wall,
      );
      draft.editDrafts.remove(draftKey);
    });
    if (!ok) {
      if (mounted)
        await showError(c.error ?? 'The program could not be saved.');
      return null;
    }
    return result;
  }

  /// Explains files from this app that are not programs, so a shared
  /// report or backup does not fail with a parser error.
  String? otherExportKind(Map<String, dynamic> file) {
    final name = (file['name'] as String).toLowerCase();
    if (!name.endsWith('.json')) return null;
    try {
      final type =
          (jsonDecode((file['content'] as String).replaceFirst('\uFEFF', ''))
              as Map)['type'];
      if (type == 'church-service-timer-report' ||
          type == 'church-service-timer-reports')
        return 'This file contains service reports, not programs. Reports can be opened in a spreadsheet (CSV) or printed, but not imported.';
      if (type == 'church-service-timer-backup')
        return 'This file is a full backup. Restore it from Settings › Backup & restore.';
    } catch (_) {}
    return null;
  }

  Future<void> importFile({Map<String, dynamic>? received}) async {
    try {
      final file = received ?? await c.port.pickFile();
      if (file == null || !mounted) return;
      final other = otherExportKind(file);
      if (other != null) throw RuleError(other);
      // Someone else's spreadsheet: match its columns first.
      if ((file['name'] as String).toLowerCase().endsWith('.csv')) {
        final rows = spreadsheetRows(file['content'] as String);
        if (rows.isNotEmpty && !isStandardProgramCsv(rows)) {
          final mapped = await Navigator.of(context).push<List<Timeline>>(
            MaterialPageRoute(
              builder: (_) => ImportMappingPage(
                controller: c,
                rows: rows,
                fileName: file['name'] as String,
              ),
            ),
          );
          if (mapped != null && mounted) await importProgramBundle(mapped);
          return;
        }
      }
      final candidates = importPrograms(
        file['content'] as String,
        file['name'] as String,
        c.state.defaults,
      );
      final raw = (file['content'] as String).replaceFirst('\uFEFF', '');
      final bundle = (file['name'] as String).toLowerCase().endsWith('.json')
          ? (jsonDecode(raw) as Map)['type'] == 'church-service-timer-programs'
          : parseCsv(raw)
                .firstWhere((r) => r.any((v) => v.trim().isNotEmpty))
                .contains('Program');
      if (candidates.length > 1 || bundle) {
        await importProgramBundle(candidates);
        return;
      }
      final candidate = importTemplate(
        file['content'] as String,
        file['name'] as String,
        c.state.defaults,
      );
      for (final l in [
        ...candidate.display.cues,
        ...candidate.display.warnings.map((w) => w.cue),
        candidate.display.end,
        if (candidate.display.zero != null) candidate.display.zero!,
      ]) {
        await NativeDisplayFonts.prepare(l);
      }
      validateTimelinePixels(candidate);
      validateProgramDuration(candidate);
      if (!mounted) return;
      final name = TextEditingController(text: candidate.name);
      String? error;
      bool validName() {
        try {
          final n = nameValue(name.text, 'Program name');
          require(
            !c.state.templates.any(
              (e) => e.name.toLowerCase() == n.toLowerCase(),
            ),
            'This name already exists. Rename the incoming program.',
          );
          error = null;
          return true;
        } catch (e) {
          error = e.toString();
          return false;
        }
      }

      validName();
      final accepted = await showDialog<Timeline>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Preview import'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Program name',
                      ),
                      onChanged: (_) => update(() {
                        validName();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${candidate.segments.length} segments · ${durationLabel(candidate.segments.fold<int>(0, (a, s) => a + s.durationMs))}',
                    ),
                    Text(
                      (file['name'] as String).toLowerCase().endsWith('.csv')
                          ? 'CSV supplies the program only. These current defaults have been captured for this import:'
                          : 'JSON includes these display settings:',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cues:\n${candidate.display.cues.map(styleSummary).join('\n')}\nZero: ${candidate.display.zero == null ? '00:00' : styleSummary(candidate.display.zero!)}\nEnd: ${styleSummary(candidate.display.end)}\nWarnings:\n${candidate.display.warnings.isEmpty ? 'None' : candidate.display.warnings.map((w) => '${w.enabled ? 'On' : 'Off'} · ${formatTime(w.seconds * 1000)} · ${w.destination} · ${styleSummary(w.cue)}').join('\n')}',
                    ),
                    const SizedBox(height: 12),
                    ...candidate.segments.map(
                      (s) => Text('${s.name} — ${s.durationText}'),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(color: appColors(context).warning),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !validName()
                    ? null
                    : () {
                        try {
                          final t = candidate.renamed(name.text);
                          require(
                            !c.state.templates.any(
                              (e) =>
                                  e.name.toLowerCase() == t.name.toLowerCase(),
                            ),
                            'This name already exists. Rename the incoming program.',
                          );
                          Navigator.pop(ctx, t);
                        } catch (e) {
                          update(() => error = e.toString());
                        }
                      },
                child: const Text('Accept import'),
              ),
            ],
          ),
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), name.dispose);
      if (accepted != null)
        await c.commit((draft, _) {
          draft.saveTemplate(accepted);
          draft.addStageCues(accepted.display.cues);
        });
    } catch (e) {
      if (mounted) await showError(e.toString());
    }
  }

  Future<void> export(Timeline t, String type) async {
    if (type == 'csv' &&
        !await confirm(
          'Export segments only?',
          'CSV includes names, order and durations. Cue formatting, zero and end screens are omitted. Choose JSON to preserve the full program.',
          'Export CSV',
        ))
      return;
    try {
      await c.port.exportFile(
        '${t.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$type',
        type == 'json' ? exportJson(t) : exportCsv(t),
      );
    } catch (e) {
      if (mounted) showError('Export failed: $e');
    }
  }

  Widget panel({required Widget child, EdgeInsets? padding}) => Material(
    color: appColors(context).surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: appColors(context).border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: padding ?? EdgeInsets.all(appLayout(context).panelPadding),
      child: child,
    ),
  );
  Widget label(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: appColors(context).muted,
      letterSpacing: 1.6,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
  Widget button(
    String text,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
    String? disabledReason,
  }) => UnavailableAction(
    reason: controlsLocked || action == null
        ? disabledReason ?? unavailableReason(text)
        : null,
    child: primary
        ? FilledButton.icon(
            onPressed: controlsLocked ? null : action,
            icon: Icon(icon, size: 20),
            label: Text(text),
          )
        : OutlinedButton.icon(
            onPressed: controlsLocked ? null : action,
            icon: Icon(icon, size: 20),
            label: Text(text),
          ),
  );

  /// A compact button with the icon above a short label, for a row of
  /// three even actions.
  Widget stackedButton(
    String text,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 4),
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 76)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
    );
    return UnavailableAction(
      reason: controlsLocked || action == null ? unavailableReason(text) : null,
      child: primary
          ? FilledButton(
              style: style,
              onPressed: controlsLocked ? null : action,
              child: child,
            )
          : OutlinedButton(
              style: style,
              onPressed: controlsLocked ? null : action,
              child: child,
            ),
    );
  }

  Widget live() => AnimatedBuilder(
    animation: c.liveClock,
    builder: (context, _) => liveContent(),
  );

  Widget liveMatrix() => RepaintBoundary(
    child: AnimatedBuilder(
      animation: c.previewClock,
      builder: (context, _) => LedMatrix(
        pixels: c.hardware.enabled
            ? c.hardware.preview(c.now)
            : c.simulator.pixels,
        hardware: c.hardware.enabled,
        stale: c.hardware.enabled
            ? c.hardware.held || !c.hardware.connected || c.hardware.interrupted
            : c.state.session.held || c.state.session.disconnected,
      ),
    ),
  );

  /// Pinned (or most recent) programs that load straight into Ready.
  Widget pinnedPrograms() {
    final lib = c.state.programLibrary;
    final pinned = c.state.templates
        .where((p) => lib.favourites.contains(p.id))
        .toList();
    final recent =
        c.state.templates.where((p) => lib.recent.containsKey(p.id)).toList()
          ..sort((a, b) => lib.recent[b.id]!.compareTo(lib.recent[a.id]!));
    final items = (pinned.isNotEmpty ? pinned : recent).take(4).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = appColors(context);
    final disabled =
        c.busy || c.corrupt || c.reportSavePending || controlsLocked;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(pinned.isNotEmpty ? 'Pinned' : 'Recent'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, space) {
              final width = (space.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in items)
                    SizedBox(
                      width: width,
                      child: Material(
                        key: ValueKey('quick-load:${p.name}'),
                        color: colors.surface,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: colors.border),
                        ),
                        child: InkWell(
                          onTap: disabled
                              ? null
                              : () async {
                                  try {
                                    c.state.templateIndex(p);
                                    await c.act('load', value: p);
                                  } catch (e) {
                                    if (mounted) await showError('$e');
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_outline,
                                      size: 18,
                                      color: colors.accent,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  templateSummary(p),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget lastServiceCard() {
    final r = c.state.reports.reduce(
      (a, b) => b.endedWall > a.endedWall ? b : a,
    );
    final colors = appColors(context);
    final variance = r.comparable ? r.totalMs! - r.plannedMs : null;
    final tone = variance == null || variance >= 1000
        ? colors.warning
        : variance <= -1000
        ? colors.info
        : colors.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        key: const ValueKey('last-service-card'),
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
        child: InkWell(
          onTap: () => openReport(r),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: label('Last service')),
                    Text(
                      'View last service report',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${r.name} · ${reportDate(r.startedWall ?? r.endedWall)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (r.totalMs != null) durationLabel(r.totalMs!),
                    variance == null
                        ? 'Partial record'
                        : varianceLabel(variance),
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: tone),
                ),
                if (r.review != null && r.review!.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.review!.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: colors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String wallTime(int wall) {
    final d = DateTime.fromMillisecondsSinceEpoch(wall);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> pickServiceStart() async {
    final now = DateTime.fromMillisecondsSinceEpoch(c.now.wall);
    final current = c.state.session.startsAtWall;
    final initial = current == null
        ? TimeOfDay.fromDateTime(
            DateTime(now.year, now.month, now.day, now.hour + 1),
          )
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(current));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Service starts at',
    );
    if (picked == null || !mounted) return;
    var start = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (!start.isAfter(now)) start = start.add(const Duration(days: 1));
    if (!await c.act('schedule', value: start.millisecondsSinceEpoch) &&
        mounted)
      await showError(c.error ?? 'Could not schedule the start.');
  }

  /// Optional scheduled start: the stage shows the clock, then a countdown to
  /// the start, then "Starting soon". The service still starts only on tap.
  Widget preServiceRow() {
    final colors = appColors(context);
    final at = c.state.session.startsAtWall;
    final left = at == null ? 0 : at - c.now.wall;
    // A hold (after Undo start, a cancelled setup or a reconnect) stops the
    // pre-service output reaching the display until it is released.
    final outputHeld =
        at != null &&
        (c.state.session.held ||
            (c.destination == 'led' &&
                c.hardware.connected &&
                c.hardware.held));
    final preServiceHint = outputHeld
        ? 'Output is held, so the display does not show it yet.'
        : 'Tap Start first segment when the service begins.';
    final summary = at == null
        ? 'Off · the display keeps its current output'
        : left > preServiceCountdownMs
        ? 'Starts ${wallTime(at)} · clock now, countdown from ${wallTime(at - preServiceCountdownMs - 1000)}\n$preServiceHint'
        : left > 0
        ? 'Starts ${wallTime(at)} · counting down on the display\n$preServiceHint'
        : 'Start time reached · display shows “Starting soon”\n$preServiceHint';
    return Material(
      key: const ValueKey('pre-service-row'),
      color: colors.background,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        leading: Icon(Icons.schedule, color: colors.accent),
        title: const Text(
          'Pre-service countdown',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          summary,
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
        trailing: at == null
            ? TextButton(
                onPressed: c.busy ? null : pickServiceStart,
                child: const Text('Set time'),
              )
            : outputHeld
            ? TextButton(
                key: const ValueKey('show-pre-service'),
                onPressed: c.busy
                    ? null
                    : () async {
                        if (!await c.showPreService() && mounted)
                          await showError(
                            c.error ?? 'Connect the display, then try again.',
                          );
                      },
                child: const Text('Show on display'),
              )
            : IconButton(
                tooltip: 'Turn off pre-service countdown',
                onPressed: c.busy ? null : () => c.act('schedule', value: null),
                icon: const Icon(Icons.close),
              ),
        onTap: c.busy ? null : pickServiceStart,
      ),
    );
  }

  /// Display status and readiness verdict, shown while a service is in Ready.
  Widget readyInline() {
    final colors = appColors(context);
    final problems = readinessChecks()
        .where((x) => !x.ok && x.key != 'program')
        .length;
    final tone = problems == 0 && c.destinationConnected
        ? colors.accent
        : colors.warning;
    return Material(
      key: const ValueKey('ready-inline'),
      color: tone.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openSettingsDetail('Ready for service', readinessSettings),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(connectionIcon(c.displayConnection), color: tone, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${c.displayConnection.label} · ${problems == 0 ? 'all set' : '${plural(problems, 'thing')} to check'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget liveContent() {
    final s = c.liveSession;
    final standingBy =
        s.phase == 'idle' || (s.phase == 'ended' && !c.reportSavePending);
    final t = standingBy ? null : s.timeline;
    final enabled =
        s.active &&
        !c.reportSavePending &&
        !c.busy &&
        !c.corrupt &&
        !controlsLocked &&
        c.pairing.localControl;
    final phase = standingBy
        ? 'Standing by'
        : s.phase == 'active'
        ? (s.phase == 'ended'
              ? 'Display blank'
              : s.paused
              ? 'Paused'
              : 'Live')
        : s.phase == 'ready'
        ? 'Ready'
        : s.phase == 'ended'
        ? 'Service ended'
        : 'Standing by';
    final canJump = enabled && t != null && s.index + 1 < t.segments.length;
    Widget timerPanelOf({required bool wide}) => panel(
      child: Column(
        key: const ValueKey('timer-card-content'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: label(
                  standingBy
                      ? 'Standing by'
                      : t == null
                      ? 'Live production'
                      : 'Segment ${s.index + 1} of ${t.segments.length}',
                ),
              ),
              // Visible whenever recording is on, so it is never left on by
              // accident.
              if (c.state.recordMetrics || c.metrics.recording)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    key: const ValueKey('metrics-chip'),
                    avatar: Icon(
                      Icons.fiber_manual_record,
                      size: 12,
                      color: appColors(context).error,
                    ),
                    label: Text(
                      s.noReport ? 'Test · recording' : 'Recording metrics',
                    ),
                    onPressed: openDiagnostics,
                  ),
                ),
              if (!standingBy)
                Chip(
                  label: Text(
                    !standingBy && s.rehearsal ? '$phase · ${s.rate}×' : phase,
                  ),
                  avatar: Icon(
                    s.active && !s.paused
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 12,
                    color: appColors(context).accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (t == null)
            const Text(
              'Ready when you are',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            )
          else
            Semantics(
              button: s.active,
              enabled: canJump,
              hint: s.active ? 'Jump to segment' : null,
              child: InkWell(
                key: const ValueKey('jump-to-segment'),
                borderRadius: BorderRadius.circular(8),
                onTap: s.active && canJump ? jumpToSegment : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.segments[s.index].name,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (s.active && canJump) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more,
                          color: appColors(context).muted,
                          semanticLabel: 'Jump to segment',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (t != null) ...[
            const SizedBox(height: 6),
            Text(
              s.index + 1 < t.segments.length
                  ? 'Next · ${t.segments[s.index + 1].name} · ${t.segments[s.index + 1].durationText}'
                  : 'Final segment',
              style: TextStyle(color: appColors(context).muted),
            ),
            if (s.active && !wide) ...[
              const SizedBox(height: 12),
              timingStatusLine(),
            ],
            const SizedBox(height: 6),
            if (t.segments[s.index].speaker.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Speaker: ${t.segments[s.index].speaker}'),
              ),
            if (t.segments[s.index].notes.isNotEmpty)
              OperatorNotes(
                key: ValueKey('${s.id}-${s.index}'),
                notes: t.segments[s.index].notes,
              ),
            SegmentGauge(session: s, now: c.now),
          ] else
            const SizedBox(height: 18),
          if (!s.active && s.phase != 'ready' && !c.reportSavePending)
            SizedBox(
              width: double.infinity,
              height: 54,
              child: button(
                'Start service',
                Icons.play_arrow,
                c.busy || c.corrupt ? null : chooseService,
                primary: true,
              ),
            ),
          if (standingBy) ...[
            const SizedBox(height: 10),
            ControlGrid(
              maxColumns: 2,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('share-service-live'),
                  onPressed:
                      c.busy ||
                          c.corrupt ||
                          c.reportSavePending ||
                          controlsLocked
                      ? null
                      : shareServiceSetup,
                  icon: const Icon(Icons.cast_connected),
                  label: Text(
                    c.pairing.hosting ? 'Manage sharing' : 'Share to screens',
                    textAlign: TextAlign.center,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      c.busy ||
                          c.corrupt ||
                          c.reportSavePending ||
                          controlsLocked ||
                          !c.pairing.localControl
                      ? null
                      : joinAsStageScreen,
                  icon: const Icon(Icons.tablet_mac_outlined),
                  label: const Text(
                    'Join as screen',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
          // Ready already counts battery in its "things to check" row.
          if (standingBy &&
              c.batteryUnrestricted == false &&
              !batteryHintDismissed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                key: const ValueKey('battery-hint'),
                color: appColors(context).warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: c.port.openBatterySettings,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.battery_alert_outlined,
                          size: 20,
                          color: appColors(context).warning,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Battery optimisation may delay warnings with the screen off. Tap to fix.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('battery-hint-dismiss'),
                          tooltip: 'Hide until the app is next opened',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              refreshHome(() => batteryHintDismissed = true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (s.phase == 'ready' && t != null)
            if (c.state.latestReviewFor(t) case final last?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  key: const ValueKey('last-review-note'),
                  color: appColors(context).info.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.rate_review_outlined,
                          size: 20,
                          color: appColors(context).info,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last time · ${serviceDateLabel(last.report.startedWall ?? last.report.endedWall)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(last.note.text),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          if (s.phase == 'ready') ...[
            if (t != null) ...[readyProgramRow(t), const SizedBox(height: 8)],
            readyInline(),
            const SizedBox(height: 10),
            preServiceRow(),
            const SizedBox(height: 12),
            ChoiceField<int>(
              key: ValueKey('speed-${s.id}'),
              value: s.rate,
              decoration: const InputDecoration(labelText: 'Service mode'),
              options: [1, 5, 10, 30, 60]
                  .map(
                    (rate) => ChoiceOption(
                      value: rate,
                      label: rate == 1
                          ? 'Live timing · 1×'
                          : 'Fast rehearsal · $rate×',
                    ),
                  )
                  .toList(),
              onChanged: c.busy ? null : (v) => c.act('rate', value: v),
            ),
            const SizedBox(height: 12),
            Text(
              'Timing has not started. The display retains its previous output.',
              style: TextStyle(color: appColors(context).muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                button(
                  'Start first segment',
                  Icons.play_arrow,
                  c.busy ? null : startFirst,
                  primary: true,
                ),
                button(
                  'Cancel setup',
                  Icons.close,
                  c.busy ? null : () => c.act('cancelReady'),
                ),
              ],
            ),
          ],
          if (s.active) ...[
            liveControls(enabled),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('end-service'),
              onPressed: enabled
                  ? () async {
                      final rev = s.revision;
                      if (await confirmTimer(
                        revision: rev,
                        title: 'End ${t!.name}?',
                        action: 'End service',
                        content: () => Text(
                          c.hardware.enabled
                              ? c.hardware.held || !c.hardware.connected
                                    ? 'Finish this service and save its report. The sign will keep its last program until you reconnect and restore output.'
                                    : 'Finish this service and save its report. The sign will show this service’s end screen, including its scrolling effect. A brief blink is expected.'
                              : 'Finish this service, save its report, clear the active cue and show “${t.display.end.text}”.',
                        ),
                      ))
                        await c.act('end', revision: rev);
                    }
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End service'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffa73238),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final displayPanel = c.destination == 'mobile'
        ? panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DisplayPreviewHeader(connection: c.displayConnection),
                const SizedBox(height: 14),
                mobileStagePreview(),
                const SizedBox(height: 12),
                stageSharingControls(),
              ],
            ),
          )
        : panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DisplayPreviewHeader(connection: c.displayConnection),
                const SizedBox(height: 14),
                liveMatrix(),
                if (s.outputBlank)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Screen intentionally blanked'),
                  ),
                const SizedBox(height: 12),
                Text(
                  '32 × 16 · ${c.state.pixelShape == 'square' ? 'Square' : 'Circular'} LEDs',
                  style: TextStyle(
                    color: appColors(context).muted,
                    fontSize: 12,
                  ),
                ),
                if (s.disconnected ||
                    (s.held && (s.active || s.phase == 'ended'))) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.disconnected
                        ? 'Output unavailable · showing the last simulated frame'
                        : 'Output paused after an interruption · resume below',
                    style: TextStyle(color: appColors(context).error),
                  ),
                ],
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final intended = s.outputBlank
                        ? 'Blank'
                        : s.intended(c.now)?.text ?? 'Nothing new';
                    final current = c.hardware.enabled
                        ? c.hardware.acceptedLabel
                        : c.simulator.delivered?.text ?? 'Blank';
                    final muted = TextStyle(color: appColors(context).muted);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.hardware.enabled
                              ? 'Sign accepted: $current'
                              : 'Showing: $current',
                          style: muted,
                        ),
                        if (intended != current)
                          Text(
                            c.hardware.enabled
                                ? 'Waiting to send: $intended'
                                : 'Waiting to show: $intended',
                            style: muted,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  c.hardware.enabled
                      ? 'Preview is an estimate of the last accepted program, not a live camera view of the sign.'
                      : 'Simulator only · connect a display in Settings for physical output.',
                  style: TextStyle(
                    color: appColors(context).muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                button(
                  'Change display',
                  Icons.devices,
                  c.busy || c.corrupt ? null : chooseDisplay,
                ),
              ],
            ),
          );
    final mode = s.outputMode(c.now);
    // Match the sent cue to its prepared button: exact formatting first,
    // then by text, so a restyled preset still swaps to its return button.
    var activeCueIndex = -1;
    if (!s.outputBlank && s.hasManualCue(c.now) && !s.alertIsMessage) {
      final sent = s.alert!;
      activeCueIndex = c.state.stageCues.indexWhere(
        (cue) => cue.toJson().toString() == sent.toJson().toString(),
      );
      if (activeCueIndex < 0)
        activeCueIndex = c.state.stageCues.indexWhere(
          (cue) => cue.text == sent.text,
        );
    }
    final clockSwap = !s.outputBlank && mode == 'Clock';
    final messageSwap =
        !s.outputBlank && mode == 'Message' && c.currentQuickMessage == null;
    // Outputs that no swapped button represents (automatic warnings, quick
    // messages, cues sent from elsewhere) still get an explicit way back.
    final needsReturn =
        (!s.outputBlank &&
            !const ['Countdown', 'Standby', 'End screen'].contains(mode) &&
            activeCueIndex < 0 &&
            !clockSwap &&
            !messageSwap) ||
        c.currentQuickMessage != null;
    final returnLabel = s.phase == 'ended' ? 'Show end screen' : 'Show timer';
    void returnToTimer() => c.act(s.phase == 'ended' ? 'endScreen' : 'timer');
    // A cue or message sits over whatever was showing; clearing it reveals
    // that output again (the clock, the countdown or the end screen).
    final cueReturnLabel = s.showClock ? 'Back to clock' : returnLabel;
    void returnFromCue() => c.act('clearCue');
    final cuePanel = panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label('Stage cues')),
              TextButton(
                onPressed: controlsLocked
                    ? null
                    : () => openSettingsDetail('Stage cues', stageCueSettings),
                child: const Text('Manage cues'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            liveShowingText(),
            key: const ValueKey('stage-showing'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          cueDeliveryFeedback(),
          const SizedBox(height: 12),
          // Cues: every button the same height; a lone last cue fills its
          // row rather than leaving a gap.
          ControlGrid(
            maxColumns: 2,
            fillLastRow: true,
            children: c.state.stageCues.asMap().entries.map((e) {
              final active = e.key == activeCueIndex;
              if (active) {
                return ShowTimerButton(
                  key: ValueKey('show-timer-cue-${e.key}'),
                  label: cueReturnLabel,
                  showing: '${e.value.text} ${destinationPhrase()}',
                  sending: c.hardware.sending,
                  onPressed: outputControlsEnabled ? returnFromCue : null,
                );
              }
              return Tooltip(
                message: e.value.text,
                child: UnavailableAction(
                  reason: outputControlsEnabled && !c.hardware.sending
                      ? null
                      : c.hardware.sending
                      ? 'Wait for the current cue to finish sending.'
                      : unavailableReason('Send cue'),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 68),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    label: Text(
                      e.value.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                    ),
                    onPressed: outputControlsEnabled && !c.hardware.sending
                        ? () => sendPreparedCue(e.value)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Display actions sit apart from the cues, in one even row.
          ControlGrid(
            maxColumns: 3,
            minWidth: 92,
            children: [
              if (clockSwap)
                ShowTimerButton(
                  key: const ValueKey('show-timer-clock'),
                  label: returnLabel,
                  showing: 'Clock ${destinationPhrase()}',
                  sending: c.hardware.sending,
                  onPressed: outputControlsEnabled ? returnToTimer : null,
                )
              else
                stackedButton(
                  'Show clock',
                  Icons.schedule,
                  outputControlsEnabled ? () => c.act('clock') : null,
                ),
              if (messageSwap)
                ShowTimerButton(
                  key: const ValueKey('show-timer-message'),
                  label: cueReturnLabel,
                  showing: 'Message ${destinationPhrase()}',
                  sending: c.hardware.sending,
                  onPressed: outputControlsEnabled ? returnFromCue : null,
                )
              else
                stackedButton(
                  'Send message',
                  Icons.edit_note,
                  outputControlsEnabled ? sendStageMessage : null,
                ),
              stackedButton(
                s.outputBlank ? 'Unblank screen' : 'Blank screen',
                s.outputBlank ? Icons.tv_outlined : Icons.tv_off_outlined,
                (s.active || s.phase == 'ended') &&
                        !c.busy &&
                        !c.corrupt &&
                        !controlsLocked &&
                        c.pairing.localControl
                    ? () async {
                        final revision = s.revision;
                        if (await confirmTimer(
                          revision: revision,
                          title: s.outputBlank
                              ? 'Unblank the display?'
                              : 'Blank the display?',
                          action: s.outputBlank
                              ? 'Confirm unblank'
                              : 'Confirm blank',
                          content: () => Text(
                            s.outputBlank
                                ? 'Show the current cue, countdown or service end screen again.'
                                : 'Blank the screen. Timing and phone warnings continue; tap Unblank screen to restore the current output.',
                          ),
                        ))
                          await c.act('blank', revision: revision);
                      }
                    : null,
                primary: s.outputBlank,
              ),
            ],
          ),
          if (needsReturn) ...[
            const SizedBox(height: 12),
            button(
              returnLabel,
              Icons.timer_outlined,
              outputControlsEnabled ? returnToTimer : null,
              primary: true,
            ),
          ],
        ],
      ),
    );
    final showRundown = t != null && !c.reportSavePending;
    Widget rundownPanel() => panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('Service rundown'),
          Wrap(
            spacing: 8,
            children: [
              if (s.active)
                TextButton.icon(
                  onPressed: enabled ? editUpcoming : null,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Edit upcoming'),
                ),
              if (s.active)
                TextButton.icon(
                  onPressed: enabled ? recoverTime : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Recover time'),
                ),
              TextButton.icon(
                onPressed: controlsLocked ? null : () => printServiceSheet(t!),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print Service'),
              ),
            ],
          ),
          if (s.targetFinishWall != null)
            Text(
              'Target finish ${clockLabel(s.targetFinishWall!)} · actual finish depends on manual advances',
            ),
          const SizedBox(height: 12),
          ...t!.segments.asMap().entries.map((e) {
            final current = e.key == s.index;
            return Column(
              children: [
                if (e.key > 0) const AppDivider(),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: current
                        ? appColors(context).accent.withValues(alpha: .14)
                        : null,
                    border: current
                        ? Border(
                            left: BorderSide(
                              color: appColors(context).accent,
                              width: 4,
                            ),
                          )
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      key: ValueKey('rundown-${e.key}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: Text('${e.key + 1}'.padLeft(2, '0')),
                      title: Text(
                        e.value.name,
                        style: TextStyle(
                          fontWeight: current
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${e.value.durationText}${current ? ' · Now' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAppSelection<void>(
                        context,
                        title: 'Segment details',
                        builder: (context) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              e.value.name,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Segment ${e.key + 1} of ${t.segments.length} · ${e.value.durationText} planned',
                            ),
                            if (current)
                              Text(
                                '${operatorTimeDescription(s.balance(c.now))} · ${formatTime(s.allocatedMs)} allocated',
                              ),
                            if (s.run?.actualMs[e.key] != null)
                              Text(
                                'Recorded duration: ${durationLabel(s.run!.actualMs[e.key]!)}',
                              ),
                            if (e.value.speaker.isNotEmpty)
                              Text('Speaker: ${e.value.speaker}'),
                            SizedBox(height: appLayout(context).gap),
                            const AppDivider(indent: 0, endIndent: 0),
                            SizedBox(height: appLayout(context).gap),
                            const Text(
                              'Private operator note',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              e.value.notes.isEmpty
                                  ? 'No private note for this segment.'
                                  : e.value.notes,
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controlsLocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  key: const ValueKey('controls-locked-banner'),
                  color: appColors(context).surface,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: appColors(context).warning),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Controls locked',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Semantics(
                          label: 'Hold to unlock controls',
                          child: OutlinedButton(
                            key: const ValueKey('unlock-controls'),
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Press and hold to unlock controls.',
                                    ),
                                  ),
                                ),
                            onLongPress: () => setState(
                              () => c.uiLocked = controlsLocked = false,
                            ),
                            child: const Text('Hold to unlock'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!c.hardware.enabled &&
                c.displayConnection == DisplayConnection.disconnected &&
                (s.active || s.phase == 'ended'))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  key: const ValueKey('display-disconnected-banner'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: appColors(context).surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.wifi_off, color: appColors(context).error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Display disconnected',
                              style: TextStyle(
                                color: appColors(context).error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.hardware.enabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: hardwareStatusPanel(),
              ),
            if (c.destination == 'simulator' &&
                s.held &&
                (s.active || s.phase == 'ended'))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Output paused after an interruption',
                        style: TextStyle(
                          color: appColors(context).warning,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${s.timeline!.name}\nLast activity: ${DateTime.fromMillisecondsSinceEpoch(s.checkpoint.wall).toLocal()}\n${s.uncertain ? 'Elapsed time is uncertain after a reboot or clock change. ' : ''}${s.phase == 'ended' ? 'The service has ended.' : 'The timer continues locally.'} Check the time, then resume to update the simulator.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          button(
                            s.phase == 'ended'
                                ? 'Send end screen'
                                : 'Resume output',
                            Icons.play_arrow,
                            c.busy ? null : () => c.act('release'),
                            primary: true,
                          ),
                          if (s.hasManualCue(c.now))
                            button(
                              'Dismiss alert & show timer',
                              Icons.timer,
                              c.busy ? null : () => c.act('releaseTimer'),
                            ),
                          button(
                            'Keep disconnected',
                            Icons.link_off,
                            c.busy ? null : () => c.act('disconnect'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (focused) ...[
              stageRequestCards(),
              timerPanelOf(wide: true),
              const SizedBox(height: 16),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DisplayPreviewHeader(connection: c.displayConnection),
                    const SizedBox(height: 12),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: c.destination == 'mobile'
                            ? mobileStagePreview()
                            : liveMatrix(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (c.destination == 'mobile')
                      stageSharingControls()
                    else
                      Text(
                        s.outputBlank
                            ? 'Screen intentionally blanked'
                            : c.hardware.enabled
                            ? c.hardware.acceptedLabel
                            : 'Simulator · ${s.intended(c.now)?.text ?? 'No new output'}',
                      ),
                  ],
                ),
              ),
              if (s.active) ...[
                const SizedBox(height: 20),
                focusedTimingOverview(),
              ],
              const SizedBox(height: 16),
              cuePanel,
              if (c.destination == 'mobile') ...[
                const SizedBox(height: 20),
                quickMessagePanel(),
              ],
              if (showRundown) ...[const SizedBox(height: 20), rundownPanel()],
            ] else if (standingBy) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      timerPanelOf(wide: false),
                      pinnedPrograms(),
                      if (c.state.reports.isNotEmpty) lastServiceCard(),
                      const SizedBox(height: 14),
                      panel(
                        padding: EdgeInsets.zero,
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: ValueKey(
                              'stage-and-display-${c.pairing.hosting || c.destination == 'mobile'}',
                            ),
                            initiallyExpanded:
                                c.pairing.hosting || c.destination == 'mobile',
                            leading: Icon(
                              connectionIcon(c.displayConnection),
                              color: appColors(context).accent,
                            ),
                            title: const Text(
                              'Stage & display',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${c.destinationName} · ${s.outputMode(c.now) == 'End screen' ? 'showing the end screen' : s.outputMode(c.now).toLowerCase()} · ${plural(c.state.stageCues.length, 'cue')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: appColors(context).muted,
                              ),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              8,
                              0,
                              8,
                              8,
                            ),
                            children: [
                              cuePanel,
                              if (c.destination == 'mobile') ...[
                                const SizedBox(height: 12),
                                quickMessagePanel(),
                              ],
                              const SizedBox(height: 12),
                              displayPanel,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (wide) ...[
              if (s.active) ...[
                timingStatusLine(bar: true),
                const SizedBox(height: 16),
              ],
              stageRequestCards(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: timerPanelOf(wide: true)),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        displayPanel,
                        const SizedBox(height: 16),
                        cuePanel,
                        if (c.destination == 'mobile') ...[
                          const SizedBox(height: 16),
                          quickMessagePanel(),
                        ],
                        if (showRundown) ...[
                          const SizedBox(height: 16),
                          rundownPanel(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              stageRequestCards(),
              timerPanelOf(wide: false),
              const SizedBox(height: 16),
              cuePanel,
              if (c.destination == 'mobile') ...[
                const SizedBox(height: 16),
                quickMessagePanel(),
              ],
              const SizedBox(height: 16),
              displayPanel,
              if (showRundown) ...[const SizedBox(height: 16), rundownPanel()],
            ],
          ],
        );
      },
    );
  }

  void handleBack() {
    if (selectingPrograms || selectingReports) {
      refreshHome(() {
        selectingPrograms = false;
        selectingReports = false;
        selectedProgramExports.clear();
        selectedReportExports.clear();
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
                            const ChurchTimerMark(),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    headerTitle(),
                                    key: const ValueKey('header-title'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
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
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                32,
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
                                          child: Text(
                                            c.backgroundError!,
                                            style: TextStyle(
                                              color: appColors(context).error,
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
                      !selectingPrograms &&
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
                      ((page == 1 && selectingPrograms) ||
                          (page == 2 && selectingReports))
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

class TextComposer extends StatefulWidget {
  final TextLayout initial;
  final String title, button;
  final Future<bool> Function()? onDelete;
  const TextComposer({
    super.key,
    required this.initial,
    required this.title,
    required this.button,
    this.onDelete,
  });
  @override
  State<TextComposer> createState() => _TextComposerState();
}

class _TextComposerState extends State<TextComposer> {
  late TextEditingController text;
  late bool bold, italic;
  bool deleting = false;
  late String effect, align, font;
  String? fontRequest, fontError;
  late int height, speed;
  final watch = Stopwatch()..start();
  final previewTick = ValueNotifier<int>(0);
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    text = TextEditingController(text: l.text);
    bold = l.bold;
    italic = l.italic;
    effect = l.effect;
    align = l.align;
    height = l.height;
    speed = l.speed;
    font = l.font;
    ticker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) previewTick.value++;
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    previewTick.dispose();
    text.dispose();
    super.dispose();
  }

  TextLayout get layout => TextLayout(
    text.text,
    bold: bold,
    italic: italic,
    effect: effect,
    align: align,
    height: height,
    speed: speed,
    font: font,
  );
  @override
  Widget build(BuildContext context) {
    final request = layout;
    if (request.font == 'tinos' &&
        NativeDisplayFonts.key(request) != fontRequest) {
      fontRequest = NativeDisplayFonts.key(request);
      fontError = null;
      final requestedKey = fontRequest;
      NativeDisplayFonts.prepare(request)
          .then((_) {
            if (mounted && fontRequest == requestedKey) setState(() {});
          })
          .catchError((Object e) {
            if (mounted && fontRequest == requestedKey)
              setState(() => fontError = '$e');
          });
    }
    String? error;
    try {
      validateLayout(layout);
    } catch (e) {
      error = e.toString();
    }
    if (font == 'tinos' && fontError != null) error = fontError;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: previewTick,
                  builder: (context, _, child) => LedMatrix(
                    pixels: error == null
                        ? renderPixels(layout, watch.elapsedMilliseconds)
                        : List.filled(512, false),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'NOT TESTED ON SIGN · simulator preview',
                style: TextStyle(
                  color: appColors(context).warning,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: text,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Display text',
                  helperText: '1–160 characters · basic Latin and punctuation',
                ),
                onChanged: (_) => setState(() {
                  watch.reset();
                }),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Bold'),
                    selected: bold,
                    onSelected: (v) => setState(() => bold = v),
                  ),
                  FilterChip(
                    label: const Text('Italic'),
                    selected: italic,
                    onSelected: (v) => setState(() => italic = v),
                  ),
                  FilterChip(
                    label: const Text('Tall · 14 px'),
                    selected: height == 2,
                    onSelected: (v) => setState(() => height = v ? 2 : 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ChoiceField<String>(
                value: font,
                decoration: const InputDecoration(labelText: 'Display font'),
                options: displayFontNames.entries
                    .map((e) => ChoiceOption(value: e.key, label: e.value))
                    .toList(),
                onChanged: (v) => setState(() {
                  font = v!;
                  fontRequest = null;
                  if (font == 'tinos') height = 2;
                  watch.reset();
                }),
              ),
              if (font == 'tinos')
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Bundled Tinos font · 14 px recommended. Compact text has fewer serif details.',
                    style: TextStyle(color: appColors(context).muted),
                  ),
                ),
              const SizedBox(height: 12),
              ChoiceField<String>(
                value: effect,
                decoration: const InputDecoration(labelText: 'Effect'),
                options: const [
                  ChoiceOption(value: 'static', label: 'Static · must fit'),
                  ChoiceOption(value: 'scroll', label: 'Scroll long text'),
                  ChoiceOption(value: 'flash', label: 'Flash · must fit'),
                ],
                onChanged: (v) => setState(() {
                  effect = v!;
                  watch.reset();
                }),
              ),
              const SizedBox(height: 12),
              ChoiceField<String>(
                value: align,
                decoration: const InputDecoration(
                  labelText: 'Alignment (text that fits)',
                ),
                options: const [
                  ChoiceOption(value: 'left', label: 'Left'),
                  ChoiceOption(value: 'center', label: 'Center'),
                  ChoiceOption(value: 'right', label: 'Right'),
                ],
                onChanged: (v) => setState(() => align = v!),
              ),
              if (effect == 'scroll') ...[
                const SizedBox(height: 12),
                Text('Scroll speed: $speed pixels / second'),
                Slider(
                  value: speed.toDouble(),
                  min: 4,
                  max: 24,
                  divisions: 20,
                  onChanged: (v) => setState(() => speed = v.round()),
                ),
                if (error == null)
                  Text(
                    'One complete message pass: approximately ${(math.max(0, textWidth(layout)) / speed).toStringAsFixed(1)} seconds.',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    style: TextStyle(color: appColors(context).warning),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton.icon(
            onPressed: deleting
                ? null
                : () async {
                    setState(() => deleting = true);
                    try {
                      final removed = await widget.onDelete!();
                      if (removed && context.mounted) Navigator.pop(context);
                    } finally {
                      if (mounted) setState(() => deleting = false);
                    }
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete cue'),
            style: TextButton.styleFrom(
              foregroundColor: appColors(context).error,
            ),
          ),
        TextButton(
          onPressed: deleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: error == null && !deleting
              ? () => Navigator.pop(context, layout)
              : null,
          child: Text(widget.button),
        ),
      ],
    );
  }
}

class TemplateEditor extends StatefulWidget {
  final Timeline initial;
  final Set<String> existingNames;
  final TextLayout defaultEnd;
  final bool upcomingOnly;
  final bool? creating;
  final ValueChanged<Json>? onDraftChanged;
  final AppController? draftController;
  final List<ServiceReport> reports;
  const TemplateEditor({
    super.key,
    required this.initial,
    required this.existingNames,
    this.defaultEnd = defaultEndScreen,
    this.upcomingOnly = false,
    this.creating,
    this.onDraftChanged,
    this.draftController,
    this.reports = const [],
  });
  @override
  State<TemplateEditor> createState() => TemplateEditorState();
}

class TemplateEditorState extends State<TemplateEditor> {
  late TextEditingController name;
  late List<Segment> segments;
  late TextLayout endScreen;
  late String templateType;
  String? error;
  void saveDraft() => widget.onDraftChanged?.call({
    'name': name.text,
    'type': templateType,
    'segments': [for (final s in segments) s.toJson()],
    'end': endScreen.toJson(),
  });
  void change(VoidCallback action) {
    setState(action);
    saveDraft();
  }

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial.name);
    segments = [...widget.initial.segments];
    endScreen = widget.initial.display.end;
    templateType = widget.initial.type;
    name.addListener(saveDraft);
  }

  @override
  void dispose() {
    name.removeListener(saveDraft);
    name.dispose();
    super.dispose();
  }

  Future<void> segment({int? index}) async {
    final label = TextEditingController(
      text: index == null ? '' : segments[index].name,
    );
    var durationSeconds = index == null ? 300 : segments[index].durationSeconds;
    final speaker = TextEditingController(
      text: index == null ? '' : segments[index].speaker,
    );
    final notes = TextEditingController(
      text: index == null ? '' : segments[index].notes,
    );
    var protected = index == null ? false : segments[index].protected;
    String? issue, saved;
    Segment build() {
      final s = Segment.fromJson({
        'name': label.text,
        'minutes': durationSeconds ~/ 60,
        'seconds': durationSeconds % 60,
        'speaker': speaker.text,
        'notes': notes.text,
        'protected': protected,
      });
      require(
        s.durationMs <= supportedCountdownMs,
        'Keep each segment within 59:59.',
      );
      return s;
    }

    final result = await showDialog<Segment>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text(index == null ? 'Add segment' : 'Edit segment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Segment name'),
              ),
              const SizedBox(height: 12),
              DurationField(
                key: const ValueKey('segment-duration-field'),
                value: formatTime(durationSeconds * 1000),
                onTap: () async {
                  final value = await showWheelTimePicker(
                    ctx,
                    title: 'Set segment duration',
                    initial: durationSeconds,
                  );
                  if (value != null && ctx.mounted)
                    update(() => durationSeconds = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: speaker,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Speaker (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Private operator notes',
                  helperText:
                      'Never shown on the sign. Included in program backups.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Protect duration'),
                subtitle: const Text(
                  'Time recovery will not shorten this segment.',
                ),
                value: protected,
                onChanged: (v) => update(() => protected = v),
              ),
              if (issue != null)
                Text(
                  issue!,
                  style: TextStyle(color: appColors(context).warning),
                ),
              if (saved != null)
                Text(
                  saved!,
                  style: TextStyle(color: appColors(context).accent),
                ),
            ],
          ),
          actions: [
            if (widget.draftController case final library?)
              TextButton.icon(
                key: const ValueKey('save-segment-to-library'),
                onPressed: () async {
                  try {
                    final s = build();
                    if (!await library.commit(
                      (draft, _) => draft.saveLibrarySegment(s),
                    ))
                      throw RuleError(
                        library.error ?? 'Could not save to the library.',
                      );
                    update(() {
                      issue = null;
                      saved = 'Saved “${s.name}” to the segment library.';
                    });
                  } catch (e) {
                    update(() {
                      saved = null;
                      issue = e.toString();
                    });
                  }
                },
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save to library'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(ctx, build());
                } catch (e) {
                  update(() => issue = e.toString());
                }
              },
              child: const Text('Save segment'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      label.dispose();

      speaker.dispose();
      notes.dispose();
    });
    if (result != null && mounted) {
      change(() {
        if (index == null) {
          segments.add(result);
        } else {
          segments[index] = result;
        }
      });
    } else if (saved != null && mounted) {
      // Shows From library after a save to the library, even on Cancel.
      setState(() {});
    }
  }

  void save() {
    try {
      if (widget.upcomingOnly) {
        require(segments.length <= 200, 'Keep at most 200 segments.');
        for (final s in segments) {
          Segment.fromJson(s.toJson());
        }
        Navigator.pop(
          context,
          Timeline(
            widget.initial.name,
            segments,
            widget.initial.display,
            type: widget.initial.type,
          ),
        );
        return;
      }
      final t = Timeline.fromJson(
        Timeline(
          name.text,
          segments,
          widget.initial.display.withEnd(endScreen),
          type: templateType,
        ).toJson(),
      );
      require(
        !widget.existingNames.contains(t.name.toLowerCase()),
        'A program with this name already exists.',
      );
      validateTimelinePixels(t);
      Navigator.pop(context, t);
    } catch (e) {
      change(() => error = e.toString());
    }
  }

  Future<void> editDuration(int i) async {
    final value = await showWheelTimePicker(
      context,
      title: 'Set segment duration',
      initial: segments[i].durationSeconds,
    );
    if (value == null || !mounted) return;
    try {
      final next = Segment.fromJson({
        ...segments[i].toJson(),
        'minutes': value ~/ 60,
        'seconds': value % 60,
      });
      change(() {
        segments[i] = next;
        error = null;
      });
    } catch (e) {
      change(() => error = e.toString());
    }
  }

  Future<void> editEndScreen() async {
    final next = await showDialog<TextLayout>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => TextComposer(
        initial: endScreen,
        title: 'Program end screen',
        button: 'Use end screen',
      ),
    );
    if (next != null && mounted) change(() => endScreen = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final muted = TextStyle(fontSize: 12, color: colors.muted);
    final totalMs = segments.fold<int>(0, (a, s) => a + s.durationMs);
    final creating = widget.creating ?? widget.initial.name.isEmpty;
    final draft = widget.draftController;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.upcomingOnly ? 'Upcoming segments' : 'Program editor',
        ),
        actions: [
          if (draft != null)
            AnimatedBuilder(
              animation: draft,
              builder: (context, _) => draft.draftError == null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Center(
                        child: Text(
                          'Draft saved',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ),
                    )
                  : TextButton(
                      onPressed: draft.flushEditDrafts,
                      child: Text(draft.draftError!),
                    ),
            ),
        ],
        bottom: draft?.liveSession.active == true
            ? RunningServiceBar.forContext(context, controller: draft!)
            : null,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!widget.upcomingOnly) ...[
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Program name',
                  hintText: 'Youth sunday',
                ),
              ),
              const SizedBox(height: 14),
              ChoiceField<String>(
                value: templateType,
                decoration: const InputDecoration(labelText: 'Program group'),
                options: const [
                  ChoiceOption(value: 'service', label: 'Service'),
                  ChoiceOption(value: 'rehearsal', label: 'Rehearsal'),
                ],
                onChanged: (value) => change(() => templateType = value!),
              ),
              const SizedBox(height: 6),
              Text(
                'Grouping organises programs. Choose rehearsal speed when starting.',
                style: muted,
              ),
            ],
            if (widget.upcomingOnly)
              Text(
                'Edit only the upcoming segments. Current and completed segments, saved programs and end screens stay unchanged.',
                style: TextStyle(color: colors.muted),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'SEGMENTS',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ),
                Text('Drag the handle to reorder', style: muted),
              ],
            ),
            if (!widget.upcomingOnly && widget.reports.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: reviewDurationSuggestions,
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: const Text('Learn from previous services'),
                ),
              ),
            const SizedBox(height: 8),
            if (segments.isNotEmpty)
              Material(
                color: colors.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.border),
                ),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: segments.length,
                  onReorderItem: (a, b) => change(() {
                    segments.insert(b, segments.removeAt(a));
                  }),
                  itemBuilder: (context, i) {
                    final s = segments[i];
                    final detail = [
                      if (s.speaker.isNotEmpty) s.speaker,
                      if (s.notes.isNotEmpty) 'private note',
                      if (s.protected) 'protected',
                    ].join(' · ');
                    return Material(
                      key: ValueKey(s),
                      color: colors.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0) const AppDivider(),
                          InkWell(
                            onTap: () => segment(index: i),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.drag_indicator,
                                        color: colors.muted,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (detail.isNotEmpty)
                                          Text(detail, style: muted),
                                      ],
                                    ),
                                  ),
                                  ActionChip(
                                    key: ValueKey('segment-duration-$i'),
                                    label: Text(
                                      formatTime(s.durationMs),
                                      style: const TextStyle(
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    onPressed: () => editDuration(i),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove segment',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        change(() => segments.removeAt(i)),
                                    icon: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: colors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: segments.length < 200 ? segment : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add segment'),
                  ),
                ),
                if (widget.draftController case final library?
                    when library.state.segmentLibrary.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('add-from-library'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: segments.length < 200
                          ? () async {
                              final s = await pickLibrarySegment(
                                context,
                                library,
                              );
                              if (s != null && mounted)
                                change(() => segments.add(s));
                            }
                          : null,
                      icon: const Icon(Icons.bookmark_outline),
                      label: const Text('From library'),
                    ),
                  ),
                ],
              ],
            ),
            if (!widget.upcomingOnly) ...[
              const SizedBox(height: 16),
              Material(
                color: colors.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      key: const ValueKey('edit-end-screen'),
                      leading: Icon(Icons.flag_outlined, color: colors.muted),
                      title: Text(
                        'End screen · ${endScreen.text}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        endScreen == widget.defaultEnd
                            ? 'Uses the current default · tap to edit'
                            : 'This program’s own end screen · tap to edit',
                        style: muted,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: editEndScreen,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 168,
                          child: LedMatrix(pixels: renderPixels(endScreen, 0)),
                        ),
                      ),
                    ),
                    if (endScreen != widget.defaultEnd)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: TextButton(
                            onPressed: () =>
                                change(() => endScreen = widget.defaultEnd),
                            child: const Text('Use current default'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Program edits apply the next time you load it.',
                style: muted,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Material(
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: colors.warning),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            totalMs % 60000 == 0
                                ? '${totalMs ~/ 60000} min'
                                : durationLabel(totalMs),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${plural(segments.length, 'segment')} · planned length',
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      onPressed: save,
                      icon: const Icon(Icons.check),
                      label: Text(
                        widget.upcomingOnly
                            ? 'Review rundown changes'
                            : creating
                            ? 'Create Program'
                            : 'Save changes',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-width controls that wrap cleanly at narrow widths and large text sizes.
class ControlGrid extends StatelessWidget {
  final List<Widget> children;
  final int maxColumns;

  /// The narrowest a column may be before the grid drops a column.
  final double minWidth;

  /// A lone item on the last row spans it, instead of leaving a gap.
  final bool fillLastRow;
  const ControlGrid({
    super.key,
    required this.children,
    this.maxColumns = 3,
    this.minWidth = 118,
    this.fillLastRow = false,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final minimum = MediaQuery.textScalerOf(
        context,
      ).scale(minWidth).clamp(minWidth, 220.0);
      final columns = ((space.maxWidth + 10) / (minimum + 10)).floor().clamp(
        1,
        maxColumns,
      );
      final gap = appLayout(context).gap;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var column = 0;
                    column <
                        (fillLastRow && start + 1 == children.length
                            ? 1
                            : columns);
                    column++
                  ) ...[
                    if (column > 0) SizedBox(width: gap),
                    Expanded(
                      child: start + column < children.length
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: appLayout(context).controlHeight,
                              ),
                              child: children[start + column],
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
