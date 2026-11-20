import 'dart:async';
import 'dart:math' as math;

import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/date_range_dialog.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

/// The inside of the mini timer window, in the app's own units.
const miniTimerSize = Size(380, 150);

/// Shown in place of a confirmation that no longer matches the service.
const staleActionText =
    'The service changed. Cancel and review this action again.';

/// The running segment in a very small window: its name, the countdown,
/// what comes next, how the service is running against plan, and the few
/// buttons an operator needs while another program fills the screen.
///
/// It only draws what it is given; [MiniTimerMode] connects it to the
/// service. Narrower than 260 or shorter than 120 it shows the name and
/// countdown alone, and smaller still just the countdown, so it never
/// overflows whatever size the window is dragged to.
class MiniTimerFace extends StatelessWidget {
  final Session session;
  final Stamp now;

  /// Lock controls is on: the buttons give way to Hold to unlock.
  final bool locked;
  final VoidCallback? onPause, onNext, onCue, onReturn;
  final VoidCallback onExpand, onUnlock, onUnlockHint;

  /// The first prepared cue, or null when there is none.
  final String? cue;

  /// That cue is on the stage now; its button offers [returnLabel].
  final bool cueShowing;
  final String returnLabel;
  const MiniTimerFace({
    super.key,
    required this.session,
    required this.now,
    required this.locked,
    required this.onPause,
    required this.onNext,
    required this.onCue,
    required this.onReturn,
    required this.onExpand,
    required this.onUnlock,
    required this.onUnlockHint,
    required this.cue,
    required this.cueShowing,
    required this.returnLabel,
  });

