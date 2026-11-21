import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/hardware_output.dart';
import 'package:flutter_test/flutter_test.dart';

import 'feature_cases.dart' show epoch, at;

Timeline program({bool noEnd = true}) => Timeline(
  noEnd ? 'Evening Prayer' : 'Morning Prayer',
  const [Segment('Welcome', 3), Segment('Prayer', 2)],
  noEnd ? DisplaySettings(end: null) : DisplaySettings(),
);

/// A service of [program] that has run its first segment and ended.
Session ended({bool noEnd = true}) {
  var s = transition(
    Session(id: 'idle', anchor: epoch),
    'load',
    epoch,
    value: program(noEnd: noEnd),
  );
  s = transition(s, 'start', at(1));
  return transition(s, 'end', at(60));
}

void main() {
  group('a service with no end screen', () {
    test('shows the clock when it ends', () {
      final s = ended();
      final now = at(61);
      expect(s.phase, 'ended');
      expect(s.endsOnClock, isTrue);
      expect(s.outputMode(now), 'Clock');
      expect(s.outputKind, 'Clock');
      expect(
        jsonEncode(s.intended(now)!.toJson()),
        jsonEncode(clockLayout(now.wall, s.clockFormat).toJson()),
      );
    });

    test('a service with an end screen still shows it', () {
      final s = ended(noEnd: false);
      expect(s.endsOnClock, isFalse);
      expect(s.outputMode(at(61)), 'End screen');
      expect(s.intended(at(61))!.text, 'Hallelujah');
    });

    test('blank, cues and Show end screen go back to the clock', () {
      var s = ended();
      s = transition(s, 'blank', at(62));
      expect(s.outputMode(at(62)), 'Blank');
      expect(s.intended(at(62)), isNull);
      s = transition(s, 'blank', at(63));
      expect(s.outputMode(at(63)), 'Clock');
      s = transition(s, 'cue', at(64), value: const TextLayout('THANK YOU'));
      expect(s.outputMode(at(64)), 'Cue');
      expect(s.intended(at(64))!.text, 'THANK YOU');
      s = transition(s, 'clearCue', at(65));
      expect(s.outputMode(at(65)), 'Clock');
      s = transition(s, 'clock', at(66));
      expect(s.outputMode(at(66)), 'Clock');
      s = transition(s, 'endScreen', at(67));
      expect(s.outputMode(at(67)), 'Clock');
      expect(s.intended(at(67))!.text, stageClockText(at(67).wall, '24h'));
      expect(s.events.last.message, 'Clock restored');
    });

    test('the LED sign is sent the clock', () {
      final plan = planHardwareOutput(ended(), at(61));
      expect(plan.kind, HardwareOutputKind.clock);
      expect(plan.layout, isNull);
      final withEnd = planHardwareOutput(ended(noEnd: false), at(61));
      expect(withEnd.kind, HardwareOutputKind.text);
      expect(withEnd.layout!.text, 'Hallelujah');
    });
  });

  group('saving no end screen', () {
    test('display settings keep it through JSON', () {
      final json = DisplaySettings(end: null).toJson();
      expect(json.containsKey('end'), isTrue);
      expect(json['end'], isNull);
      final back = DisplaySettings.fromJson(
        jsonDecode(jsonEncode(json)) as Json,
      );
      expect(back.end, isNull);
      expect(back.withCues(const []).end, isNull);
      expect(back.withEnd(defaultEndScreen).end!.text, 'Hallelujah');
    });

    test('display settings saved by earlier versions read as before', () {
      // Earlier versions always save an end screen.
      final old = {
        'zero': null,
        'end': const TextLayout('AMEN', bold: true).toJson(),
        'cues': <Object>[],
        'warnings': <Object>[],
      };
      final d = DisplaySettings.fromJson(old);
      expect(d.end!.text, 'AMEN');
      expect(d.end!.bold, isTrue);
      expect(jsonEncode(d.toJson()), jsonEncode(old));
      // Leaving it out altogether is still refused.
      expect(
        () => DisplaySettings.fromJson(Map.of(old)..remove('end')),
        throwsA(isA<RuleError>()),
      );
      expect(
        () => DisplaySettings.fromJson({...old, 'end': 'AMEN'}),
        throwsA(isA<RuleError>()),
      );
    });

    test('earlier versions refuse it, as they need an end screen', () {
      // Earlier versions open display settings only when "end" is a text
      // layout (`j['end'] is Map`), so a file without one is refused.
      final file = jsonDecode(exportJson(program())) as Json;
      expect((file['display'] as Map).containsKey('end'), isTrue);
      expect((file['display'] as Map)['end'] is Map, isFalse);
      final withEnd = jsonDecode(exportJson(program(noEnd: false))) as Json;
      expect((withEnd['display'] as Map)['end'] is Map, isTrue);
    });

    test('program files and bundles keep it', () {
      final one = importTemplate(
        exportJson(program()),
        'evening.json',
        DisplaySettings(),
      );
      expect(one.display.end, isNull);
      final many = importPrograms(
        exportProgramsJson([program(), program(noEnd: false)]),
        'programs.json',
        DisplaySettings(),
      );
      expect(many.first.display.end, isNull);
      expect(many.last.display.end!.text, 'Hallelujah');
    });

    test('saved state and backups keep it, for defaults and programs', () {
      final a = AppState.fresh(epoch)
        ..defaults = DisplaySettings(end: null)
        ..templates = [program(), program(noEnd: false)];
      final back = AppState.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Json,
        now: epoch,
      );
      expect(back.defaults.end, isNull);
      expect(back.templates.first.display.end, isNull);
      expect(back.templates.last.display.end!.text, 'Hallelujah');
      // A quick timer uses the default, so it ends on the clock too.
      final quick = const QuickTimerChoice('', 300).timeline(back.defaults);
      expect(quick.display.end, isNull);
    });

    test('an unsaved edit keeps it', () {
      final draft = {
        'name': 'Evening Prayer',
        'type': 'Sunday',
        'segments': [for (final s in program().segments) s.toJson()],
        'end': null,
      };
      expect(programFromDraft(draft, DisplaySettings()).display.end, isNull);
      final withEnd = {...draft, 'end': defaultEndScreen.toJson()};
      expect(
        programFromDraft(withEnd, DisplaySettings(end: null)).display.end!.text,
        'Hallelujah',
      );
    });
  });
}
