import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/lyrics/scripture_search.dart';
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/quick_timer_sheet.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/live/shortcuts_sheet.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/windows/second_screen.dart';

/// One thing the operator can do from the command palette. Running it
/// calls the same function as its button on screen, so anything that asks
/// to confirm there asks here too.
class PaletteCommand {
  /// Stable name, used by the suggestions and the tests.
  final String id;
  final String label;

  /// A quieter second part of the line, such as a segment's length.
  final String detail;
  final IconData icon;

  /// The heading it is listed under when nothing has been typed.
  final String group;

  /// Its keyboard key on Live, where it has one.
  final String? keys;

  /// Extra words the search matches besides the label.
  final String words;

  /// Listed only once the operator has typed something.
  final bool searchOnly;
  final FutureOr<void> Function() run;
  const PaletteCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    required this.run,
    this.detail = '',
    this.keys,
    this.words = '',
    this.searchOnly = false,
  });

  /// Whether every word typed is found in the label, detail or extra
  /// words. Upper and lower case are the same.
  bool matches(String query) {
    final text = '$label $detail $words $group'.toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .every(text.contains);
  }
}

/// The command palette: every action by name, opened with Ctrl+K on a
/// computer or from the Live menu.
extension CommandPalette on HomeState {
  /// On a computer, with the controls unlocked. Lock controls blocks the
  /// palette like every other input.
  bool get commandPaletteAvailable =>
      c.ready &&
      c.port.isDesktop &&
      !controlsLocked &&
      !c.pairing.joined &&
      ModalRoute.of(context)?.isCurrent == true;