  @override
  Widget build(BuildContext context) {
    final s = session, colors = appColors(context);
    // Before a service, and after one, the time of day.
    if (!s.active) return _standingBy(colors);
    final t = s.timeline;
    if (t == null) return const SizedBox.expand();
    final balance = s.balance(now);
    final warning = s.nearWarning(now);
    final expired = balance < 0 || (s.active && balance == 0);
    // The same colours as the main dial.
    final stateColor = expired
        ? colors.error
        : warning
        ? colors.warning
        : colors.id == 'royal_navy'
        ? colors.success
        : colors.accent;
    final clock = Semantics(
      label:
          '${operatorTimeDescription(balance)}, ${formatTime(s.allocatedMs)} allocated',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          operatorTime(balance),
          key: const ValueKey('mini-clock'),
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w300,
            height: 1.05,
            letterSpacing: -2,
            color: expired
                ? colors.error
                : warning
                ? colors.warning
                : colors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    final segment = t.segments[s.index];
    Widget name(double size) => Row(
      children: [
        if (s.paused)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.pause_circle_outline,
              size: size + 2,
              color: colors.muted,
              semanticLabel: 'Paused',
            ),
          ),
        Expanded(
          child: Tooltip(
            message: segment.name,
            child: Text(
              segment.name,
              key: const ValueKey('mini-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 120 || box.maxHeight < 56) {
          return Padding(padding: const EdgeInsets.all(2), child: clock);
        }
        if (box.maxWidth < 260 || box.maxHeight < 120) {
          return Padding(
            key: const ValueKey('mini-compact'),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name(13),
                Expanded(child: clock),
              ],
            ),
          );
        }
        final hasNext = s.index + 1 < t.segments.length;
        final next = s.quickTimer
            ? ''
            : hasNext
            ? 'Next · ${t.segments[s.index + 1].name} · ${t.segments[s.index + 1].durationText}'
            : 'Final segment';
        final variance = s.run == null
            ? null
            : s.projectedTotal(now) - s.plannedMs;
        final details = LayoutBuilder(
          builder: (context, side) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: side.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name(15),
                  if (next.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        next,
                        key: const ValueKey('mini-next'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: colors.muted),
                      ),
                    ),
                  if (variance != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: variance > 999
                                  ? colors.warning
                                  : colors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              varianceLabel(variance),
                              key: const ValueKey('mini-variance'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        final progress = (s.remaining(now) / math.max(1, s.allocatedMs)).clamp(
          0.0,
          1.0,
        );
        return Padding(
          key: const ValueKey('mini-full'),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: clock,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: details),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              // The share of the segment's time that is left.
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: ColoredBox(
                    color: colors.track,
                    child: FractionallySizedBox(
                      key: const ValueKey('mini-progress'),
                      alignment: Alignment.centerLeft,
                      widthFactor: expired ? 1 : progress,
                      child: ColoredBox(color: stateColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(height: 36, child: locked ? _lockRow(colors) : _buttons),
            ],
          ),
        );
      },
    );
  }

  /// No service running: the time of day, and the loaded service's name
  /// and start time with the pre-service countdown when there is one.
  Widget _standingBy(AppPalette colors) {
    final s = session, t = s.timeline;
    final loaded = s.phase == 'ready' && t != null;
    final at = loaded ? s.startsAtWall : null;
    final left = at == null ? 0 : at - now.wall;
    final title = loaded ? t.name : 'No service running';
    final String detail;
    if (!loaded) {
      final day = DateTime.fromMillisecondsSinceEpoch(now.wall).toLocal();
      detail = '${_weekdays[day.weekday - 1]} ${longDate(day, year: false)}';
    } else if (at == null) {
      detail = 'No start time set';
    } else if (left > preServiceCountdownMs) {
      detail = 'Starts at ${clockLabel(at)}';
    } else if (left > 0) {
      detail = 'Starts in ${formatTime(left)} · at ${clockLabel(at)}';
    } else {
      detail = 'Start time reached · ${clockLabel(at)}';
    }
    final clock = Semantics(
      label: 'The time is ${clockLabel(now.wall)}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          clockLabel(now.wall),
          key: const ValueKey('mini-clock'),
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w300,
            height: 1.05,
            letterSpacing: -2,
            color: colors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    Widget name(double size) => Tooltip(
      message: title,
      child: Text(
        title,
        key: const ValueKey('mini-name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
      ),
    );
    return LayoutBuilder(
      key: const ValueKey('mini-standing-by'),
      builder: (context, box) {
        if (box.maxWidth < 120 || box.maxHeight < 56) {
          return Padding(padding: const EdgeInsets.all(2), child: clock);
        }
        if (box.maxWidth < 260 || box.maxHeight < 120) {
          return Padding(
            key: const ValueKey('mini-compact'),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name(13),
                Expanded(child: clock),
              ],
            ),
          );
        }
        final details = LayoutBuilder(
          builder: (context, side) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: side.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name(15),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail,
                      key: const ValueKey('mini-standing-by-detail'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: colors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return Padding(
          key: const ValueKey('mini-full'),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: clock,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: details),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 36,
                child: locked
                    ? _lockRow(colors)
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              loaded
                                  ? 'Start the service in the full window.'
                                  : 'Load a service in the full window.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.muted,
                              ),
                            ),
                          ),
                          _expandButton,
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  Widget get _expandButton => IconButton(
    key: const ValueKey('mini-expand'),
    tooltip: 'Expand to the full window',
    onPressed: onExpand,
    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
    padding: EdgeInsets.zero,
    iconSize: 20,
    icon: const Icon(Icons.open_in_full),
  );

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );
  static const _padding = EdgeInsets.symmetric(horizontal: 8);
  static const _text = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

  /// An icon and a word that shrink together rather than wrap or clip.
  static Widget _label(IconData icon, String text) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        Text(text, maxLines: 1, style: _text),
      ],
    ),
  );

  Widget _lockRow(AppPalette colors) => Row(
    key: const ValueKey('mini-locked'),
    children: [
      Icon(Icons.lock, size: 18, color: colors.warning),
      const SizedBox(width: 8),
      const Expanded(
        flex: 2,
        child: Text(
          'Controls locked',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        flex: 3,
        child: Semantics(
          label: 'Hold to unlock controls',
          child: OutlinedButton(
            key: const ValueKey('mini-unlock'),
            onPressed: onUnlockHint,
            onLongPress: onUnlock,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: _shape,
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Hold to unlock', maxLines: 1, style: _text),
            ),
          ),
        ),
      ),
    ],
  );

