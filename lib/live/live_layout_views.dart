import 'dart:async';
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/live/shortcuts_sheet.dart';

/// Header status, menus and compact Live helpers shared by the phone and
/// tablet layouts.
extension LiveLayout on HomeState {
  bool get liveStandingBy {
    final s = c.liveSession;
    return s.phase == 'idle' || (s.phase == 'ended' && !c.reportSavePending);
  }

  String get headerChurchName =>
      c.ready ? c.state.churchName : c.loadingChurchName;

  /// The loaded program names the header; otherwise the app name does.
  String headerTitle() {
    final t = c.ready && !liveStandingBy ? c.liveSession.timeline : null;
    return t?.name ?? appName;
  }

  String headerSubtitle() => headerChurchName;

  /// Whether clicking the header's title goes back to Live: on another
  /// tab, while the title is a loaded or running service's name. Locked
  /// controls block it, as they block the tabs.
  bool get headerReturnsToLive =>
      c.ready &&
      page != 0 &&
      !controlsLocked &&
      !liveStandingBy &&
      c.liveSession.timeline != null;

  /// Wide screens use a side rail so Live keeps its full height.
  bool get useNavigationRail =>
      !focused &&
      c.ready &&
      !useTopTabs &&
      MediaQuery.sizeOf(context).width >= 840;

