import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/windows/file_drop.dart';
import 'package:church_service_timer/windows/windows_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/widget_setup.dart';
import 'desktop_clock_and_storage_test.dart' show FakeProtector;
import 'windows_port_test.dart' show FakeDialogs, FakeSystem, tinosFace;

/// A computer whose files are held in memory. Drops arrive on the window
/// channel, as the Windows runner sends them, and are wired up the way
/// the Windows start-up code does it.
class DropPort extends DesktopFakePort {
  final files = <String, String>{};
  final offered = <String>[];
  Future<void> Function()? _incoming;
  void Function(List<String> paths)? _drop;

  DropPort() {
    listenForDroppedFiles((paths) => _drop?.call(paths));
  }

  @override
  void setIncomingFileHandler(Future<void> Function()? handler) =>
      _incoming = handler;
  @override
  void setFileDropHandler(void Function(List<String> paths)? handler) =>
      _drop = handler;
  @override
  void offerIncomingFile(String path) {
    offered.add(path);
    _incoming?.call();
  }

  @override
  Future<Map<String, dynamic>?> takeIncomingFile() async {
    if (offered.isEmpty) return null;
    final path = offered.removeLast();
    offered.clear();
    return {'name': path.split('\\').last, 'content': files[path]!};
  }
}

/// What the runner does when files are dropped on the window.
Future<void> drop(WidgetTester t, List<String> paths) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    windowChannel.name,
    windowChannel.codec.encodeMethodCall(MethodCall('filesDropped', paths)),
    (_) {},
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  const sunday = r'C:\Users\Ruth\Desktop\Shared Sunday.json';

  Future<(AppController, DropPort)> app(WidgetTester t) async {
    setScreen(t, const Size(1366, 768));
    final port = DropPort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    port.files[sunday] = exportProgramsJson([
      c.state.templates.first.renamed('Shared Sunday'),
    ]);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  final refused = find.byKey(const ValueKey('drop-refused'));

  testWidgets(
    'one program file dropped on the window opens the import review',
    (t) async {
      final (c, _) = await app(t);
      await drop(t, [sunday]);
      expect(refused, findsNothing);
      // Reviewed first: nothing is imported until it is confirmed.
      expect(find.text('Preview program import'), findsOneWidget);
      expect(find.text('Shared Sunday'), findsOneWidget);
      expect(c.state.templates.any((p) => p.name == 'Shared Sunday'), isFalse);
      await t.tap(find.text('Import 1 program'));
      await t.pumpAndSettle();
      expect(c.state.templates.any((p) => p.name == 'Shared Sunday'), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('anything but one program file is refused in one line', (
    t,
  ) async {
    final (c, port) = await app(t);
    final before = c.state.templates.length;
    for (final paths in const [
      [r'C:\Users\Ruth\Desktop\Notes.txt'],
      // A folder, as the Windows port marks one.
      [r'C:\Users\Ruth\Desktop\Programs.json\'],
      [r'C:\Users\Ruth\Desktop\Programs'],
      [sunday, r'C:\Users\Ruth\Desktop\Midweek.csv'],
    ]) {
      await drop(t, paths);
      expect(
        find.descendant(
          of: refused,
          matching: find.text('Drop one program file (.json or .csv).'),
        ),
        findsOneWidget,
        reason: '$paths',
      );
      expect(find.text('Preview program import'), findsNothing);
      expect(port.offered, isEmpty);
      // The line goes away by itself.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(refused, findsNothing);
    }
    expect(c.state.templates.length, before);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a drop while a service runs imports nothing', (t) async {
    final (c, port) = await app(t);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await t.pumpAndSettle();
    await drop(t, [sunday]);
    expect(
      find.text('A service is running. End it before you import a program.'),
      findsOneWidget,
    );
    expect(find.text('Preview program import'), findsNothing);
    expect(port.offered, isEmpty);
    expect(c.state.templates.any((p) => p.name == 'Shared Sunday'), isFalse);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a drop while controls are locked imports nothing', (t) async {
    final (c, port) = await app(t);
    t.state<HomeState>(find.byType(Home)).lockControls();
    await t.pumpAndSettle();
    await drop(t, [sunday]);
    expect(
      find.text(
        'Controls are locked. Unlock them before you import a program.',
      ),
      findsOneWidget,
    );
    expect(find.text('Preview program import'), findsNothing);
    expect(port.offered, isEmpty);
    expect(c.state.templates.any((p) => p.name == 'Shared Sunday'), isFalse);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Programs says a file can be dropped, on a computer only', (
    t,
  ) async {
    final (c, _) = await app(t);
    await c.commit((draft, _) => draft.templates.clear());
    t.state<HomeState>(find.byType(Home)).goToPage(1);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('programs-empty')), findsOneWidget);
    expect(find.text('Or drop a file on the window.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('which drops are one program file', () {
    expect(droppedProgramFile([r'C:\a\Plan.JSON']), r'C:\a\Plan.JSON');
    expect(droppedProgramFile([r'C:\a\plan.csv']), r'C:\a\plan.csv');
    expect(droppedProgramFile([r'C:\a\plan.txt']), isNull);
    expect(droppedProgramFile([r'C:\a\plan.json\']), isNull);
    expect(droppedProgramFile([r'C:\a\one.json', r'C:\a\two.json']), isNull);
    expect(droppedProgramFile(const []), isNull);
    expect(droppedProgramFile(['']), isNull);
  });

  test('the Windows port passes drops on and marks folders', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('cst-drop');
    addTearDown(() => dir.deleteSync(recursive: true));
    final port = WindowsPort(
      dataDir: Directory('${dir.path}/data'),
      monotonicMs: () => 0,
      wallMs: () => 1700000000000,
      protector: FakeProtector(),
      dialogs: FakeDialogs(),
      system: FakeSystem(),
      loadTinosFace: tinosFace,
    );
    final file = File('${dir.path}/plan.json')..writeAsStringSync('{}');
    final folder = Directory('${dir.path}/folder.json')..createSync();
    // No page is listening yet: nothing happens.
    port.filesDropped([file.path]);
    final drops = <List<String>>[];
    port.setFileDropHandler(drops.add);
    port.filesDropped([file.path]);
    port.filesDropped([folder.path]);
    expect(drops, [
      [file.path],
      ['${folder.path}${Platform.pathSeparator}'],
    ]);
    expect(droppedProgramFile(drops.first), file.path);
    expect(droppedProgramFile(drops.last), isNull);
  });
}
