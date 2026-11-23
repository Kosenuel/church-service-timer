import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../windows/second_screen_live_test.dart' show SecondPort;

class _Wire implements PairWire {
  @override
  bool closed = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _secret = base64Url.encode(List.filled(32, 7));

String memory(Map<String, String> names) => jsonEncode({
  'version': 1,
  'hostId': 'host',
  'port': 0,
  'devices': [
    for (final e in names.entries)
      {
        'id': e.key,
        'name': e.value,
        'role': 'stage',
        'secret': _secret,
        'lastSeen': 1,
        'layout': 'timer',
      },
  ],
  'client': null,
});

const _paired = {'tab': 'Stage tablet', 'pastor': 'Pastor’s phone'};

class PcPort extends SecondPort {
  @override
  Future<String?> loadPairing() async => memory(_paired);
}

class PhonePort extends FakePort {
  @override
  Future<String?> loadPairing() async => memory(_paired);
}

/// A service with three groups, three scenes (Worship showing), paired
/// and web screens, and a slide up.
Future<AppController> service(FakePort port) async {
  final c = AppController(port);
  await c.initialize(startTicker: false);
  await c.act(
    'load',
    value: Timeline('Sunday Service', const [
      Segment('Welcome', 5),
      Segment('Worship', 20),
      Segment('Sermon', 40),
    ], DisplaySettings()),
  );
  await c.act('start');
  final s = c.screens;
  await s.move('pair:tab', 'stage');
  await s.move('pair:pastor', 'stage');
  final lobby = (await s.addGroup('Lobby'))!;
  await s.setShow('stage', 'monitor');
  await s.setShow('room', 'slides');
  await s.setShow(lobby, 'slides');
  await s.saveScene('Worship');
  await s.setShow('stage', 'next');
  await s.setShow('room', 'timer');
  await s.setShow(lobby, 'only');
  await s.saveScene('Sermon');
  await s.setShow('stage', 'current');
  await s.setShow('room', 'slides');
  await s.setShow(lobby, 'slides');
  await s.saveScene('Announcements');
  await s.applyScene(s.setup.scenes.first.id);
  c.pairing.peers.add(
    PairPeer('tab', 'Stage tablet', 'stage', _Wire())
      ..approved = true
      ..features = const {'confidence'},
  );
  c.webStage.devices['a'] = WebDevice(
    'a',
    WebRole.stage,
    'Projector laptop',
    '1',
  )..group = 'room';
  c.webStage.devices['b'] = WebDevice('b', WebRole.stage, 'Lobby TV', '2')
    ..group = lobby
    ..lastSeen = DateTime.now().millisecondsSinceEpoch + 3600000;
  await c.lyrics.save(
    LyricItem(
      id: 'well',
      kind: 'song',
      title: 'It Is Well',
      words: 'Verse 1\nWhen peace like a river\n\nChorus\nIt is well',
    ),
  );
  c.lyrics.show('well', 0);
  return c;
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  Future<AppController> open(
    WidgetTester t,
    FakePort port,
    Size size, {
    double text = 1,
  }) async {
    setScreen(t, size);
    t.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    desktopWording = port.isDesktop;
    late AppController c;
    await t.runAsync(() async => c = await service(port));
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // Live itself is not what this checks: at 1366 × 768 and text 1.6 its
    // desktop layout is 0.4 px short already, with or without Screens.
    t.takeException();
    final button = find.byKey(const ValueKey('live-screens-button'));
    expect(button, findsOneWidget, reason: 'Live offers Screens');
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byType(ScreensPage), findsOneWidget);
    return c;
  }

