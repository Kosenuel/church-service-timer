import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/programs/import_mapping_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

const sheet =
    'Order,Item,Time (mins),Who\n'
    '1,Welcome,5,Pastor Ade\n'
    '2,Worship,20,Choir\n'
    '3,Sermon,35,Rev. Bello\n';

class SheetPort extends FakePort {
  Map<String, dynamic>? incoming;
  @override
  Future<Map<String, dynamic>?> takeIncomingFile() async {
    final f = incoming;
    incoming = null;
    return f;
  }
}

void main() {
  void size(WidgetTester t, [Size value = const Size(430, 1400)]) =>
      setScreen(t, value);

  testWidgets('A church’s own spreadsheet is matched, reviewed and imported', (
    t,
  ) async {
    size(t);
    final port = SheetPort()
      ..incoming = {'name': 'Sunday 9 Nov.csv', 'content': sheet};
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.text('Match spreadsheet columns'), findsOneWidget);
    expect(find.text('Sunday 9 Nov · 3 segments · 60 min'), findsOneWidget);
    expect(find.text('5 min · Welcome · Pastor Ade'), findsOneWidget);
    final next = find.byKey(const ValueKey('mapping-continue'));
    await t.ensureVisible(next);
    await t.pumpAndSettle();
    await t.tap(next);
    await t.pumpAndSettle();
    expect(find.text('Preview program import'), findsOneWidget);
    await t.tap(find.text('Import 1 programs'));
    await t.pumpAndSettle();
    final p = c.state.templates.firstWhere((p) => p.name == 'Sunday 9 Nov');
    expect(p.segments.map((s) => s.speaker), [
      'Pastor Ade',
      'Choir',
      'Rev. Bello',
    ]);
    // The layout is remembered for next week's sheet.
    expect(
      c.state.rememberedMapping(spreadsheetRows(sheet).first)?.duration,
      2,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Problems are listed and block Continue until fixed', (t) async {
    size(t);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final rows = spreadsheetRows('Item,Length\nWelcome,five\nSermon,30\n');
    await t.pumpWidget(
      MaterialApp(
        home: ImportMappingPage(controller: c, rows: rows, fileName: 'x.csv'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('“five” is not a duration'), findsOneWidget);
    final next = t.widget<FilledButton>(
      find.byKey(const ValueKey('mapping-continue')),
    );
    expect(next.onPressed, isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('Column letters run A to Z, then AA', () {
    expect(columnLetter(0), 'A');
    expect(columnLetter(25), 'Z');
    expect(columnLetter(26), 'AA');
  });
}
