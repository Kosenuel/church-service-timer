import 'package:church_service_timer/screens/led_preview.dart';
import 'package:church_service_timer/screens/screen_group_note.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

/// What the Simulator stands in for: an LED sign or a stage screen. The
/// choice is remembered on this device and changed from the chip beside
/// "Display preview" or from Choose display.
extension SimulatorChoice on HomeState {
  /// Whether the choice can be changed now. Locked controls, and a phone
  /// that has handed control to another, leave it as it is.
  bool get canChooseSimulatorKind =>
      !controlsLocked && c.pairing.localControl && !c.corrupt;

  /// The heading over a display preview. Its chip names the Simulator by
  /// what it stands in for and, unless [secondScreen] has taken its
  /// place, opens the choice between the two.
  Widget displayPreviewHeader({bool secondScreen = false}) =>
      DisplayPreviewHeader(
        connection: c.displayConnection,
        secondScreen: secondScreen,
        simulatorKind: c.state.simulatorKind,
        onSimulatorKind: canChooseSimulatorKind ? c.setSimulatorKind : null,
      );

  /// The picture of the display: the LED matrix, or a stage screen where
  /// the Simulator stands in for one.
  ///
  /// With a real LED sign as the display, the sign keeps a small strip of
  /// its own above the stage picture (what this device's own screen
  /// shows), so both are in view at once; with the LED simulator the big
  /// picture is the sign itself, as before.
  Widget displayPreview() {
    if (c.stageSimulator) return stageSimulatorPreview();
    // With the second screen open its copy is already under the sign's
    // preview, so the sign keeps its full-size picture.
    if (c.destination == 'led' &&
        c.hardware.enabled &&
        c.port.stageOutput?.open != true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedSignStrip(controller: c),
          const SizedBox(height: 10),
          // No taller than the sign's picture was, so the panes below
          // keep their room.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: stageSimulatorPreview(),
            ),
          ),
        ],
      );
    }
    return liveMatrix();
  }

  /// A live copy of what a stage screen would show, in a 16:9 box.
  Widget stageSimulatorPreview() => Semantics(
    key: const ValueKey('stage-simulator-preview'),
    label: 'Stage simulator preview',
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: Listenable.merge([c, c.liveClock]),
            builder: (context, _) {
              final data = c.stageSimulatorSnapshot();
              return ColoredBox(
                color: stageBackdropOf(data),
                child: StageSurface(
                  data: data,
                  stale: c.state.session.held || c.state.session.disconnected,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  /// The two-way choice under the Simulator in Choose display, and, for a
  /// stage screen, what it shows under the time, in the words every
  /// stage screen's choice uses.
  Widget simulatorKindChoice() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        simulatorKindButtons(),
        if (c.state.simulatorKind == 'stage') ...[
          const SizedBox(height: 8),
          ScreenGroupNote(
            controller: c,
            screen: thisScreenKey,
            locked: !canChooseSimulatorKind,
          ),
        ],
      ],
    ),
  );

  Widget simulatorKindButtons() => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Simulate', style: Theme.of(context).textTheme.titleSmall),
      SegmentedButton<String>(
        key: const ValueKey('simulator-kind'),
        showSelectedIcon: false,
        segments: [
          for (final kind in simulatorKinds.entries)
            ButtonSegment(value: kind.key, label: Text(kind.value)),
        ],
        selected: {c.state.simulatorKind},
        onSelectionChanged: canChooseSimulatorKind && !c.busy
            ? (kinds) => c.setSimulatorKind(kinds.single)
            : null,
      ),
    ],
  );
}
