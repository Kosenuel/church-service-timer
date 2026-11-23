import 'package:church_service_timer/shared/device_words.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/programs/send_program_views.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:church_service_timer/shared/reconnect_banner.dart';
import 'package:church_service_timer/shared/screen_orientation.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/pairing/scrolling_text.dart';
import 'package:church_service_timer/main.dart';

class PairedScreen extends StatefulWidget {
  final AppController controller;
  const PairedScreen({super.key, required this.controller});
  @override
  State<PairedScreen> createState() => _PairedScreenState();
}

class _PairedScreenState extends State<PairedScreen> {
  AppController get controller => widget.controller;

  /// After about a minute, suggest checking the Wi-Fi connection.
  bool longHostWait(PairHub hub) {
    final since = hub.reconnectingSince;
    return since != null &&
        DateTime.now().difference(since) >= const Duration(seconds: 60);
  }

  bool _stage = false, _showTools = true;
  Timer? _hideTools;
  @override
  void initState() {
    super.initState();
    controller.pairing.addListener(updateMode);
    updateMode();
  }

  void updateMode() {
    final next = controller.pairing.mode == 'stage';
    if (_stage == next) return;
    _stage = next;
    unawaited(
      ScreenOrientation.setApp(next ? ScreenOrientation.landscape : const []),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    if (next) revealTools();
  }

  void revealTools() {
    _hideTools?.cancel();
    if (mounted) setState(() => _showTools = true);
    _hideTools = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showTools = false);
    });
  }

  @override
  void dispose() {
    controller.pairing.removeListener(updateMode);
    _hideTools?.cancel();
    if (_stage) {
      unawaited(ScreenOrientation.setApp(const []));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  Future<void> leave() async {
    if (controller.pairing.canControl) {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave paired service?'),
          content: const Text(
            'Control returns to the host. Its service keeps running.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await controller.pairing.stop();
  }

  Widget leaveButton() => Tooltip(
    message: 'Leave paired service',
    child: TextButton(
      onPressed: leave,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.close, size: 22),
          Text('Leave', style: TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
  Future<void> action(
    BuildContext context,
    String label,
    String action, [
    dynamic value,
  ]) async {
    final revision = controller.pairing.snapshot?['revision'] as int?;
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: Text('$label?'),
        content: const Text('Apply this action to the host’s running service.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await controller.pairing.sendCommand(
          action,
          value,
          expectedRevision: revision,
        );
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Control unavailable. Reconnect and request control.',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = controller.pairing, data = controller.pairing.snapshot;
    final stage = hub.mode == 'stage', stale = hub.stale;
    final rows = (data?['rundown'] as List?) ?? [];
    if (stage)
      return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: revealTools,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Padding(
                  // A lyric slide's background reaches the edges.
                  padding: EdgeInsets.all(data?['lyrics'] is Map ? 0 : 24),
                  child: data == null
                      ? Text(
                          hub.status,
                          style: const TextStyle(color: Colors.white),
                        )
                      : StageSurface(data: data, stale: stale),
                ),
              ),
              if (data?['quickMessage'] is Map &&
                  data!['quickMessage']['requestSeen'] == true &&
                  data['blank'] != true &&
                  data['stageSharing'] == true)
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: stale || data['messageSeen'] == true
                            ? null
                            : () async {
                                try {
                                  await hub.acknowledgeMessage();
                                } catch (_) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Message is no longer available.',
                                        ),
                                      ),
                                    );
                                }
                              },
                        icon: Icon(
                          data['messageSeen'] == true
                              ? Icons.done_all
                              : Icons.check,
                        ),
                        label: Text(
                          data['messageSeen'] == true ? 'Seen' : 'Mark seen',
                        ),
                      ),
                    ),
                  ),
                ),
              // Requests to the operator: the button with the tools, and
              // the request's state for as long as there is one.
              if (data?['stageRequests'] == true &&
                  !stale &&
                  (_showTools || data!['stageRequest'] is Map))
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: StageRequestButton(
                        status: data!['stageRequest'] is Map
                            ? Map<String, dynamic>.from(data['stageRequest'])
                            : null,
                        enabled: !stale,
                        onSend: (kind) async {
                          try {
                            await hub.sendStageRequest(kind);
                          } catch (_) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Request not sent. Try again in a moment.',
                                  ),
                                ),
                              );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              if (_showTools || stale)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    // Clear of the top edge.
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => hub.showStage(false),
                            icon: const Icon(Icons.view_list),
                            label: const Text('Back to service overview'),
                          ),
                          const Spacer(),
                          leaveButton(),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              if (hub.reconnecting)
                const SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: ReconnectingChip(
                        key: ValueKey('stage-reconnecting'),
                        label: 'Reconnecting to the host device…',
                      ),
                    ),
                  ),
                )
              else if (stale)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      hub.pausedByHost
                          ? 'Session paused by host'
                          : 'Host disconnected · last received display',
                      style: TextStyle(
                        color: Colors.amber,
                        backgroundColor: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    final wide = isWideWindow(context);
    // The order of service: below the controls on a phone, in its own
    // pane in a wide window.
    final rundown = <Widget>[
      if (data != null)
        for (final e in rows.asMap().entries)
          ListTile(
            title: Text(
              e.value['name'],
              style: TextStyle(
                fontWeight: e.key == data['index']
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              [
                    durationLabel(
                      ((e.value['minutes'] as int) * 60 +
                              (e.value['seconds'] as int? ?? 0)) *
                          1000,
                    ),
                    if ((e.value['speaker'] as String? ?? '').isNotEmpty)
                      e.value['speaker'],
                  ].join(' · ') +
                  // Private notes only when there are some.
                  ((e.value['notes'] as String? ?? '').isEmpty
                      ? ''
                      : '\nPrivate: ${e.value['notes']}'),
            ),
          ),
    ];
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!stage) ReceivedProgramCards(controller: controller),
        Text(data?['church'] ?? '', textAlign: TextAlign.center),
        Text(
          data?['service'] ?? 'Waiting for host',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (!stage)
          Text(
            data?['segment'] ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
          ),
        const SizedBox(height: 20),
        if (data != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                if (data['blank'] == true)
                  const SizedBox(
                    height: 150,
                    child: Center(
                      child: Text(
                        'Screen blank',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                if (data['blank'] != true && stage)
                  StageMessage(data: data, stale: stale),
                if (data['blank'] != true && !stage)
                  SelectableText(
                    data['remaining'] ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: stage ? 54 : 64,
                      color: !stage && data['overtime'] == true
                          ? Colors.redAccent
                          : Colors.white,
                      fontWeight: data['bold'] == true
                          ? FontWeight.bold
                          : FontWeight.w400,
                      fontStyle: data['italic'] == true
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                if (!stage && data['displayText'] != data['remaining'])
                  Text(
                    'Stage: ${data['displayText']}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (data['paused'] == true)
                  const Text('PAUSED', style: TextStyle(color: Colors.amber)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          data == null
              ? hub.status
              : stale
              ? 'Connection stale · showing last received state'
              : hub.status,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: stale ? appColors(context).error : appColors(context).accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!stage && data != null) ...[
          Text(
            'Display: ${data['connection'] ?? 'Unknown'}',
            textAlign: TextAlign.center,
          ),
          if (hub.mode == 'operator' && !hub.canControl)
            OutlinedButton(
              onPressed: stale ? null : () => hub.requestControl(),
              child: const Text('Request control'),
            ),
          if (hub.canControl) ...[
            const Text(
              'You control this service. The host device must stay connected.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in [
                    ('−2 min', 'adjust', -120),
                    (
                      data['paused'] == true ? 'Resume' : 'Pause',
                      'pause',
                      null,
                    ),
                    ('+2 min', 'adjust', 120),
                    ('Next segment', 'advance', false),
                    ('Show timer', 'timer', null),
                    (
                      data['blank'] == true ? 'Unblank screen' : 'Blank screen',
                      'blank',
                      null,
                    ),
                  ])
                    SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed:
                            data['phase'] == 'active' ||
                                (item.$2 == 'blank' && data['phase'] == 'ended')
                            ? () => action(context, item.$1, item.$2, item.$3)
                            : null,
                        child: item.$2 == 'pause'
                            ? Tooltip(
                                message: item.$1,
                                child: Icon(
                                  data['paused'] == true
                                      ? Icons.play_arrow
                                      : Icons.pause,
                                  semanticLabel: item.$1,
                                ),
                              )
                            : Text(item.$1, textAlign: TextAlign.center),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Stage cues',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e
                      in ((data['cues'] as List?) ?? []).asMap().entries)
                    SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        onPressed: data['phase'] == 'active'
                            ? () async {
                                try {
                                  await hub.sendCommand('cue', {
                                    'session': data['session'],
                                    'segment': data['index'],
                                    'index': e.key,
                                    'version':
                                        (data['cueVersions'] as List? ??
                                        [])[e.key],
                                  });
                                } catch (_) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cue not sent. Check the host connection and request control.',
                                        ),
                                      ),
                                    );
                                }
                              }
                            : null,
                        child: Text(
                          e.value as String,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: appColors(context).error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 52),
              ),
              onPressed: data['phase'] == 'active'
                  ? () => action(context, 'End service', 'end')
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End service'),
            ),
            const SizedBox(height: 12),
            Text(hub.requestResult),
          ],
          if (!wide) ...rundown,
        ],
      ],
    );
    final openStage = FilledButton.icon(
      onPressed: () => hub.showStage(!stage),
      icon: Icon(stage ? Icons.view_list : Icons.fullscreen),
      label: Text(stage ? 'Back to service overview' : 'Open stage display'),
    );
    final main = <Widget>[
      if (hub.reconnecting) ...[
        ReconnectingBanner(
          key: const ValueKey('host-reconnecting'),
          title: 'Reconnecting to host device',
          attempt: hub.reconnectAttempt,
          detail: hub.rejoiningWifi
              ? 'Rejoining ${hub.rejoinSsid}…'
              : longHostWait(hub)
              ? deviceText(
                  'Still trying. Make sure this phone is on the same Wi-Fi or hotspot as the host. Controls return when the host answers.',
                )
              : 'Controls are paused until the host answers. The host keeps the service running.',
          actions: [
            if (longHostWait(hub))
              OutlinedButton.icon(
                key: const ValueKey('open-wifi-settings'),
                onPressed: () => controller.port.openWifiSettings(),
                icon: const Icon(Icons.wifi),
                label: const Text('Open Wi-Fi settings'),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      // Commands cannot reach the host while reconnecting, so the
      // controls are dimmed and ignore taps until it answers.
      IgnorePointer(
        ignoring: hub.reconnecting,
        child: AnimatedOpacity(
          opacity: hub.reconnecting ? .45 : 1,
          duration: reduceAppMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          child: content,
        ),
      ),
      const SizedBox(height: 24),
      if (hub.mode != 'operator') wide ? Center(child: openStage) : openStage,
    ];
    return Scaffold(
      appBar: stage
          ? null
          : AppBar(
              title: Text(
                hub.mode == 'operator' ? 'Paired operator' : 'Service viewer',
              ),
              actions: [leaveButton()],
            ),
      body: SafeArea(
        child: wide
            ? SplitPage(
                mainMaxWidth: 640,
                main: ListView(
                  key: const ValueKey('paired-main-pane'),
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                  children: main,
                ),
                side: Material(
                  key: const ValueKey('paired-rundown-pane'),
                  color: appColors(context).surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: PaneLabel('Order of service'),
                      ),
                      Expanded(
                        child: rundown.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  4,
                                  24,
                                  0,
                                ),
                                child: Text(
                                  'The segments appear here when the host starts a service.',
                                  style: TextStyle(
                                    color: appColors(context).muted,
                                    height: 1.4,
                                  ),
                                ),
                              )
                            : ListView(
                                primary: false,
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                                children: rundown,
                              ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(padding: const EdgeInsets.all(20), children: main),
      ),
    );
  }
}

/// The colour of the text a stage snapshot shows: the cue's colour when the
/// host sent one, otherwise white.
Color stageCueColor(Json data) {
  final rgb = stageCueRgb(data);
  return rgb == null ? Colors.white : Color(0xff000000 | rgb);
}

/// Over a cue on screens while its screen flash is lit: a coloured
/// full-screen cue's words are then warm white, so they stay readable on
/// the flash in their own colour.
class StageFlashScope extends InheritedWidget {
  final bool lit;
  const StageFlashScope({super.key, required this.lit, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StageFlashScope>()?.lit ??
      false;
  @override
  bool updateShouldNotify(StageFlashScope old) => lit != old.lit;
}

/// How bright a pulsing cue is [seconds] after it appears: from full
/// brightness down to 55% and back, once every two seconds.
double stagePulseOpacity(double seconds) =>
    .775 + .225 * math.cos(2 * math.pi * seconds / 2);

/// How long a cue takes to slide in on screens.
const stageSlideInSeconds = .3;

/// Smooth local animation between host snapshots; freezes when the link is stale.
class StageMessage extends StatefulWidget {
  final Json data;
  final bool stale, fullscreen;

  /// Where a cue that slides in comes from: the top edge for a banner at
  /// the top, otherwise the bottom.
  final bool fromTop;

  /// The most lines a cue with "Wrap long text" may use here.
  final int wrapLines;

  /// The height of the whole screen, where this is only part of it (a
  /// banner's band): a countdown bar's thickness follows it. Null when
  /// this fills the screen.
  final double? screenHeight;

  /// The text's colour in place of the cue's own, as on a coloured
  /// full-screen cue (see [stageColouredCard]); a countdown bar keeps the
  /// cue's colour. While a screen flash lights the screen in the cue's
  /// colour, words in that colour would not read on it, so they are warm
  /// white until it settles.
  final Color? ink;
  const StageMessage({
    super.key,
    required this.data,
    required this.stale,
    this.fullscreen = false,
    this.fromTop = false,
    this.wrapLines = stageWrapLines,
    this.screenHeight,
    this.ink,
  });
  @override
  State<StageMessage> createState() => _StageMessageState();
}

class _StageMessageState extends State<StageMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  // Seconds since the cue appeared, and since the bar's time last came.
  double elapsed = 0, barElapsed = 0;
  int previousTick = 0;
  ({int total, int left})? barTime;
  // Wrapped text: the box and style it was last fitted to, the size found
  // (null when it does not fit, and then scrolls), and whether it scrolls.
  Object? wrapKey;
  double? wrapSize;
  bool wrapScrolls = false;
  String? get screenEffect => stageScreenEffect(widget.data);
  bool get sample => widget.data['cueBarSample'] == true;
  bool get animates {
    if (widget.stale) return false;
    // Scrolling text, including wrapped text too long to wrap, moves
    // itself frame by frame (see [ScrollingText]) and plays no effect.
    if (stageWrapsText(widget.data) && wrapScrolls) return false;
    if (widget.data['effect'] == 'flash') return true;
    return switch (screenEffect) {
      'pulse' => true,
      'flashHold' => elapsed < flashHoldMs / 1000,
      'slideIn' => elapsed < stageSlideInSeconds,
      'bar' => sample || (barTime != null && barFraction > 0),
      _ => false,
    };
  }

  /// How much of a countdown bar is left, from 1 down to 0.
  double get barFraction {
    if (sample) return 1 - (elapsed % 8) / 8;
    final time = barTime;
    if (time == null) return 0;
    return ((time.left - barElapsed * 1000) / time.total).clamp(0.0, 1.0);
  }

  void syncTicker() {
    if (animates && !ticker.isAnimating) {
      previousTick = 0;
      ticker.repeat();
    } else if (!animates && ticker.isAnimating) {
      ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    barTime = stageCueTime(widget.data);
    ticker =
        AnimationController(vsync: this, duration: const Duration(hours: 24))
          ..addListener(() {
            final tick = ticker.lastElapsedDuration?.inMilliseconds ?? 0;
            if (!widget.stale) {
              elapsed += (tick - previousTick) / 1000;
              barElapsed += (tick - previousTick) / 1000;
            }
            previousTick = tick;
            if (mounted) setState(() {});
            // An entrance stops the ticker once it has played.
            if (!animates) ticker.stop();
          });
    syncTicker();
  }

  @override
  void didUpdateWidget(StageMessage old) {
    super.didUpdateWidget(old);
    if (old.data['displayText'] != widget.data['displayText'] ||
        old.data['effect'] != widget.data['effect'] ||
        stageScreenEffect(old.data) != screenEffect)
      elapsed = 0;
    // Each snapshot says how long the bar has left; it runs on smoothly
    // from there until the next.
    final time = stageCueTime(widget.data);
    if (time != barTime) {
      barTime = time;
      barElapsed = 0;
    }
    syncTicker();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  /// The size [text] is wrapped at in a box [width] × [height], worked out
  /// once for each text, box and style; null when it scrolls instead.
  double? wrappedSize(
    String text,
    TextStyle style,
    double width,
    double height,
  ) {
    final key = (
      text,
      width,
      height,
      style.fontSize,
      style.fontWeight,
      style.fontStyle,
      widget.wrapLines,
    );
    if (key != wrapKey) {
      wrapKey = key;
      wrapSize = stageWrapSize(
        text,
        style,
        width: width * .94,
        height: height,
        lines: widget.wrapLines,
        min: height * stageWrapMinimum / widget.wrapLines,
        max: style.fontSize!,
      );
    }
    final scrolls = wrapSize == null;
    if (scrolls != wrapScrolls) {
      wrapScrolls = scrolls;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) syncTicker();
      });
    }
    return wrapSize;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final text = widget.data['displayText'] as String? ?? '';
      var effect = widget.data['effect'];
      final screenEffect = this.screenEffect;
      final fullHeight = widget.fullscreen && space.maxHeight.isFinite;
      final previewSize = (space.maxWidth / 7).clamp(
        42.0,
        widget.fullscreen ? 260.0 : 130.0,
      );
      final color = stageCueColor(widget.data);
      final style = TextStyle(
        // Roboto, the face the app carries, on every device: not the
        // system's own font, such as Segoe UI on Windows.
        fontFamily: stageFontFamily,
        // Start at screen height; static text then fits proportionally to width.
        // This keeps short cues large without cropping a long countdown.
        fontSize: fullHeight ? space.maxHeight * .9 : previewSize,
        height: fullHeight ? 1.1 : null,
        color: widget.ink == null
            ? color
            : StageFlashScope.of(context)
            ? const Color(0xff000000 | stageCardInk)
            : widget.ink,
        fontWeight: widget.data['bold'] == true
            ? FontWeight.bold
            : FontWeight.w500,
        fontStyle: widget.data['italic'] == true
            ? FontStyle.italic
            : FontStyle.normal,
      );
      // The time in the same face, with its digits the same width.
      final steady = style.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final height = fullHeight ? space.maxHeight : 170.0;
      final hasBar = screenEffect == 'bar' && (sample || barTime != null);
      // A countdown bar is about 2% of the screen's height, 4–10 px thick,
      // with a gap of one and a half times that between it and the words.
      final thickness = ((widget.screenHeight ?? height) * .02)
          .clamp(4.0, 10.0)
          .toDouble();
      final gap = thickness * 1.5;
      double? wrapped;
      if (stageWrapsText(widget.data) && text.trim().isNotEmpty) {
        wrapped = wrappedSize(
          text,
          // Measured in the font it is drawn in.
          DefaultTextStyle.of(context).style.merge(style),
          space.maxWidth,
          // With room for the countdown bar under it, when there is one.
          hasBar ? height - gap - thickness : height,
        );
        // Wrapped text holds still on screens (its effect still plays);
        // text too long to wrap at a readable size scrolls instead.
        if (wrapped == null) {
          effect = 'scroll';
        } else if (effect == 'scroll') {
          effect = 'static';
        }
      }
      if (effect == 'scroll') {
        return ScrollingText(
          text: text,
          style: style,
          speed:
              stageScrollSpeed(widget.data) *
              6 *
              (style.fontSize! / previewSize),
          height: fullHeight ? space.maxHeight : null,
          paused: widget.stale,
        );
      }
      // Flash or Pulse text too wide for the LED sign steps through the
      // same groups of words as the sign, in time with it, unless it is
      // wrapped, when the whole block flashes or pulses.
      final wordEffect = stageWordEffect(widget.data);
      final groups = wordEffect == null ? null : stageWordGroups(widget.data);
      final step = groups == null
          ? null
          : wordGroupAt(wordEffect!, groups.length, (elapsed * 1000).floor());
      final hidden =
          step == null &&
              (effect == 'flash' && (elapsed * 2).floor() % 2 == 1) ||
          (screenEffect == 'flashHold' &&
              elapsed < flashHoldMs / 1000 &&
              (elapsed * 2).floor() % 2 == 1);
      Widget body = groups != null
          // Every group at the size the widest fits at, so the words stay
          // the same size as they change.
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final group in groups)
                    ExcludeSemantics(
                      child: Opacity(
                        opacity: 0,
                        child: Text(
                          group,
                          style: style,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                        ),
                      ),
                    ),
                  Text(
                    groups[step!.index],
                    key: const ValueKey('stage-word-group'),
                    style: style,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                  ),
                ],
              ),
            )
          : wrapped != null
          ? Center(
              child: Text(
                text,
                key: const ValueKey('stage-wrapped'),
                style: style.copyWith(fontSize: wrapped, height: 1.1),
                maxLines: widget.wrapLines,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
              ),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              // The clock and the countdown blink their colons; the countdown
              // stays steady while paused, so a steady colon means stopped.
              child: stageShowsTime(widget.data)
                  // Every digit in a place as wide as the widest digit,
                  // so the time keeps one size and each digit its place
                  // as it counts instead of being refitted each second.
                  ? ClockText(
                      key: const ValueKey('stage-time-width'),
                      text: text,
                      style: steady,
                      blink: stageTimeBlinks(widget.data),
                      stale: widget.stale,
                    )
                  : Text(
                      text,
                      style: style,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      textAlign: TextAlign.center,
                    ),
            );
      final opacity = step != null
          ? step.opacity
          : hidden
          ? 0.0
          : screenEffect == 'pulse'
          ? stagePulseOpacity(elapsed)
          : 1.0;
      if (!hasBar) {
        body = Opacity(
          key: const ValueKey('stage-cue-opacity'),
          opacity: opacity,
          child: body,
        );
      }
      // A countdown bar sits just under the words, as wide as they are,
      // and empties over the cue's time; a cue shown until cleared has no
      // time, and no bar. The words and the bar are laid out together at
      // the words' own size and shrunk together to fit, so the bar always
      // matches the words as drawn; its thickness and gap are set so they
      // come out at their size on the screen after shrinking.
      if (hasBar) {
        final shown = wrapped != null
            ? style.copyWith(fontSize: wrapped, height: 1.1)
            : style;
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(shown),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          maxLines: wrapped != null ? widget.wrapLines : null,
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: wrapped != null ? space.maxWidth : double.infinity);
        final wordsWidth = math.max(1.0, painter.width);
        final wordsHeight = math.max(1.0, painter.height);
        // With nothing below the line (as in capitals), the bar is measured
        // from the line the last words stand on, so it sits just under them
        // rather than under the room kept for letters such as g and y.
        final lines = painter.computeLineMetrics();
        final lastLine = text.trimRight().split('\n').last;
        final standsOn =
            lines.isEmpty ||
                RegExp(r'[gjpqyQ,;()\[\]{}|@_$]').hasMatch(lastLine)
            ? wordsHeight
            : math.min(wordsHeight, lines.last.baseline);
        painter.dispose();
        final shrink = math
            .min(
              1.0,
              math.min(
                space.maxWidth / wordsWidth,
                (height - gap - thickness) / standsOn,
              ),
            )
            .clamp(.01, 1.0)
            .toDouble();
        // Nine tenths of the words' width, and never under 80 px.
        final barWidth = math.min(
          math.max(wordsWidth * .9, 80 / shrink),
          space.maxWidth / shrink,
        );
        final thick = thickness / shrink;
        body = FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: math.max(wordsWidth, barWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: standsOn,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: wordsHeight,
                    maxHeight: wordsHeight,
                    child: Opacity(
                      key: const ValueKey('stage-cue-opacity'),
                      opacity: opacity,
                      child: Text(
                        text,
                        key: wrapped != null
                            ? const ValueKey('stage-wrapped')
                            : null,
                        style: shown,
                        softWrap: wrapped != null,
                        maxLines: wrapped != null ? widget.wrapLines : null,
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        textWidthBasis: TextWidthBasis.longestLine,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: gap / shrink),
                SizedBox(
                  width: barWidth,
                  height: thick,
                  child: DecoratedBox(
                    key: const ValueKey('stage-cue-bar-track'),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(thick),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: barFraction,
                      child: DecoratedBox(
                        key: const ValueKey('stage-cue-bar'),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(thick),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Slides in from the edge once, as the cue appears; with reduced
      // motion it is simply there.
      if (screenEffect == 'slideIn') {
        final shown = reduceAppMotion(context)
            ? 1.0
            : Curves.easeOutCubic.transform(
                (elapsed / stageSlideInSeconds).clamp(0.0, 1.0),
              );
        body = ClipRect(
          child: Transform.translate(
            key: const ValueKey('stage-cue-slide'),
            offset: Offset(0, (1 - shown) * height * (widget.fromTop ? -1 : 1)),
            child: body,
          ),
        );
      }
      return SizedBox(height: height, width: space.maxWidth, child: body);
    },
  );
}

/// The largest font size from [min] to [max] at which [text] wraps onto at
/// most [lines] centred lines inside [width] × [height], 1.1 lines apart,
/// with no word split across lines; null when it does not fit at [min].
double? stageWrapSize(
  String text,
  TextStyle style, {
  required double width,
  required double height,
  required int lines,
  required double min,
  required double max,
}) {
  TextPainter painter(String value, double size, [double? maxWidth]) =>
      TextPainter(
        text: TextSpan(
          text: value,
          style: style.copyWith(fontSize: size, height: 1.1),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: maxWidth ?? double.infinity);
  double measure(String value, double size) {
    final p = painter(value, size);
    final w = p.width;
    p.dispose();
    return w;
  }

  // The widest word, which must fit on a line of its own.
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return null;
  var widest = words.first;
  var widestWidth = 0.0;
  for (final word in words) {
    final w = measure(word, max);
    if (w > widestWidth) (widest, widestWidth) = (word, w);
  }
  bool fits(double size) {
    if (measure(widest, size) > width) return false;
    final p = painter(text, size, width);
    final ok = p.height <= height && p.computeLineMetrics().length <= lines;
    p.dispose();
    return ok;
  }

  if (max < min || !fits(min)) return null;
  if (fits(max)) return max;
  var lo = min, hi = max;
  for (var i = 0; i < 14; i++) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo.floorToDouble();
}
