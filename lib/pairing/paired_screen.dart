import 'package:church_service_timer/shared/device_words.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/programs/send_program_views.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/reconnect_banner.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
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
      SystemChrome.setPreferredOrientations(
        next
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [],
      ),
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
      unawaited(SystemChrome.setPreferredOrientations([]));
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
                  padding: const EdgeInsets.all(24),
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
        ],
      ],
    );
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
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
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
            if (hub.mode != 'operator')
              FilledButton.icon(
                onPressed: () => hub.showStage(!stage),
                icon: Icon(stage ? Icons.view_list : Icons.fullscreen),
                label: Text(
                  stage ? 'Back to service overview' : 'Open stage display',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Smooth local animation between host snapshots; freezes when the link is stale.
class StageMessage extends StatefulWidget {
  final Json data;
  final bool stale, fullscreen;
  const StageMessage({
    super.key,
    required this.data,
    required this.stale,
    this.fullscreen = false,
  });
  @override
  State<StageMessage> createState() => _StageMessageState();
}

class _StageMessageState extends State<StageMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  double elapsed = 0;
  int previousTick = 0;
  bool get animates =>
      !widget.stale &&
      (widget.data['effect'] == 'scroll' || widget.data['effect'] == 'flash');
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
    ticker =
        AnimationController(vsync: this, duration: const Duration(hours: 24))
          ..addListener(() {
            final tick = ticker.lastElapsedDuration?.inMilliseconds ?? 0;
            if (!widget.stale) elapsed += (tick - previousTick) / 1000;
            previousTick = tick;
            if (mounted) setState(() {});
          });
    syncTicker();
  }

  @override
  void didUpdateWidget(StageMessage old) {
    super.didUpdateWidget(old);
    if (old.data['displayText'] != widget.data['displayText'] ||
        old.data['effect'] != widget.data['effect'])
      elapsed = 0;
    syncTicker();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final text = widget.data['displayText'] as String? ?? '';
      final effect = widget.data['effect'];
      final fullHeight = widget.fullscreen && space.maxHeight.isFinite;
      final previewSize = (space.maxWidth / 7).clamp(
        42.0,
        widget.fullscreen ? 260.0 : 130.0,
      );
      final style = TextStyle(
        // Start at screen height; static text then fits proportionally to width.
        // This keeps short cues large without cropping a long countdown.
        fontSize: fullHeight ? space.maxHeight * .9 : previewSize,
        height: fullHeight ? 1.1 : null,
        color: Colors.white,
        fontWeight: widget.data['bold'] == true
            ? FontWeight.bold
            : FontWeight.w500,
        fontStyle: widget.data['italic'] == true
            ? FontStyle.italic
            : FontStyle.normal,
      );
      if (effect == 'scroll') {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final travel = space.maxWidth + painter.width;
        final speed =
            ((widget.data['speed'] as num?) ?? 12).toDouble() *
            6 *
            (style.fontSize! / previewSize);
        final x = space.maxWidth - (elapsed * speed) % travel;
        final height = fullHeight ? space.maxHeight : painter.height + 24;
        final top = (height - painter.height) / 2;
        painter.dispose();
        return SizedBox(
          height: height,
          width: space.maxWidth,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: x,
                  top: top,
                  child: Text(
                    text,
                    style: style,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Opacity(
        opacity: effect == 'flash' && (elapsed * 2).floor() % 2 == 1 ? 0 : 1,
        child: SizedBox(
          height: fullHeight ? space.maxHeight : 170,
          width: space.maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            // The clock and the countdown blink their colons; the countdown
            // stays steady while paused, so a steady colon means stopped.
            child:
                widget.data['outputMode'] == 'Clock' ||
                    (widget.data['displayIsTimer'] == true &&
                        effect == 'static')
                ? ClockText(
                    text: text,
                    style: style,
                    blink:
                        widget.data['clockBlink'] != false &&
                        (widget.data['outputMode'] == 'Clock' ||
                            widget.data['paused'] != true),
                    stale: widget.stale,
                  )
                : Text(
                    text,
                    style: style,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
      );
    },
  );
}
