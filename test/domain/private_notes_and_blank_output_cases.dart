import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/feedback/feedback_message.dart';
import 'feature_cases.dart' show epoch, at, equal, rejects, service;

final revision10Cases = <String, void Function()>{
  'Legacy Times selections migrate to bundled Tinos with formatting intact':
      () {
        final old = const TextLayout(
          'AMEN',
          bold: true,
          italic: true,
          height: 2,
          speed: 18,
          align: 'right',
        ).toJson()..['font'] = 'times_new_roman';
        final layout = TextLayout.fromJson(old);
        equal(layout.toJson(), {...old, 'font': 'tinos'});
        for (final id in ['i-proton_matrix', 'i-proton_sq_matrix']) {
          final matrix = {...old, 'font': id};
          equal(TextLayout.fromJson(matrix).toJson(), matrix);
        }
      },
  'Cue cleanup runs once and preserves the retained WRAP UP formatting': () {
    const retained = TextLayout(
      'WRAP UP',
      bold: true,
      italic: true,
      speed: 23,
      font: 'i-proton_sq_matrix',
    );
    final old = AppState.fresh(epoch).toJson()..['version'] = 8;
    old['stageCues'] = [
      const TextLayout('WRAP UP').toJson(),
      const TextLayout('Nursery call').toJson(),
      retained.toJson(),
      const TextLayout('CUSTOM').toJson(),
    ];
    final migrated = AppState.fromJson(old);
    equal(migrated.stageCues.map((c) => c.toJson()).toList(), [
      retained.toJson(),
      const TextLayout('CUSTOM').toJson(),
    ]);
    migrated.stageCues.add(const TextLayout('Nursery call'));
    equal(AppState.fromJson(migrated.toJson()).stageCues.length, 3);
  },
  'Grouped list is the default and a later single-list choice persists': () {
    final state = AppState.fresh(epoch);
    equal(state.groupTemplates, true);
    state.groupTemplates = false;
    equal(AppState.fromJson(state.toJson()).groupTemplates, false);
    equal(
      importBackup(exportBackup(state, epoch), epoch).groupTemplates,
      false,
    );
  },
  'Global warnings normalize imports and templates while end screens stay independent':
      () {
        final state = AppState.fresh(epoch);
        state.defaults = state.defaults.withWarnings(const [
          WarningRule(40, TextLayout('GLOBAL')),
        ]);
        state.applySharedWarnings();
        final imported = importTemplate(
          exportJson(
            Timeline(
              'Imported',
              const [Segment('Talk', 5)],
              DisplaySettings(
                end: const TextLayout('AMEN'),
                warnings: const [WarningRule(10, TextLayout('LOCAL'))],
              ),
            ),
          ),
          'test.json',
          state.defaults,
        );
        equal(imported.display.warnings.single.cue.text, 'GLOBAL');
        equal(imported.display.end.text, 'AMEN');
        state.saveTemplate(imported);
        equal(
          AppState.fromJson(
            state.toJson(),
          ).templates.every((t) => t.display.warnings.single.seconds == 40),
          true,
        );
      },
  'Changed warning thresholds consume past crossings even while paused': () {
    final state = AppState.fresh(epoch)
      ..session = transition(service(firstMinutes: 1), 'pause', at(20));
    state.defaults = state.defaults.withWarnings(const [
      WarningRule(50, TextLayout('PAST')),
      WarningRule(40, TextLayout('NOW')),
      WarningRule(10, TextLayout('FUTURE')),
    ]);
    final legacy = state.toJson()..['version'] = 8;
    final migrated = AppState.fromJson(legacy, now: at(25));
    equal(migrated.session.warningSeen, [0, 1]);
    state.applySharedWarnings(at(25));
    equal(state.session.warningSeen, [0, 1]);
    state.session = transition(state.session, 'pause', at(30));
    equal(dueWarnings(state.session, at(59)), []);
    equal(dueWarnings(state.session, at(60)), [2]);
  },
  'Shared warning remapping covers undo and prior snapshots without replay':
      () {
        final state = AppState.fresh(epoch)
          ..session = transition(service(firstMinutes: 1), 'advance', at(45));
        state.session.prior = service(firstMinutes: 1);
        state.defaults = state.defaults.withWarnings(const [
          WarningRule(20, TextLayout('TWENTY')),
          WarningRule(10, TextLayout('TEN')),
        ]);
        state.applySharedWarnings(at(46));
        equal(state.session.undo!.warningSeen, [0]);
        equal(state.session.prior!.warningSeen, [0]);
        final undo = transition(state.session, 'undo', at(47));
        equal(dueWarnings(undo, at(47)), []);
        equal(dueWarnings(undo, at(50)), [1]);
      },
  'Speaker and private notes round trip through template JSON and backup': () {
    const segment = Segment(
      'Talk',
      5,
      speaker: 'Pastor Grace',
      notes: 'Private\nOperator reminder',
    );
    final state = AppState.fresh(epoch);
    state.saveTemplate(Timeline('Notes', [segment], state.defaults));
    final imported = importTemplate(
      exportJson(state.templates.last),
      'notes.json',
      state.defaults,
    );
    equal(imported.segments.single.toJson(), segment.toJson());
    equal(
      importBackup(
        exportBackup(state, epoch),
        epoch,
      ).templates.last.segments.single.toJson(),
      segment.toJson(),
    );
    var session = transition(state.session, 'load', epoch, value: imported);
    session = transition(session, 'start', epoch);
    equal(session.intended(epoch)!.text, '05:00');
    equal(
      session.intended(epoch)!.toJson().toString().contains('Private'),
      false,
    );
  },
  'Private metadata rejects wrong types, oversized fields and control characters':
      () {
        for (final pair in [
          ['speaker', 'a' * 81],
          ['notes', 'a' * 1001],
          ['speaker', 'a\nb'],
          ['notes', 'bad\x00'],
          ['notes', 4],
        ]) {
          rejects(
            () => Segment.fromJson({
              'name': 'Talk',
              'minutes': 5,
              pair[0] as String: pair[1],
            }),
          );
        }
        equal(Segment.fromJson({'name': 'Talk', 'minutes': 5}).speaker, '');
      },
  'Blank output persists while clock and phone warning notice continue': () {
    var s = transition(service(firstMinutes: 1), 'blank', at(10));
    s = transition(s, 'warnings', at(30));
    equal(s.outputBlank, true);
    equal(s.intended(at(30)), null);
    equal(s.automaticCue, null);
    equal(s.warningNotice!.contains('skipped'), true);
    equal(s.remaining(at(30)), 30000);
    s = recover(Session.fromJson(s.toJson()), at(31));
    equal(s.outputBlank, true);
    s = transition(s, 'timer', at(31));
    equal(s.intended(at(31))!.text, '00:29');
  },
  'Sending a cue and ending the service explicitly restore blank output': () {
    var s = transition(service(), 'blank', at(10));
    s = transition(s, 'cue', at(11), value: const TextLayout('AMEN'));
    equal(s.intended(at(11))!.text, 'AMEN');
    s = transition(s, 'blank', at(12));
    s = transition(s, 'end', at(13));
    equal(s.outputBlank, false);
    equal(s.intended(at(13))!.text, 'Hallelujah');
  },
  'Diagnostics are omitted by default and included only when supplied': () {
    FeedbackMessage draft({String? diagnostics}) => FeedbackMessage(
      title: 'Test',
      message: 'Check',
      contact: 'user@example.com',
      version: appVersion,
      diagnostics: diagnostics,
    );
    equal(draft().body.contains('diagnostics'), false);
    equal(
      draft(diagnostics: 'Output adapter: Simulator').body.contains(
        'Optional diagnostics (reviewed):\nOutput adapter: Simulator',
      ),
      true,
    );
    equal(feedbackRecipient, 'immanuelproton@gmail.com');
  },
  'New schema versions retain zero and per-template end choices': () {
    final state = AppState.fresh(epoch);
    state.defaults = state.defaults.withZero(const TextLayout('STOP'));
    state.templates[0] = state.templates[0].withDisplay(
      state.templates[0].display.withEnd(const TextLayout('AMEN')),
    );
    state.applySharedZero();
    final restored = importBackup(exportBackup(state, epoch), epoch);
    equal(restored.templates.first.display.zero!.text, 'STOP');
    equal(restored.templates.first.display.end.text, 'AMEN');
    equal(restored.templates.last.display.end.text, 'Hallelujah');
    equal(restored.toJson()['version'], 14);
    equal(restored.templates.first.toJson()['schemaVersion'], 4);
    equal(jsonDecode(exportBackup(state, epoch))['schemaVersion'], 7);
  },
};
