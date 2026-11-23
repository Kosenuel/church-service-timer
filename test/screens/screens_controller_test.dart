import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../windows/second_screen_live_test.dart' show SecondPort;

class _Wire implements PairWire {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _secret = base64Url.encode(List.filled(32, 7));

/// Saved pairing memory with these stage screens and their old layouts.
String pairingMemory(Map<String, String> layouts, {String role = 'stage'}) =>
    jsonEncode({
      'version': 1,
      'hostId': 'host',
      'port': 0,
      'devices': [
        for (final e in layouts.entries)
          {
            'id': e.key,
            'name': 'Screen ${e.key}',
            'role': role,
            'secret': _secret,
            'lastSeen': 1,
            'layout': e.value,
          },
      ],
      'client': null,
    });

/// A PC with saved settings from before groups: its second screen's
/// layout, paired screens' layouts, and the rest in [state].
class OldPort extends SecondPort {
  String? pairing;
  OldPort({String secondLayout = 'timer', this.pairing}) {
    saved = {'layout': secondLayout};
  }
  @override
  Future<String?> loadPairing() async => pairing;
}

/// A phone (no second screen) with saved pairing memory.
class PhonePort extends FakePort {
  String? pairing;
  PhonePort({this.pairing});
  @override
  Future<String?> loadPairing() async => pairing;
}

/// Saved state from before groups: the web layout, Full screen's layout
/// and the Send to boxes.
String oldState({
  String web = 'timer',
  String fullScreen = 'timer',
  bool toSecond = true,
  bool toWeb = true,
  bool toStage = false,
}) {
  final s = AppState.fresh(start)
    ..webStage = {'stageLayout': web}
    ..fullScreenLayout = fullScreen
    ..lyrics = LyricsLibrary(
      look: LyricsLook(toSecond: toSecond, toWeb: toWeb, toStage: toStage),
    );
  return jsonEncode(s.toJson()..remove('screens'));
}

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5),
  Segment('Worship', 20),
  Segment('Sermon', 40),
], DisplaySettings());

Future<AppController> boot(FakePort port, {String? state}) async {
  port.data = state;
  final c = AppController(port);
  await c.initialize(startTicker: false);
  addTearDown(c.dispose);
  return c;
}

Future<void> songUp(AppController c, {int slide = 0}) async {
  await c.lyrics.save(
    LyricItem(
      id: 'well',
      kind: 'song',
      title: 'It Is Well',
      words:
          'Verse 1\nWhen peace like a river\nAttendeth my way\n\n'
          'Chorus\nIt is well with my soul\nIt is well\n\n'
          'Verse 2\nThough Satan should buffet',
    ),
  );
  c.lyrics.show('well', slide);
}

PairPeer peer(String id, {Set<String> features = const {'confidence'}}) =>
    PairPeer(id, 'Screen $id', 'stage', _Wire())..features = features;

