import 'package:flutter/material.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/windows/second_screen.dart';

/// Where Live's display preview puts a copy of the second screen.
enum SecondScreenPreviewPlace {
  /// No copy: the preview is as it is without a second screen.
  none,

  /// In place of the Simulator.
  replaces,

  /// Under the preview that is already there.
  beneath,
}

/// Where the copy goes while the second screen is [showing]. [sign]: an
/// LED sign is the display. [screens]: the display is phone, tablet or
/// web stage screens.
///
/// The Simulator alone gives way to it. One real display keeps its
/// preview, with the copy under it. With a sign and stage screens both
/// in use the preview is left alone.
SecondScreenPreviewPlace secondScreenPreviewPlace({
  required bool showing,
  required bool sign,
  required bool screens,
}) => !showing || (sign && screens)
    ? SecondScreenPreviewPlace.none
    : sign || screens
    ? SecondScreenPreviewPlace.beneath
    : SecondScreenPreviewPlace.replaces;

/// The second screen on Live: what it is doing, in words, beside the one
/// button that changes it. A phone has no second screen and shows nothing.
extension SecondScreenControl on HomeState {
  /// Where the copy of the second screen goes in the display preview
  /// now. It is there only while the second screen is showing: Stop, Esc
  /// on that screen and unplugging it all take it away.
  SecondScreenPreviewPlace get secondScreenPreviewNow =>
      secondScreenPreviewPlace(
        showing: c.secondScreen?.host.open ?? false,
        sign: c.hardware.enabled,
        screens: c.destination == 'mobile',
      );

  /// The display preview's main picture: [usual], or the copy of the
  /// second screen where that stands in for the Simulator.
  Widget previewOrSecondScreen(Widget usual) =>
      secondScreenPreviewNow == SecondScreenPreviewPlace.replaces
      ? secondScreenPreview()
      : usual;

  /// The copy of the second screen to add under the preview; nothing
  /// unless it belongs there.
  List<Widget> secondScreenPreviewBeneath() =>
      secondScreenPreviewNow == SecondScreenPreviewPlace.beneath
      ? [
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: secondScreenPreview(),
          ),
        ]
      : const [];

  /// A small live copy of what the second screen shows, in that screen's
  /// shape, with its name under it.
  Widget secondScreenPreview() {
    final rect = c.secondScreen?.showingOn?.rect;
    final width = rect == null ? 16 : rect[2] - rect[0];
    final height = rect == null ? 9 : rect[3] - rect[1];
    return Column(
      key: const ValueKey('second-screen-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: width > 0 && height > 0 ? width / height : 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.black,
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: Listenable.merge([c, c.liveClock]),
                  builder: (context, _) =>
                      StageSurface(data: c.stageWindowSnapshot(), stale: false),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Second screen',
          style: TextStyle(fontSize: 12, color: appColors(context).muted),
        ),
      ],
    );
  }

  /// The lines to add under the stage preview; none on a phone.
  List<Widget> secondScreenControl() {
    final second = c.secondScreen;
    if (second == null) return const [];
    final colors = appColors(context);
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.muted);
    final host = second.host;
    final others = second.others;
    if (others.isEmpty && !host.open) {
      return [
        const SizedBox(height: 12),
        Text(
          'No second screen connected',
          key: const ValueKey('live-second-screen'),
          style: muted,
        ),
      ];
    }
    final showing = second.showingOn;
    final target = second.target;
    final status = !host.open
        ? 'Second screen: not showing'
        : showing == null
        ? 'Showing on the second screen'
        : host.connected
        ? 'Showing on ${stageMonitorLabel(showing)}'
        : 'Opening on ${stageMonitorLabel(showing)}…';
    return [
      const SizedBox(height: 12),
      SizedBox(
        key: const ValueKey('live-second-screen'),
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              status,
              key: const ValueKey('live-second-screen-status'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!host.open && others.length > 1)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: DropdownButton<int>(
                  key: const ValueKey('live-second-screen-choice'),
                  value: target?.index,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: controlsLocked
                      ? null
                      : (index) => second.choose(
                          others.firstWhere((s) => s.index == index),
                        ),
                  items: [
                    for (final screen in others)
                      DropdownMenuItem(
                        value: screen.index,
                        child: Text(
                          stageMonitorLabel(screen),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            if (host.open)
              OutlinedButton(
                key: const ValueKey('live-second-screen-stop'),
                onPressed: controlsLocked ? null : second.stop,
                child: const Text('Stop'),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('live-second-screen-show'),
                onPressed: controlsLocked || target == null
                    ? null
                    : () => second.show(target),
                icon: const Icon(Icons.connected_tv, size: 20),
                label: const Text('Show on second screen'),
              ),
          ],
        ),
      ),
      if (second.note case final note? when !host.open)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            note,
            key: const ValueKey('live-second-screen-note'),
            style: muted,
          ),
        ),
      if (host.error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            error,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ),
    ];
  }
}
