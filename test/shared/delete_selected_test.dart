import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import '../domain/service_timing_test.dart' show FakePort, timeline;

void main() {
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

  Future<AppController> withPrograms(List<String> names) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      for (final n in names) draft.saveTemplate(timeline().renamed(n));
    });
    return c;
  }

  group('Bulk delete in the domain', () {
    test(
      'Programs restore to their positions with pins and recent use',
      () async {
        final c = await withPrograms(['Alpha', 'Beta', 'Gamma']);
        await c.commit((draft, _) {
          draft.programLibrary.favourites.add('Beta');
          draft.programLibrary.recent['Gamma'] = 42;
        });
        final before = c.state.templates.map((t) => t.name).toList();
        final removed = await c.deletePrograms({'Beta', 'Gamma'});
        expect(removed, hasLength(2));
        expect(c.state.templates.map((t) => t.name), isNot(contains('Beta')));
        expect(c.state.programLibrary.favourites, isNot(contains('Beta')));
        expect(await c.restorePrograms(removed!), isTrue);
        expect(c.state.templates.map((t) => t.name).toList(), before);
        expect(c.state.programLibrary.favourites, contains('Beta'));
        expect(c.state.programLibrary.recent['Gamma'], 42);
      },
    );

    test(
      'Deleting the loaded program leaves the running service and reports intact',
      () async {
        final c = await withPrograms(['Alpha']);
        final alpha = c.state.templates.firstWhere((t) => t.name == 'Alpha');
        await c.act('load', value: alpha);
        await c.act('start');
        await c.act('end');
        await c.act('load', value: alpha);
        await c.act('start');
        final reports = c.state.reports.length;
        expect(await c.deletePrograms({'Alpha'}), isNotNull);
        expect(c.state.session.active, isTrue);
        expect(c.state.session.timeline!.name, 'Alpha');
        expect(c.state.reports, hasLength(reports));
        expect(c.state.reports.last.name, 'Alpha');
      },
    );

    test('A stale selection deletes nothing', () async {
      final c = await withPrograms(['Alpha', 'Beta']);
      final count = c.state.templates.length;
      expect(await c.deletePrograms({'Alpha', 'Missing'}), isNull);
      expect(c.state.templates, hasLength(count));
    });

    test('Restore refuses a name that was reused meanwhile', () async {
      final c = await withPrograms(['Alpha']);
      final removed = await c.deletePrograms({'Alpha'});
      await c.commit(
        (draft, _) => draft.saveTemplate(timeline().renamed('Alpha')),
      );
      expect(await c.restorePrograms(removed!), isFalse);
      expect(c.state.templates.where((t) => t.name == 'Alpha'), hasLength(1));
    });

    test('Reports restore in their original order', () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      for (final n in ['One', 'Two', 'Three']) {
        await c.act('load', value: timeline().renamed(n));
        await c.act('start');
        await c.act('end');
      }
      final order = c.state.reports.map((r) => r.id).toList();
      final removed = await c.deleteReports({order[0], order[2]});
      expect(c.state.reports.map((r) => r.id), [order[1]]);
      expect(await c.restoreReports(removed!), isTrue);
      expect(c.state.reports.map((r) => r.id).toList(), order);
      expect(await c.restoreReports(removed), isFalse);
    });
  });

  testWidgets(
    'Delete selected confirms with the count and hidden items, then Undo restores',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      for (final name in ['Morning Service', 'Evening Service']) {
        await c.act('load', value: timeline().renamed(name));
        await c.act('start');
        await c.act('end');
      }
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, find.text('Reports').last);
      await tap(t, find.byKey(const ValueKey('select-reports')));
      final delete = find.byKey(const ValueKey('delete-selected-reports'));
      expect(t.widget<TextButton>(delete).onPressed, isNull);
      await tap(t, find.text('Select all shown'));
      await t.enterText(find.byKey(const ValueKey('report-search')), 'Morning');
      await t.pumpAndSettle();
      expect(find.text('Delete selected (2)'), findsOneWidget);
      await tap(t, delete);
      expect(find.text('Delete 2 reports?'), findsOneWidget);
      expect(
        find.textContaining('1 of them is hidden by your current search'),
        findsOneWidget,
      );
      await tap(t, find.text('Cancel'));
      expect(c.state.reports, hasLength(2));
      await tap(t, delete);
      await tap(t, find.byKey(const ValueKey('confirm-action')));
      expect(c.state.reports, isEmpty);
      expect(find.text('2 reports deleted'), findsOneWidget);
      await tap(t, find.text('Undo'));
      expect(c.state.reports.map((r) => r.name), [
        'Morning Service',
        'Evening Service',
      ]);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Delete selected programs keeps the running service', (t) async {
    size(t);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final first = c.state.templates.first;
    await c.act('load', value: first);
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await tap(t, find.text('Programs').last);
    await tap(t, find.byKey(const ValueKey('select-programs')));
    await tap(t, find.text('Select all shown'));
    final count = c.state.templates.length;
    await tap(t, find.byKey(const ValueKey('delete-selected-programs')));
    expect(find.text('Delete $count programs?'), findsOneWidget);
    expect(find.textContaining('A service already running'), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('confirm-action')));
    expect(c.state.templates, isEmpty);
    expect(c.state.session.active, isTrue);
    expect(c.state.session.timeline!.name, first.name);
    await t.pumpWidget(const SizedBox());
  });
}
