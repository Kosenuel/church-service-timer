import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/programs/template_editor.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// A program segment can name a scene, chosen in the program editor next
/// to the segment's other fields.
void main() {
  setUpAll(loadAppFonts);

  Future<AppController> withScenes(WidgetTester t) async {
    late AppController c;
    await t.runAsync(() async {
      c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.screens.setShow('stage', 'monitor');
      await c.screens.saveScene('Worship');
      await c.screens.setShow('stage', 'next');
      await c.screens.saveScene('Sermon');
    });
    return c;
  }

  Future<void> editor(WidgetTester t, AppController c, Timeline program) async {
    setScreen(t, const Size(430, 1100));
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme('midnight_lime'),
        home: TemplateEditor(
          initial: program,
          existingNames: const {},
          draftController: c,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('choose a scene for a segment; the list says so', (t) async {
    final c = await withScenes(t);
    final program = c.state.templates.first;
    await editor(t, c, program);
    await t.tap(find.text(program.segments.first.name).first);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('segment-scene')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('segment-scene')),
        matching: find.text('Worship'),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../goldens/screens-segment-scene.png'),
    );
    await t.tap(find.text('Save segment'));
    await t.pumpAndSettle();
    final state = t.state<TemplateEditorState>(find.byType(TemplateEditor));
    final first = state.segments.first;
    expect(first.sceneName, 'Worship');
    expect(first.sceneId, c.screens.setup.scenes.first.id);
    expect(find.textContaining('Scene: Worship'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/screens-program-editor-scene.png'),
    );
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a scene this device does not have: a quiet note', (t) async {
    final c = await withScenes(t);
    final program = Timeline('Visitor', const [
      Segment('Song', 5, sceneId: 'sNope', sceneName: 'Celebration'),
    ], DisplaySettings());
    await editor(t, c, program);
    await t.tap(find.text('Song').first);
    await t.pumpAndSettle();
    expect(
      find.text(
        'Scene “Celebration” is not on this device. This segment changes nothing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Celebration (not on this device)'), findsOneWidget);
    // Saved as it came, so it works again on the device that has it.
    await t.tap(find.text('Save segment'));
    await t.pumpAndSettle();
    final state = t.state<TemplateEditorState>(find.byType(TemplateEditor));
    expect(state.segments.single.sceneName, 'Celebration');
    expect(state.segments.single.sceneId, 'sNope');
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('None takes the scene off', (t) async {
    final c = await withScenes(t);
    final program = Timeline('Sunday', [
      const Segment(
        'Song',
        5,
      ).withScene(c.screens.setup.scenes.first.id, 'Worship'),
    ], DisplaySettings());
    await editor(t, c, program);
    await t.tap(find.text('Song').first);
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('segment-scene')),
        matching: find.text('None'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Save segment'));
    await t.pumpAndSettle();
    final state = t.state<TemplateEditorState>(find.byType(TemplateEditor));
    expect(state.segments.single.hasScene, isFalse);
    await t.pump(const Duration(seconds: 2));
  });
}
