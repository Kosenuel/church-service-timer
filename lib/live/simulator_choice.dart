import 'package:flutter/material.dart';
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
  Widget displayPreview() =>
      c.stageSimulator ? stageSimulatorPreview() : liveMatrix();

  /// A live copy of what a stage screen would show, in a 16:9 box.
  Widget stageSimulatorPreview() => Semantics(
    key: const ValueKey('stage-simulator-preview'),
    label: 'Stage simulator preview',
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: Listenable.merge([c, c.liveClock]),
              builder: (context, _) => StageSurface(
                data: c.stageSimulatorSnapshot(),
                stale: c.state.session.held || c.state.session.disconnected,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The two-way choice under the Simulator in Choose display.
  Widget simulatorKindChoice() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
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
    ),
  );
}
