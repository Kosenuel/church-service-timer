import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort, start;

void main() {
  test('Library keeps newest first, replaces by name, and has a limit', () {
    final s = AppState.fresh(start);
    s.saveLibrarySegment(const Segment('Offering', 5));
    s.saveLibrarySegment(const Segment('Notices', 3));
    s.saveLibrarySegment(const Segment('offering', 6, speaker: 'Deacon'));
    expect(s.segmentLibrary.map((v) => v.name), ['offering', 'Notices']);
    expect(s.segmentLibrary.first.speaker, 'Deacon');
    for (var i = s.segmentLibrary.length; i < segmentLibraryLimit; i++) {
      s.saveLibrarySegment(Segment('Item $i', 1));
    }
    expect(
      () => s.saveLibrarySegment(const Segment('One more', 1)),
      throwsA(isA<RuleError>()),
    );
    final removed = s.removeLibrarySegment('Notices')!;
    expect(s.segmentLibrary.any((v) => v.name == 'Notices'), isFalse);
    s.restoreLibrarySegment(removed.$1, removed.$2);
    expect(s.segmentLibrary[removed.$1].name, 'Notices');
  });

  test('Library survives saving and goes into backups', () {
    final s = AppState.fresh(start)
      ..saveLibrarySegment(const Segment('Offering', 5, notes: 'Ushers'));
    final reloaded = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(reloaded.segmentLibrary.single.notes, 'Ushers');
    final raw = exportBackup(s, start);
    expect((jsonDecode(raw) as Json)['schemaVersion'], 9);
    expect(importBackup(raw, start).segmentLibrary.single.name, 'Offering');
    final plain = AppState.fresh(start);
    expect(
      (jsonDecode(exportBackup(plain, start)) as Json)['schemaVersion'],
      7,
    );
  });

  testWidgets('Save a segment to the library, then add it to a program', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final program = c.state.templates.first;
    await t.pumpWidget(
      MaterialApp(
        home: TemplateEditor(
          initial: program,
          existingNames: const {},
          draftController: c,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-from-library')), findsNothing);
    await t.tap(find.text(program.segments.first.name).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('save-segment-to-library')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Saved “${program.segments.first.name}”'),
      findsOneWidget,
    );
    expect(c.state.segmentLibrary.single.name, program.segments.first.name);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    final before = program.segments.length;
    final add = find.byKey(const ValueKey('add-from-library'));
    await t.ensureVisible(add);
    await t.tap(add);
    await t.pumpAndSettle();
    await t.tap(
      find.byKey(ValueKey('library-pick:${program.segments.first.name}')),
    );
    await t.pumpAndSettle();
    final state = t.state<TemplateEditorState>(find.byType(TemplateEditor));
    expect(state.segments, hasLength(before + 1));
    expect(state.segments.last.name, program.segments.first.name);
    await t.pumpWidget(const SizedBox());
  });
}
