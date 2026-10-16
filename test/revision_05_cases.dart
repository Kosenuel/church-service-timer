import 'dart:convert';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/display_connection.dart';
import 'package:church_service_timer/warning_notifications.dart';
import 'feature_cases.dart' show epoch, at, equal, rejects, service;

final revision05Cases = <String, void Function()>{
  'Overtime uses elapsed time while stage output retains At Zero': () {
    final s = service(firstMinutes: 1, warnings: []);
    equal(s.balance(at(60)), 0);
    equal(s.balance(at(83)), -23000);
    equal(s.overtime(at(83)), 23000);
    equal(s.remaining(at(83)), 0);
    equal(s.intended(at(83))!.text, '00:00');
    s.timeline = Timeline(
      s.timeline!.name,
      s.timeline!.segments,
      s.timeline!.display.withZero(const TextLayout('DONE')),
    );
    equal(s.intended(at(90))!.text, 'DONE');
    equal(s.index, 0);
  },
  'Pause and restored state freeze overtime until resumed': () {
    var s = transition(service(firstMinutes: 1, warnings: []), 'pause', at(83));
    s = Session.fromJson(jsonDecode(jsonEncode(s.toJson())) as Json);
    equal(s.balance(at(200)), -23000);
    s = transition(s, 'pause', at(200));
    equal(s.balance(at(210)), -33000);
  },
  'Added time pays down overtime and updates allocated duration': () {
    var s = transition(
      service(firstMinutes: 1, warnings: []),
      'adjust',
      at(83),
      value: 120,
    );
    equal(s.balance(at(83)), 97000);
    equal(s.allocatedMs, 180000);
    equal(s.formatted(at(90)), '01:30');
    s = transition(s, 'adjust', at(90), value: -100);
    equal(s.balance(at(90)), 0);
    equal(s.allocatedMs, 90000);
  },
  'Partial added time preserves remaining overtime across reload': () {
    var s = transition(
      service(firstMinutes: 1, warnings: []),
      'adjust',
      at(83),
      value: 10,
    );
    equal(s.balance(at(83)), -13000);
    equal(s.allocatedMs, 70000);
    s = recover(Session.fromJson(s.toJson()), at(90));
    equal(s.balance(at(90)), -20000);
    equal(s.held, false);
  },
  'Removal at overtime is a no-op and upper bound still rejects': () {
    var s = service(firstMinutes: 1, warnings: []);
    s = transition(s, 'adjust', at(83), value: -120);
    equal(s.balance(at(83)), -23000);
    equal(s.allocatedMs, 60000);
    s = transition(s, 'adjust', at(83), value: 6022);
    equal(s.remaining(at(83)), maxRemainingMs);
    rejects(() => transition(s, 'adjust', at(83), value: 1));
  },
  'Undo restores adjusted allocation and running overtime': () {
    var s = transition(
      service(firstMinutes: 1, warnings: []),
      'adjust',
      at(1),
      value: 30,
    );
    s = transition(s, 'advance', at(113));
    equal(s.undoAllocatedMs, 90000);
    equal(s.undoBalance(at(118)), -28000);
    s = transition(s, 'undo', at(118));
    equal(s.balance(at(118)), -28000);
    equal(s.allocatedMs, 90000);
    equal(s.paused, false);
  },
  'Undo restores paused overtime and discards next-segment edits': () {
    var s = transition(service(firstMinutes: 1, warnings: []), 'pause', at(83));
    s = transition(s, 'advance', at(90));
    s = transition(s, 'adjust', at(91), value: 120);
    s = transition(s, 'undo', at(100));
    equal(s.balance(at(200)), -23000);
    equal(s.allocatedMs, 60000);
    equal(s.run!.adjustmentsMs[1], 0);
    equal(s.paused, true);
  },
  'Rehearsal, recovery holds and end preserve signed operator time': () {
    var s = service(firstMinutes: 1, rate: 10, warnings: []);
    equal(s.balance(at(9)), -30000);
    s = recover(s, at(10, boot: 'new-boot'));
    equal(s.held, true);
    equal(s.uncertain, true);
    equal(s.balance(at(10, boot: 'new-boot')), -40000);
    s = transition(s, 'end', at(11, boot: 'new-boot'));
    equal(s.balance(at(20, boot: 'new-boot')), -50000);
    equal(s.intended(at(20, boot: 'new-boot'))!.text, 'Hallelujah');
    equal(
      ServiceReport.fromSession(s, at(11, boot: 'new-boot')).totalMs,
      110000,
    );
  },
  'Warning colour uses configured eligible thresholds': () {
    final s = service(
      firstMinutes: 1,
      warnings: [
        const WarningRule(120, TextLayout('TOO EARLY')),
        const WarningRule(10, TextLayout('WRAP')),
      ],
    );
    equal(s.nearWarning(at(30)), false);
    equal(s.nearWarning(at(50)), true);
    equal(s.nearWarning(at(60)), false);
    equal(service(firstMinutes: 1, warnings: []).nearWarning(at(55)), false);
  },
  'Warnings fire once and no obsolete alarm remains during overtime': () {
    var s = service(
      firstMinutes: 1,
      warnings: [
        const WarningRule(0, TextLayout('STOP'), destination: 'stage'),
      ],
    );
    s = transition(s, 'warnings', at(83));
    equal(s.intended(at(84))!.text, 'STOP');
    equal(s.intended(at(92))!.text, '00:00');
    equal(warningNotificationPlan(s, at(92))['alarms'], []);
    s = transition(s, 'adjust', at(92), value: 120);
    equal(dueWarnings(s, at(300)), []);
  },
  'Version four upgrades without changing saved cues or zero output': () {
    final state = AppState.fresh(epoch);
    state.session = service(firstMinutes: 1, warnings: []);
    final data = state.toJson()..['version'] = 4;
    final restored = AppState.fromJson(data);
    equal(restored.toJson()['version'], 5);
    equal(
      restored.stageCues.map((v) => v.toJson()).toList(),
      state.stageCues.map((v) => v.toJson()).toList(),
    );
    equal(restored.session.balance(at(83)), -23000);
  },
  'Display labels distinguish simulator and actual adapter connectivity': () {
    equal(
      DisplayConnection.fromAdapter(simulated: true, connected: true).label,
      'Simulator',
    );
    equal(
      DisplayConnection.fromAdapter(simulated: false, connected: true).label,
      'Display connected',
    );
    equal(
      DisplayConnection.fromAdapter(simulated: true, connected: false).label,
      'Disconnected',
    );
    equal(
      DisplayConnection.fromAdapter(simulated: false, connected: false).label,
      'Disconnected',
    );
  },
};