  /// What can be done right now. A command whose button would be greyed
  /// out is left off the list.
  List<PaletteCommand> paletteCommands() {
    if (controlsLocked || !c.ready) return const [];
    final s = c.liveSession;
    final standingBy = liveStandingBy;
    final t = standingBy ? null : s.timeline;
    // The same conditions as the buttons on Live.
    final enabled =
        s.active &&
        !c.reportSavePending &&
        !c.busy &&
        !c.corrupt &&
        c.pairing.localControl;
    final later = t == null || s.quickTimer
        ? const <int>[]
        : [for (var i = s.index + 1; i < t.segments.length; i++) i];
    final output = outputControlsEnabled;
    final cueShowing =
        !s.outputBlank && (s.hasManualCue(c.now) || s.hasAutomaticCue(c.now));
    final quickShowing = c.currentQuickMessage != null;
    // With no end screen an ended service shows the clock, with nothing
    // to swap back to.
    final clockShowing =
        !s.outputBlank && s.outputMode(c.now) == 'Clock' && !s.endsOnClock;
    final returnLabel = s.endsOnClock
        ? 'Back to clock'
        : s.phase == 'ended'
        ? 'Show end screen'
        : 'Show timer';
    final keys = c.port.isDesktop;
    return [
      // Timer.
      if (!s.active && s.phase != 'ready' && !c.reportSavePending) ...[
        if (!c.busy && !c.corrupt)
          PaletteCommand(
            id: 'start',
            label: 'Start service',
            detail: 'Choose a program',
            icon: Icons.play_arrow,
            group: 'Timer',
            words: 'begin load',
            run: () {
              navigatePage(0);
              return chooseService();
            },
          ),
        if (quickTimerAvailable)
          PaletteCommand(
            id: 'quick-timer',
            label: 'Quick timer',
            detail: 'One countdown, no program',
            icon: Icons.timer_outlined,
            group: 'Timer',
            words: 'countdown',
            run: openQuickTimer,
          ),
      ],
      if (s.phase == 'ready' && t != null && !c.busy) ...[
        PaletteCommand(
          id: 'start-first',
          label: 'Start first segment',
          detail: t.segments.first.name,
          icon: Icons.play_arrow,
          group: 'Timer',
          words: 'begin service',
          run: () {
            navigatePage(0);
            return startFirst();
          },
        ),
        PaletteCommand(
          id: 'cancel-setup',
          label: 'Cancel setup',
          icon: Icons.close,
          group: 'Timer',
          run: () => c.act('cancelReady'),
        ),
      ],
      if (enabled) ...[
        PaletteCommand(
          id: 'pause',
          label: s.paused ? 'Resume timer' : 'Pause timer',
          icon: s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          group: 'Timer',
          keys: keys && c.state.clickerControls ? shortcutHint('pause') : null,
          words: 'pause resume hold continue',
          run: confirmPause,
        ),
        if (later.isNotEmpty)
          PaletteCommand(
            id: 'next',
            label: 'Next segment',
            detail:
                '${t!.segments[later.first].name} · ${t.segments[later.first].durationText}',
            icon: Icons.skip_next_rounded,
            group: 'Timer',
            keys: keys && c.state.clickerControls ? shortcutHint('next') : null,
            words: 'advance move on',
            run: advance,
          ),
        PaletteCommand(
          id: 'adjust',
          label: 'Adjust time',
          detail: 'Add or remove time',
          icon: Icons.more_time,
          group: 'Timer',
          keys: keys ? shortcutHint('adjust') : null,
          words: 'custom extend shorten minutes',
          run: adjustTime,
        ),
        if (s.undo != null)
          PaletteCommand(
            id: 'undo',
            label: 'Undo',
            detail: 'Back to ${t!.segments[s.undo!.index].name}',
            icon: Icons.undo,
            group: 'Timer',
            keys: keys ? shortcutHint('undo') : null,
            words: 'previous segment restore',
            run: undo,
          ),
        if (later.isNotEmpty) ...[
          PaletteCommand(
            id: 'jump',
            label: 'Jump to segment',
            detail: 'Choose a later segment',
            icon: Icons.low_priority,
            group: 'Timer',
            keys: keys ? shortcutHint('jump') : null,
            words: 'skip',
            run: jumpToSegment,
          ),
          for (final i in later)
            PaletteCommand(
              id: 'jump-$i',
              label: 'Jump to ${t!.segments[i].name}',
              detail: t.segments[i].durationText,
              icon: Icons.low_priority,
              group: 'Timer',
              words: 'skip segment',
              searchOnly: true,
              run: () => confirmJump(i),
            ),
        ],
        PaletteCommand(
          id: 'recover',
          label: 'Recover time',
          detail: 'Shorten what is still to come',
          icon: Icons.auto_fix_high_outlined,
          group: 'Timer',
          keys: keys ? shortcutHint('recover') : null,
          words: 'late behind catch up',
          run: recoverTime,
        ),
        PaletteCommand(
          id: 'edit-upcoming',
          label: 'Edit upcoming',
          detail: 'Change the segments still to come',
          icon: Icons.edit_calendar_outlined,
          group: 'Timer',
          keys: keys ? shortcutHint('edit-upcoming') : null,
          words: 'segments rundown program',
          run: editUpcoming,
        ),
        PaletteCommand(
          id: 'end',
          label: s.quickTimer ? 'End timer' : 'End service',
          icon: Icons.stop_circle_outlined,
          group: 'Timer',
          words: 'finish stop',
          run: confirmEndService,
        ),
      ],
      // Stage.
      if (output) ...[
        if (cueShowing || quickShowing)
          PaletteCommand(
            id: 'show-timer',
            // A cue sits over what was showing; clearing it brings that
            // back. A warning or quick message goes back to the timer.
            label: quickShowing || !s.hasManualCue(c.now)
                ? returnLabel
                : s.showClock
                ? 'Back to clock'
                : returnLabel,
            detail: 'Clear what is showing',
            icon: Icons.timer_outlined,
            group: 'Stage',
            words: 'back return timer clear cue message countdown',
            run: () => c.act(
              quickShowing || !s.hasManualCue(c.now)
                  ? (s.phase == 'ended' ? 'endScreen' : 'timer')
                  : 'clearCue',
            ),
          )
        else if (clockShowing)
          PaletteCommand(
            id: 'show-timer',
            label: returnLabel,
            detail: 'The clock is showing',
            icon: Icons.timer_outlined,
            group: 'Stage',
            words: 'back return timer countdown',
            run: () => c.act(s.phase == 'ended' ? 'endScreen' : 'timer'),
          ),
        if (!c.hardware.sending)
          for (final (i, cue) in c.state.stageCues.indexed)
            if (!(cueShowing &&
                s.hasManualCue(c.now) &&
                !s.alertIsMessage &&
                s.alert!.text == cue.text))
              PaletteCommand(
                id: 'cue-$i',
                label: 'Show cue: ${cue.text}',
                icon: Icons.chat_bubble_outline,
                group: 'Stage',
                keys: keys && i < 9 ? '${i + 1}' : null,
                words: 'send stage',
                run: () => sendPreparedCue(cue),
              ),
        if (!clockShowing && !s.endsOnClock)
          PaletteCommand(
            id: 'clock',
            label: 'Show clock',
            icon: Icons.schedule,
            group: 'Stage',
            words: 'time of day',
            run: () => c.act('clock'),
          ),
        PaletteCommand(
          id: 'message',
          label: 'Send message',
          detail: 'Type a message for the stage',
          icon: Icons.edit_note,
          group: 'Stage',
          keys: keys ? shortcutHint('message') : null,
          words: 'write text stage',
          run: sendStageMessage,
        ),
      ],
      if ((s.active || s.phase == 'ended') &&
          !c.busy &&
          !c.corrupt &&
          c.pairing.localControl)
        PaletteCommand(
          id: 'blank',
          label: s.outputBlank ? 'Unblank screen' : 'Blank screen',
          icon: s.outputBlank ? Icons.tv_outlined : Icons.tv_off_outlined,
          group: 'Stage',
          words: 'blank unblank black hide display',
          run: confirmBlank,
        ),
      if (c.secondScreen case final second?
          when second.host.open || second.target != null)
        PaletteCommand(
          id: 'second-screen',
          label: second.host.open
              ? 'Stop the second screen'
              : 'Show on second screen',
          detail: switch (second.showingOn ?? second.target) {
            final screen? => stageMonitorLabel(screen),
            null => '',
          },
          icon: second.host.open ? Icons.tv_off_outlined : Icons.connected_tv,
          group: 'Stage',
          words: 'projector monitor hdmi output full screen second stop show',
          run: () =>
              second.host.open ? second.stop() : second.show(second.target!),
        ),
      // This window.
      if (c.liveSession.active)
        PaletteCommand(
          id: 'lock',
          label: 'Lock controls',
          detail: 'Hold to unlock afterwards',
          icon: Icons.lock_outline,
          group: 'This window',
          keys: keys ? shortcutHint('lock') : null,
          words: 'block keyboard touch',
          run: lockControls,
        ),
      if (miniTimerAvailable)
        PaletteCommand(
          id: 'mini',
          label: 'Mini timer',
          detail: 'A small window that stays on top',
          icon: Icons.picture_in_picture_alt_outlined,
          group: 'This window',
          keys: keys ? shortcutHint('mini') : null,
          words: 'small always on top lyrics slides shrink',
          run: () => setMiniTimer(true),
        ),
      if (hostFullScreenAvailable && !miniTimer)
        PaletteCommand(
          id: 'fullscreen',
          label: 'Full screen',
          detail: 'Show the stage on this screen',
          icon: Icons.fullscreen,
          group: 'This window',
          keys: keys ? shortcutHint('fullscreen') : null,
          words: 'stage big countdown whole screen present audience',
          run: () => setHostFullScreen(true),
        ),
      if (keys)
        PaletteCommand(
          id: 'shortcuts',
          label: 'Keyboard shortcuts',
          detail: 'Every key and what it does',
          icon: Icons.keyboard_outlined,
          group: 'This window',
          keys: shortcutHint('shortcuts'),
          words: 'keys help clicker pedal',
          run: openShortcutsSheet,
        ),
      PaletteCommand(
        id: 'focus',
        label: focused ? 'Exit focused view' : 'Focused operator view',
        icon: focused ? Icons.fullscreen_exit : Icons.fullscreen,
        group: 'This window',
        words: 'focus simple',
        run: () => setFocused(!focused),
      ),
      if (t != null && !c.reportSavePending)
        PaletteCommand(
          id: 'print',
          label: 'Print order of service',
          icon: Icons.print_outlined,
          group: 'This window',
          words: 'rundown paper sheet',
          run: () => printServiceSheet(t),
        ),
      // Go to.
      if (!focused)
        for (final p in homePageOrder)
          // Screens has its own command below.
          if (p.page != page && p.page != screensPage)
            PaletteCommand(
              id: 'go-${p.page}',
              label: 'Go to ${p.name}',
              icon: p.icon,
              group: 'Go to',
              words: p.page == lyricsPage
                  ? 'open tab page songs hymns words bible verses announcements slides'
                  : 'open tab page',
              run: () => goToPage(p.page),
            ),
      if (!controlsLocked)
        PaletteCommand(
          id: 'search-bible',
          label: 'Search the Bible',
          detail: 'A reference or words from a verse, on Slides',
          icon: Icons.menu_book_outlined,
          group: 'Go to',
          words:
              'scripture verse find look up reference passage text slides ready',
          run: () async {
            final there = page == lyricsPage;
            if (!there) await goToPage(lyricsPage);
            ScriptureSearchFocus.request(pageShowing: there);
          },
        ),
      if (c.lyrics.showing && !controlsLocked)
        PaletteCommand(
          id: 'clear-lyrics',
          label: 'Clear slide',
          detail: 'Every screen goes back to what it showed before',
          icon: Icons.lyrics_outlined,
          group: 'This window',
          words: 'songs words slide remove black hide',
          run: c.lyrics.clear,
        ),
      PaletteCommand(
        id: 'screens-panel',
        label: 'Screens',
        detail: 'What each group of screens shows, and scenes',
        icon: Icons.dashboard_customize_outlined,
        group: 'This window',
        words: 'groups scenes stage second web slides layout monitor',
        run: () => openScreensPanel(context, c),
      ),
      if (!controlsLocked && c.pairing.localControl)
        for (final scene in c.screens.setup.scenes)
          PaletteCommand(
            id: 'scene-${scene.id}',
            label: 'Scene: ${scene.name}',
            detail: 'Sets every group it names at once',
            icon: Icons.dashboard_customize_outlined,
            group: 'This window',
            words: 'scene screens groups apply',
            run: () => c.screens.applyScene(scene.id),
          ),
      PaletteCommand(
        id: 'appearance',
        label: 'Appearance',
        detail: 'Theme, layout and spacing',
        icon: Icons.palette_outlined,
        group: 'Go to',
        words: 'settings colours dark light look desktop layout',
        run: () async {
          if (await ensureSettingsUnlocked() && mounted) await openAppearance();
        },
      ),
      PaletteCommand(
        id: 'screens',
        label: 'Screens & devices',
        detail: 'Stage screens, second screen and sign',
        icon: Icons.devices,
        group: 'Go to',
        words: 'settings pair display projector led tablet phone',
        run: () => openSettingsDetail(
          'Screens & devices',
          pairedDeviceSettings,
          showLiveShortcut: true,
        ),
      ),
    ];
  }

