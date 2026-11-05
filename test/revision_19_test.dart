import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/hardware/hardware_output.dart';
import 'domain_test.dart' show start, after, running, FakePort;
import 'hardware_integration_test.dart' show W2Port, setup, flush;

class BackgroundClockPort extends W2Port {
  bool background = false;
  @override
  Future<bool> setActiveService(bool active) async => background = active;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Second precision survives programs, state, CSV, backup and report', () {
    final program = Timeline('Precise', const [
      Segment('Short', 0, seconds: 35),
      Segment('Long', 59, seconds: 59),
    ], DisplaySettings());
    final state = AppState.fresh(start)..clockFormat = '12h';
    state.saveTemplate(program);
    expect(
      Timeline.fromJson(program.toJson()).segments.first.durationMs,
      35000,
    );
    expect(
      importPrograms(
        exportCsv(program),
        'program.csv',
        state.defaults,
      ).single.segments.last.durationMs,
      3599000,
    );
    final restored = importBackup(exportBackup(state, start), start);
    expect(restored.clockFormat, '12h');
    expect(restored.templates.last.segments.first.seconds, 35);
    var s = transition(state.session, 'load', start, value: program);
    s = transition(s, 'start', start);
    s = transition(s, 'end', after(5));
    expect(ServiceReport.fromSession(s, after(5)).rows.first.plannedMs, 35000);
  });
  test(
    'Legacy over-hour programs remain readable; new saves and starts respect 59:59',
    () {
      final old = Timeline('Old', const [
        Segment('Legacy', 90),
      ], DisplaySettings());
      final state = AppState.fresh(start);
      state.templates.add(old);
      expect(
        AppState.fromJson(
          state.toJson(),
        ).templates.last.segments.single.minutes,
        90,
      );
      expect(
        () => state.saveTemplate(old.renamed('New')),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => transition(state.session, 'load', start, value: old),
        throwsA(isA<RuleError>()),
      );
      final maximum = transition(running(), 'adjust', start, value: 2999);
      expect(maximum.remaining(start), 3599000);
      expect(
        () => transition(maximum, 'adjust', start, value: 1),
        throwsA(isA<RuleError>()),
      );
    },
  );
  test(
    'Jump marks skipped segments, preserves pause and Undo restores metrics',
    () {
      var s = transition(running(), 'pause', after(10));
      final before = jsonEncode(s.run!.toJson());
      s = transition(s, 'jump', after(10), value: 2);
      expect(s.index, 2);
      expect(s.paused, true);
      expect(s.run!.skipped, {1});
      expect(s.run!.actualMs.first, 10000);
      final report = ServiceReport.fromSession(
        transition(s, 'end', after(15)),
        after(15),
      );
      expect(report.rows[1].skipped, true);
      expect(exportReportCsv(report), contains('Skipped'));
      expect(ServiceReport.fromJson(report.toJson()).rows[1].skipped, true);
      s = transition(s, 'undo', after(10));
      expect(s.index, 0);
      expect(s.paused, true);
      expect(jsonEncode(s.run!.toJson()), before);
      expect(
        () => transition(s, 'jump', start, value: 0),
        throwsA(isA<RuleError>()),
      );
    },
  );
  test(
    'Clock continues countdown and timed messages return to underlying mode',
    () {
      var s = transition(running(), 'clock', start);
      expect(s.outputMode(after(30)), 'Clock');
      expect(s.remaining(after(30)), 570000);
      s = transition(
        s,
        'message',
        after(30),
        value: const StageOutputMessage(TextLayout('WAIT'), seconds: 5),
      );
      expect(s.intended(after(34))!.text, 'WAIT');
      expect(s.outputMode(after(35)), 'Clock');
      s = transition(s, 'blank', after(35));
      expect(s.outputMode(after(40)), 'Blank');
      s = transition(s, 'blank', after(40));
      expect(s.outputMode(after(40)), 'Clock');
      s = transition(s, 'timer', after(40));
      expect(s.intended(after(40))!.text, '09:20');
    },
  );
  test(
    'Clock formats handle midnight, noon and persistence; countdown format unchanged',
    () {
      int time(int hour) =>
          DateTime(2026, 10, 26, hour, 4).millisecondsSinceEpoch;
      expect(stageClockText(time(0), '12h'), '12:04 AM');
      expect(stageClockText(time(12), '12h'), '12:04 PM');
      expect(stageClockText(time(23), '24h'), '23:04');
      final old = AppState.fresh(start).toJson()..remove('clockFormat');
      expect(AppState.fromJson(old).clockFormat, '24h');
      final s = transition(running(), 'clock', start)..clockFormat = '12h';
      expect(Session.fromJson(s.toJson()).clockFormat, '12h');
      expect(s.formatted(after(60)), '09:00');
    },
  );
  test(
    'Bulk JSON preserves formatting, seconds and notes only when opted in; CSV roundtrip',
    () {
      final state = AppState.fresh(start);
      final programs = [
        Timeline('Youth, Sunday', const [
          Segment(
            'Talk',
            2,
            seconds: 15,
            notes: 'PRIVATE',
            speaker: '=Speaker',
            protected: true,
          ),
        ], DisplaySettings(end: const TextLayout('Peace', bold: true))),
      ];
      final plain = exportProgramsJson(programs);
      expect(plain, isNot(contains('PRIVATE')));
      final restored = importPrograms(
        exportProgramsJson(programs, privateNotes: true),
        'programs.json',
        state.defaults,
      ).single;
      expect(restored.toJson(), programs.single.toJson());
      final csv = exportProgramsCsv(programs, privateNotes: true);
      final fromCsv = importPrograms(
        csv,
        'programs.csv',
        state.defaults,
      ).single;
      expect(fromCsv.name, 'Youth, Sunday');
      expect(
        fromCsv.segments.single.toJson(),
        programs.single.segments.single.toJson(),
      );
      expect(
        () => importPrograms(
          exportProgramsJson([programs.single, programs.single]),
          'programs.json',
          state.defaults,
        ),
        throwsA(isA<RuleError>()),
      );
    },
  );
  test(
    'Recovery uses seconds and respects protected and sub-minute segments',
    () {
      final s = running()
        ..timeline = Timeline('Timing', const [
          Segment('Now', 1),
          Segment('Short', 0, seconds: 30),
          Segment('Protected', 5, seconds: 45, protected: true),
          Segment('Talk', 2, seconds: 15),
        ], DisplaySettings());
      final plan = timeRecoveryPlanSeconds(s, 75);
      expect(plan.map((v) => v.durationSeconds), [30, 345, 60]);
      expect(() => timeRecoveryPlanSeconds(s, 76), throwsA(isA<RuleError>()));
    },
  );
  test(
    'Clock sends once, changes format once, recalibrates on wall change without tick uploads',
    () async {
      final p = W2Port(), c = await setup(p);
      addTearDown(c.dispose);
      await c.act('clock');
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.clock);
      expect(p.sent.last.deadline, isNull);
      final count = p.sent.length;
      p.at = after(30);
      await c.tick();
      await flush();
      expect(p.sent.length, count);
      expect(c.pairedSnapshot(false)['displayIsTimer'], false);
      await c.commit((draft, _) => draft.clockFormat = '12h');
      await flush();
      expect(p.sent.length, count + 1);
      p.at = after(31, wallShift: 120000);
      await c.tick();
      await flush();
      expect(p.sent.length, count + 2);
      p.at = after(32, wallShift: 120000);
      await c.tick();
      await flush();
      expect(p.sent.length, count + 2);
    },
  );
  test(
    'Reconnect refreshes current countdown and keeps last acknowledged preview during connection',
    () async {
      final p = W2Port(), c = await setup(p);
      addTearDown(c.dispose);
      await c.hardware.disconnect();
      p.at = after(25);
      await c.tick();
      expect(c.hardware.preview(c.now).any((v) => v), true);
      p.nativeGeneration++;
      await c.hardware.connect('synthetic-w2', 'synthetic');
      await flush();
      expect(c.hardware.held, false);
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
      expect(p.sent.last.deadline, start.wall + 600000);
    },
  );
  test(
    'Reconnect preserves deliberate blank; expired message returns to clock instead of replaying',
    () async {
      final p = W2Port(), c = await setup(p);
      addTearDown(c.dispose);
      await c.act('clock');
      await flush();
      await c.act('blank');
      await flush();
      await c.hardware.disconnect();
      await c.hardware.connect('synthetic-w2', 'synthetic');
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.blank);
      await c.act('blank');
      await flush();
      await c.act(
        'message',
        value: const StageOutputMessage(TextLayout('WAIT'), seconds: 2),
      );
      await flush();
      await c.hardware.disconnect();
      p.at = after(10);
      await c.tick();
      await c.hardware.connect('synthetic-w2', 'synthetic');
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.clock);
    },
  );
  test(
    'Post-service message expiry runs in background and never alters the completed report',
    () async {
      final p = BackgroundClockPort(), c = await setup(p);
      addTearDown(c.dispose);
      p.at = after(10);
      await c.act('end');
      await flush();
      final report = jsonEncode(c.state.reports.single.toJson());
      await c.act('clock');
      await flush();
      await c.act(
        'message',
        value: const StageOutputMessage(TextLayout('AMEN'), seconds: 5),
      );
      await flush();
      expect(p.background, true);
      p.at = after(16);
      await c.tick();
      await flush();
      expect(c.hardware.accepted!.kind, HardwareOutputKind.clock);
      await c.checkpoint();
      expect(jsonEncode(c.state.reports.single.toJson()), report);
      await c.act('endScreen');
      await flush();
      expect(c.hardware.accepted!.reason, HardwareOutputReason.endScreen);
    },
  );
  test(
    'Failed persistence never changes output mode or sends an upload',
    () async {
      final p = W2Port(), c = await setup(p);
      addTearDown(c.dispose);
      final count = p.sent.length;
      p.fail = true;
      expect(await c.act('clock'), false);
      await flush();
      expect(c.state.session.showClock, false);
      expect(p.sent.length, count);
    },
  );
  test(
    'Deleting saved program leaves the active program snapshot intact',
    () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      final program = c.state.templates.first;
      await c.act('load', value: program);
      await c.act('start');
      final before = jsonEncode(c.state.session.timeline!.toJson());
      await c.commit((draft, _) => draft.deleteTemplate(program));
      expect(jsonEncode(c.state.session.timeline!.toJson()), before);
    },
  );
  test(
    'Warnings and prepared cues overlay clock, then return without stopping the timer',
    () {
      var s = transition(running(), 'clock', start);
      s.automaticCue = const TextLayout('WRAP UP');
      s.automaticCueAt = after(2);
      s.automaticCueDurationMs = 5000;
      expect(s.outputMode(after(3)), 'Cue');
      expect(s.intended(after(3))!.text, 'WRAP UP');
      expect(s.outputMode(after(7)), 'Clock');
      expect(s.remaining(after(7)), 593000);
      s = transition(s, 'cue', after(8), value: const TextLayout('AMEN'));
      expect(s.outputMode(after(8)), 'Cue');
      s = transition(s, 'clearCue', after(9));
      expect(s.outputMode(after(9)), 'Clock');
      s = transition(
        s,
        'message',
        after(10),
        value: const StageOutputMessage(TextLayout('WAIT')),
      );
      expect(Session.fromJson(s.toJson()).outputMode(after(10)), 'Message');
    },
  );
}
