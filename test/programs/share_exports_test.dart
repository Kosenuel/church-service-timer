import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

class SharePort extends FakePort {
  final shared = <List<SharedFile>>[];
  final subjects = <String?>[];
  Map<String, dynamic>? incoming;
  @override
  Future<bool> shareFiles(List<SharedFile> files, {String? subject}) async {
    shared.add(files);
    subjects.add(subject);
    return true;
  }

  @override
  Future<Map<String, dynamic>?> takeIncomingFile() async {
    final file = incoming;
    incoming = null;
    return file;
  }
}

void main() {
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<(AppController, SharePort)> app(WidgetTester t) async {
    size(t);
    final port = SharePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    return (c, port);
  }

  Future<void> selectFirstProgram(WidgetTester t, AppController c) async {
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Programs').last);
    await t.pumpAndSettle();
    await t.longPress(find.text(c.state.templates.first.name).first);
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  }

  testWidgets('Share selected programs as a JSON bundle', (t) async {
    final (c, port) = await app(t);
    await selectFirstProgram(t, c);
    await t.tap(find.byKey(const ValueKey('share-selected-programs')));
    await t.pumpAndSettle();
    expect(find.text('Share 1 program'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('share-programs-json')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-programs-go')));
    await t.pumpAndSettle();
    final file = port.shared.single.single;
    expect(file.mimeType, 'application/json');
    expect(file.name, endsWith('.json'));
    final json = jsonDecode(utf8.decode(file.bytes)) as Map;
    expect(json['type'], 'church-service-timer-programs');
    expect(port.subjects.single, c.state.templates.first.name);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Share selected programs as one PDF each', (t) async {
    final (c, port) = await app(t);
    await selectFirstProgram(t, c);
    await t.tap(find.text(c.state.templates[1].name).first);
    await t.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('share-selected-programs')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-programs-pdf')));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('share-programs-go')));
      for (var i = 0; i < 50 && port.shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await t.pumpAndSettle();
    final files = port.shared.single;
    expect(files, hasLength(2));
    for (final f in files) {
      expect(f.mimeType, 'application/pdf');
      expect(f.name, endsWith('.pdf'));
      expect(ascii.decode(f.bytes.sublist(0, 4)), '%PDF');
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Share selected reports as CSV', (t) async {
    final (c, port) = await app(t);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    await c.act('end');
    final id = c.state.reports.single.id;
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    await t.longPress(find.byKey(ValueKey('open-report-$id')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-selected-reports')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-reports-pdf')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('share-reports-csv')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-reports-go')));
    await t.pumpAndSettle();
    if (find.text('Continue').evaluate().isNotEmpty) {
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
    }
    final file = port.shared.single.single;
    expect(file.mimeType, 'text/csv');
    expect(utf8.decode(file.bytes), contains(c.state.reports.single.name));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Print Service offers Share PDF', (t) async {
    final (c, port) = await app(t);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    await c.act('end');
    final id = c.state.reports.single.id;
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('open-report-$id')));
    await t.pumpAndSettle();
    final print = find.text('Print Service');
    await t.ensureVisible(print.last);
    await t.tap(print.last);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('share-service-pdf')));
      for (var i = 0; i < 50 && port.shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await t.pumpAndSettle();
    final file = port.shared.single.single;
    expect(file.mimeType, 'application/pdf');
    expect(ascii.decode(file.bytes.sublist(0, 4)), '%PDF');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A received program file opens the import review', (t) async {
    final (c, port) = await app(t);
    final program = c.state.templates.first;
    port.incoming = {
      'name': 'received.json',
      'content': exportProgramsJson([program.renamed('Shared Sunday')]),
    };
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.text('Preview program import'), findsOneWidget);
    expect(find.text('Shared Sunday'), findsOneWidget);
    await t.tap(find.text('Import 1 programs'));
    await t.pumpAndSettle();
    expect(c.state.templates.any((p) => p.name == 'Shared Sunday'), isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A received report file explains it cannot be imported', (
    t,
  ) async {
    final (c, port) = await app(t);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    await c.act('end');
    port.incoming = {
      'name': 'reports.json',
      'content': exportReportsJson(c.state.reports),
    };
    final before = c.state.templates.length;
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.textContaining('contains service reports'), findsOneWidget);
    expect(c.state.templates, hasLength(before));
    await t.pumpWidget(const SizedBox());
  });
}
