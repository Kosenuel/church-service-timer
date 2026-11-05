import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import '../domain/service_timing_test.dart' show FakePort, timeline;

void main() {
  Future<AppController> withReport([String name = 'Sunday']) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline().renamed(name));
    await c.act('start');
    await c.act('end');
    return c;
  }

  group('Review notes', () {
    test('A note never changes the recorded timings', () async {
      final c = await withReport();
      final before = c.state.reports.single;
      final timings = jsonEncode({...before.toJson()}..remove('review'));
      expect(
        await c.setReviewNote(before.id, '  Reduce welcome next week. '),
        isTrue,
      );
      final after = c.state.reports.single;
      expect(after.review!.text, 'Reduce welcome next week.');
      expect(jsonEncode({...after.toJson()}..remove('review')), timings);
    });

    test('Empty text removes the note; invalid text is refused', () async {
      final c = await withReport();
      final id = c.state.reports.single.id;
      await c.setReviewNote(id, 'Offering took longer.');
      expect(await c.setReviewNote(id, '   '), isTrue);
      expect(c.state.reports.single.review, isNull);
      expect(
        await c.setReviewNote(id, 'x' * (ReviewNote.maxLength + 1)),
        isFalse,
      );
      expect(await c.setReviewNote(id, 'bad\x01text'), isFalse);
      expect(await c.setReviewNote(id, 'Line one\nLine two'), isTrue);
    });

    test('Notes survive saved state and backups', () async {
      final c = await withReport();
      await c.setReviewNote(c.state.reports.single.id, 'Start on time.');
      final restored = AppState.fromJson(
        jsonDecode(jsonEncode(c.state.toJson())),
        now: c.now,
      );
      expect(restored.reports.single.review!.text, 'Start on time.');
    });

    test('Exports leave notes out unless asked', () async {
      final c = await withReport();
      await c.setReviewNote(c.state.reports.single.id, 'Shorter notices.');
      final r = c.state.reports.single;
      expect(exportReportJson(r), isNot(contains('Shorter notices.')));
      expect(
        exportReportJson(r, includeReview: true),
        contains('Shorter notices.'),
      );
      expect(exportReportCsv(r), isNot(contains('Review note')));
      expect(
        exportReportCsv(r, includeReview: true),
        allOf(contains('Review note'), contains('Shorter notices.')),
      );
      expect(exportReportsJson([r]), isNot(contains('Shorter notices.')));
      expect(
        exportReportsCsv([r], includeReview: true),
        contains('Shorter notices.'),
      );
    });

    test('The newest note for a program is offered next time', () async {
      final c = await withReport('Sunday');
      await c.setReviewNote(c.state.reports.last.id, 'First week.');
      await c.act('load', value: timeline().renamed('Sunday'));
      await c.act('start');
      await c.act('end');
      await c.setReviewNote(c.state.reports.last.id, 'Second week.');
      await c.act('load', value: timeline().renamed('Midweek'));
      await c.act('start');
      await c.act('end');
      expect(c.state.latestReviewFor('Sunday')!.note.text, 'Second week.');
      expect(c.state.latestReviewFor('Midweek'), isNull);
    });
  });

  void size(WidgetTester t) {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  testWidgets(
    'A note can be added from the report and shows on the next load',
    (t) async {
      size(t);
      final c = await withReport('Sunday');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Reports').last);
      await tap(
        t,
        find.byKey(ValueKey('open-report-${c.state.reports.single.id}')),
      );
      await tap(t, find.byKey(const ValueKey('add-review-note')));
      await t.enterText(
        find.byKey(const ValueKey('review-note-field')),
        'Reduce welcome next week.',
      );
      await tap(t, find.byKey(const ValueKey('save-review-note')));
      expect(find.byKey(const ValueKey('review-note-text')), findsOneWidget);
      expect(find.textContaining('Added after service'), findsOneWidget);
      expect(c.state.reports.single.review!.text, 'Reduce welcome next week.');
      await t.pageBack();
      await t.pumpAndSettle();
      await c.act('load', value: timeline().renamed('Sunday'));
      await tap(t, find.text('Live').last);
      expect(find.byKey(const ValueKey('last-review-note')), findsOneWidget);
      expect(find.text('Reduce welcome next week.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
