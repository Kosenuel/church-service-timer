import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/app/update_checker.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// A device whose update check answers from [reply] and counts the asks.
class UpdatePort extends FakePort {
  String? reply;
  final asked = <String>[];
  final opened = <String>[];
  bool browser = true;
  UpdatePort(this.reply);
  @override
  Future<String> installedVersion() async => '0.32.0 (37)';
  @override
  UpdateChecker get updateChecker => UpdateChecker((url) async {
    asked.add(url);
    return reply;
  });
  @override
  Future<bool> openWebPage(String url) async {
    opened.add(url);
    return browser;
  }
}

String release(String tag, {String? page}) => jsonEncode({
  'tag_name': tag,
  'html_url':
      page ??
      'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/tag/$tag',
});

void main() {
  setUpAll(loadAppFonts);

  group('version comparison', () {
    Future<UpdateResult> check(String? reply, [String mine = '0.32.0 (37)']) =>
        UpdateChecker((_) async => reply).check(mine);

    test('reads x.y.z and ignores the build number', () {
      expect(versionNumbers('0.32.0 (37)'), [0, 32, 0]);
      expect(versionNumbers('v0.32.0'), [0, 32, 0]);
      expect(versionNumbers('1.2.3'), [1, 2, 3]);
      expect(versionNumbers('v0.32'), isNull);
      expect(versionNumbers('latest'), isNull);
      expect(versionNumbers('v0.33.0-beta'), isNull);
      expect(versionNumbers('0.36.0-beta.1 (41)'), isNull);
      expect(versionNumbers(''), isNull);
    });

    test('compares numbers, not text', () {
      expect(compareVersions([0, 9, 0], [0, 10, 0]), lessThan(0));
      expect(compareVersions([1, 0, 0], [0, 99, 99]), greaterThan(0));
      expect(compareVersions([0, 32, 1], [0, 32, 1]), 0);
    });

    test('reads a pre-release part', () {
      expect(parseVersion('0.36.0-beta.1 (41)')!.numbers, [0, 36, 0]);
      expect(parseVersion('0.36.0-beta.1 (41)')!.pre, 'beta.1');
      expect(parseVersion('v1.0.0-rc.1')!.pre, 'rc.1');
      expect(parseVersion('0.36.0 (42)')!.pre, isNull);
      expect(parseVersion('0.36.0-'), isNull);
      expect(parseVersion('0.36-beta'), isNull);
    });

    test('a pre-release is older than its release', () {
      int cmp(String a, String b) =>
          compareParsed(parseVersion(a)!, parseVersion(b)!);
      expect(cmp('0.36.0-beta.1', '0.36.0'), lessThan(0));
      expect(cmp('0.36.0', '0.36.0-beta.1'), greaterThan(0));
      expect(cmp('0.36.0-beta.1', '0.36.0-beta.2'), lessThan(0));
      expect(cmp('0.36.0-beta.2', '0.36.0-beta.10'), lessThan(0));
      expect(cmp('0.36.0-beta.2', '0.36.0-rc.1'), lessThan(0));
      expect(cmp('0.36.0-beta', '0.36.0-beta.1'), lessThan(0));
      expect(cmp('0.36.0-beta.1', '0.35.9'), greaterThan(0));
      expect(cmp('0.36.0-beta.1', '0.36.0-beta.1'), 0);
    });

    test('a beta is never offered to a stable install', () async {
      // Even if a beta were the answer, tagged or flagged.
      expect(await check(release('v0.36.0-beta.1')), isA<UpToDate>());
      expect(await check(release('v1.0.0-rc.1')), isA<UpToDate>());
      final flagged = jsonEncode({
        'tag_name': 'v0.36.0',
        'prerelease': true,
        'html_url': 'https://github.com/x',
      });
      expect(await check(flagged), isA<UpToDate>());
      final draft = jsonEncode({'tag_name': 'v0.36.0', 'draft': true});
      expect(await check(draft), isA<UpToDate>());
      final stable = jsonEncode({'tag_name': 'v0.36.0', 'prerelease': false});
      expect(await check(stable), isA<UpdateAvailable>());
    });

    test('a beta install is offered the stable release above it', () async {
      const beta = '0.36.0-beta.1 (41)';
      final up = await check(release('v0.36.0'), beta);
      expect(up, isA<UpdateAvailable>());
      expect((up as UpdateAvailable).version, '0.36.0');
      expect(await check(release('v0.37.0'), beta), isA<UpdateAvailable>());
      // An older stable release, or a newer beta, is not an update.
      final older = await check(release('v0.35.0'), beta);
      expect(older, isA<UpToDate>());
      expect((older as UpToDate).version, '0.36.0-beta.1');
      expect(await check(release('v0.36.0-beta.2'), beta), isA<UpToDate>());
    });

    test('an older release means this is the latest', () async {
      final found = await check(release('v0.31.4'));
      expect(found, isA<UpToDate>());
      expect((found as UpToDate).version, '0.32.0');
    });

    test('the same release means this is the latest', () async {
      expect(await check(release('v0.32.0')), isA<UpToDate>());
    });

    test('a newer release is offered with its page', () async {
      final found = await check(release('v0.33.0'));
      expect(found, isA<UpdateAvailable>());
      found as UpdateAvailable;
      expect(found.version, '0.33.0');
      expect(
        found.page,
        'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/tag/v0.33.0',
      );
      expect(await check(release('v0.100.0')), isA<UpdateAvailable>());
    });

    test('a page somewhere else is not opened', () async {
      final found = await check(
        release('v0.33.0', page: 'https://example.com/download'),
      );
      expect((found as UpdateAvailable).page, downloadPageUrl);
    });

    test('a malformed tag or answer is a failed check', () async {
      expect(await check(release('nightly')), isA<UpdateUnknown>());
      expect(await check(release('v0.33')), isA<UpdateUnknown>());
      expect(await check(release('0.33.0 (40)')), isA<UpdateUnknown>());
      expect(await check('{"tag_name": 33}'), isA<UpdateUnknown>());
      expect(await check('[]'), isA<UpdateUnknown>());
      expect(await check('<html>'), isA<UpdateUnknown>());
      expect(await check(null), isA<UpdateUnknown>());
      expect(await check(release('v0.33.0'), 'unknown'), isA<UpdateUnknown>());
    });

    test('a fetch that throws is a failed check', () async {
      final checker = UpdateChecker((_) async => throw Exception('no route'));
      expect(await checker.check('0.32.0 (37)'), isA<UpdateUnknown>());
    });

    test('the checker a device has by default never asks anything', () async {
      final checker = FakePort().updateChecker;
      expect(await checker.check('0.32.0 (37)'), isA<UpdateUnknown>());
    });
  });

  Future<UpdatePort> openAbout(WidgetTester t, String? reply) async {
    setScreen(t, const Size(430, 1000));
    final port = UpdatePort(reply);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('About', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('About'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('about-check-updates')));
    await t.pumpAndSettle();
    return port;
  }

  Future<void> press(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('about-check-updates')));
    await t.pumpAndSettle();
  }

  testWidgets('Nothing is fetched until the row is pressed', (t) async {
    final port = await openAbout(t, release('v0.33.0'));
    expect(find.text('Check for updates'), findsOneWidget);
    expect(
      find.text('Contacts GitHub to look for a newer version'),
      findsOneWidget,
    );
    expect(port.asked, isEmpty);
    expect(find.textContaining('is available'), findsNothing);
    await press(t);
    expect(port.asked, [latestReleaseUrl]);
    expect(
      latestReleaseUrl,
      'https://api.github.com/repos/ImmanuelOkose/church-service-timer-guide/releases/latest',
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The latest version says so, with no download button', (t) async {
    await openAbout(t, release('v0.32.0'));
    await press(t);
    expect(find.text('You have the latest version (0.32.0)'), findsOneWidget);
    expect(find.text('Open the download page'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A newer version offers the download page', (t) async {
    final port = await openAbout(t, release('v0.33.0'));
    await press(t);
    expect(find.text('Version 0.33.0 is available'), findsOneWidget);
    expect(port.opened, isEmpty);
    await t.tap(find.text('Open the download page'));
    await t.pumpAndSettle();
    expect(port.opened, [
      'https://github.com/ImmanuelOkose/church-service-timer-guide/releases/tag/v0.33.0',
    ]);
    // Without a browser the address is shown instead.
    port.browser = false;
    await t.tap(find.text('Open the download page'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Could not open a browser. The download page is at'),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A failed check says so plainly', (t) async {
    final port = await openAbout(t, null);
    await press(t);
    expect(
      find.text('Could not check. This device may be offline.'),
      findsOneWidget,
    );
    expect(find.text('Open the download page'), findsNothing);
    expect(port.asked, hasLength(1));
    await t.pumpWidget(const SizedBox());
  });
}