  Widget get _buttons => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        flex: 5,
        child: Tooltip(
          message: session.paused ? 'Resume' : 'Pause',
          child: FilledButton(
            key: const ValueKey('mini-pause'),
            onPressed: onPause,
            style: FilledButton.styleFrom(
              minimumSize: Size.zero,
              padding: _padding,
              shape: _shape,
            ),
            child: _label(
              session.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              session.paused ? 'Resume' : 'Pause',
            ),
          ),
        ),
      ),
      // A quick timer is one countdown: there is no next segment.
      if (!session.quickTimer) ...[
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: Tooltip(
            message: 'Next segment',
            child: OutlinedButton(
              key: const ValueKey('mini-next-segment'),
              onPressed: onNext,
              style: OutlinedButton.styleFrom(
                minimumSize: Size.zero,
                padding: _padding,
                shape: _shape,
              ),
              child: _label(Icons.skip_next_rounded, 'Next'),
            ),
          ),
        ),
      ],
      if (cue != null) ...[
        const SizedBox(width: 6),
        Expanded(
          flex: 5,
          child: cueShowing
              ? MiniReturnButton(
                  key: const ValueKey('mini-show-timer'),
                  label: returnLabel,
                  showing: cue!,
                  onPressed: onReturn,
                )
              : Tooltip(
                  message: 'Send cue: ${cue!}',
                  child: OutlinedButton(
                    key: const ValueKey('mini-cue'),
                    onPressed: onCue,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: _padding,
                      shape: _shape,
                    ),
                    child: Text(
                      cue!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text,
                    ),
                  ),
                ),
        ),
      ],
      const SizedBox(width: 2),
      _expandButton,
    ],
  );
}

/// The cue button while its cue is on the stage: one press returns to the
/// timer. Like the full window's button it ignores presses for a moment
/// after it appears, so a double click on the cue does not send it and
/// take it straight off again.
class MiniReturnButton extends StatefulWidget {
  final String label, showing;
  final VoidCallback? onPressed;
  const MiniReturnButton({
    super.key,
    required this.label,
    required this.showing,
    required this.onPressed,
  });
  @override
  State<MiniReturnButton> createState() => _MiniReturnButtonState();
}

class _MiniReturnButtonState extends State<MiniReturnButton> {
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
  Widget build(BuildContext context) => Tooltip(
    message: '${widget.label} · ${widget.showing} is showing',
    child: FilledButton(
      onPressed: widget.onPressed == null
          ? null
          : () {
              if (!guarded) widget.onPressed!();
            },
      style: FilledButton.styleFrom(
        minimumSize: Size.zero,
        padding: MiniTimerFace._padding,
        shape: MiniTimerFace._shape,
      ),
      child: MiniTimerFace._label(Icons.timer_outlined, widget.label),
    ),
  );
}

/// A question or a note small enough for the mini timer window: a title,
/// text that scrolls if it must, and its buttons on one line. In a large
/// window it is an ordinary card in the middle.
class MiniDialogCard extends StatefulWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  const MiniDialogCard({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
  });
  @override
  State<MiniDialogCard> createState() => _MiniDialogCardState();
}

class _MiniDialogCardState extends State<MiniDialogCard> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    // In the mini timer window the card covers the timer; in a large
    // window it is only as tall as its text.
    final small = MediaQuery.sizeOf(context).height < 300;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 300),
          child: Material(
            key: const ValueKey('mini-dialog'),
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
              child: Column(
                mainAxisSize: small ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    fit: small ? FlexFit.tight : FlexFit.loose,
                    child: Scrollbar(
                      controller: scroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: scroll,
                        padding: const EdgeInsets.only(right: 10),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 12.5, height: 1.25),
                          child: widget.body,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final (i, action) in widget.actions.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        // The last button names the action, which can be
                        // long ("Start Praise & Worship"); it gives way.
                        i == widget.actions.length - 1
                            ? Flexible(child: action)
                            : action,
                      ],
                    ],
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

