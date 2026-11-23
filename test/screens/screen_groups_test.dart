import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';

/// The settings of a screen from before groups.
OldScreenChoice old(String layout, {bool slides = false}) =>
    (layout: layout, slides: slides);

void main() {
  group('Migration from the settings of before groups', () {
    test('a new install: Room 1 shows slides, Stage the timer', () {
      // The old defaults: Send to second screen and web on, stage off.
      final s = migrateScreens(
        self: old('timer', slides: true),
        web: old('timer', slides: true),
        paired: const [],
        pairedSlides: false,
      );
      expect([for (final g in s.groups) g.name], ['Room 1', 'Stage']);
      expect(s.groupOf(thisScreenKey).name, 'Room 1');
      expect(s.groupOf(thisScreenKey).show, 'slides');
      expect(s.groupOf(thisScreenKey).layout, 'timer');
      expect(s.byId('stage')!.show, 'timer');
      // A new paired screen joins Stage; a browser with no link Room 1.
      expect(s.defaultOne.name, 'Stage');
      expect(s.groupForWeb(null).name, 'Room 1');
    });

    test('second screen and web screens that differ are split', () {
      final s = migrateScreens(
        self: old('current', slides: true),
        web: old('next'),
        paired: const [],
        pairedSlides: false,
      );
      expect(
        [for (final g in s.groups) g.name],
        ['Room 1', 'Web screens', 'Stage'],
      );
      expect(s.groupOf(thisScreenKey).show, 'slides');
      expect(s.groupOf(thisScreenKey).fallback, 'current');
      // A browser naming no group joins the web screens' group.
      expect(s.groupForWeb(null).name, 'Web screens');
      expect(s.groupForWeb(null).show, 'next');
      expect(s.defaultOne.name, 'Stage');
    });

    test('only Send to differs: still split, as slides would change', () {
      final s = migrateScreens(
        self: old('timer', slides: true),
        web: old('timer'),
        paired: const [],
        pairedSlides: false,
      );
      expect(s.groups.length, 3);
      expect(s.byId('room')!.show, 'slides');
      expect(s.byId('web')!.show, 'timer');
    });

    test('paired screens with one choice share Stage', () {
      final s = migrateScreens(
        self: old('timer'),
        web: old('timer'),
        paired: const [(id: 'a', layout: 'next'), (id: 'b', layout: 'next')],
        pairedSlides: true,
      );
      expect([for (final g in s.groups) g.name], ['Room 1', 'Stage']);
      expect(s.groupOf(pairedScreenKey('a')).name, 'Stage');
      expect(s.groupOf(pairedScreenKey('b')).name, 'Stage');
      // Send to Stage screens ticked: slides, the countdown as it was.
      expect(s.byId('stage')!.show, 'slides');
      expect(s.byId('stage')!.fallback, 'next');
    });

    test('paired screens with different choices get Stage 2, Stage 3', () {
      final s = migrateScreens(
        self: old('timer'),
        web: old('timer'),
        paired: const [
          (id: 'pulpit', layout: 'current'),
          (id: 'choir', layout: 'only'),
          (id: 'band', layout: 'only'),
          (id: 'desk', layout: 'timer'),
        ],
        pairedSlides: false,
      );
      // The most common choice keeps the name Stage; the rest in order.
      expect(
        [for (final g in s.groups) g.name],
        ['Room 1', 'Stage', 'Stage 2', 'Stage 3'],
      );
      expect(s.groupOf(pairedScreenKey('choir')).name, 'Stage');
      expect(s.groupOf(pairedScreenKey('band')).show, 'only');
      expect(s.groupOf(pairedScreenKey('pulpit')).name, 'Stage 2');
      expect(s.groupOf(pairedScreenKey('pulpit')).show, 'current');
      expect(s.groupOf(pairedScreenKey('desk')).name, 'Stage 3');
      expect(s.groupOf(pairedScreenKey('desk')).show, 'timer');
    });

    test('ties keep the first saved screen\'s choice as Stage', () {
      final s = migrateScreens(
        self: old('timer'),
        web: old('timer'),
        paired: const [(id: 'a', layout: 'next'), (id: 'b', layout: 'current')],
        pairedSlides: false,
      );
      expect(s.groupOf(pairedScreenKey('a')).name, 'Stage');
      expect(s.groupOf(pairedScreenKey('b')).name, 'Stage 2');
    });

    test('nothing any screen shows changes', () {
      // Every combination of the four layouts and Send to.
      for (final self in stageLayouts.keys) {
        for (final web in stageLayouts.keys) {
          for (final slides in [false, true]) {
            final s = migrateScreens(
              self: old(self, slides: slides),
              web: old(web, slides: !slides),
              paired: [(id: 'p', layout: web)],
              pairedSlides: slides,
            );
            final room = s.groupOf(thisScreenKey);
            expect(room.layout, self);
            expect(room.show, slides ? 'slides' : self);
            expect(s.groupForWeb(null).layout, web);
            expect(s.groupForWeb(null).show, !slides ? 'slides' : web);
            final stage = s.groupOf(pairedScreenKey('p'));
            expect(stage.layout, web);
            expect(stage.show, slides ? 'slides' : web);
          }
        }
      }
    });

    test('unknown old layouts read as the timer', () {
      final s = migrateScreens(
        self: old('wobble'),
        web: old(''),
        paired: const [(id: 'a', layout: 'zz')],
        pairedSlides: false,
      );
      expect(s.groups.length, 2);
      expect(s.groupOf(pairedScreenKey('a')).show, 'timer');
    });

    test('saved state from before groups loads with none, to migrate', () {
      final saved = AppState.fresh(start).toJson()..remove('screens');
      expect(AppState.fromJson(saved).screens, isNull);
    });
  });

  group('One group per screen', () {
    ScreenSetup two() => ScreenSetup(
      groups: const [
        ScreenGroup('room', 'Room 1', 'slides'),
        ScreenGroup('stage', 'Stage', 'timer'),
      ],
      defaultGroup: 'room',
      members: const {thisScreenKey: 'room', 'pair:a': 'stage'},
    );

    test('a screen never in a group is in the default group', () {
      final s = two();
      expect(s.groupOf('pair:new').id, 'room');
      expect(s.groupNamed(null).id, 'room');
      expect(s.groupNamed('gone').id, 'room');
      expect(s.withDefault('stage').groupOf('pair:new').id, 'stage');
    });

    test('moving a screen changes its one group', () {
      final s = two().moved('pair:a', 'room');
      expect(s.groupOf('pair:a').id, 'room');
      expect(s.members.values.where((g) => g == 'stage'), isEmpty);
      expect(() => two().moved('pair:a', 'nowhere'), throwsA(isA<RuleError>()));
    });

    test('add, rename and delete groups', () {
      var s = two().added('Lobby', id: 'globby');
      expect(s.byId('globby')!.show, 'timer');
      expect(
        () => s.added('lobby', id: 'gother'),
        throwsA(isA<RuleError>()),
        reason: 'names are unique without regard to case',
      );
      expect(() => s.added('  ', id: 'gx'), throwsA(isA<RuleError>()));
      s = s.renamed('globby', 'Foyer');
      expect(s.byId('globby')!.name, 'Foyer');
      expect(() => s.renamed('globby', 'Stage'), throwsA(isA<RuleError>()));
      s = s.moved('pair:b', 'globby');
      // Deleting a group sends its screens to the default group.
      s = s.deleted('globby');
      expect(s.byId('globby'), isNull);
      expect(s.groupOf('pair:b').id, 'room');
      // Deleting the default group makes another the default.
      s = s.deleted('room');
      expect(s.defaultGroup, 'stage');
      expect(s.groupOf(thisScreenKey).id, 'stage');
      // The last group stays.
      expect(() => s.deleted('stage'), throwsA(isA<RuleError>()));
    });

    test('at most twelve groups', () {
      var s = two();
      for (var i = 0; i < screenGroupLimit - 2; i++) {
        s = s.added('Group $i', id: 'g$i');
      }
      expect(() => s.added('One more', id: 'gmore'), throwsA(isA<RuleError>()));
    });

    test('a group keeps its last countdown layout for when no slide shows', () {
      var g = const ScreenGroup('x', 'X', 'next', fallback: 'next');
      g = g.withShow('monitor');
      expect(g.layout, 'next');
      g = g.withShow('only').withShow('slides');
      expect(g.fallback, 'only');
      expect(g.layout, 'only');
    });

    test('saves and reads back, members included; backups leave them out', () {
      final s = two().sceneSaved('Worship', id: 'sworship');
      final back = ScreenSetup.tryRead(jsonDecode(jsonEncode(s.toJson())))!;
      expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
      expect(s.toBackupJson().containsKey('members'), isFalse);
    });

    test('unreadable saved groups are left out, not fatal', () {
      final back = ScreenSetup.tryRead({
        'groups': [
          {'id': 'room', 'name': 'Room 1', 'show': 'sparkles'},
          {'id': 'BAD ID', 'name': 'x', 'show': 'timer'},
          {'id': 'two', 'name': 'room 1', 'show': 'timer'},
          'nonsense',
        ],
        'default': 'missing',
        'members': {'this': 'missing', 'pair:a': 'room'},
      })!;
      expect(back.groups.length, 1);
      expect(back.groups.single.show, 'timer');
      expect(back.defaultGroup, 'room');
      expect(back.members, {'pair:a': 'room'});
      expect(ScreenSetup.tryRead({'groups': []}), isNull);
      expect(ScreenSetup.tryRead('x'), isNull);
    });
  });

  group('Scenes', () {
    ScreenSetup setup() => ScreenSetup(
      groups: const [
        ScreenGroup('room', 'Room 1', 'slides'),
        ScreenGroup('stage', 'Stage', 'monitor'),
      ],
      defaultGroup: 'room',
    );

    test('save, apply, update, rename and delete', () {
      var s = setup().sceneSaved('Worship', id: 'sworship');
      expect(s.scenes.single.shows, {'room': 'slides', 'stage': 'monitor'});
      expect(s.sceneShowing(s.scenes.single), isTrue);
      s = s.withShow('room', 'timer').withShow('stage', 'next');
      expect(s.sceneShowing(s.scenes.single), isFalse);
      s = s.sceneSaved('Sermon', id: 'ssermon');
      s = s.sceneApplied(s.sceneById('sworship')!);
      expect(s.byId('room')!.show, 'slides');
      expect(s.byId('stage')!.show, 'monitor');
      s = s.withShow('stage', 'only').sceneUpdated('sworship');
      expect(s.sceneById('sworship')!.shows['stage'], 'only');
      s = s.sceneRenamed('sworship', 'Praise');
      expect(s.sceneById('sworship')!.name, 'Praise');
      expect(
        () => s.sceneRenamed('sworship', 'sermon'),
        throwsA(isA<RuleError>()),
      );
      s = s.sceneDeleted('ssermon');
      expect(s.scenes.map((x) => x.name), ['Praise']);
    });

    test('a scene leaves groups it does not list alone', () {
      var s = setup().sceneSaved('Worship', id: 'sworship');
      s = s.added('Lobby', id: 'globby', show: 'only');
      s = s.withShow('room', 'timer');
      s = s.sceneApplied(s.sceneById('sworship')!);
      expect(s.byId('room')!.show, 'slides');
      expect(s.byId('globby')!.show, 'only');
      // Still lit: it says nothing about the new group.
      expect(s.sceneShowing(s.sceneById('sworship')!), isTrue);
    });

    test('a deleted group drops out of every scene', () {
      var s = setup().sceneSaved('Worship', id: 'sworship').deleted('stage');
      expect(s.scenes.single.shows.keys, ['room']);
      s = s.sceneApplied(s.scenes.single);
      expect(s.groups.length, 1);
    });

    test('a segment finds its scene by id, else by name', () {
      final s = setup().sceneSaved('Worship', id: 'sworship');
      expect(s.sceneFor('sworship', 'Anything')!.name, 'Worship');
      expect(s.sceneFor('elsewhere', 'worship')!.id, 'sworship');
      expect(s.sceneFor('elsewhere', 'Sermon'), isNull);
      expect(s.sceneFor('', ''), isNull);
    });
  });

  group('Segments naming a scene', () {
    test('saved with id and name, only when set', () {
      const plain = Segment('Sermon', 30);
      expect(plain.toJson().containsKey('scene'), isFalse);
      final named = plain.withScene('sworship', 'Worship');
      final back = Segment.fromJson(jsonDecode(jsonEncode(named.toJson())));
      expect(back.sceneId, 'sworship');
      expect(back.sceneName, 'Worship');
      expect(back.withScene('', '').hasScene, isFalse);
    });

    test('a program file keeps the scene through export and import', () {
      final program = Timeline('Sunday', [
        const Segment('Worship', 20).withScene('sworship', 'Worship'),
        const Segment('Sermon', 30),
      ], DisplaySettings());
      final raw = exportProgramsJson([program]);
      final read = importPrograms(raw, 'p.json', DisplaySettings());
      expect(read.single.segments.first.sceneName, 'Worship');
      expect(read.single.segments.last.hasScene, isFalse);
    });

    test('an unreadable scene is refused with a plain message', () {
      expect(
        () => Segment.fromJson({
          'name': 'X',
          'minutes': 1,
          'scene': {'id': 4},
        }),
        throwsA(isA<RuleError>()),
      );
    });
  });

  group('Backups', () {
    test('carry groups and scenes when there are scenes, never members', () {
      final state = AppState.fresh(start)
        ..screens = migrateScreens(
          self: old('timer', slides: true),
          web: old('timer', slides: true),
          paired: const [(id: 'a', layout: 'timer')],
          pairedSlides: false,
        );
      // No scenes: a plain backup, as readable by earlier versions.
      final plain = jsonDecode(exportBackup(state, start)) as Map;
      expect((plain['data'] as Map).containsKey('screens'), isFalse);
      expect(plain['schemaVersion'], isNot(13));
      state.screens = state.screens!.sceneSaved('Worship', id: 'sworship');
      final raw = exportBackup(state, start);
      final j = jsonDecode(raw) as Map;
      expect(j['schemaVersion'], 13);
      expect((j['data'] as Map)['screens'].containsKey('members'), isFalse);
      final restored = importBackup(raw, start);
      expect(restored.screens!.scenes.single.name, 'Worship');
      expect(restored.screens!.members, isEmpty);
    });
  });
}