  /// The few commands most likely wanted in the state the service is in,
  /// listed first before anything is typed.
  List<String> paletteSuggestions() {
    final s = c.liveSession;
    if (!s.active) {
      return s.phase == 'ready'
          ? const ['start-first']
          : const ['start', 'quick-timer', 'show-timer'];
    }
    final behind = s.run != null && s.projectedTotal(c.now) - s.plannedMs > 999;
    final overtime = s.balance(c.now) <= 0;
    return [
      // Something other than the timer is on the stage: the way back.
      'show-timer',
      if (s.outputBlank) 'blank',
      if (s.paused) 'pause',
      if (overtime) 'next',
      if (behind) 'recover',
      if (!overtime) 'next',
      if (!s.paused) 'pause',
      if (overtime) 'adjust',
    ].take(4).toList();
  }

  /// Opens the palette, then runs the chosen command once it has closed.
  Future<void> openCommandPalette() async {
    if (!commandPaletteAvailable) return;
    final commands = paletteCommands();
    final chosen = await showDialog<PaletteCommand>(
      context: context,
      barrierLabel: 'Close commands',
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => CommandPaletteDialog(
        commands: commands,
        suggested: paletteSuggestions(),
        showKeys: c.port.isDesktop,
      ),
    );
    // Locked or changed hands while it was open: do nothing.
    if (chosen == null || !mounted || controlsLocked) return;
    await chosen.run();
  }
}