void main() {
  group('Migration at start', () {
    test('a PC keeps every screen showing what it showed', () async {
      final port = OldPort(
        secondLayout: 'current',
        pairing: pairingMemory({'a': 'next', 'b': 'only', 'c': 'next'}),
      );
      final c = await boot(port, state: oldState(web: 'only', toStage: true));
      final s = c.state.screens!;
      expect(
        [for (final g in s.groups) g.name],
        ['Room 1', 'Web screens', 'Stage', 'Stage 2'],
      );
      expect(c.screens.groupOf(thisScreenKey).show, 'slides');
      expect(c.screens.groupOf(thisScreenKey).layout, 'current');
      expect(c.screens.groupOf('pair:a').name, 'Stage');
      expect(c.screens.groupOf('pair:b').name, 'Stage 2');
      expect(c.stageWindowSnapshot()['stageLayout'], 'current');
      expect(
        c.decoratePairedSnapshot(
          peer('b'),
          c.pairedSnapshot(false),
        )['stageLayout'],
        'only',
      );
      expect(c.webStageSnapshot()['stageLayout'], 'only');
      // Saved once; a restart reads it back as it is.
      final again = await boot(OldPort(), state: port.data);
      expect(jsonEncode(again.state.screens!.toJson()), jsonEncode(s.toJson()));
    });

    test('a phone takes Full screen\'s layout for itself', () async {
      final c = await boot(
        PhonePort(pairing: pairingMemory({'tab': 'timer'})),
        state: oldState(
          fullScreen: 'next',
          web: 'next',
          toSecond: false,
          toWeb: false,
        ),
      );
      expect(c.state.screens!.groups.map((g) => g.name), ['Room 1', 'Stage']);
      expect(c.screens.groupOf(thisScreenKey).show, 'next');
      expect(c.stageSimulatorSnapshot()['stageLayout'], 'next');
    });

    test(
      'a viewer phone counts as a stage screen; an operator does not',
      () async {
        final c = await boot(
          PhonePort(pairing: pairingMemory({'v': 'current'}, role: 'viewer')),
          state: oldState(),
        );
        expect(c.screens.groupOf('pair:v').layout, 'current');
        expect(c.screens.screens.map((s) => s.kind), ['this', 'paired']);
        final op = await boot(
          PhonePort(pairing: pairingMemory({'o': 'next'}, role: 'operator')),
          state: oldState(),
        );
        expect(op.screens.screens.map((s) => s.kind), ['this']);
      },
    );

    test('a new install starts with Room 1 and Stage', () async {
      final c = await boot(FakePort());
      expect(c.state.screens!.groups.map((g) => g.name), ['Room 1', 'Stage']);
      expect(c.screens.groupOf(thisScreenKey).show, 'slides');
      expect(c.screens.setup.defaultOne.name, 'Stage');
      expect(c.screens.webDefault.name, 'Room 1');
    });
  });

  group('Each choice on each kind of screen', () {
    late AppController c;
    setUp(() async {
      c = await boot(OldPort(pairing: pairingMemory({'tab': 'timer'})));
      await c.act('load', value: sunday());
      await c.act('start');
      c.webStage.devices['tok'] = WebDevice(
        'tok',
        WebRole.stage,
        'TV · Chrome',
        '10.0.0.9',
      );
      // Every screen in one group, to set it once for all.
      await c.screens.move('pair:tab', 'room');
      await c.screens.move('web:tok', 'room');
    });

    Map<String, Json> snapshots() => {
      'second screen': c.stageWindowSnapshot(),
      'simulator': c.stageSimulatorSnapshot(),
      'paired': c.decoratePairedSnapshot(peer('tab'), c.pairedSnapshot(false)),
      'web': c.webStageSnapshot(token: 'tok'),
    };

    for (final show in screenShows.keys) {
      test('“${screenShows[show]}” reaches every screen', () async {
        expect(await c.screens.setShow('room', show), isTrue);
        await songUp(c);
        for (final e in snapshots().entries) {
          final data = e.value;
          expect(data['stageShow'], show, reason: e.key);
          // Always a countdown layout, so an older screen draws it.
          expect(stageLayouts.containsKey(data['stageLayout']), isTrue);
          if (stageLayouts.containsKey(show)) {
            expect(data['stageLayout'], show, reason: e.key);
          }
          expect(data.containsKey('lyrics'), show == 'slides', reason: e.key);
          expect(
            data.containsKey('confidence'),
            show == 'monitor',
            reason: e.key,
          );
        }
        // The web page gets the same through its view.
        final view = viewFor(
          WebRole.stage,
          c.webStageSnapshot(token: 'tok'),
          c.webStageSettings,
        );
        expect(view['show'], show);
        expect(view.containsKey('lyrics'), show == 'slides');
        expect(view.containsKey('confidence'), show == 'monitor');
      });
    }

    test('no slide: the countdown in the group\'s last layout', () async {
      await c.screens.setShow('room', 'only');
      await c.screens.setShow('room', 'monitor');
      for (final data in snapshots().values) {
        expect(data['stageLayout'], 'only');
        expect(data.containsKey('confidence'), isFalse);
        expect(data['displayIsTimer'], isTrue);
      }
      await songUp(c);
      c.lyrics.clear();
      for (final data in snapshots().values) {
        expect(data.containsKey('confidence'), isFalse);
        expect(data.containsKey('lyrics'), isFalse);
      }
    });

    test('the confidence monitor names the next slide', () async {
      await c.screens.setShow('room', 'monitor');
      await songUp(c);
      final m = c.stageWindowSnapshot()['confidence'] as Map;
      expect(m['label'], 'Verse 1');
      expect(m['text'], 'When peace like a river\nAttendeth my way');
      expect(m['next'], {'label': 'Chorus', 'line': 'It is well with my soul'});
      c.lyrics.show('well', 2);
      expect(
        (c.stageWindowSnapshot()['confidence'] as Map).containsKey('next'),
        isFalse,
        reason: 'the last slide has nothing after it',
      );
      // Black: the monitor goes back to the countdown; Slides goes black.
      c.lyrics.toggleBlack();
      expect(c.stageWindowSnapshot().containsKey('confidence'), isFalse);
      await c.screens.setShow('room', 'slides');
      expect((c.stageWindowSnapshot()['lyrics'] as Map)['black'], isTrue);
    });

    test('a phone following the rundown never gets a slide', () async {
      await songUp(c);
      final viewer = PairPeer('tab', 'Tab', 'viewer', _Wire());
      final data = c.decoratePairedSnapshot(viewer, c.pairedSnapshot(false));
      expect(data.containsKey('lyrics'), isFalse);
    });

    test('the LED sign is untouched', () async {
      await c.screens.setShow('room', 'monitor');
      await songUp(c);
      expect(c.state.session.intended(c.now)?.text, isNot(contains('peace')));
    });
  });

  group('Moving screens', () {
    test('a moved screen shows its new group\'s choice at once', () async {
      final c = await boot(OldPort(pairing: pairingMemory({'tab': 'timer'})));
      await c.act('load', value: sunday());
      await c.act('start');
      await songUp(c);
      final tab = peer('tab');
      expect(
        c.decoratePairedSnapshot(tab, c.pairedSnapshot(false))['lyrics'],
        isNull,
      );
      expect(await c.screens.move('pair:tab', 'room'), isTrue);
      expect(
        c.decoratePairedSnapshot(tab, c.pairedSnapshot(false))['lyrics'],
        isA<Map>(),
      );
      expect(c.screens.membersOf('room').map((s) => s.key), [
        thisScreenKey,
        'pair:tab',
      ]);
      // Kept on this device.
      expect(
        AppState.fromJson(c.state.toJson()).screens!.members['pair:tab'],
        'room',
      );
    });

    test('web screens: the group the browser names, or the default', () async {
      final c = await boot(FakePort());
      final added = await c.screens.addGroup('Lobby');
      expect(added, isNotNull);
      c.webStage.devices['a'] = WebDevice('a', WebRole.stage, 'TV', '1')
        ..group = added;
      c.webStage.devices['b'] = WebDevice('b', WebRole.stage, 'Tab', '2');
      c.webStage.devices['c'] = WebDevice('c', WebRole.stage, 'Old', '3')
        ..group = 'deleted-long-ago';
      expect(c.screens.groupOf('web:a').name, 'Lobby');
      expect(c.screens.groupOf('web:b').name, 'Room 1');
      expect(c.screens.groupOf('web:c').name, 'Room 1');
      expect(await c.screens.move('web:b', added!), isTrue);
      expect(c.webStage.devices['b']!.group, added);
      // Deleting a group sends its screens to the default group.
      expect(await c.screens.deleteGroup(added), isTrue);
      expect(c.screens.groupOf('web:a').name, 'Room 1');
    });

    test('a new screen joins the default group', () async {
      final c = await boot(FakePort());
      expect(c.screens.groupOf('pair:new').name, 'Stage');
      await c.screens.setDefault('room');
      expect(c.screens.groupOf('pair:new').name, 'Room 1');
      expect(c.screens.groupOf(thisScreenKey).name, 'Room 1');
    });

    test('rename and delete; the last group stays', () async {
      final c = await boot(FakePort());
      expect(await c.screens.renameGroup('stage', 'Pulpit'), isTrue);
      expect(c.screens.setup.byId('stage')!.name, 'Pulpit');
      expect(await c.screens.renameGroup('stage', 'room 1'), isFalse);
      expect(c.error, contains('already a group'));
      expect(await c.screens.deleteGroup('room'), isTrue);
      expect(c.screens.groupOf(thisScreenKey).name, 'Pulpit');
      expect(await c.screens.deleteGroup('stage'), isFalse);
    });
  });

  group('Scenes and segments', () {
    late AppController c;
    late String worship, sermon;
    setUp(() async {
      c = await boot(FakePort());
      await c.screens.setShow('room', 'slides');
      await c.screens.setShow('stage', 'monitor');
      worship = (await c.screens.saveScene('Worship'))!;
      await c.screens.setShow('room', 'timer');
      await c.screens.setShow('stage', 'next');
      sermon = (await c.screens.saveScene('Sermon'))!;
    });

    test('apply, update, rename and delete', () async {
      expect(c.screens.showingScene?.name, 'Sermon');
      expect(await c.screens.applyScene(worship), isTrue);
      expect(c.screens.groupOf(thisScreenKey).show, 'slides');
      expect(c.screens.showingScene?.name, 'Worship');
      await c.screens.setShow('stage', 'current');
      expect(c.screens.showingScene, isNull);
      expect(await c.screens.updateScene(worship), isTrue);
      expect(c.screens.showingScene?.name, 'Worship');
      expect(await c.screens.renameScene(worship, 'Praise'), isTrue);
      expect(await c.screens.deleteScene(sermon), isTrue);
      expect(c.screens.setup.scenes.map((s) => s.name), ['Praise']);
      expect(await c.screens.applyScene(sermon), isFalse);
    });

    Timeline program() => Timeline('Sunday Service', [
      const Segment('Welcome', 5),
      const Segment('Worship', 20).withScene(worship, 'Worship'),
      const Segment('Notices', 5),
      const Segment('Sermon', 40).withScene(sermon, 'Sermon'),
    ], DisplaySettings());

    String room() => c.screens.groupOf(thisScreenKey).show;

    test(
      'a segment\'s scene applies when it starts: Next and a jump',
      () async {
        await c.screens.setShow('room', 'only');
        await c.act('load', value: program());
        await c.act('start');
        expect(room(), 'only', reason: 'Welcome names no scene');
        await c.act('advance');
        expect(room(), 'slides', reason: 'Worship');
        // A change by hand holds until the next segment with a scene.
        await c.screens.setShow('room', 'current');
        expect(room(), 'current');
        await c.act('advance');
        expect(room(), 'current', reason: 'Notices names no scene');
        await c.act('advance');
        expect(room(), 'timer', reason: 'Sermon');
        // Undo into a segment with no scene changes nothing.
        await c.act('undo');
        expect(c.state.session.index, 2);
        expect(room(), 'timer');
        await c.act('jump', value: 3);
        expect(room(), 'timer');
      },
    );

    test('Undo back into a segment applies its scene', () async {
      await c.act('load', value: program());
      await c.act('start');
      await c.act('jump', value: 1);
      expect(room(), 'slides');
      await c.screens.setShow('room', 'only');
      await c.act('advance');
      expect(room(), 'only');
      await c.act('undo');
      expect(c.state.session.index, 1);
      expect(room(), 'slides', reason: 'Worship started again');
    });

    test('starting the service applies the first segment\'s scene', () async {
      await c.act(
        'load',
        value: Timeline('Worship first', [
          const Segment('Worship', 20).withScene(worship, 'Worship'),
        ], DisplaySettings()),
      );
      expect(room(), 'timer', reason: 'loading is not starting');
      await c.act('start');
      expect(room(), 'slides');
      // Pausing is not a start.
      await c.screens.setShow('room', 'next');
      await c.act('pause');
      await c.act('pause');
      expect(room(), 'next');
    });

    test(
      'a program from elsewhere finds a scene by name, or changes nothing',
      () async {
        final elsewhere = Timeline('Visitor', const [
          Segment('Song', 5, sceneId: 'sOther', sceneName: 'worship'),
          Segment('Talk', 5, sceneId: 'sNope', sceneName: 'Not here'),
        ], DisplaySettings());
        await c.act('load', value: elsewhere);
        await c.act('start');
        expect(room(), 'slides', reason: 'matched by name');
        await c.screens.setShow('room', 'next');
        await c.act('advance');
        expect(room(), 'next', reason: 'an unknown scene changes nothing');
      },
    );
  });

  group('Older screens', () {
    test(
      'a paired screen without the confidence monitor gets the countdown',
      () async {
        final c = await boot(OldPort(pairing: pairingMemory({'tab': 'next'})));
        await c.act('load', value: sunday());
        await c.act('start');
        await c.screens.setShow('stage', 'monitor');
        await songUp(c);
        final data = c.decoratePairedSnapshot(
          peer('tab', features: const {}),
          c.pairedSnapshot(false),
        );
        // An old screen ignores `confidence` and draws `stageLayout`: the
        // countdown as it was, never a slide covering it.
        expect(data['stageLayout'], 'next');
        expect(data.containsKey('lyrics'), isFalse);
        expect(data['displayIsTimer'], isTrue);
      },
    );
  });

  group('Blank, cues and the clock', () {
    test(
      'the group\'s choice is added; the override fields stay as they were',
      () async {
        final c = await boot(FakePort());
        await c.act('load', value: sunday());
        await c.act('start');
        await c.act('blank');
        final blankSlides = c.stageWindowSnapshot();
        expect(blankSlides['blank'], isTrue);
        await c.screens.setShow('room', 'monitor');
        final blankMonitor = c.stageWindowSnapshot();
        expect(blankMonitor['blank'], isTrue);
        String without(Json j) =>
            jsonEncode({...j}..removeWhere((k, _) => k.startsWith('stage')));
        expect(without(blankMonitor), without(blankSlides));
      },
    );
  });

  group('Screen awake', () {
    test(
      'a slide keeps it awake only while a group with a screen shows it',
      () async {
        final c = await boot(FakePort());
        await songUp(c);
        expect(c.lyrics.onScreens, isTrue);
        expect(c.wantsScreenAwake, isTrue);
        await c.screens.setShow('room', 'timer');
        expect(c.lyrics.onScreens, isFalse);
        expect(c.wantsScreenAwake, isFalse);
        // Stage shows slides, but no screen is in it.
        await c.screens.setShow('stage', 'monitor');
        expect(c.lyrics.onScreens, isFalse);
        await c.screens.move(thisScreenKey, 'stage');
        expect(c.lyrics.onScreens, isTrue);
        c.lyrics.clear();
        expect(c.wantsScreenAwake, isFalse);
      },
    );
  });
}
