import 'package:flutter/material.dart';

import 'package:church_service_timer/shared/app_theme.dart';

/// Shows that a connection is being recovered automatically: a spinner, what
/// is reconnecting, the attempt number and what still works meanwhile.
class ReconnectingBanner extends StatelessWidget {
  final String title, detail;
  final int attempt;
  final List<Widget> actions;
  const ReconnectingBanner({
    super.key,
    required this.title,
    required this.detail,
    this.attempt = 0,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. ${attempt > 0 ? 'Attempt $attempt. ' : ''}$detail',
      excludeSemantics: true,
      child: Material(
        color: colors.warning.withValues(alpha: .14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.warning.withValues(alpha: .5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: reduce
                        ? Icon(Icons.sync, size: 20, color: colors.warning)
                        : CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colors.warning,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      attempt > 0 ? '$title · attempt $attempt' : title,
                      style: TextStyle(
                        color: colors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(detail),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact spinner chip for full-screen stage displays.
class ReconnectingChip extends StatelessWidget {
  final String label;
  const ReconnectingChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withValues(alpha: .6)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: reduce
                    ? const Icon(Icons.sync, size: 16, color: Colors.amber)
                    : const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.amber,
                      ),
              ),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Colors.amber)),
            ],
          ),
        ),
      ),
    );
  }
}
