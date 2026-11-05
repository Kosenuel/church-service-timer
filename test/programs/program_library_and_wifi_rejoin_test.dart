import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import '../domain/service_timing_test.dart'
    show FakePort, timeline, start, after;
import '../hardware/hardware_integration_test.dart' show W2Port, flush;

class RejoinPort extends W2Port {
  bool wifi = false;
  String? secret = 'synthetic';
  int scans = 0, connections = 0, joins = 0, cancels = 0;
  String? authenticatedId;
  List<Json>? visible;
  @override
  Future<String?> savedDisplayPassword(String id) async => secret;
  @override
  Future<List<Json>> discoverDisplays() async {
    scans++;
    return visible ?? (wifi ? [profile] : []);
  }

  @override
  Future<Json> connectDisplay(String id, String password) async {
    connections++;
    authenticatedId = id;
    return super.connectDisplay(id, password);
  }

  @override
  Future<bool> joinSignWifi(String id) async {
    joins++;
    wifi = true;
    return true;
  }

  @override
  Future<void> cancelSignWifi() async {
    cancels++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Library migrates absent metadata and preserves pins/recent across rename/delete',
    () {
      final s = AppState.fresh(start);
      final old = s.toJson()..remove('programLibrary');
      expect(AppState.fromJson(old).programLibrary.favourites, isEmpty);
      s.saveTemplate(timeline());
      s.programLibrary.favourites.add('Sunday');
      s.programLibrary.recent['Sunday'] = start.wall;
      final restored = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(restored.programLibrary.favourites, {'Sunday'});
      restored.saveTemplate(
        timeline().renamed('Youth Sunday'),
        replacing: restored.templates.indexWhere((p) => p.name == 'Sunday'),
      );
      expect(restored.programLibrary.favourites, {'Youth Sunday'});
      expect(restored.programLibrary.recent['Youth Sunday'], start.wall);
      restored.deleteTemplate(
        restored.templates.firstWhere((p) => p.name == 'Youth Sunday'),
      );
      expect(restored.programLibrary.favourites, isEmpty);
      expect(restored.programLibrary.recent, isEmpty);
      expect(exportBackup(s, start), isNot(contains('programLibrary')));
    },
  );
  test(
    'Library search matches words, favs sort first and recent uses last load',
    () {
      final programs = [
        timeline(),
        timeline().renamed('Youth Sunday'),
        timeline().renamed('Prayer'),
      ];
      final library = ProgramLibrary(
        favourites: {'Prayer'},
        recent: {'Sunday': 100, 'Youth Sunday': 200},
      );
      expect(library.find(programs, '', 'all').map((p) => p.name), [
        'Prayer',
        'Youth Sunday',
        'Sunday',
      ]);
      expect(library.find(programs, 'sunday first', 'all').length, 2);
      expect(library.find(programs, '', 'recent').map((p) => p.name), [
        'Youth Sunday',
        'Sunday',
      ]);
      expect(library.find(programs, '', 'favourites').single.name, 'Prayer');
      expect(library.find(programs, 'absent', 'all'), isEmpty);
    },
  );
  test(
    'Only successful load persists recent usage; picker prefs survive restart',
    () async {
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.commit((d, _) {
        d.saveTemplate(timeline());
        d.appearance = d.appearance.copyWith(pickerFeedback: 'both');
      });
      port.fail = true;
      expect(await c.act('load', value: timeline()), false);
      expect(c.state.programLibrary.recent, isEmpty);
      port.fail = false;
      expect(await c.act('load', value: timeline()), true);
      expect(c.state.programLibrary.recent['Sunday'], start.wall);
      final s = AppState.fromJson(jsonDecode(port.data!));
      expect(s.appearance.pickerFeedback, 'both');
      expect(AppearancePreferences.fromJson({}).pickerFeedback, 'haptics');
    },
  );
  test(
    'Timed cue return countdown follows real elapsed time through pause',
    () async {
      final p = FakePort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act(
        'message',
        value: const StageOutputMessage(TextLayout('WAIT'), seconds: 8),
      );
      expect(c.messageReturnSeconds, 8);
      p.at = after(3);
      await c.tick();
      await c.act('pause');
      expect(c.messageReturnSeconds, 5);
      p.at = after(9);
      await c.tick();
      expect(c.messageReturnSeconds, isNull);
    },
  );
  test(
    'Reconnect discovers first and joins Wi-Fi only if remembered sign is absent',
    () async {
      final p = RejoinPort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      expect(
        await c.hardware.reconnectSaved(
          joinWifi: () => p.joinSignWifi('synthetic-w2'),
        ),
        true,
      );
      expect(p.joins, 1);
      expect(p.scans, 2);
      expect(p.authenticatedId, 'synthetic-w2');
      expect(
        p.sent,
        isEmpty,
      ); // A first connection must preserve the existing sign output.
      await c.hardware.disconnect();
      expect(
        await c.hardware.reconnectSaved(
          joinWifi: () => p.joinSignWifi('synthetic-w2'),
        ),
        true,
      );
      expect(p.joins, 1);
    },
  );
  test(
    'Missing device secret never prompts Wi-Fi or authenticates another sign',
    () async {
      final p = RejoinPort()..secret = null;
      final c = AppController(p);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      expect(
        await c.hardware.reconnectSaved(
          joinWifi: () => p.joinSignWifi('synthetic-w2'),
        ),
        false,
      );
      expect(p.joins, 0);
      expect(p.connections, 0);
      p.secret = 'synthetic';
      p.visible = [
        {...p.profile, 'id': 'different-sign'},
      ];
      expect(
        await c.hardware.reconnectSaved(
          joinWifi: () => p.joinSignWifi('synthetic-w2'),
        ),
        false,
      );
      expect(p.connections, 0);
    },
  );
  test(
    'Destination switch cancels pending rejoin and late completion cannot connect',
    () async {
      final p = RejoinPort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.selectDestination('led');
      final gate = Completer<bool>();
      final future = c.hardware.reconnectSaved(joinWifi: () => gate.future);
      await flush();
      await c.selectDestination('simulator');
      gate.complete(true);
      expect(await future, false);
      expect(p.connections, 0);
      expect(c.destination, 'simulator');
      expect(c.hardware.autoReconnect, false);
    },
  );
  test(
    'Cancelled Wi-Fi or join failure leaves current timer and cues untouched',
    () async {
      final p = RejoinPort();
      final c = AppController(p);
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.act('load', value: timeline());
      await c.act('start');
      await c.act('cue', value: const TextLayout('WAIT'));
      final before = jsonEncode(c.state.session.toJson());
      expect(
        await c.hardware.reconnectSaved(joinWifi: () async => false),
        false,
      );
      expect(
        await c.hardware.reconnectSaved(
          joinWifi: () async => throw RuleError('Wi-Fi is off.'),
        ),
        false,
      );
      expect(c.hardware.status, contains('Wi-Fi is off'));
      expect(jsonEncode(c.state.session.toJson()), before);
      expect(p.connections, 0);
    },
  );
}