/// The palette itself: a search field over a list of commands. Arrow keys
/// move, Enter runs, Esc closes. It returns the chosen command and runs
/// nothing itself.
class CommandPaletteDialog extends StatefulWidget {
  final List<PaletteCommand> commands;

  /// Ids of the commands to list first, under "Suggested now".
  final List<String> suggested;
  final bool showKeys;
  const CommandPaletteDialog({
    super.key,
    required this.commands,
    required this.suggested,
    this.showKeys = true,
  });

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final search = TextEditingController();
  final selectedKey = GlobalKey();
  String query = '';
  int selected = 0;
  bool closed = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  /// The rows in view, each with the heading it starts, if any.
  List<(String?, PaletteCommand)> get rows {
    if (query.trim().isNotEmpty) {
      final found = widget.commands.where((e) => e.matches(query)).toList();
      // A command whose name starts with what was typed comes first.
      final q = query.trim().toLowerCase();
      final first = found.where((e) => e.label.toLowerCase().startsWith(q));
      final rest = found.where((e) => !e.label.toLowerCase().startsWith(q));
      return [
        for (final e in first) (null, e),
        for (final e in rest) (null, e),
      ];
    }
    final listed = widget.commands.where((e) => !e.searchOnly).toList();
    final suggested = [
      for (final id in widget.suggested) ...listed.where((e) => e.id == id),
    ];
    final out = <(String?, PaletteCommand)>[];
    for (final (i, e) in suggested.indexed) {
      out.add((i == 0 ? 'Suggested now' : null, e));
    }
    String? group;
    for (final e in listed) {
      if (suggested.contains(e)) continue;
      out.add((e.group == group ? null : e.group, e));
      group = e.group;
    }
    return out;
  }

