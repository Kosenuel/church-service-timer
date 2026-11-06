import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Durations are read the ways people write them', () {
    expect(parseDuration('5'), 300);
    expect(parseDuration('5.5'), 330);
    expect(parseDuration('5,5'), 330);
    expect(parseDuration('05:30'), 330);
    expect(parseDuration('1:05:30'), 3930);
    expect(parseDuration('5 min'), 300);
    expect(parseDuration('5m 30s'), 330);
    expect(parseDuration('90s'), 90);
    expect(parseDuration('1 hour'), 3600);
    expect(parseDuration('Ten'), isNull);
    expect(parseDuration('05:75'), isNull);
    expect(parseDuration('0'), isNull);
    expect(parseDuration('330', DurationFormat.seconds), 330);
    expect(parseDuration('5', DurationFormat.clock), isNull);
  });

  test('Column titles are matched, duration before name', () {
    final rows = spreadsheetRows(
      'Order,Item,Time (mins),Who,Comments\n'
      '1,Welcome,5,Pastor Ade,Mic 1\n'
      '2,Worship,20,Choir,\n',
    );
    final m = guessMapping(rows);
    expect(m.name, 1);
    expect(m.duration, 2);
    expect(m.speaker, 3);
    expect(m.notes, 4);
    expect(m.headerRow, isTrue);
    final result = applyMapping(rows, m, programName: 'Sunday');
    expect(result.errors, isEmpty);
    final p = result.programs.single;
    expect(p.name, 'Sunday');
    expect(p.segments.map((s) => s.name), ['Welcome', 'Worship']);
    expect(p.segments.first.speaker, 'Pastor Ade');
    expect(p.segments.first.notes, 'Mic 1');
    expect(p.segments.last.durationMs, 20 * 60000);
  });

  test('Without titles, columns are guessed from the values', () {
    final rows = spreadsheetRows('Welcome,05:00\nSermon,40:00\nClosing,5:00\n');
    final m = guessMapping(rows);
    expect(m.name, 0);
    expect(m.duration, 1);
    expect(m.headerRow, isFalse);
    final p = applyMapping(rows, m, programName: 'Sunday').programs.single;
    expect(p.segments, hasLength(3));
  });

  test('A program column splits the rows into programs', () {
    final rows = spreadsheetRows(
      'Service,Segment,Minutes\n'
      'Morning,Welcome,5\nMorning,Sermon,30\nEvening,Prayer,10\n',
    );
    final m = guessMapping(rows);
    expect(m.program, 0);
    final programs = applyMapping(rows, m, programName: 'Imported').programs;
    expect(programs.map((p) => p.name), ['Morning', 'Evening']);
    expect(programs.first.segments, hasLength(2));
  });

  test('Every bad row is listed and nothing is imported', () {
    final rows = spreadsheetRows(
      'Item,Minutes\nWelcome,5\n,3\nSermon,lots\nLong,75\n,\n',
    );
    final result = applyMapping(rows, guessMapping(rows), programName: 'X');
    expect(result.programs, isEmpty);
    expect(result.errors, [
      'Row 3: no segment name.',
      'Row 4: “lots” is not a duration.',
      'Row 5: “Long” is longer than 59:59.',
    ]);
  });

  test('The app’s own CSV needs no wizard; others do', () {
    expect(
      isStandardProgramCsv(
        spreadsheetRows('Segment Name,Duration (Minutes)\nA,5\n'),
      ),
      isTrue,
    );
    expect(isStandardProgramCsv(spreadsheetRows('Item,Mins\nA,5\n')), isFalse);
  });

  test('A mapping survives being saved', () {
    const m = ColumnMapping(
      name: 1,
      duration: 2,
      speaker: 3,
      format: DurationFormat.clock,
      headerRow: false,
    );
    final back = ColumnMapping.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
  });
}
