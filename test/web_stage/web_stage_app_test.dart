import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:church_service_timer/web_stage/web_stage_views.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;
import '../pairing/saved_devices_test.dart' show eventually;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes HTTP; these tests talk to a real local server.
  setUpAll(() => HttpOverrides.global = null);

  test('Sharing to screens starts the web page; stopping ends it', () async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.commit((d, _) => d.churchName = "St. Mary's Chapel");
    await c.pairing.host('127.0.0.1');
    await eventually(() => c.webStage.running);
    final settings = c.webStageSettings;
    expect(settings.localName, 'st-marys-chapel');
    expect(validOrderCode(settings.orderCode), isTrue);
    // The generated code is kept, so slides stay valid.
    expect(c.state.webStage['orderCode'], settings.orderCode);
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('${c.webStageUrl}/api/info'));
    final info = jsonDecode(
      await (await req.close()).transform(utf8.decoder).join(),
    );
    expect(info['church'], "St. Mary's Chapel");
    expect(info['orderAccess'], 'code');
    await c.pairing.stop();
    await eventually(() => !c.webStage.running);
    expect(c.webStageUrl, isNull);
  });

  test('Changing the order code signs out order viewers', () async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await c.pairing.host('127.0.0.1');
    await eventually(() => c.webStage.running);
    final client = HttpClient();
    Future<int> join(String code) async {
      final req = await client.postUrl(Uri.parse('${c.webStageUrl}/api/join'));
      req.write(jsonEncode({'code': code}));
      return (await req.close()).statusCode;
    }

    final old = c.webStageSettings.orderCode;
    expect(await join(old), 200);
    expect(c.webStage.devices, hasLength(1));
    await c.setWebStageSettings(
      c.webStageSettings.copyWith(orderCode: 'GRACE'),
    );
    expect(c.webStage.devices, isEmpty);
    expect(await join(old), 403);
    expect(await join('grace'), 200, reason: 'Codes ignore case');
    await c.pairing.stop();
  });

  test('The join slide is a 1920 × 1080 PNG', () async {
    final png = await joinSlidePng(
      church: 'Grace Chapel',
      url: 'http://192.168.1.23:8080',
      localUrl: 'http://grace-chapel.local:8080',
      code: '4821',
    );
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1920);
    expect(frame.image.height, 1080);
  });
}