/// The mini timer: a small window that stays above other programs.
extension MiniTimerMode on HomeState {
  /// Whether the mini timer can be opened now: on a computer this device
  /// controls, during a service or before one, when it shows the clock.
  bool get miniTimerAvailable =>
      c.ready &&
      c.port.isDesktop &&
      c.port.miniWindow != null &&
      !c.pairing.joined;

  static final _buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  Future<T?> _showMini<T>(WidgetBuilder builder) => showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cancel',
    barrierColor: Colors.black54,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, _, _) => builder(ctx),
  );

  static Widget _cancel(BuildContext ctx, String text, Object? result) =>
      TextButton(
        key: const ValueKey('mini-confirm-cancel'),
        onPressed: () => Navigator.pop(ctx, result),
        style: _buttonStyle,
        child: Text(text, maxLines: 1, style: MiniTimerFace._text),
      );

  /// The question every confirmation asks, in the mini timer window: the
  /// same title, text and buttons as the dialog in the full window.
  /// [revision], when given, is the service the question was asked about;
  /// if the service has moved on, only Cancel is left.
  Future<bool> miniConfirm({
    required String title,
    required String action,
    required Widget Function() content,
    int? revision,
    bool destructive = false,
  }) async =>
      await _showMini<bool>(
        (ctx) => AnimatedBuilder(
          animation: Listenable.merge([c, c.liveClock]),
          builder: (ctx, _) {
            final stale =
                revision != null && c.state.session.revision != revision;
            return MiniDialogCard(
              title: title,
              body: stale ? const Text(staleActionText) : content(),
              actions: [
                _cancel(ctx, 'Cancel', false),
                FilledButton(
                  key: const ValueKey('mini-confirm-action'),
                  // Space or Enter answers what Space asked, as in the
                  // full window; never for a destructive question.
                  autofocus: !destructive,
                  onPressed: stale || (revision != null && c.busy)
                      ? null
                      : () => Navigator.pop(ctx, true),
                  style: destructive
                      ? destructiveFilled().merge(_buttonStyle)
                      : _buttonStyle,
                  child: Text(
                    action,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MiniTimerFace._text,
                  ),
                ),
              ],
            );
          },
        ),
      ) ??
      false;

  /// "Please review" in the mini timer window.
  Future<void> miniError(String message) => _showMini<void>(
    (ctx) => MiniDialogCard(
      title: 'Please review',
      body: Text(message),
      actions: [_cancel(ctx, 'Close', null)],
    ),
  );

  /// What the mini timer window shows in place of the whole app.
  Widget miniTimerView() {
    final s = c.liveSession;
    final enabled =
        s.active &&
        !c.reportSavePending &&
        !c.busy &&
        !c.corrupt &&
        !controlsLocked &&
        c.pairing.localControl;
    final cue = c.state.stageCues.isEmpty ? null : c.state.stageCues.first;
    final cueShowing =
        cue != null &&
        !s.outputBlank &&
        s.hasManualCue(c.now) &&
        !s.alertIsMessage &&
        s.alert!.text == cue.text;
    final canSend = outputControlsEnabled && !c.hardware.sending;
    return Scaffold(
      key: const ValueKey('mini-timer'),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: c.liveClock,
          builder: (context, _) => MiniTimerFace(
            session: s,
            now: c.now,
            locked: controlsLocked,
            onPause: enabled ? confirmPause : null,
            onNext:
                enabled &&
                    s.timeline != null &&
                    s.index + 1 < s.timeline!.segments.length
                ? advance
                : null,
            cue: cue?.text,
            cueShowing: cueShowing,
            returnLabel: s.showClock ? 'Back to clock' : 'Show timer',
            onCue: canSend && cue != null ? () => sendPreparedCue(cue) : null,
            onReturn: canSend ? () => c.act('clearCue') : null,
            onExpand: () => unawaited(setMiniTimer(false)),
            onUnlock: () =>
                refreshHome(() => c.uiLocked = controlsLocked = false),
            onUnlockHint: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(deviceText('Press and hold to unlock controls.')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