  Widget navigationShell(Widget body) {
    if (!useNavigationRail) return body;
    final colors = appColors(context);
    return Row(
      children: [
        SafeArea(
          right: false,
          child: NavigationRail(
            key: const ValueKey('navigation-rail'),
            backgroundColor: colors.surface,
            selectedIndex: page,
            labelType: NavigationRailLabelType.all,
            // Clear of the top edge, in line with the header beside it.
            leading: const SizedBox(height: 12),
            onDestinationSelected: (v) {
              if (!controlsLocked) goToPage(v);
            },
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.radio_button_checked),
                label: Text('Live'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.view_timeline_outlined),
                label: Text('Programs'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.assessment_outlined),
                label: Text('Reports'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                label: Text('Settings'),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.border),
        Expanded(child: body),
      ],
    );
  }

  /// Short, glanceable destination status for the header chip.
  /// The LED sign link is being recovered automatically.
  bool get displayReconnecting =>
      c.destination == 'led' && c.hardware.reconnecting;

  String headerDisplayLabel() => displayReconnecting
      ? 'Reconnecting…'
      : switch (c.displayConnection) {
          DisplayConnection.disconnected => 'Disconnected',
          DisplayConnection.stageDisconnected => 'Stage offline',
          DisplayConnection.stageWaiting => 'Waiting for a screen',
          DisplayConnection.stageConnected => 'Stage screens',
          DisplayConnection.connected =>
            c.destination == 'led' ? 'LED sign' : 'Display',
          DisplayConnection.simulator => 'Simulator',
        };

  Widget liveMenu() => PopupMenuButton<String>(
    key: const ValueKey('live-menu'),
    tooltip: 'More Live options',
    icon: const Icon(Icons.more_vert),
    onSelected: (value) {
      if (value == 'focus') setFocused(!focused);
      if (value == 'mini') unawaited(setMiniTimer(true));
      if (value == 'fullscreen') unawaited(setHostFullScreen(true));
      if (value == 'ready') {
        openSettingsDetail('Ready for service', readinessSettings);
      }
      if (value == 'commands') openCommandPalette();
      if (value == 'shortcuts') openShortcutsSheet();
    },
    itemBuilder: (context) => appMenuEntries(context, [
      AppMenuAction(
        'focus',
        focused ? 'Exit focused view' : 'Focused operator view',
      ),
      if (miniTimerAvailable)
        AppMenuAction(
          'mini',
          'Mini timer',
          keys: showKeyHints ? 'Ctrl M' : null,
        ),
      if (hostFullScreenAvailable && !controlsLocked)
        AppMenuAction(
          'fullscreen',
          'Full screen',
          keys: showKeyHints ? shortcutHint('fullscreen') : null,
        ),
      if (!focused && !controlsLocked)
        const AppMenuAction('ready', 'Ready for service'),
      // Every action by name, for a mouse as well as Ctrl+K.
      if (commandPaletteAvailable)
        AppMenuAction(
          'commands',
          'Commands',
          keys: showKeyHints ? 'Ctrl K' : null,
        ),
      if (shortcutsSheetAvailable)
        AppMenuAction(
          'shortcuts',
          'Keyboard shortcuts',
          keys: showKeyHints ? shortcutHint('shortcuts') : null,
        ),
    ]),
  );

  /// Where the current output is shown, for "WRAP UP on sign".
  String destinationPhrase() => switch (c.destination) {
    'led' => 'on sign',
    'mobile' => 'on stage screens',
    _ => 'in simulator',
  };

  /// Plain one-line description of what the stage output shows right now.
  String liveShowingText() {
    final s = c.liveSession;
    if (s.outputBlank) {
      return s.phase == 'ended'
          ? 'Screen blank'
          : s.paused
          ? 'Screen blank · timer paused'
          : 'Screen blank · timing continues';
    }
    if (c.currentQuickMessage != null) return 'Showing a quick message';
    if (s.hasAutomaticCue(c.now))
      return 'Showing warning: ${s.automaticCue!.text}';
    if (s.hasManualCue(c.now)) {
      return s.alertIsMessage
          ? 'Showing message: ${s.alert!.text}'
          : 'Showing cue: ${s.alert!.text}';
    }
    return switch (s.outputMode(c.now)) {
      'Clock' => 'Showing the clock',
      'End screen' => 'Showing the end screen',
      'Countdown' =>
        s.paused ? 'Showing countdown · paused' : 'Showing countdown',
      // Before the start the cue buttons are greyed out; say why rather
      // than inviting a tap that does nothing.
      _ =>
        s.active || s.phase == 'ended'
            ? deviceText('Tap a cue to send it to the stage')
            : 'Cues work once the service starts',
    };
  }

  /// One line summarising the service timing; tap it for the full overview.
  Widget timingStatusLine({bool bar = false}) {
    final s = c.liveSession;
    if (s.run == null) return const SizedBox.shrink();
    final projected = s.projectedTotal(c.now);
    final variance = projected - s.plannedMs;
    final eta =
        c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round();
    final colors = appColors(context);
    final over = variance > 999;
    final color = over ? colors.warning : colors.success;
    final status = varianceLabel(variance);
    final finish = s.paused
        ? 'ends ${clockLabel(eta)} if resumed now'
        : 'ends ${clockLabel(eta)}';
    void openDetails() => showAppSelection<void>(
      context,
      title: s.rehearsal ? 'Rehearsal timing' : 'Service timing',
      builder: (_) => timingOverview(),
    );
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (bar) {
      return Material(
        key: const ValueKey('timing-status-bar'),
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: openDetails,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 24,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot,
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text('Elapsed ${durationLabel(s.totalElapsed(c.now))}'),
                Text('Planned ${durationLabel(s.plannedMs)}'),
                Text(
                  'Estimated finish ${clockLabel(eta)}${s.paused ? ' · if resumed now' : ''}',
                ),
                if (s.rehearsal) Text('Rehearsal · ${s.rate}×'),
              ],
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        key: const ValueKey('timing-status-line'),
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: openDetails,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  dot,
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$status · $finish',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled display destination chip: the most important status on Live.
class HeaderDisplayChip extends StatelessWidget {
  final DisplayConnection connection;
  final String label;
  final VoidCallback? onPressed;

  /// Shows a spinner in the warning colour while the link is recovering.
  final bool reconnecting;
  const HeaderDisplayChip({
    super.key,
    required this.connection,
    required this.label,
    required this.onPressed,
    this.reconnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final dot = reconnecting
        ? colors.warning
        : switch (connection) {
            DisplayConnection.disconnected ||
            DisplayConnection.stageDisconnected => colors.error,
            DisplayConnection.connected ||
            DisplayConnection.stageConnected => colors.success,
            DisplayConnection.stageWaiting => colors.warning,
            // Blue, not grey, so the simulator never looks disabled.
            DisplayConnection.simulator => colors.info,
          };
    return Tooltip(
      message: '${connection.label} · connection details',
      child: Semantics(
        button: true,
        label: 'Display: $label. Connection details',
        excludeSemantics: true,
        child: Material(
          color: dot.withValues(alpha: .12),
          shape: StadiumBorder(
            side: BorderSide(color: dot.withValues(alpha: .45)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reconnecting &&
                        !MediaQuery.disableAnimationsOf(context))
                      SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: dot,
                        ),
                      )
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the active cue, clock or message button so the way back to the
/// timer sits where the operator just tapped. It ignores taps briefly after
/// appearing and while the output is still sending, so a double tap on a cue
/// cannot immediately hide it again.
class ShowTimerButton extends StatefulWidget {
  final String label;
  final String showing;
  final bool sending;
  final VoidCallback? onPressed;
  static const guard = Duration(milliseconds: 600);
  const ShowTimerButton({
    super.key,
    required this.label,
    required this.showing,
    required this.sending,
    required this.onPressed,
  });

  @override
  State<ShowTimerButton> createState() => _ShowTimerButtonState();
}

class _ShowTimerButtonState extends State<ShowTimerButton> {
  bool guarded = true;
  Timer? release;

  @override
  void initState() {
    super.initState();
    release = Timer(ShowTimerButton.guard, () {
      if (mounted) setState(() => guarded = false);
    });
  }

  @override
  void dispose() {
    release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final enabled = widget.onPressed != null && !widget.sending;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.sending
          ? 'Sending ${widget.showing}'
          : '${widget.label}. ${widget.showing}',
      excludeSemantics: true,
      child: FilledButton(
        onPressed: enabled
            ? () {
                if (!guarded) widget.onPressed!();
              }
            : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon above the label, like the buttons beside it, so "Show
            // timer" fits a narrow tile instead of shrinking to "Show ti…".
            Icon(widget.sending ? Icons.sync : Icons.timer_outlined, size: 18),
            const SizedBox(height: 2),
            Text(
              widget.sending ? 'Sending…' : widget.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              widget.showing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: enabled ? colors.background : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
