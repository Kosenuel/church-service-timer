import 'package:flutter/material.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';

class RunningServiceBar extends StatelessWidget implements PreferredSizeWidget {
  final AppController controller;
  final double height;
  const RunningServiceBar({
    super.key,
    required this.controller,
    this.height = 72,
  });
  factory RunningServiceBar.forContext(
    BuildContext context, {
    required AppController controller,
  }) => RunningServiceBar(
    controller: controller,
    height: 44 + MediaQuery.textScalerOf(context).scale(28),
  );
  @override
  Size get preferredSize => Size.fromHeight(height);
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, controller.liveClock]),
    builder: (ctx, _) {
      final c = controller;
      if (!c.ready || !c.liveSession.active || c.pairing.joined)
        return const SizedBox.shrink();
      final s = c.liveSession, colors = appColors(ctx);
      final overtime = s.balance(c.now) < 0;
      final warning = s.nearWarning(c.now);
      final color = overtime
          ? colors.error
          : warning
          ? colors.warning
          : colors.accent;
      final status =
          '${overtime ? '+${formatTime(s.overtime(c.now))}' : s.formatted(c.now)} ${overtime ? 'overtime' : 'remaining'}${s.paused
              ? ' · Paused'
              : warning
              ? ' · Warning'
              : ''}';
      return Material(
        color: colors.surface,
        child: InkWell(
          key: const ValueKey('running-service-bar'),
          onTap: () => c.liveNavigation.value++,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: MediaQuery.textScalerOf(ctx).scale(14) > 19
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            s.paused
                                ? Icons.pause_circle_outline
                                : Icons.timelapse,
                            color: color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.timeline!.segments[s.index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Return to Live',
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              fontSize: 12,
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 18),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        s.paused ? Icons.pause_circle_outline : Icons.timelapse,
                        color: color,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.timeline!.segments[s.index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: color, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Return to Live',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          fontSize: 12,
                        ),
                      ),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