  void choose(PaletteCommand command) {
    if (closed) return;
    closed = true;
    Navigator.pop(context, command);
  }

  void move(int by) {
    final count = rows.length;
    if (count == 0) return;
    setState(() => selected = (selected + by) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = selectedKey.currentContext;
      if (row == null) return;
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: by > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) runSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (!closed) {
        closed = true;
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void runSelected() {
    final list = rows;
    if (list.isEmpty) return;
    choose(list[selected.clamp(0, list.length - 1)].$2);
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final text = Theme.of(context).textTheme;
    final list = rows;
    final current = list.isEmpty ? -1 : selected.clamp(0, list.length - 1);
    final muted = text.bodySmall?.copyWith(color: colors.muted, fontSize: 12);
    Widget row(int i) {
      final (heading, command) = list[i];
      final on = i == current;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading != null)
            Padding(
              padding: EdgeInsets.fromLTRB(20, i == 0 ? 10 : 16, 20, 6),
              child: Text(
                heading,
                style: text.labelMedium?.copyWith(
                  color: colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Semantics(
            button: true,
            selected: on,
            child: Material(
              key: on ? selectedKey : null,
              color: on
                  ? colors.accent.withValues(alpha: .14)
                  : Colors.transparent,
              child: InkWell(
                key: ValueKey('command-${command.id}'),
                onTap: () => choose(command),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 3,
                        color: on ? colors.accent : Colors.transparent,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(17, 8, 20, 8),
                  child: Row(
                    children: [
                      Icon(
                        command.icon,
                        size: 20,
                        color: on ? colors.accent : colors.muted,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: command.label),
                              if (command.detail.isNotEmpty)
                                TextSpan(
                                  text: '   ${command.detail}',
                                  style: muted?.copyWith(fontSize: 13),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (widget.showKeys && command.keys != null) ...[
                        const SizedBox(width: 12),
                        ExcludeSemantics(child: _KeyCap(command.keys!)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final finished = finishLook(context).active;
    return Dialog(
      key: const ValueKey('command-palette'),
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      // A finish lays it on its material (FinishPopupFrame), in its shape.
      backgroundColor: finished ? null : colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: finished
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.border),
            ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Focus(
          onKeyEvent: onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: TextField(
                  key: const ValueKey('command-search'),
                  controller: search,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: text.titleMedium?.copyWith(color: colors.text),
                  decoration: InputDecoration(
                    hintText: 'Type what you want to do',
                    hintStyle: text.titleMedium?.copyWith(color: colors.muted),
                    icon: Icon(Icons.search, color: colors.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: (value) => setState(() {
                    query = value;
                    selected = 0;
                  }),
                  onSubmitted: (_) => runSelected(),
                ),
              ),
              Divider(height: 1, color: colors.border),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Nothing matches “${query.trim()}”. Try another word, such as pause, cue or settings.',
                          key: const ValueKey('command-none'),
                          style: text.bodyMedium?.copyWith(color: colors.muted),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < list.length; i++) row(i),
                          ],
                        ),
                      ),
              ),
              Divider(height: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Arrow keys to move   ·   Enter to choose   ·   Esc to close',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Timer changes still ask to confirm', style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A keyboard key drawn as a small outlined cap at the right of a row.
class _KeyCap extends StatelessWidget {
  final String keys;
  const _KeyCap(this.keys);
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        keys,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.muted,
          fontSize: 11,
          letterSpacing: .4,
        ),
      ),
    );
  }
}