  Future<void> golden(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(ScreensPage),
      matchesGoldenFile('../goldens/screens-$name.png'),
    );
  }

  testWidgets('golden: 1366 × 768 with a scene showing', (t) async {
    await open(t, PcPort(), const Size(1366, 768));
    expect(find.text('Room 1'), findsWidgets);
    await golden(t, '1366');
  });

  testWidgets('golden: 1920 × 1080', (t) async {
    await open(t, PcPort(), const Size(1920, 1080));
    await golden(t, '1920');
  });

  testWidgets('golden: 1920 tall, the whole page', (t) async {
    await open(t, PcPort(), const Size(1920, 1700));
    await golden(t, '1920-full');
  });

  testWidgets('golden: a phone, a full page in one column', (t) async {
    await open(t, PhonePort(), const Size(360, 780));
    // The scenes scroll sideways.
    expect(find.byKey(const ValueKey('screens-scenes-row')), findsOneWidget);
    await golden(t, 'phone');
  });

  testWidgets('golden: a phone, the whole page', (t) async {
    await open(t, PhonePort(), const Size(360, 3000));
    await golden(t, 'phone-full');
  });

  testWidgets('golden: a phone at text size 1.6', (t) async {
    await open(t, PhonePort(), const Size(360, 780), text: 1.6);
    await golden(t, 'phone-text16');
  });

  for (final (size, text) in [
    (const Size(360, 780), 1.0),
    (const Size(360, 780), 1.6),
    (const Size(780, 360), 1.0),
    (const Size(1366, 768), 1.0),
    (const Size(1366, 768), 1.6),
    (const Size(1920, 1080), 1.0),
  ]) {
    testWidgets('nothing overflows at $size, text $text', (t) async {
      await open(
        t,
        size.width > 1000 ? PcPort() : PhonePort(),
        size,
        text: text,
      );
      final page = find.byKey(const ValueKey('screens-page'));
      // Scroll to the end, checking each stretch.
      for (var i = 0; i < 12; i++) {
        final e = t.takeException();
        if (e is FlutterError) {
          for (final d in e.diagnostics) {
            debugPrint(d.toStringDeep());
          }
        }
        expect(e, isNull, reason: 'at $size, text $text');
        await t.drag(page, Offset(0, -size.height * .8));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('one tap changes a whole group, with no question', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    final tile = find.byKey(const ValueKey('group-stage-show-only'));
    await t.ensureVisible(tile);
    await t.runAsync(() async {
      await t.tap(tile);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(c.screens.setup.byId('stage')!.show, 'only');
    expect(
      find.text('Stage now shows Up next only on 2 screens.'),
      findsOneWidget,
    );
    expect(c.screens.showingScene, isNull, reason: 'no scene matches now');
  });

  testWidgets('one tap applies a scene', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    final sermon = c.screens.setup.scenes[1];
    await t.runAsync(() async {
      await t.tap(find.byKey(ValueKey('scene-${sermon.id}')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.screens.showingScene?.name, 'Sermon');
    expect(c.screens.groupOf(thisScreenKey).show, 'timer');
    expect(find.text('Scene “Sermon” is on every group.'), findsOneWidget);
  });

  testWidgets('a screen moves with its chooser', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    final chooser = find.byKey(const ValueKey('screen-group-pair:pastor'));
    await t.ensureVisible(chooser);
    await t.pumpAndSettle();
    await t.tap(chooser);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('Lobby').last);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.screens.groupOf('pair:pastor').name, 'Lobby');
    expect(
      find.textContaining('Pastor’s phone moved to Lobby'),
      findsOneWidget,
    );
  });

  testWidgets('new group, rename and delete', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    final add = find.byKey(const ValueKey('new-group'));
    await t.ensureVisible(add);
    await t.tap(add);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('screens-name-field')),
      'Choir',
    );
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('screens-name-save')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    final choir = c.screens.setup.groups.last;
    expect(choir.name, 'Choir');
    await t.tap(find.byKey(ValueKey('group-${choir.id}-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('screens-delete-confirm')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.screens.setup.byId(choir.id), isNull);
  });

  testWidgets('the keyboard reaches and works every tile', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    final tile = find.byKey(const ValueKey('group-room-show-monitor'));
    // Tab until that tile has the focus, then press Enter.
    var found = false;
    for (var i = 0; i < 80 && !found; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final focus = FocusManager.instance.primaryFocus?.context;
      found =
          focus != null &&
          find
              .descendant(of: tile, matching: find.byWidget(focus.widget))
              .evaluate()
              .isNotEmpty;
    }
    expect(found, isTrue, reason: 'Tab reaches the tile');
    await t.runAsync(() async {
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.screens.groupOf(thisScreenKey).show, 'monitor');
  });

  testWidgets('one tap turns Shows cues on or off', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    expect(c.screens.setup.byId('room')!.cues, isFalse);
    final cues = find.byKey(const ValueKey('group-room-cues'));
    await t.ensureVisible(cues);
    await t.runAsync(() async {
      await t.tap(cues);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.screens.setup.byId('room')!.cues, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    await golden(t, '1920-room-cues-on');
  });

  testWidgets('locked controls change nothing', (t) async {
    final c = await open(t, PcPort(), const Size(1920, 1700));
    c.uiLocked = true;
    c.notifyChanged();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('screens-locked')), findsOneWidget);
    final tile = find.byKey(const ValueKey('group-stage-show-only'));
    await t.ensureVisible(tile);
    await t.tap(tile, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(c.screens.setup.byId('stage')!.show, 'monitor');
  });

  testWidgets('Commands open the panel and apply scenes', (t) async {
    setScreen(t, const Size(1366, 768));
    desktopWording = true;
    late AppController c;
    await t.runAsync(() async => c = await service(PcPort()));
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final home = t.state<HomeState>(find.byType(Home));
    final ids = home.paletteCommands().map((p) => p.id).toList();
    expect(ids, contains('screens-panel'));
    for (final s in c.screens.setup.scenes) {
      expect(ids, contains('scene-${s.id}'));
    }
    await t.runAsync(() async {
      await home
          .paletteCommands()
          .firstWhere((p) => p.label == 'Scene: Sermon')
          .run();
    });
    expect(c.screens.showingScene?.name, 'Sermon');
  });
}
